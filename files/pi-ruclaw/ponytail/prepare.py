#!/usr/bin/env python3
"""Create an opt-in frozen Ponytail overlay; never edit the source profile/repo."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(destination, source=HERE.parent):
    destination, source = Path(destination).resolve(), Path(source).resolve()
    vendor = HERE / 'vendor'
    provenance = json.loads((vendor / 'provenance.json').read_text())
    for item in provenance['files']:
        if digest(vendor / item['path']) != item['sha256']:
            raise ValueError(f"Upstream content changed: {item['path']}")
    implement = (source / 'skills/implement/SKILL.md').read_text()
    title = '# Implement — plan-cycle v2 (default)\n'
    if implement.count(title) != 1:
        raise ValueError('Unsupported implement skill: expected current plan-cycle v2')
    implement = implement.replace(title, '# Implement — plan-cycle v2 + Ponytail full\n\n'
        'Before intake/checkpoint 0 read `../ponytail/SKILL.md` IN FULL and use level full.\n'
        'It replaces default code-design policy; the process below stays unchanged.\n')
    safeguards = (source / 'skills/implement/references/plan-cycle.md').read_text()
    start, end = '## Design and checks\n', '## Docker and resources\n'
    if safeguards.count(start) != 1 or safeguards.count(end) != 1:
        raise ValueError('Unsupported safeguards: cannot isolate the old design policy')
    before, section = safeguards.split(start)
    design, after = section.split(end)
    marker = 'During fixes run affected regressions.'
    if design.count(marker) != 1:
        raise ValueError('Unsupported safeguards: cannot preserve check-evidence rules')
    equivalence = marker + design.split(marker)[1]
    safeguards = (before + '## Code policy and check entry points\n\n'
        'Use skills/ponytail/SKILL.md (full) for code and ponytail-review for review,\n'
        'instead of the original design/checklist paragraph. The original task and\n'
        'its required checks still apply. profile/testing.md supplies command and\n'
        'execution-topology facts; inspect the actual recipes before running them.\n\n'
        + equivalence + end + after)
    engine = source.parent / 'pi-extensions/plan-cycle'
    if not engine.is_dir():
        engine = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'pi-plan-cycle'
    for path in [source / 'launch.py', engine / 'core.ts', engine / 'index.ts']:
        if not path.is_file():
            raise ValueError(f'Required source missing: {path}')
    destination.mkdir(parents=True, exist_ok=False)
    runtime = destination / 'pi-ruclaw'
    runtime.mkdir()
    shutil.copyfile(source / 'launch.py', runtime / 'launch.py')
    ignore = shutil.ignore_patterns('__pycache__', '*.pyc', 'node_modules')
    for folder in ('profile', 'skills', 'agents', 'prompts'):
        shutil.copytree(source / folder, runtime / folder, ignore=ignore)
    shutil.copytree(engine, destination / 'pi-extensions/plan-cycle', ignore=ignore)
    for path in (HERE / 'overrides').rglob('*'):
        if path.is_file():
            target = runtime / path.relative_to(HERE / 'overrides')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
    for name in ('ponytail', 'ponytail-review'):
        shutil.copytree(vendor / 'skills' / name, runtime / 'skills' / name)
    shutil.copyfile(vendor / 'LICENSE', runtime / 'PONYTAIL-LICENSE')
    (runtime / 'skills/implement/SKILL.md').write_text(implement)
    (runtime / 'skills/implement/references/plan-cycle.md').write_text(safeguards)
    # Do not leave the alternate legacy review role as a second code-policy route.
    role = (runtime / 'agents/plan-reviewer.md').read_text()
    (runtime / 'agents/reviewer.md').write_text(role.replace(
        'name: ruclaw-plan-reviewer\n', 'name: ruclaw-reviewer\n', 1))
    workflow = runtime / 'profile/workflow.md'
    workflow.write_text(workflow.read_text() + '\nCode policy for this runtime is pinned Ponytail full;\n'
        'review policy is pinned ponytail-review, NOT the default RuClaw checklists.\n')
    manifest = {'variant': 'plan-cycle-v2-ponytail-full', 'source': str(source),
        'upstream': provenance, 'changes': [
            'neutral project/navigation context instead of architecture/design directives',
            'ponytail full before checkpoint 0 instead of the default design paragraph',
            'ponytail-review instead of default code-review and both reviewer-role checklists',
            'upstream review format with short artifact index; native safety policy unchanged'],
        'files': [{'path': str(p.relative_to(destination)), 'sha256': digest(p)}
                  for p in sorted(destination.rglob('*')) if p.is_file()]}
    (runtime / 'ponytail-runtime.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return runtime


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path, help='new, nonexistent runtime directory')
    parser.add_argument('--source', type=Path, default=HERE.parent,
                        help='base profile to freeze (default: sibling source profile)')
    options = parser.parse_args()
    print(prepare(options.destination, options.source))
