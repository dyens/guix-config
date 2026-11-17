#!/usr/bin/env python3
"""Read-only, session-scoped RuClaw incident bundle. Python stdlib + kubectl + psql."""
import argparse
import base64
import collections
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import urllib.parse
import uuid

TABLES = ('user_front_sessions', 'user_front_messages', 'user_front_progress',
          'sessions', 'traces', 'spans', 'agent_run_checkpoints',
          'agent_run_tool_attempts', 'user_front_files', 'session_replay_archives')
SECRET_KEY = re.compile(r'(^|_)(password|passwd|secret|api_key|authorization|cookie|'
                        r'private_key|dsn|ciphertext|credential)(s|_.*)?$|'
                        r'^(token|access_token|refresh_token|id_token|auth_token)$', re.I)


def scrub(value):
    """Best effort, not a guarantee that arbitrary conversation text is secret-free."""
    if isinstance(value, dict):
        return {k: '[REDACTED]' if SECRET_KEY.search(k) else scrub(v)
                for k, v in value.items()}
    if isinstance(value, list):
        return [scrub(v) for v in value]
    if not isinstance(value, str):
        return value
    value = re.sub(r'-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----',
                   '[PRIVATE KEY REDACTED]', value, flags=re.S)
    value = re.sub(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '[JWT REDACTED]', value)
    value = re.sub(r'(?i)\bBearer\s+[^\s"\'<>]+', 'Bearer [REDACTED]', value)
    value = re.sub(r'(?i)\bpostgres(?:ql)?://[^\s"\'<>]+', '[DSN REDACTED]', value)
    value = re.sub(r'(?i)(["\']?(?:password|api_key|access_token|refresh_token|authorization|cookie)'
                   r'["\']?\s*[:=]\s*)("[^"\n]*"|\'[^\'\n]*\'|[^\s,;}]+)',
                   r'\1[REDACTED]', value)
    return value


def literal(value):
    return "'" + value.replace("'", "''") + "'"


def identifier(value):
    return '"' + value.replace('"', '""') + '"'


def pg_env(dsn):
    u = urllib.parse.urlsplit(dsn)
    if u.scheme not in ('postgres', 'postgresql') or not u.hostname or not u.username:
        raise ValueError('expected a PostgreSQL URI with host and user')
    # Do not inherit service/passfile/options or arbitrary DSN command-line options.
    env = {k: v for k, v in os.environ.items() if not k.startswith('PG')}
    env.update(PGHOST=u.hostname, PGPORT=str(u.port or 5432),
               PGUSER=urllib.parse.unquote(u.username),
               PGPASSWORD=urllib.parse.unquote(u.password or ''),
               PGDATABASE=urllib.parse.unquote(u.path.lstrip('/')),
               PGCONNECT_TIMEOUT='8', PGAPPNAME='ruclaw-session-incident',
               PGPASSFILE='/dev/null', PGSERVICEFILE='/dev/null')
    # Poolers may reject startup options. Every query starts its own READ ONLY
    # transaction instead; never retry a failed query outside that transaction.
    allowed = {'sslmode': 'PGSSLMODE', 'sslrootcert': 'PGSSLROOTCERT',
               'sslcert': 'PGSSLCERT', 'sslkey': 'PGSSLKEY',
               'target_session_attrs': 'PGTARGETSESSIONATTRS'}
    for key, val in urllib.parse.parse_qsl(u.query):
        if key not in allowed:
            raise ValueError('unsupported DSN parameter (not silently ignored)')
        env[allowed[key]] = val
    return env


def structured_log(line):
    """Read top-level slog fields only, never search payloads for correlation."""
    text = line.split(' ', 1)[-1]  # kubectl --timestamps prefix
    try:
        if text.startswith('{'):
            def unique(pairs):
                result = {}
                for key, value in pairs:
                    if key in result:
                        raise ValueError()
                    result[key] = value
                return result
            value = json.loads(text, object_pairs_hook=unique)
            return value if isinstance(value, dict) else {}
        fields = {}
        for item in shlex.split(text):
            key, sep, value = item.partition('=')
            if not sep or key in fields:
                return {}
            fields[key] = value
        return fields
    except (ValueError, TypeError):
        return {}


def operation_id(value):
    if not isinstance(value, str):
        return None
    try:
        parsed = uuid.UUID(value)
        return value if parsed.int and str(parsed) == value else None
    except ValueError:
        return None


def pod_metadata(pods):
    # Explicit allowlist: no env, labels, termination messages or annotations.
    return [{'name': p['metadata']['name'], 'uid': p['metadata']['uid'],
             'containers': [{'name': c['name'], 'image': c['image']}
                            for c in p['spec']['containers']],
             'container_statuses': [{k: s[k] for k in ('name', 'image', 'imageID', 'containerID', 'restartCount', 'ready') if k in s}
                                    for s in p.get('status', {}).get('containerStatuses', [])]}
            for p in pods]


class CollectionError(Exception):
    pass


def failure_hint(program, stderr):
    # Emit only fixed categories, never raw stderr (which may echo SQL/secrets).
    if program != 'psql':
        return ''
    text = stderr.lower()
    for needle, hint in (
        ('unsupported startup parameter', 'pooler rejected a PostgreSQL startup parameter'),
        ('password authentication failed', 'database authentication failed'),
        ('no pg_hba.conf entry', 'database connection rejected by pg_hba.conf'),
        ('could not translate host name', 'database hostname could not be resolved'),
        ('name or service not known', 'database hostname could not be resolved'),
        ('connection refused', 'database connection refused'),
        ('timeout expired', 'database connection timed out'),
        ('certificate verify failed', 'database TLS certificate verification failed'),
        ('permission denied', 'database role lacks required permissions'),
        ('row-level security', 'database tenant/RLS check failed'),
        ('statement timeout', 'database statement timed out'),
        ('lock timeout', 'database lock wait timed out'),
        ('does not exist', 'database/schema object missing'),
        ('syntax error', 'database query syntax error'),
    ):
        if needle in text:
            return '; ' + hint
    return ''


class Collector:
    def __init__(self, args):
        self.args = args
        # New directory only: never mix incidents or overwrite user files/symlinks.
        if args.output is None:
            self.root = Path(tempfile.mkdtemp(prefix=f'ruclaw-incident-{args.session}-', dir='/tmp'))
        else:
            self.root = Path(args.output)
            self.root.mkdir(mode=0o700, parents=False, exist_ok=False)
        self.manifest = {'format': 1, 'started_at': dt.datetime.now(dt.timezone.utc).isoformat(),
                         'session_id': args.session, 'context': args.context,
                         'namespace': args.namespace, 'selector': args.selector,
                         'broker_selector': args.broker_selector,
                         'stage': 'initializing',
                         'datasets': {}, 'errors': [], 'limitations': [
                             'Contains private conversation/tool data. Do not publish without review.',
                             'Redaction is best effort; arbitrary text may contain unrecognized secrets.',
                             'Only retained DB data; no decryption keys, document bodies or object storage downloads.',
                             'DB snapshot and Kubernetes logs are not one atomic snapshot.',
                             'Logs are bounded by since-time/tail; rotated/deleted pod logs may be unavailable.',
                             'Missing checkpoints/traces can mean retention, not absence of execution.',
                         ]}
        self.env = None

    def save(self, name, value):
        path = self.root / name
        with path.open('x', encoding='utf-8') as f:
            os.chmod(path, 0o600)
            if isinstance(value, str):
                f.write(scrub(value))
            else:
                json.dump(scrub(value), f, ensure_ascii=False, indent=2)
                f.write('\n')

    def command(self, cmd, *, env=None, sql=None):
        # Never include argv/stdout/stderr in errors: DB/log errors can echo credentials/content.
        try:
            p = subprocess.run(cmd, input=sql, text=True, capture_output=True,
                               env=env, timeout=self.args.timeout)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise CollectionError(f'{Path(cmd[0]).name}: {type(exc).__name__}') from None
        if p.returncode:
            program = Path(cmd[0]).name
            hint = failure_hint(program, p.stderr)
            raise CollectionError(f'{program}: exit {p.returncode}{hint}; raw stderr deliberately omitted')
        return p.stdout

    def kube(self, *args):
        return self.command(['kubectl', '--context', self.args.context, '--namespace',
                             self.args.namespace, '--request-timeout=30s', *args])

    def secret_env(self, key):
        # JSONPath reads only the requested key, not all values of the Secret.
        encoded = self.kube('get', 'secret', self.args.secret,
                            '-o', 'jsonpath={.data.' + key + '}')
        if not encoded:
            raise CollectionError('requested database credential key is absent')
        try:
            return pg_env(base64.b64decode(encoded, validate=True).decode())
        except (ValueError, UnicodeError):
            raise CollectionError('invalid/unsupported database credential URI') from None

    def query(self, sql, *, env=None, tenant=None):
        scope = f'SET LOCAL app.tenant = {literal(tenant)};' if tenant else ''
        sql = ('BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;\n'
               f"SET LOCAL statement_timeout = '{self.args.statement_timeout}s';\n"
               "SET LOCAL lock_timeout = '2s';\n" + scope + '\n' + sql + '\nROLLBACK;\n')
        raw = self.command(['psql', '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
                            '-P', 'pager=off'], env=env or self.env, sql=sql)
        try:
            return [json.loads(line) for line in raw.splitlines() if line.strip()]
        except ValueError:
            raise CollectionError('psql returned invalid JSON') from None

    def database(self):
        self.manifest['stage'] = 'app-credential'
        self.env = self.secret_env(self.args.app_dsn_key)
        tenant = self.args.tenant
        sid = literal(self.args.session)
        if not tenant:
            self.manifest['stage'] = 'tenant-discovery'
            maint = self.secret_env(self.args.maint_dsn_key)
            rows = self.query('SELECT json_build_object(\'tenant_id\', tenant_id) '
                              f'FROM public.user_front_sessions WHERE id={sid}::uuid;', env=maint)
            if len(rows) != 1:
                raise CollectionError('tenant discovery did not find exactly one session; supply --tenant')
            tenant = str(uuid.UUID(rows[0]['tenant_id']))
            del maint
        self.manifest['tenant_id'] = tenant
        self.manifest['stage'] = 'session-lookup'
        rows = self.query(f'SELECT row_to_json(s) FROM public.user_front_sessions s '
                          f'WHERE tenant_id={literal(tenant)}::uuid AND id={sid}::uuid;', tenant=tenant)
        if len(rows) != 1:
            raise CollectionError('session not visible with app credential and specified tenant')
        session = rows[0]
        key = session['internal_session_key']
        self.save('session.json', session)
        self.manifest['datasets']['session'] = {'status': 'ok', 'rows': 1}
        names = ','.join(literal(t) for t in TABLES)
        self.manifest['stage'] = 'schema-discovery'
        columns = self.query("SELECT json_build_object('table', table_name, 'column', column_name) "
                             "FROM information_schema.columns WHERE table_schema='public' "
                             f'AND table_name IN ({names}) ORDER BY table_name, ordinal_position;', tenant=tenant)
        schema = collections.defaultdict(list)
        for row in columns:
            schema[row['table']].append(row['column'])
        self.save('schema.json', dict(schema))
        t = literal(tenant)
        k = literal(key)
        runs = []
        if 'agent_run_checkpoints' in schema:
            runs.append(f'SELECT run_id::text FROM public.agent_run_checkpoints WHERE tenant_id::text={t} AND session_key={k}')
        if 'traces' in schema:
            runs.append(f'SELECT run_id::text FROM public.traces WHERE tenant_id={t}::uuid AND session_key={k}')
        if 'accepted_run_id' in schema.get('user_front_messages', []):
            runs.append(f'SELECT accepted_run_id::text FROM public.user_front_messages WHERE tenant_id={t}::uuid AND session_id={sid}::uuid')
        seed_runs = ' UNION '.join(runs) or 'SELECT NULL::text WHERE false'
        cte = ''
        run_ids = seed_runs
        if 'traces' in schema:
            descendants = ''
            if 'parent_trace_id' in schema['traces']:
                descendants = (f' UNION SELECT child.id, child.run_id FROM public.traces child '
                               f'JOIN trace_scope parent ON child.parent_trace_id=parent.id '
                               f'WHERE child.tenant_id={t}::uuid')
            cte = (f'WITH RECURSIVE trace_scope AS (SELECT id, run_id FROM public.traces '
                   f'WHERE tenant_id={t}::uuid AND (session_key={k} OR run_id::text IN ({seed_runs}))'
                   f'{descendants}) ')
            run_ids = seed_runs + ' UNION SELECT run_id::text FROM trace_scope'
        trace_ids = 'SELECT id FROM trace_scope'
        conditions = {
            'user_front_sessions': f'id={sid}::uuid',
            'user_front_messages': f'session_id={sid}::uuid',
            'user_front_progress': f'session_id={sid}::uuid',
            'user_front_files': f'session_id={sid}::uuid',
            'sessions': f'session_key={k}',
            'session_replay_archives': f'session_key={k}',
            'traces': f'id IN ({trace_ids})',
            'spans': f'trace_id IN ({trace_ids})',
            'agent_run_checkpoints': f'(session_key={k} OR run_id::text IN ({run_ids}))',
            'agent_run_tool_attempts': f'run_id::text IN ({run_ids})',
        }
        queries = []
        for table in TABLES:
            cols = schema.get(table, [])
            if not cols or 'tenant_id' not in cols or (table == 'spans' and 'traces' not in schema):
                self.manifest['datasets'][table] = {'status': 'unavailable', 'reason': 'table/required scope absent'}
                continue
            # Do not export protected replay ciphertext (or other credential-like columns).
            selected = [c for c in cols if not SECRET_KEY.search(c)]
            order = next((c for c in ('ordinal', 'start_time', 'created_at', 'run_id', 'id') if c in cols), None)
            sort = ' ORDER BY ' + identifier(order) if order else ''
            queries.append(cte + f'SELECT json_build_object(\'dataset\', {literal(table)}, \'row\', row_to_json(r)) '
                           f'FROM (SELECT {",".join(identifier(c) for c in selected)} FROM public.{identifier(table)} '
                           f'WHERE tenant_id::text={t} AND {conditions[table]}{sort} LIMIT {self.args.max_rows + 1}) r;')
        # All exported tables share one repeatable-read snapshot. Any query failure aborts the batch.
        datasets = {table: [] for table in TABLES if table not in self.manifest['datasets']}
        for table in datasets:
            self.manifest['datasets'][table] = {'status': 'error', 'reason': 'snapshot not exported'}
        self.manifest['stage'] = 'database-snapshot'
        rows = self.query('\n'.join(queries), tenant=tenant)
        for row in rows:
            datasets[row['dataset']].append(row['row'])
        for table, data in datasets.items():
            truncated = len(data) > self.args.max_rows
            data = data[:self.args.max_rows]
            self.save(table + '.json', data)
            self.manifest['datasets'][table] = {'status': 'truncated' if truncated else 'ok', 'rows': len(data)}
        self.summary(datasets)
        return session, [r.get('run_id') for r in datasets.get('traces', [])] + [r.get('run_id') for r in datasets.get('agent_run_checkpoints', [])]

    def summary(self, datasets):
        spans = datasets.get('spans', [])[:self.args.max_rows]
        calls = collections.Counter((r.get('tool_name') or r.get('name') or '',
                                     json.dumps(scrub(r.get('input_preview')), ensure_ascii=False, sort_keys=True))
                                    for r in spans if r.get('span_type') == 'tool_call')
        self.save('summary.json', {
            'trace_statuses': dict(collections.Counter(r.get('status', 'unknown') for r in datasets.get('traces', []))),
            'span_errors': [r for r in spans if r.get('status') == 'error' or r.get('error')],
            'repeated_tool_calls': [{'tool': name, 'input_preview': preview, 'count': count}
                                    for (name, preview), count in calls.most_common() if count > 1],
            'note': 'Based on retained/bounded previews, not necessarily complete model requests or exact tool arguments.',
        })

    def logs(self, session, run_ids):
        self.manifest['stage'] = 'kubernetes-logs'
        pods = json.loads(self.kube('get', 'pods', '-l', self.args.selector, '-o', 'json'))['items']
        self.save('pods.json', pod_metadata(pods))
        if not pods:
            raise CollectionError('no pods matched the selector')
        runs = {r for r in run_ids if isinstance(r, str) and r}
        operations = set()
        sources = []

        def scoped(fields):
            # Explicit conflicting fields veto a match; payload text is never scope.
            anchors = {'session_id': {self.args.session}, 'session': {self.args.session},
                       'session_key': {session['internal_session_key']}, 'run_id': runs}
            if fields.get('tenant_id') and fields['tenant_id'] != session['tenant_id']:
                return False
            matched = False
            for key, allowed in anchors.items():
                value = fields.get(key)
                if value:
                    if not isinstance(value, str) or value not in allowed:
                        return False
                    matched = True
            return matched
        # Default from session creation; caller may provide an earlier explicit RFC3339 bound.
        since = self.args.since_time or session['created_at']
        self.manifest['logs'] = {'since_time': since, 'tail_per_container': self.args.log_tail,
                                 'matching': 'top-level session/run fields without conflicting scope, or anchored A2A operation diagnostics'}
        for pod in pods:
            name = pod['metadata']['name']
            statuses = {s['name']: s for s in pod.get('status', {}).get('containerStatuses', [])}
            for container in pod['spec']['containers']:
                cname = container['name']
                for previous in (False, True):
                    if previous and not statuses.get(cname, {}).get('restartCount', 0):
                        continue
                    label = f'logs-{name}-{cname}' + ('-previous' if previous else '')
                    try:
                        command = ['logs', name, '-c', cname, '--timestamps=true',
                                   '--since-time=' + since, '--tail=' + str(self.args.log_tail)]
                        if previous:
                            command.append('--previous')
                        raw = self.kube(*command)
                        parsed = [(line, structured_log(line)) for line in raw.splitlines()]
                        sources.append((label, parsed))
                        for _, fields in parsed:
                            op = operation_id(fields.get('operation_id'))
                            if (scoped(fields) and fields.get('msg') == 'a2a.call' and op
                                    and fields.get('session_id') == self.args.session
                                    and fields.get('run_id') in runs):
                                operations.add(op)
                    except CollectionError as exc:
                        self.manifest['datasets'][label] = {'status': 'error', 'error': str(exc)}
                        self.manifest['errors'].append(f'{label}: {exc}')

        # Resolve anchors across ALL containers before export: diagnostics can
        # precede the completing a2a.call or live in a different container.
        for label, parsed in sources:
            lines = []
            for line, fields in parsed:
                diagnostic = (fields.get('msg') == 'a2a.diagnostic'
                              and fields.get('component') in ('backend', 'broker_client')
                              and operation_id(fields.get('operation_id')) in operations)
                has_scope = any(fields.get(k) for k in ('session_id', 'session', 'session_key', 'run_id', 'tenant_id'))
                if scoped(fields) or (diagnostic and not has_scope):
                    lines.append(line)
            self.save_log(label, lines, len(parsed))
        self.manifest['limitations'].append('Unstructured or payload-only log matches are excluded: session/run or anchored operation fields are required. Reaching the log-tail ceiling is conservatively reported as truncated/partial.')
        self.broker_logs(operations, since)

    def save_log(self, label, lines, fetched):
        self.save(label + '.log', '\n'.join(lines) + ('\n' if lines else ''))
        self.manifest['datasets'][label] = {
            'status': 'truncated' if fetched >= self.args.log_tail else 'bounded',
            'matched_lines': len(lines), 'fetched_lines': fetched}

    def broker_logs(self, operations, since):
        self.manifest['stage'] = 'credbroker-logs'
        self.manifest['broker_logs'] = {'since_time': since, 'tail_per_container': self.args.log_tail,
                                       'operation_ids': sorted(operations),
                                       'matching': 'top-level a2a.diagnostic operation_id from session/run-scoped backend a2a.call'}
        try:
            pods = json.loads(self.kube('get', 'pods', '-l', self.args.broker_selector, '-o', 'json'))['items']
            self.save('credbroker-pods.json', pod_metadata(pods))
            if not pods:
                raise CollectionError('no credbroker pods matched the selector')
        except (CollectionError, ValueError, KeyError, TypeError) as exc:
            message = str(exc) if isinstance(exc, CollectionError) else 'invalid credbroker pod metadata'
            self.manifest['datasets']['credbroker_logs'] = {'status': 'unavailable', 'reason': message}
            self.manifest['errors'].append(message)
            return
        if not operations:
            self.manifest['datasets']['credbroker_logs'] = {
                'status': 'unavailable', 'reason': 'no correlated operation IDs in bounded backend logs; old instrumentation or retention may apply'}
            return
        matched_operations = set()
        for pod in pods:
            name = pod['metadata']['name']
            statuses = {s['name']: s for s in pod.get('status', {}).get('containerStatuses', [])}
            for container in pod['spec']['containers']:
                cname = container['name']
                for previous in (False, True):
                    if previous and not statuses.get(cname, {}).get('restartCount', 0):
                        continue
                    label = f'logs-credbroker-{name}-{cname}' + ('-previous' if previous else '')
                    try:
                        command = ['logs', name, '-c', cname, '--timestamps=true',
                                   '--since-time=' + since, '--tail=' + str(self.args.log_tail)]
                        if previous:
                            command.append('--previous')
                        raw = self.kube(*command)
                        lines = []
                        for line in raw.splitlines():
                            fields = structured_log(line)
                            if (fields.get('msg') == 'a2a.diagnostic' and fields.get('component') == 'broker'
                                    and operation_id(fields.get('operation_id')) in operations):
                                lines.append(line)
                                matched_operations.add(fields['operation_id'])
                        self.save_log(label, lines, len(raw.splitlines()))
                    except CollectionError as exc:
                        self.manifest['datasets'][label] = {'status': 'error', 'error': str(exc)}
                        self.manifest['errors'].append(f'{label}: {exc}')
        missing = operations - matched_operations
        self.manifest['datasets']['credbroker_correlation'] = {
            'status': 'unavailable' if missing else 'bounded',
            'matched_operations': len(matched_operations), 'unmatched_operation_ids': sorted(missing)}
        self.manifest['limitations'].append('Pod images/imageIDs describe current containers, not necessarily the versions that handled historical calls. Broker logs require retained operation-correlated instrumentation; no matches do not prove absence of execution.')

    def run(self):
        try:
            if self.args.context is None:
                self.manifest['stage'] = 'context-discovery'
                context = self.command(['kubectl', 'config', 'current-context']).strip()
                if not context or context.startswith('-') or any(ord(c) < 32 for c in context):
                    raise CollectionError('kubectl returned an invalid/empty current context')
                self.args.context = context
                self.manifest['context'] = context
            session, runs = self.database()
            self.logs(session, runs)
            self.manifest['stage'] = 'finished'
        except KeyboardInterrupt:
            self.manifest['errors'].append('collection interrupted by operator')
        except (CollectionError, ValueError, KeyError, TypeError) as exc:
            # Do not serialize malformed remote values/exception payloads.
            message = str(exc) if isinstance(exc, CollectionError) else type(exc).__name__
            self.manifest['errors'].append(message)
        finally:
            self.env = None
            self.manifest['finished_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
            self.manifest['files'] = {p.name: {'bytes': p.stat().st_size,
                                             'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                                      for p in sorted(self.root.iterdir()) if p.is_file()}
            self.manifest['complete'] = not self.manifest['errors'] and all(
                v['status'] not in ('unavailable', 'truncated', 'error')
                for v in self.manifest['datasets'].values())
            self.save('manifest.json', self.manifest)
        return 0 if self.manifest['complete'] else 2


def positive(value):
    n = int(value)
    if n < 1:
        raise argparse.ArgumentTypeError('must be positive')
    return n


def parse_args(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--session', required=True, type=lambda s: str(uuid.UUID(s)), help='RuClaw public chat UUID, NOT Pi session UUID')
    p.add_argument('--context', help='kubectl context; default: resolve current-context once before collection')
    p.add_argument('--namespace', required=True)
    scope = p.add_mutually_exclusive_group()
    scope.add_argument('--tenant', type=lambda s: str(uuid.UUID(s)), help='tenant UUID; default: discover by session UUID with maint credential')
    scope.add_argument('--discover-tenant', action='store_true', help='discover tenant (already the default; retained for compatibility)')
    p.add_argument('--secret', default='ruclaw-secrets')
    p.add_argument('--app-dsn-key', default='RUCLAW_POSTGRES_DSN')
    p.add_argument('--maint-dsn-key', default='RUCLAW_DB_MAINT_DSN')
    p.add_argument('--selector', default='app.kubernetes.io/component=backend', help='verify against your deployment labels')
    p.add_argument('--broker-selector', default='app.kubernetes.io/component=credbroker', help='selector for correlated broker diagnostics')
    p.add_argument('--since-time', help='RFC3339 log lower bound; default session created_at')
    p.add_argument('--log-tail', type=positive, default=100000)
    p.add_argument('--max-rows', type=positive, default=50000, help='per table; truncation is explicit and exits 2')
    p.add_argument('--timeout', type=positive, default=180, help='wall timeout per subprocess, seconds')
    p.add_argument('--statement-timeout', type=positive, default=30)
    p.add_argument('--output', help='new directory; default: unique private /tmp/ruclaw-incident-<session>-*')
    args = p.parse_args(argv)
    for value in ([args.context] if args.context is not None else []) + [args.namespace, args.secret, args.selector, args.broker_selector]:
        if not value or value.startswith('-') or any(ord(c) < 32 for c in value):
            p.error('invalid Kubernetes argument')
    for value in (args.app_dsn_key, args.maint_dsn_key):
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', value):
            p.error('invalid secret key')
    if args.since_time:
        try:
            parsed = dt.datetime.fromisoformat(args.since_time.replace('Z', '+00:00'))
            if parsed.tzinfo is None:
                raise ValueError()
        except ValueError:
            p.error('--since-time must be RFC3339 with timezone')
    return args


def main(argv=None):
    args = parse_args(argv)
    os.umask(0o077)
    try:
        collector = Collector(args)
        result = collector.run()
    except OSError:
        print('Cannot create/write private output directory (must not already exist).', file=sys.stderr)
        return 2
    print(f'Bundle: {collector.root}; ' + ('collected' if result == 0 else 'PARTIAL — inspect manifest.json'))
    return result


if __name__ == '__main__':
    sys.exit(main())
