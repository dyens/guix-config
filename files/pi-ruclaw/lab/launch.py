#!/usr/bin/env python3
"""Opt-in continuous-context RuClaw experiment; only in an experiment worktree."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone
from uuid import uuid4

ROOT = Path(__file__).resolve().parent
SHARED = ROOT.parent
PRIMARY = Path.home() / 'dev/croc/ruclaw'
spec = importlib.util.spec_from_file_location('_ruclaw_personal_context', SHARED / 'launch.py')
assert spec is not None and spec.loader is not None
shared = importlib.util.module_from_spec(spec)
bytecode = sys.dont_write_bytecode
try:
    sys.dont_write_bytecode = True  # Do not add generated files to the Guix source tree.
    spec.loader.exec_module(shared)
finally:
    sys.dont_write_bytecode = bytecode


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), 'rev-parse', *args], text=True, stderr=subprocess.PIPE).strip()


def make_plan(worktree, primary=PRIMARY, environ=None):
    env = dict(os.environ if environ is None else environ)
    target, primary = worktree.expanduser().resolve(), primary.expanduser().resolve()
    if target == primary or Path(git(target, '--show-toplevel')).resolve() != target:
        raise ValueError('Use a separate registered experiment worktree, not the active primary checkout')
    common = lambda p: Path(git(p, '--path-format=absolute', '--git-common-dir')).resolve()
    if common(target) != common(primary):
        raise ValueError('Worktree must belong to the configured RuClaw repository')
    branch = git(target, '--abbrev-ref', 'HEAD')
    if not branch.startswith('experiment/pi-lite-'):
        raise ValueError('Use an experiment/pi-lite-* branch; never switch the active feature branch')
    agent_dir = Path(env.get('PI_CODING_AGENT_DIR', str(Path.home() / '.pi/agent'))).expanduser().resolve()
    subagents = agent_dir / 'npm/node_modules/pi-subagents/index.js'
    files = [ROOT / 'policy.md', ROOT / 'workflows/review.js', ROOT / 'prompts/lite-review.md',
             ROOT / 'workflows/prepare.js', ROOT / 'prompts/lite-acceptance.md', ROOT / 'scripts/acceptance.py',
             ROOT / 'skills/lite-implement/SKILL.md', ROOT / 'skills/lite-spec/SKILL.md',
             ROOT / 'agents/lite-reviewer.md', ROOT / 'agents/lite-evaluator.md',
             subagents, *[SHARED / 'profile' / n for n in shared.PROFILE_FILES]]
    for path in files:
        if not path.is_file():
            raise ValueError(f'Required profile/runtime file missing: {path}')
    personal = shared.personal_context(primary, agent_dir)
    if any('\n' in str(p) for p in [target, ROOT, *personal]):
        raise ValueError('Newline in profile/context path is unsupported')
    env.update(PI_CODING_AGENT_DIR=str(agent_dir), PI_RUCLAW_ROOT=str(SHARED), PI_RUCLAW_LAB_ROOT=str(ROOT),
               PI_RUCLAW_GLOBALS='\n'.join(map(str, personal)),
               PI_SUBAGENT_EXTRA_AGENT_DIRS=str(ROOT / 'agents'))
    # Explicit resources only: no old implement/cycle extension or generic API-guide skill.
    # The existing native runtime owns subagent execution; no extra registry dependency.
    args = ['pi', '--no-context-files', '--no-skills', '--no-prompt-templates',
            '--skill', str(ROOT / 'skills'), '--prompt-template', str(ROOT / 'prompts/lite-review.md'),
            '--prompt-template', str(ROOT / 'prompts/lite-acceptance.md'),
            '--extension', str(subagents)]
    for path in [*personal, SHARED / 'profile/project.md', ROOT / 'policy.md']:
        args += ['--append-system-prompt', str(path)]
    return target, env, args, branch, personal


def command(target, args, primary=PRIMARY, profile_env=None):
    # direnv may change cwd. Restore the worktree AFTER loading primary credentials.
    # No shell interpolation, env dump, copied .envrc or global configuration changes.
    enter = 'import os,sys; os.chdir(sys.argv[1]); os.execvp(sys.argv[2],sys.argv[2:])'
    settings = [f'{key}={value}' for key, value in (profile_env or {}).items()]
    return ['direnv', 'exec', str(primary), 'env', '-u', 'LD_LIBRARY_PATH', *settings,
            sys.executable, '-c', enter, str(target), *args]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--worktree', type=Path, required=True)
    parser.add_argument('--check', action='store_true')
    options, forwarded = parser.parse_known_args()
    try:
        target, env, args, branch, personal = make_plan(options.worktree, primary=PRIMARY)
        info = {'profile': 'pi-ruclaw-lite', 'profile_revision': 'lite-v3-acceptance-first',
                'cwd': str(target), 'branch': branch,
                'starting_head': git(target, 'HEAD'), 'credentials_cwd': str(PRIMARY),
                'context_resets': False, 'compaction': 'native settings, unchanged',
                'personal_context': list(map(str, personal)), 'publication': 'not authorized by profile'}
        if options.check:
            print(json.dumps(info, indent=2))
            return 0
        runs = target / '.scratch/pi-lite/runs'
        runs.mkdir(parents=True, exist_ok=True)
        receipt = runs / f'{uuid4()}.json'
        receipt.write_text(json.dumps({**info, 'started_at': datetime.now(timezone.utc).isoformat()}, indent=2))
        env['PI_RUCLAW_LAB_RUN'] = str(receipt)
        os.chdir(target)
        keys = ('PI_CODING_AGENT_DIR', 'PI_RUCLAW_ROOT', 'PI_RUCLAW_LAB_ROOT',
                'PI_RUCLAW_GLOBALS', 'PI_SUBAGENT_EXTRA_AGENT_DIRS', 'PI_RUCLAW_LAB_RUN')
        cmd = command(target, [*args, *forwarded], primary=PRIMARY,
                      profile_env={key: env[key] for key in keys})
        os.execvpe(cmd[0], cmd, env)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f'pi-ruclaw-lite: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
