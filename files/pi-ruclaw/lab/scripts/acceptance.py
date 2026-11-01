#!/usr/bin/env python3
"""Freeze/replay contract integrity and aggregate declared case results; no test execution or sandbox."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def inventory(root):
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise ValueError('suite must be a real directory')
    files = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError('symlinks are not allowed in a frozen suite')
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError('suite contains a non-regular file')
        files[path.relative_to(root).as_posix()] = sha(path.read_bytes())
    for name in ('criteria.json', 'authority.md', 'run.md'):
        if name not in files or not (root / name).read_text().strip():
            raise ValueError(f'missing/nonempty required suite file: {name}')
    return files


def validate_plan(root, base, files):
    plan = json.loads((root / 'criteria.json').read_text())
    if not isinstance(plan, dict) or plan.get('baseSha') != base or not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', base):
        raise ValueError('base SHA mismatch or unresolved base')
    criteria = plan.get('criteria')
    if not isinstance(criteria, list) or not criteria:
        raise ValueError('criteria must enumerate approved IDs')
    ids, cases = set(), set()
    for row in criteria:
        if not isinstance(row, dict) or not isinstance(row.get('id'), str) or not row['id'].strip() or row['id'] in ids:
            raise ValueError('missing/duplicate criterion ID')
        ids.add(row['id'])
        if row.get('tier') not in ('requirement', 'delivery'):
            raise ValueError('criterion needs an explicit requirement/delivery tier')
        if any(not isinstance(row.get(k), str) or not row[k].strip() for k in ('boundary', 'expected')):
            raise ValueError('criterion needs observable outcome and actual boundary')
        checks = row.get('cases')
        if not isinstance(checks, list) or not checks:
            raise ValueError('criterion needs cases, not only source reasoning')
        polarities = set()
        for case in checks:
            if not isinstance(case, dict) or not isinstance(case.get('id'), str) or not case['id'].strip() or case['id'] in cases:
                raise ValueError('missing/duplicate case ID')
            cases.add(case['id'])
            if case.get('polarity') not in ('positive', 'negative') or case.get('baseline') not in ('pass', 'fail', 'blocked'):
                raise ValueError('case needs polarity and truthful baseline status')
            polarities.add(case['polarity'])
            evidence = case.get('evidence')
            if not isinstance(evidence, str) or PurePosixPath(evidence).is_absolute() or '..' in PurePosixPath(evidence).parts or evidence not in files:
                raise ValueError('case needs baseline evidence inside suite')
            if not isinstance(case.get('reason'), str) or not case['reason'].strip():
                raise ValueError('case needs intended failure/control or blocker reason')
        if polarities != {'positive', 'negative'}:
            raise ValueError('criterion needs a positive control and a negative scenario')
    return plan


def freeze(suite, seal, base):
    suite, seal = Path(suite).absolute(), Path(seal).absolute()
    if suite != suite.resolve() or seal != seal.resolve():
        raise ValueError('use canonical paths without symlink parents')
    if suite == seal or suite in seal.parents:
        raise ValueError('seal must be outside the suite')
    files = inventory(suite)
    validate_plan(suite, base, files)
    body = (json.dumps({'version': 1, 'suite': str(suite), 'baseSha': base, 'files': files},
                       sort_keys=True, indent=2) + '\n').encode()
    # Never silently replace an earlier contract. Amendment needs a NEW seal/anchor.
    with seal.open('xb') as stream:
        stream.write(body)
    return sha(body)


def verify(seal, anchor, base, copy=None):
    seal = Path(seal)
    if seal.is_symlink() or seal.absolute() != seal.resolve():
        raise ValueError('seal must use a canonical non-symlink path')
    raw = seal.read_bytes()
    if not re.fullmatch(r'[0-9a-f]{64}', anchor) or sha(raw) != anchor:
        raise ValueError('seal SHA256 mismatch: do not replace the original anchor')
    record = json.loads(raw)
    if not isinstance(record, dict) or record.get('version') != 1 or record.get('baseSha') != base:
        raise ValueError('contract version/base mismatch')
    suite = Path(record['suite'])
    if suite != suite.resolve():
        raise ValueError('suite path changed')
    files = inventory(suite)
    if record.get('files') != files:
        raise ValueError('frozen suite changed (including added/deleted files)')
    validate_plan(suite, base, files)
    if copy is not None:
        copied = Path(copy)
        if copied.absolute() != copied.resolve() or inventory(copied) != files:
            raise ValueError('execution copy differs from the frozen suite')
        return copied
    return suite


def judge(seal, anchor, base, candidate, results):
    suite = verify(seal, anchor, base)
    if not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', candidate):
        raise ValueError('resolve candidate SHA')
    plan = json.loads((suite / 'criteria.json').read_text())
    expected = {case['id']: row['tier'] for row in plan['criteria'] for case in row['cases']}
    results = Path(results)
    if results.is_symlink() or results.absolute() != results.resolve():
        raise ValueError('results must use a canonical non-symlink path')
    record = json.loads(results.read_text())
    if not isinstance(record, dict) or record.get('candidateSha') != candidate or record.get('sealSha256') != anchor:
        raise ValueError('result candidate/anchor mismatch')
    actual = {}
    for case in record.get('cases', []):
        if not isinstance(case, dict) or case.get('id') not in expected or case['id'] in actual:
            raise ValueError('unknown/duplicate result case')
        if case.get('status') not in ('pass', 'fail', 'blocked', 'skip'):
            raise ValueError('case result must be pass/fail/blocked/skip')
        evidence = case.get('evidence')
        if not isinstance(evidence, str) or PurePosixPath(evidence).is_absolute() or '..' in PurePosixPath(evidence).parts:
            raise ValueError('result needs local evidence path')
        file = results.parent / evidence
        if file.resolve() != file.absolute() or not file.is_file() or not file.stat().st_size:
            raise ValueError('missing/non-regular result evidence or symlink')
        actual[case['id']] = case['status']
    if set(actual) != set(expected):
        raise ValueError('missing frozen case results; no subset acceptance')
    required = [actual[key] for key, tier in expected.items() if tier == 'requirement']
    delivery = [actual[key] for key, tier in expected.items() if tier == 'delivery']
    return {'candidateSha': candidate, 'sealSha256': anchor,
            'requirement_acceptance': 'met' if required and all(s == 'pass' for s in required) else 'not_met',
            'declared_delivery_checks': 'pass' if delivery and all(s == 'pass' for s in delivery) else 'pending',
            'production_readiness': 'not_established',
            'notice': 'Aggregates declared outcomes; does not prove execution, assertion quality or complete delivery gates.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['freeze', 'verify', 'judge'])
    parser.add_argument('--suite', type=Path, help='source for freeze; optional exact execution copy for verify')
    parser.add_argument('--seal', type=Path, required=True)
    parser.add_argument('--base', required=True)
    parser.add_argument('--sha', help='original anchor printed by freeze, not a freshly computed hash')
    parser.add_argument('--results', type=Path, help='candidate case result JSON for judge')
    parser.add_argument('--candidate', help='exact candidate SHA for judge')
    args = parser.parse_args()
    try:
        if args.action == 'freeze':
            if args.suite is None:
                parser.error('--suite is required to freeze')
            print(freeze(args.suite, args.seal, args.base))
        else:
            if args.sha is None:
                parser.error('--sha is required to verify')
            if args.action == 'verify':
                print(verify(args.seal, args.sha, args.base, args.suite))
            else:
                if args.suite is not None:
                    parser.error('use verify --suite for an execution copy, not judge')
                if args.results is None or args.candidate is None:
                    parser.error('--results and --candidate are required to judge')
                verdict = judge(args.seal, args.sha, args.base, args.candidate, args.results)
                print(json.dumps(verdict, sort_keys=True))
                return 0 if verdict['requirement_acceptance'] == 'met' else 1
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'acceptance: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
