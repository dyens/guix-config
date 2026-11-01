import importlib.util
import json
import os
from io import StringIO
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ruclaw_lite_launch', ROOT / 'launch.py')
assert spec and spec.loader
launch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launch)


class LiteLauncherTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.primary = self.root / 'main'
        self.primary.mkdir()
        self.git(self.primary, 'init', '-q', '-b', 'feature')
        self.git(self.primary, 'config', 'user.name', 'test')
        self.git(self.primary, 'config', 'user.email', 'test@example.invalid')
        self.git(self.primary, 'commit', '--allow-empty', '-qm', 'fixture')
        self.target = self.root / 'experiment'
        self.git(self.primary, 'worktree', 'add', '-qb', 'experiment/pi-lite-test', str(self.target))
        self.agent = self.root / 'agent'
        native = self.agent / 'npm/node_modules/pi-subagents'
        native.mkdir(parents=True)
        (native / 'index.js').write_text('// fixture')
        (self.agent / 'AGENTS.md').write_text('PERSONAL')
        self.env = {'PATH': os.environ['PATH'], 'PI_CODING_AGENT_DIR': str(self.agent)}

    def git(self, cwd, *args):
        return subprocess.check_output(['git', '-C', str(cwd), *args], text=True, stderr=subprocess.PIPE).strip()

    def plan(self, path=None):
        return launch.make_plan(path or self.target, primary=self.primary, environ=self.env)

    def test_main_checkout_refused_without_switching_branch(self):
        before = self.git(self.primary, 'rev-parse', 'HEAD')
        with self.assertRaisesRegex(ValueError, 'separate registered'):
            self.plan(self.primary)
        self.assertEqual(self.git(self.primary, 'branch', '--show-current'), 'feature')
        self.assertEqual(self.git(self.primary, 'rev-parse', 'HEAD'), before)

    def test_different_repository_refused(self):
        other = self.root / 'other'
        other.mkdir()
        self.git(other, 'init', '-q')
        with self.assertRaisesRegex(ValueError, 'configured RuClaw'):
            self.plan(other)

    def test_non_experiment_branch_refused(self):
        self.git(self.target, 'branch', '-m', 'normal-feature')
        with self.assertRaisesRegex(ValueError, 'experiment/pi-lite'):
            self.plan()

    def test_only_lite_resources_no_cycle_or_generic_guide_skill(self):
        target, env, args, branch, personal = self.plan()
        self.assertEqual(target, self.target)
        self.assertEqual(branch, 'experiment/pi-lite-test')
        self.assertIn(self.agent / 'AGENTS.md', personal)
        self.assertEqual(env['PI_SUBAGENT_EXTRA_AGENT_DIRS'], str(ROOT / 'agents'))
        self.assertEqual(env['PI_RUCLAW_ROOT'], str(ROOT.parent))
        self.assertIn(str(ROOT / 'skills'), args)
        self.assertIn('--no-context-files', args)
        self.assertIn('--no-skills', args)
        self.assertIn('--prompt-template', args)
        self.assertIn(str(ROOT / 'prompts/lite-acceptance.md'), args)
        self.assertFalse(any('work-cycles' in a for a in args))
        self.assertFalse(any('skills/pi-subagents' in a for a in args))
        self.assertNotIn('PI_RUCLAW_ROOT', self.env)
        self.assertFalse((target / '.scratch').exists())

    def test_missing_runtime_fails(self):
        (self.agent / 'npm/node_modules/pi-subagents/index.js').unlink()
        with self.assertRaisesRegex(ValueError, 'runtime file missing'):
            self.plan()

    def test_missing_evaluator_fails_before_launch(self):
        original = Path.is_file
        with patch.object(Path, 'is_file', lambda p: False if p == ROOT / 'agents/lite-evaluator.md' else original(p)):
            with self.assertRaisesRegex(ValueError, 'lite-evaluator.md'):
                self.plan()
        self.assertFalse((self.target / '.scratch').exists())

    def test_check_is_read_only(self):
        output = StringIO()
        with patch.object(launch, 'PRIMARY', self.primary), patch.dict(os.environ, self.env), \
             patch.object(sys, 'argv', ['launch.py', '--worktree', str(self.target), '--check']), \
             patch('sys.stdout', output):
            self.assertEqual(launch.main(), 0)
        info = json.loads(output.getvalue())
        self.assertEqual(info['cwd'], str(self.target))
        self.assertEqual(info['profile_revision'], 'lite-v3-acceptance-first')
        self.assertFalse((self.target / '.scratch').exists())

    def test_cwd_profile_env_restored_after_direnv_and_ld_removed(self):
        binaries = self.root / 'bin'
        binaries.mkdir()
        for name, body in {
            'direnv': 'import os,sys; os.chdir(sys.argv[2]); os.environ["PI_RUCLAW_LAB_ROOT"]="wrong-profile"; os.execvp(sys.argv[3],sys.argv[3:])',
            'pi': 'import os,json; print(json.dumps({"cwd":os.getcwd(),"ld_present":"LD_LIBRARY_PATH" in os.environ,"profile":os.environ.get("PI_RUCLAW_LAB_ROOT")}))',
        }.items():
            p = binaries / name
            p.write_text(f'#!{sys.executable}\n{body}\n')
            p.chmod(0o700)
        cmd = launch.command(self.target, ['pi'], primary=self.primary,
                             profile_env={'PI_RUCLAW_LAB_ROOT': 'expected-profile'})
        result = subprocess.check_output(cmd, text=True, env={**os.environ,
            'PATH': str(binaries) + os.pathsep + os.environ['PATH'], 'LD_LIBRARY_PATH': '/unused-fixture'})
        self.assertEqual(json.loads(result), {'cwd': str(self.target), 'ld_present': False, 'profile': 'expected-profile'})


if __name__ == '__main__':
    unittest.main()
