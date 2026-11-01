#!/usr/bin/env python3
"""Offline pinned-source probes; no writes/Git ref changes in product checkouts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import time

CANDIDATES = {
    'lite': '8e8790416963fd8185df0aa40b7746badad8474a',
    'original': 'a9b5de71b3ecbe2c718313501177fc475c0070a1',
}
PROBES = {
    'selection_test.go': 'internal/agent/quality_probe_test.go',
    'polling_test.go': 'internal/credbroker/a2abroker/quality_probe_test.go',
    'envelope_test.go': 'internal/credbroker/server/quality_probe_test.go',
}
ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path, help='new retained evidence/export directory')
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.out.resolve()
    top = Path(subprocess.check_output(['git', '-C', str(repo), 'rev-parse', '--show-toplevel'], text=True).strip()).resolve()
    worktrees = subprocess.check_output(
        ['git', '-C', str(repo), 'worktree', 'list', '--porcelain', '-z'], text=True)
    roots = [Path(record[9:]).resolve() for record in worktrees.split('\0')
             if record.startswith('worktree ')]
    if any(out == root or root in out.parents for root in [top, *roots]):
        parser.error('output must be outside every product worktree')
    if out.exists():
        parser.error('output already exists; choose a fresh directory')
    go = shutil.which('go')
    if not go:
        parser.error('Go not found')
    # Keep the existing compiler/module caches, but not project credentials,
    # DSNs, model credentials, inherited stand settings or user Go config.
    gopath = subprocess.check_output([go, 'env', 'GOPATH'], text=True).strip()
    gocache = subprocess.check_output([go, 'env', 'GOCACHE'], text=True).strip()
    out.mkdir(parents=True)
    home = out / 'empty-home'
    home.mkdir()
    env = {key: os.environ[key] for key in ('PATH', 'TMPDIR', 'LANG') if key in os.environ}
    env.update(HOME=str(home), GOPATH=gopath, GOCACHE=gocache, GOWORK='off',
               GOENV='off', GOPROXY='off', GOSUMDB='off', GOTOOLCHAIN='local',
               GOFLAGS='', CGO_ENABLED='0', GOMAXPROCS='2')
    command = [go, 'test', '-tags=goolm', '-mod=readonly', '-p=2', '-count=1', '-json',
               '-timeout=30s', '-run=^TestQuality', './internal/agent',
               './internal/credbroker/a2abroker', './internal/credbroker/server']
    report = {'go': subprocess.check_output([go, 'version'], text=True).strip(),
              'command': command, 'network': 'GOPROXY off; owned ephemeral HTTP loopback and TLS private-interface fixtures; hostname resolution; not an OS sandbox',
              'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'shared_go_caches': True, 'probes': {}, 'candidates': {}}
    for name in PROBES:
        report['probes'][name] = hashlib.sha256((ROOT / 'probes' / name).read_bytes()).hexdigest()
    for label, sha in CANDIDATES.items():
        resolved = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', f'{sha}^{{commit}}'], text=True).strip()
        if resolved != sha:
            raise RuntimeError('unexpected commit resolution')
        archive, dest = out / f'{label}.tar', out / label
        with archive.open('wb') as stream:
            subprocess.run(['git', '-C', str(repo), 'archive', sha], stdout=stream, check=True)
        archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
        dest.mkdir()
        with tarfile.open(archive) as source:
            source.extractall(dest, filter='data')
        # Only our newly created archive, not user data or an existing checkout.
        archive.unlink()
        for name, target in PROBES.items():
            path = dest / target
            if path.exists():
                raise RuntimeError(f'refusing to overwrite existing source: {target}')
            shutil.copyfile(ROOT / 'probes' / name, path)
        started = time.monotonic()
        log = out / f'{label}.jsonl'
        with log.open('w') as stream:
            try:
                result = subprocess.run(command, cwd=dest, env=env, stdout=stream,
                                        stderr=subprocess.STDOUT, timeout=240)
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = 124
        tests, failures, skipped = {}, [], []
        for line in log.read_text().splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            test, action = event.get('Test'), event.get('Action')
            if test and action in ('pass', 'fail', 'skip'):
                tests[f"{event['Package']}::{test}"] = action
            if action == 'output':
                text = event.get('Output', '').strip()
                if 'quality_probe_test.go:' in text:
                    failures.append(text)
            if action == 'skip':
                skipped.append(test or event.get('Package'))
        required = {
            'ruclaw/internal/agent::TestQualityFinalSelectionAfterTool',
            'ruclaw/internal/credbroker/a2abroker::TestQualityPollingProgressBeforeRelease',
            'ruclaw/internal/credbroker/server::TestQualityContextlessHTTPEnvelope',
        }
        coverage_ok = required.issubset(tests) and len(tests) == 15 and not skipped
        report['candidates'][label] = {'sha': sha, 'archive_sha256': archive_hash,
            'exit_code': code, 'coverage_ok': coverage_ok,
            'seconds': round(time.monotonic() - started, 2),
            'tests': tests, 'diagnostics': failures, 'skipped': skipped}
        (out / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
        print(label, 'exit=', code, 'test outcomes=', len(tests), flush=True)
    # Fail closed for infrastructure/build failure as well as real regressions.
    ok = all(row['exit_code'] == 0 and row['coverage_ok']
             for row in report['candidates'].values())
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
