#!/usr/bin/env python3
"""Default compact RuClaw Pi profile; never writes configuration into the target repo."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

CONTEXT_NAMES = ('AGENTS.override.md', 'AGENTS.md', 'AGENTS.MD', 'CLAUDE.md', 'CLAUDE.MD')
ROOT = Path(__file__).resolve().parent
PROFILE_FILES = ('project.md', 'areas.md', 'testing.md')
DEFAULT_REPO = Path.home() / 'dev/croc/ruclaw'


def git_path(cwd, *args):
    result = subprocess.run(
        ['git', '-C', str(cwd), 'rev-parse', *args],
        check=True, capture_output=True, text=True,
    )
    return Path(result.stdout.strip()).resolve()


def context_file(directory):
    return next((directory / name for name in CONTEXT_NAMES
                 if (directory / name).is_file()), None)


def personal_context(repo, agent_dir):
    # Match Pi's per-directory precedence, but intentionally exclude repo files.
    candidates = [context_file(agent_dir)]
    candidates.extend(context_file(p) for p in reversed(repo.parents))
    return list(dict.fromkeys(p.resolve() for p in candidates if p))


def plan_cycle_root(root, env):
    candidates = [root.parent / 'pi-extensions/plan-cycle',
                  Path(env.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'pi-plan-cycle']
    for candidate in candidates:
        if all((candidate / name).is_file() for name in ('index.ts', 'core.ts')):
            return candidate.resolve()
    raise ValueError('Plan-cycle v2 extension missing; activate Guix Home or use the source checkout')


def make_plan(repo, root=ROOT, environ=None, legacy_cycles=False):
    env = dict(os.environ if environ is None else environ)
    root = root.expanduser().resolve()
    repo = repo.expanduser().resolve()
    if git_path(repo, '--show-toplevel') != repo:
        raise ValueError('Configured repo must be a Git checkout root')
    for name in PROFILE_FILES:
        path = root / 'profile' / name
        if not path.is_file():
            raise ValueError(f'Required profile file missing: {path}')
    agent_dir = Path(env.get('PI_CODING_AGENT_DIR', str(Path.home() / '.pi/agent'))).expanduser().resolve()
    globals_ = personal_context(repo, agent_dir)
    paths = [root, *globals_]
    if any('\n' in str(p) for p in paths):
        raise ValueError('Newline in profile/context path is unsupported')
    env['PI_RUCLAW_ROOT'] = str(root)
    env['PI_RUCLAW_GLOBALS'] = '\n'.join(map(str, globals_))
    extra = env.get('PI_SUBAGENT_EXTRA_AGENT_DIRS')
    env['PI_SUBAGENT_EXTRA_AGENT_DIRS'] = str(root / 'agents') + (os.pathsep + extra if extra else '')
    skills = root / 'skills'
    prompt_template = root / 'prompts/wait-what.md'
    if not prompt_template.is_file():
        raise ValueError(f'Required prompt template missing: {prompt_template}')
    subagents_skill = agent_dir / 'npm/node_modules/pi-subagents/skills/pi-subagents'
    if not (subagents_skill / 'SKILL.md').is_file():
        raise ValueError(f'pi-subagents skill missing: {subagents_skill}; install package before using pi-ruclaw')
    subagents = agent_dir / 'npm/node_modules/pi-subagents/index.js'
    if not subagents.is_file():
        raise ValueError(f'pi-subagents runtime missing: {subagents}')
    if legacy_cycles:
        cycles = root / 'extensions/work-cycles.ts'
        if not cycles.is_file():
            raise ValueError(f'Work-cycle extension missing: {cycles}')
    else:
        cycles = plan_cycle_root(root, env) / 'index.ts'
    args = ['pi', '--no-context-files', '--no-skills', '--no-prompt-templates',
            '--skill', str(skills), '--skill', str(subagents_skill),
            '--extension', str(subagents), '--extension', str(cycles),
            '--prompt-template', str(prompt_template)]
    compare_template = root / 'prompts/compare.md'
    if compare_template.is_file():
        args += ['--prompt-template', str(compare_template)]
    if legacy_cycles:
        args += ['--append-system-prompt',
                 'Legacy work-cycles recovery ONLY: continue the existing task through '
                 + str(root / 'skills/implement/references/resume.md')
                 + '. Do not invoke the new /skill:implement or plan_cycle_start/next. '
                 'Do not migrate task bases, permissions or gates silently.']
    args += ['--append-system-prompt',
             'RuClaw profile paths (external to the product checkout):\n'
             f'Profile root / PI_RUCLAW_ROOT: {root}\n'
             f'Area map: {root / "profile/areas.md"}\n'
             f'Test map: {root / "profile/testing.md"}\n'
             f'Bundled skills: {root / "skills"}\n'
             f'Product checkout: {repo}\n'
             'Use the absolute profile paths above with read; read does not expand '
             '$PI_RUCLAW_ROOT or shell variables. Never resolve profile areas.md or '
             'testing.md from the product checkout. Relative links in profile documents '
             'resolve beside their source file; code/repository paths refer to the checkout.']
    prompts = [*globals_, root / 'profile/project.md']
    if not legacy_cycles:
        prompts.append(root / 'profile/workflow.md')
    for path in prompts:
        if not path.is_file():
            raise ValueError(f'Required profile file missing: {path}')
        args += ['--append-system-prompt', str(path)]
    return repo, env, args, globals_


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--legacy-cycles', action='store_true')
    options, forwarded = parser.parse_known_args()
    try:
        if any(arg == '--worktree' or arg.startswith('--worktree=') for arg in forwarded):
            raise ValueError('--worktree is no longer supported; use the configured RuClaw checkout')
        target, env, args, globals_ = make_plan(DEFAULT_REPO, legacy_cycles=options.legacy_cycles)
        if options.check:
            print(json.dumps({
                'profile': str(ROOT / 'profile'), 'cwd': str(target),
                'personal_context': list(map(str, globals_)),
                'project_context_autoload': False,
                'agent_dir': str(ROOT / 'agents'),
                'skills': str(ROOT / 'skills'),
                'profile_files': [*PROFILE_FILES, *([] if options.legacy_cycles else ['workflow.md'])],
                'workflow': 'legacy-work-cycles' if options.legacy_cycles else 'plan-cycle-v2',
                'extensions': [args[i + 1] for i, arg in enumerate(args) if arg == '--extension'],
                'prompt_templates': [args[i + 1] for i, arg in enumerate(args) if arg == '--prompt-template'],
                'forwarded_arguments': len(forwarded),
            }, indent=2))
            return 0
        os.chdir(target)
        # Use the configured checkout's direnv approval/credentials.
        # env -u runs AFTER direnv, as in the original alias.
        command = ['direnv', 'exec', str(DEFAULT_REPO), 'env', '-u', 'LD_LIBRARY_PATH',
                   *args, *forwarded]
        os.execvpe(command[0], command, env)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f'pi-ruclaw: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
