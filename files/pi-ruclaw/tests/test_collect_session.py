"""Offline incident collector tests: no Kubernetes, database or real credentials."""
import base64
import importlib.util
import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'diagnostics/collect-session.py'
spec = importlib.util.spec_from_file_location('collect_session', SCRIPT)
assert spec is not None and spec.loader is not None
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)
SID = '01a1cf44-9795-7084-b05b-324fb1635713'
TENANT = '12b4bf2f-d4f1-40cd-994a-ec6214571895'
RUN = '01a1cf44-980b-728c-9d4e-5d217137b458'
OP = '7a7208c3-000b-4de8-ad23-c9cc509eb8ac'
SESSION = {'id': SID, 'tenant_id': TENANT, 'internal_session_key': 'agent:test:' + SID,
           'created_at': '2026-11-12T10:00:00+00:00'}


class CollectorTests(unittest.TestCase):
    def setUp(self):
        self.temp = self.enterContext(tempfile.TemporaryDirectory())
        self.args = collector.parse_args(['--session', SID, '--tenant', TENANT,
                                         '--context', 'explicit-context', '--namespace', 'test',
                                         '--output', str(Path(self.temp) / 'bundle')])
        self.calls = []

    def fake_command(self, cmd, *, env=None, sql=None):
        self.calls.append((cmd, env, sql))
        if cmd[0] == 'kubectl':
            self.assertIn('--context', cmd)
            self.assertIn('explicit-context', cmd)
            self.assertNotIn('exec', cmd)
            self.assertNotIn('apply', cmd)
            if 'secret' in cmd:
                return base64.b64encode(b'postgres://app:never-save-this@localhost/db?sslmode=require').decode()
            if 'pods' in cmd:
                if self.args.broker_selector in cmd:
                    return json.dumps({'items': [{'metadata': {'name': 'broker', 'uid': 'broker-uid'},
                        'spec': {'containers': [{'name': 'credbroker', 'image': 'broker:sha'}]},
                        'status': {'containerStatuses': [{'name': 'credbroker', 'imageID': 'sha256:resolved', 'restartCount': 0,
                                                         'state': {'terminated': {'message': 'never-save-this'}}}]}}]})
                return json.dumps({'items': [
                    {'metadata': {'name': name, 'uid': name + '-uid'},
                     'spec': {'containers': [{'name': 'backend', 'image': 'ruclaw:sha'}]},
                     'status': {'containerStatuses': [{'name': 'backend', 'restartCount': 1}]}}
                    for name in ('backend-a', 'backend-b')]})
            if 'logs' in cmd:
                if 'broker' in cmd:
                    return (f'2026-11-12T10:01:00Z time=2026-11-12T10:01:00Z level=INFO msg=a2a.diagnostic '
                            f'component=broker operation_id={OP} stage=dispatch reason=http_status http_status=502\n'
                            '2026-11-12T10:01:00Z msg=a2a.diagnostic component=broker operation_id=other private=OTHER TENANT CHAT\n')
                return (f'2026-11-12T10:01:00Z session={SID} error=test\n'
                        f'2026-11-12T10:01:00Z time=2026-11-12T10:01:00Z level=INFO msg=a2a.call '
                        f'session_id={SID} run_id={RUN} operation_id={OP}\nOTHER TENANT CHAT\n')
        self.assertEqual(cmd[0], 'psql')
        assert sql is not None
        self.assertIn('READ ONLY', sql)
        self.assertIn('REPEATABLE READ', sql)
        self.assertIn('ROLLBACK;', sql)
        if 'information_schema.columns' in sql:
            schema = {t: ['id', 'tenant_id', 'created_at'] for t in collector.TABLES}
            schema['user_front_messages'] += ['accepted_run_id', 'session_id']
            schema['sessions'] += ['session_key', 'replay_ciphertext']
            schema['traces'] += ['run_id', 'session_key', 'parent_trace_id']
            return '\n'.join(json.dumps({'table': t, 'column': c}) for t, cs in schema.items() for c in cs)
        if 'row_to_json(s)' in sql:
            return json.dumps(SESSION)
        if "json_build_object('tenant_id'" in sql:
            return json.dumps({'tenant_id': TENANT})
        self.assertNotIn('"replay_ciphertext"', sql)
        self.assertIn('tenant_id::text=', sql)
        self.assertIn('session_id=', sql)
        self.assertIn('trace_id IN', sql)
        self.assertIn('run_id::text IN', sql)
        self.assertIn('WITH RECURSIVE trace_scope', sql)
        self.assertIn('child.parent_trace_id=parent.id', sql)
        self.assertIn('child.tenant_id=', sql)
        return '\n'.join(json.dumps({'dataset': table, 'row': row}) for table, row in [
            ('user_front_messages', {'content': 'hello', 'accepted_run_id': RUN}),
            ('traces', {'run_id': RUN, 'status': 'error', 'total_input_tokens': 123}),
            ('spans', {'span_type': 'tool_call', 'tool_name': 'knowledge_search',
                       'input_preview': '{"query":"PSM"}', 'input_tokens': 123}),
            ('spans', {'span_type': 'tool_call', 'tool_name': 'knowledge_search',
                       'input_preview': '{"query":"PSM"}'}),
            ('agent_run_checkpoints', {'run_id': RUN, 'plan_json': {'api_key': 'never-save-this'}}),
        ])

    def test_full_offline_bundle(self):
        c = collector.Collector(self.args)
        with patch.object(c, 'command', side_effect=self.fake_command):
            self.assertEqual(c.run(), 0)
        manifest = json.loads((c.root / 'manifest.json').read_text())
        self.assertTrue(manifest['complete'])
        self.assertEqual(len([name for name in manifest['datasets'] if name.startswith('logs-')]), 5)
        summary = json.loads((c.root / 'summary.json').read_text())
        self.assertEqual(summary['repeated_tool_calls'][0]['count'], 2)
        self.assertEqual(json.loads((c.root / 'traces.json').read_text())[0]['total_input_tokens'], 123)
        for path in c.root.iterdir():
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            self.assertNotIn('never-save-this', path.read_text())
            self.assertNotIn('OTHER TENANT CHAT', path.read_text())
        self.assertEqual(c.root.stat().st_mode & 0o777, 0o700)
        self.assertEqual(len([cmd for cmd, _, _ in self.calls if 'secret' in cmd]), 1)
        for cmd, env, sql in self.calls:
            if cmd[0] == 'psql':
                self.assertNotIn('never-save-this', ' '.join(cmd))
                self.assertIn('SET LOCAL app.tenant', sql)
                self.assertEqual(env['PGSSLMODE'], 'require')

    def test_explicit_discovery_only_then_app_scope(self):
        self.args.tenant = None
        self.args.discover_tenant = True
        c = collector.Collector(self.args)
        with patch.object(c, 'command', side_effect=self.fake_command):
            self.assertEqual(c.run(), 0)
        secrets = [cmd for cmd, _, _ in self.calls if 'secret' in cmd]
        self.assertEqual(len(secrets), 2)
        sqls = [sql for _, _, sql in self.calls if sql]
        self.assertNotIn('SET LOCAL app.tenant', sqls[0])
        self.assertIn('WHERE id=', sqls[0])
        self.assertNotIn('owner_id', sqls[0])
        self.assertTrue(all('SET LOCAL app.tenant' in sql for sql in sqls[1:]))

    def test_partial_manifest_on_database_failure_without_echoing_stderr(self):
        c = collector.Collector(self.args)
        with patch.object(c, 'secret_env', return_value={}), patch('subprocess.run', return_value=
                subprocess.CompletedProcess([], 1, '', 'password=do-not-persist')):
            self.assertEqual(c.run(), 2)
        text = (c.root / 'manifest.json').read_text()
        self.assertNotIn('do-not-persist', text)
        self.assertIn('stderr deliberately omitted', text)
        self.assertEqual(json.loads(text)['stage'], 'session-lookup')
        self.assertFalse(json.loads(text)['complete'])

    def test_log_errors_do_not_discard_db_bundle(self):
        c = collector.Collector(self.args)
        def failed(cmd, **kwargs):
            if 'logs' in cmd:
                raise collector.CollectionError('kubectl: exit 1')
            return self.fake_command(cmd, **kwargs)
        with patch.object(c, 'command', side_effect=failed):
            self.assertEqual(c.run(), 2)
        self.assertTrue((c.root / 'spans.json').exists())
        self.assertEqual(len(c.manifest['errors']), 4)
        self.assertEqual(c.manifest['datasets']['credbroker_logs']['status'], 'unavailable')

    def test_truncation_not_silent(self):
        self.args.max_rows = 1
        c = collector.Collector(self.args)
        with patch.object(c, 'command', side_effect=self.fake_command):
            self.assertEqual(c.run(), 2)
        self.assertEqual(c.manifest['datasets']['spans']['status'], 'truncated')
        self.assertEqual(len(json.loads((c.root / 'spans.json').read_text())), 1)

    def test_missing_optional_table_is_explicit(self):
        c = collector.Collector(self.args)
        def missing(cmd, **kwargs):
            result = self.fake_command(cmd, **kwargs)
            if kwargs.get('sql') and 'information_schema.columns' in kwargs['sql']:
                return '\n'.join(line for line in result.splitlines()
                                 if json.loads(line)['table'] != 'session_replay_archives')
            return result
        with patch.object(c, 'command', side_effect=missing):
            self.assertEqual(c.run(), 2)
        self.assertEqual(c.manifest['datasets']['session_replay_archives']['status'], 'unavailable')
        self.assertFalse((c.root / 'session_replay_archives.json').exists())

    def test_tenant_mismatch_stops_before_scanning_or_logs(self):
        c = collector.Collector(self.args)
        with patch.object(c, 'secret_env', return_value={}), patch.object(c, 'query', return_value=[]) as query:
            with patch.object(c, 'logs') as logs:
                self.assertEqual(c.run(), 2)
                logs.assert_not_called()
        query.assert_called_once()
        self.assertIn('app credential', c.manifest['errors'][0])

    def test_export_query_failure_marks_unexported_tables(self):
        c = collector.Collector(self.args)
        def failed(cmd, **kwargs):
            if kwargs.get('sql') and "json_build_object('dataset'" in kwargs['sql']:
                raise collector.CollectionError('psql: exit 1')
            return self.fake_command(cmd, **kwargs)
        with patch.object(c, 'command', side_effect=failed):
            self.assertEqual(c.run(), 2)
        self.assertEqual(c.manifest['datasets']['spans']['status'], 'error')
        self.assertTrue((c.root / 'manifest.json').exists())
        self.assertFalse((c.root / 'spans.json').exists())

    def test_broker_correlation_versions_and_bounds(self):
        c = collector.Collector(self.args)
        with patch.object(c, 'command', side_effect=self.fake_command):
            self.assertEqual(c.run(), 0)
        self.assertEqual(c.manifest['broker_logs']['operation_ids'], [OP])
        pods = json.loads((c.root / 'credbroker-pods.json').read_text())
        self.assertEqual(pods[0]['container_statuses'][0]['imageID'], 'sha256:resolved')
        data = (c.root / 'logs-credbroker-broker-credbroker.log').read_text()
        self.assertIn('http_status=502', data)
        self.assertNotIn('OTHER TENANT', data)
        for cmd, _, _ in self.calls:
            if 'logs' in cmd:
                self.assertIn('--since-time=' + SESSION['created_at'], cmd)
                self.assertIn('--tail=100000', cmd)
        self.assertEqual(c.manifest['datasets']['credbroker_correlation']['unmatched_operation_ids'], [])

    def test_untrusted_previews_cannot_expand_broker_correlation(self):
        c = collector.Collector(self.args)
        other = '070b9b77-beee-4bad-950c-e091f37fd7ac'
        def fake(cmd, **kwargs):
            raw = self.fake_command(cmd, **kwargs)
            if 'logs' in cmd and 'broker' not in cmd:
                # Matching session UUID in a payload is not a trusted field.
                raw += ('2026-11-12T10:01:00Z ' + json.dumps({'msg': 'tool.output', 'session_id': SID,
                        'preview': {'msg': 'a2a.call', 'session_id': SID, 'run_id': RUN, 'operation_id': other}}) + '\n')
                raw += (f'2026-11-12T10:01:00Z msg=a2a.call session_id=another run_id={RUN} operation_id={other} content={SID}\n')
                raw += (f'2026-11-12T10:01:00Z msg=a2a.call session_id={SID} run_id=another operation_id={other}\n')
            return raw
        with patch.object(c, 'command', side_effect=fake):
            self.assertEqual(c.run(), 0)
        self.assertEqual(c.manifest['broker_logs']['operation_ids'], [OP])
        for path in c.root.glob('logs-backend-*.log'):
            self.assertNotIn('session_id=another', path.read_text())
            self.assertNotIn('run_id=another', path.read_text())

    def test_backend_diagnostics_across_containers_and_before_anchor(self):
        c = collector.Collector(self.args)
        def fake(cmd, **kwargs):
            raw = self.fake_command(cmd, **kwargs)
            if 'logs' in cmd and 'broker' not in cmd:
                diagnostic = (f'2026-11-12T10:01:00Z msg=a2a.diagnostic component=backend operation_id={OP} '
                              'stage=identity_persist reason=db_error\n')
                client = (f'2026-11-12T10:01:00Z msg=a2a.diagnostic component=broker_client operation_id={OP} '
                          'stage=dispatch reason=http_status http_status=502\n')
                foreign = (f'2026-11-12T10:01:00Z msg=a2a.diagnostic component=backend operation_id={OP} '
                           f'session_id=another content={SID} private=FOREIGN\n')
                raw = diagnostic + client + foreign + (raw if 'backend-b' in cmd else '')
            return raw
        with patch.object(c, 'command', side_effect=fake):
            self.assertEqual(c.run(), 0)
        for path in c.root.glob('logs-backend-*.log'):
            text = path.read_text()
            self.assertIn('stage=identity_persist reason=db_error', text)
            self.assertIn('component=broker_client', text)
            self.assertNotIn('FOREIGN', text)

    def test_payload_substrings_never_export_foreign_backend_rows(self):
        c = collector.Collector(self.args)
        def fake(cmd, **kwargs):
            raw = self.fake_command(cmd, **kwargs)
            if 'logs' in cmd and 'broker' not in cmd:
                raw += (f'2026-11-12T10:01:00Z msg=tool.output session_id=another content={SID} private=FOREIGN\n'
                        f'2026-11-12T10:01:00Z msg=tool.output run_id={RUN} tenant_id=another private=FOREIGN\n'
                        f'2026-11-12T10:01:00Z msg=tool.output content={SID} private=FOREIGN\n')
            return raw
        with patch.object(c, 'command', side_effect=fake):
            self.assertEqual(c.run(), 0)
        for path in c.root.glob('logs-backend-*.log'):
            self.assertNotIn('FOREIGN', path.read_text())

    def test_log_tail_ceiling_is_partial_even_when_all_operations_found(self):
        for source in ('backend', 'broker'):
            with self.subTest(source=source):
                self.args.output = str(Path(self.temp) / source)
                self.args.log_tail = 10
                c = collector.Collector(self.args)
                def fake(cmd, **kwargs):
                    raw = self.fake_command(cmd, **kwargs)
                    if 'logs' in cmd and (('broker' in cmd) == (source == 'broker')):
                        lines = raw.splitlines()
                        raw += 'padding\n' * (self.args.log_tail - len(lines))
                    return raw
                with patch.object(c, 'command', side_effect=fake):
                    self.assertEqual(c.run(), 2)
                self.assertEqual(c.manifest['datasets']['credbroker_correlation']['unmatched_operation_ids'], [])
                labels = [k for k in c.manifest['datasets'] if k.startswith('logs-')
                          and (('logs-credbroker-' in k) == (source == 'broker'))]
                self.assertTrue(labels)
                for label in labels:
                    self.assertEqual(c.manifest['datasets'][label]['status'], 'truncated')
                self.assertFalse(c.manifest['complete'])

    def test_missing_broker_or_correlation_is_partial(self):
        for mode in ('pods', 'logs', 'no_backend_ids'):
            with self.subTest(mode=mode):
                self.args.output = str(Path(self.temp) / mode)
                c = collector.Collector(self.args)
                def fake(cmd, **kwargs):
                    raw = self.fake_command(cmd, **kwargs)
                    if mode == 'pods' and 'pods' in cmd and self.args.broker_selector in cmd:
                        return '{"items": []}'
                    if mode == 'logs' and 'logs' in cmd and 'broker' in cmd:
                        return '2026-11-12T10:01:00Z msg=a2a.diagnostic component=broker operation_id=other\n'
                    if mode == 'no_backend_ids' and 'logs' in cmd and 'broker' not in cmd:
                        return f'2026-11-12T10:01:00Z session={SID}\n'
                    return raw
                with patch.object(c, 'command', side_effect=fake):
                    self.assertEqual(c.run(), 2)
                self.assertFalse(c.manifest['complete'])
                self.assertTrue((c.root / 'spans.json').exists())
                if mode == 'logs':
                    self.assertEqual(c.manifest['datasets']['credbroker_correlation']['unmatched_operation_ids'], [OP])

    def test_broker_log_permission_failure_is_partial(self):
        c = collector.Collector(self.args)
        def fake(cmd, **kwargs):
            if 'logs' in cmd and 'broker' in cmd:
                raise collector.CollectionError('kubectl: exit 1; raw stderr deliberately omitted')
            return self.fake_command(cmd, **kwargs)
        with patch.object(c, 'command', side_effect=fake):
            self.assertEqual(c.run(), 2)
        self.assertEqual(c.manifest['datasets']['logs-credbroker-broker-credbroker']['status'], 'error')

    def test_structured_log_parser(self):
        for fields in ('msg=a2a.call msg=forged', '{"msg":"a2a.call","msg":"forged"}', 'msg="unterminated'):
            self.assertEqual(collector.structured_log('2026-11-12T10:01:00Z ' + fields), {})
        self.assertIsNone(collector.operation_id('00000000-0000-0000-0000-000000000000'))
        self.assertIsNone(collector.operation_id('invalid; shell'))
        self.assertEqual(collector.operation_id(OP), OP)

    def test_no_overwrite(self):
        collector.Collector(self.args)
        with self.assertRaises(FileExistsError):
            collector.Collector(self.args)

    def test_redaction_retains_diagnostic_metrics(self):
        value = {'access_token': 'abc', 'credentials': {'x': 'secret'},
                 'input_tokens': 120, 'total_output_tokens': 30,
                 'text': 'Bearer abcdef postgres://user:password@db/name '
                         'eyJabc.def.ghi password="hello world"',
                 'preview': '{"api_key": "do-not-save"}'}
        result = collector.scrub(value)
        self.assertEqual(result['input_tokens'], 120)
        self.assertEqual(result['total_output_tokens'], 30)
        self.assertEqual(result['credentials'], '[REDACTED]')
        for secret in ('abcdef', 'user:password', 'eyJabc', 'hello world', 'do-not-save'):
            self.assertNotIn(secret, json.dumps(result))

    def test_pg_env_does_not_inherit_connection_settings(self):
        with patch.dict(os.environ, {'PGSERVICE': 'unrelated', 'PGOPTIONS': 'unsafe', 'PGHOST': 'wrong'}):
            env = collector.pg_env('postgresql://app:p%40ss@host:5433/db?sslmode=verify-full')
        self.assertEqual(env['PGPASSWORD'], 'p@ss')
        self.assertEqual(env['PGHOST'], 'host')
        self.assertEqual(env['PGPASSFILE'], '/dev/null')
        self.assertNotIn('PGSERVICE', env)
        self.assertNotIn('PGOPTIONS', env, 'pooler must not receive unsupported startup options')
        with self.assertRaises(ValueError):
            collector.pg_env('postgres://app:pw@host/db?options=-c+read_only=off')

    def test_pooler_startup_error_is_classified_without_secret_output(self):
        c = collector.Collector(self.args)
        result = subprocess.CompletedProcess([], 2, '',
            'FATAL: unsupported startup parameter in options: default_transaction_read_only '
            'password=do-not-persist postgres://app:private@host/db')
        with patch('subprocess.run', return_value=result):
            with self.assertRaises(collector.CollectionError) as error:
                c.command(['psql'], sql='private SQL')
        self.assertIn('pooler rejected', str(error.exception))
        self.assertNotIn('private', str(error.exception))
        self.assertNotIn('do-not-persist', str(error.exception))

    def test_failure_hints_only_return_fixed_categories(self):
        cases = [('could not translate host name SECRET', 'hostname could not be resolved'),
                 ('password authentication failed SECRET', 'authentication failed'),
                 ('permission denied SECRET', 'required permissions'),
                 ('canceling statement due to statement timeout SECRET', 'statement timed out'),
                 ('unknown error SECRET', '')]
        for text, expected in cases:
            hint = collector.failure_hint('psql', text)
            self.assertIn(expected, hint)
            self.assertNotIn('SECRET', hint)
        self.assertEqual(collector.failure_hint('kubectl', 'permission denied SECRET'), '')

    def test_timeout_does_not_echo_input(self):
        c = collector.Collector(self.args)
        with patch('subprocess.run', side_effect=subprocess.TimeoutExpired('sensitive', 1)):
            with self.assertRaisesRegex(collector.CollectionError, '^psql: TimeoutExpired$'):
                c.command(['psql'], sql='private content')

    def test_cli_defaults_and_unique_private_tmp_output(self):
        args = collector.parse_args(['--session', SID, '--namespace', 'test'])
        self.assertIsNone(args.context)
        self.assertIsNone(args.tenant)
        self.assertIsNone(args.output)
        roots = []
        for _ in range(2):
            c = collector.Collector(args)
            self.addCleanup(shutil.rmtree, c.root)
            roots.append(c.root)
            self.assertEqual(c.root.parent, Path('/tmp'))
            self.assertTrue(c.root.name.startswith('ruclaw-incident-' + SID + '-'))
            self.assertEqual(c.root.stat().st_mode & 0o777, 0o700)
        self.assertNotEqual(*roots)

    def test_current_context_is_resolved_once_and_pinned(self):
        self.args.context = None
        self.args.tenant = None
        c = collector.Collector(self.args)
        def command(cmd, **kwargs):
            if cmd == ['kubectl', 'config', 'current-context']:
                self.calls.append((cmd, None, None))
                return 'explicit-context\n'
            return self.fake_command(cmd, **kwargs)
        with patch.object(c, 'command', side_effect=command):
            self.assertEqual(c.run(), 0)
        self.assertEqual(c.manifest['context'], 'explicit-context')
        self.assertEqual(len([cmd for cmd, _, _ in self.calls if 'current-context' in cmd]), 1)
        self.assertEqual(len([cmd for cmd, _, _ in self.calls if 'secret' in cmd]), 2)

    def test_empty_current_context_stops_before_database(self):
        self.args.context = None
        c = collector.Collector(self.args)
        with patch.object(c, 'command', return_value='\n') as command:
            self.assertEqual(c.run(), 2)
        command.assert_called_once_with(['kubectl', 'config', 'current-context'])
        self.assertIn('current context', c.manifest['errors'][0])


if __name__ == '__main__':
    unittest.main()
