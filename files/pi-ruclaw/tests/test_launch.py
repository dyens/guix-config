import importlib.util
import json
import os
from io import StringIO
import re
import shlex
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ruclaw_launch', ROOT / 'launch.py')
assert spec is not None and spec.loader is not None
launch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launch)


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.repo = self.base / 'ruclaw'
        self.repo.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.repo / 'CLAUDE.md').write_text('TEAM_CANARY\n')
        (self.repo / 'docs/agents').mkdir(parents=True)
        (self.repo / 'docs/agents/workflow.md').write_text('workflow\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'test fixture')
        self.config = self.base / 'pi-ruclaw'
        self.profile = self.config / 'profile'
        self.profile.mkdir(parents=True)
        for name in launch.PROFILE_FILES:
            (self.profile / name).write_text(f'PROFILE_CANARY {name}\n')
        (self.profile / 'workflow.md').write_text('PLAN_CYCLE_DEFAULT\n')
        (self.config / 'agents').mkdir()
        (self.config / 'skills').mkdir()
        (self.config / 'prompts').mkdir()
        (self.config / 'prompts/wait-what.md').write_text('Explain clearly\n')
        (self.config / 'extensions').mkdir()
        (self.config / 'extensions/work-cycles.ts').write_text('// test fixture')
        self.agent_dir = self.base / 'agent'
        skill = self.agent_dir / 'npm/node_modules/pi-subagents/skills/pi-subagents'
        skill.mkdir(parents=True)
        (skill / 'SKILL.md').write_text('test')
        (self.agent_dir / 'AGENTS.md').write_text('PERSONAL_CANARY\n')
        (self.base / 'AGENTS.md').write_text('PARENT_PERSONAL_CANARY\n')
        (self.agent_dir / 'npm/node_modules/pi-subagents/index.js').write_text('// runtime fixture')
        self.extension_dir = self.base / 'pi-extensions/plan-cycle'
        self.extension_dir.mkdir(parents=True)
        for name in ('index.ts', 'core.ts', 'tasks.ts'):
            (self.extension_dir / name).write_text('// plan-cycle fixture')
        self.env = {'PATH': os.environ['PATH'], 'PI_CODING_AGENT_DIR': str(self.agent_dir),
                    'XDG_CONFIG_HOME': str(self.base / 'xdg')}

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.repo), *args], check=True,
                              capture_output=True, text=True)

    def plan(self):
        return launch.make_plan(self.repo, self.config, self.env)

    def test_aliases_launch_pi_and_runner_and_forward_arguments(self):
        source = (ROOT.parents[1] / 'home/base.scm').read_text()
        aliases = dict(re.findall(r'\("(pi-ruclaw(?:-[a-z]+)?)"\s*\.\s*"([^"]+)"\)', source))
        self.assertEqual(set(aliases), {'pi-ruclaw', 'pi-ruclaw-runner', 'pi-ruclaw-lite'})
        self.assertEqual(aliases['pi-ruclaw-lite'], 'python3 /home/dyens/.config/pi-ruclaw/lab/launch.py')
        self.assertEqual(aliases['pi-ruclaw'], 'python3 /home/dyens/.config/pi-ruclaw/launch.py')
        self.assertEqual(aliases['pi-ruclaw-runner'], 'python3 /home/dyens/.config/pi-ruclaw/runner/run.py')
        script = ('shopt -s expand_aliases\n'
                  'python3() { printf "%s\\n" "$@"; }\n'
                  f'alias pi-ruclaw-runner={shlex.quote(aliases["pi-ruclaw-runner"])}\n'
                  'pi-ruclaw-runner .scratch/RCL-123 --only 01,02\n')
        output = subprocess.check_output(['bash', '--noprofile', '--norc', '-c', script], text=True)
        self.assertEqual(output.splitlines(), ['/home/dyens/.config/pi-ruclaw/runner/run.py', '.scratch/RCL-123', '--only', '01,02'])

    def test_main_preserves_personal_context_and_uses_new_layout(self):
        target, env, args, personal = self.plan()
        self.assertEqual(target, self.repo)
        self.assertIn((self.agent_dir / 'AGENTS.md').resolve(), personal)
        self.assertIn((self.base / 'AGENTS.md').resolve(), personal)
        self.assertNotIn(self.repo / 'CLAUDE.md', personal)
        for flag in ['--no-context-files', '--no-skills', '--no-prompt-templates']:
            self.assertIn(flag, args)
        self.assertEqual(args.count('--prompt-template'), 1)
        self.assertEqual(args[args.index('--prompt-template') + 1], str(self.config / 'prompts/wait-what.md'))
        self.assertEqual(args.count('--extension'), 2)
        self.assertIn(str(self.extension_dir / 'index.ts'), args)
        self.assertNotIn(str(self.config / 'extensions/work-cycles.ts'), args)
        self.assertIn(str(self.profile / 'project.md'), args)
        self.assertIn(str(self.profile / 'workflow.md'), args)
        for name in ('areas.md', 'testing.md'):
            self.assertNotIn(str(self.profile / name), args)
        self.assertFalse((self.profile / 'sources.json').exists())
        self.assertIn(str(self.config / 'skills'), args)
        self.assertEqual(env['PI_RUCLAW_ROOT'], str(self.config))
        self.assertEqual(env['PI_SUBAGENT_EXTRA_AGENT_DIRS'], str(self.config / 'agents'))
        self.assertNotIn('PI_RUCLAW_ROOT', self.env)
        self.assertFalse((self.repo / '.pi').exists())

    def test_profile_navigation_uses_absolute_external_paths_without_preloading_maps(self):
        (self.repo / 'areas.md').write_text('WRONG_CHECKOUT_MAP')
        (self.repo / 'testing.md').write_text('WRONG_CHECKOUT_TESTS')
        for layout in ('source', 'installed'):
            root = self.config if layout == 'source' else self.config.rename(self.base / 'store runtime')
            for legacy in (False, True):
                args = launch.make_plan(self.repo, root, self.env, legacy_cycles=legacy)[2]
                appended = [args[i + 1] for i, arg in enumerate(args) if arg == '--append-system-prompt']
                navigation = next(text for text in appended if text.startswith('RuClaw profile paths'))
                self.assertIn(f'Profile root / PI_RUCLAW_ROOT: {root}', navigation)
                for label, name in [('Area map', 'areas.md'), ('Test map', 'testing.md')]:
                    path = str(root / 'profile' / name)
                    self.assertIn(f'{label}: {path}', navigation)
                    self.assertNotIn(path, args, 'navigation maps must remain selectively read, not startup context')
                    self.assertNotIn(f'{label}: {self.repo / name}', navigation)
                self.assertIn('read does not expand', navigation)
                self.assertIn('external to the product checkout', navigation)
                self.assertNotIn('WRONG_CHECKOUT_MAP', navigation)

    def test_loaded_implement_policy_has_bounded_standing_user_authority(self):
        workflow = (ROOT / 'profile/workflow.md').read_text()
        implement = (ROOT / 'skills/implement/SKILL.md').read_text()
        git_policy = (ROOT / 'skills/git-workflow/SKILL.md').read_text()
        safeguards = (ROOT / 'skills/implement/references/plan-cycle.md').read_text()
        self.assertIn('Standing USER permission for implement', workflow)
        self.assertIn('Do not ask again within these bounds', workflow)
        self.assertIn('restrictions/revocations override defaults', workflow)
        self.assertIn('Ordinary LOCAL commits', implement)
        self.assertIn('Local Docker/Compose for isolated task-owned', implement)
        self.assertIn('No default permission for push/MR publication', implement)
        self.assertIn('only owned paths/hunks', implement)
        self.assertIn('develop/main/release', implement)
        for boundary in ('global prune', 'volume deletion', 'persistent-data resets', 'privileged'):
            self.assertIn(boundary, implement)
        self.assertIn('standing USER permission', git_policy)
        self.assertIn('Review/advisory requests do not activate implement defaults', git_policy)
        self.assertIn('Standing USER permission for implement permits local Docker/Compose', safeguards)
        self.assertNotIn('commits and remote publication need real user authority', safeguards)
        self.assertNotIn('Commit/push/rebase/force-push require', git_policy)

    def test_compare_template_is_loaded_when_available(self):
        template = self.config / 'prompts/compare.md'
        template.write_text('Compare two sessions\n')
        args = self.plan()[2]
        templates = [args[i + 1] for i, arg in enumerate(args) if arg == '--prompt-template']
        self.assertEqual(templates, [str(self.config / 'prompts/wait-what.md'), str(template)])
        service = (ROOT.parents[1] / 'home/pi.scm').read_text()
        self.assertIn('.pi/agent/prompts/compare.md', service)
        self.assertIn('.pi/agent/skills/compare', service)

    def test_incident_template_is_loaded_and_deployed_with_collector(self):
        template = self.config / 'prompts/ruclaw-incident.md'
        template.write_text('Collect session diagnostics\n')
        args = self.plan()[2]
        templates = [args[i + 1] for i, arg in enumerate(args) if arg == '--prompt-template']
        self.assertEqual(templates, [str(self.config / 'prompts/wait-what.md'), str(template)])
        service = (ROOT.parents[1] / 'home/pi.scm').read_text()
        self.assertIn('.pi/agent/prompts/ruclaw-incident.md', service)
        self.assertIn('../files/pi-ruclaw/prompts/ruclaw-incident.md', service)
        self.assertIn('(local-file "../files/pi-ruclaw" "pi-ruclaw" #:recursive? #t)', service)
        content = (ROOT / 'prompts/ruclaw-incident.md').read_text()
        for fragment in ('argument-hint:', '$1', '$2', '$3', 'PI_RUCLAW_ROOT',
                         'diagnostics/collect-session.py', 'manifest.json', 'summary.json',
                         'Exit 2', 'Не дублируй сбор ручными', 'best effort'):
            self.assertIn(fragment, content)
        self.assertTrue((ROOT / 'diagnostics/collect-session.py').is_file())

    def test_missing_prompt_template_fails_before_launch(self):
        (self.config / 'prompts/wait-what.md').unlink()
        with self.assertRaisesRegex(ValueError, 'Required prompt template missing'):
            self.plan()

    def test_missing_plan_extension_fails_before_launch(self):
        for name in ('index.ts', 'core.ts', 'tasks.ts'):
            path = self.extension_dir / name
            content = path.read_text()
            path.unlink()
            with self.assertRaisesRegex(ValueError, 'Plan-cycle v2 extension missing'):
                self.plan()
            path.write_text(content)

    def test_installed_xdg_layout_and_guix_service(self):
        installed = self.base / 'xdg/pi-plan-cycle'
        installed.parent.mkdir()
        self.extension_dir.rename(installed)
        self.assertIn(str(installed / 'index.ts'), self.plan()[2])
        service = (ROOT.parents[1] / 'home/pi.scm').read_text()
        self.assertIn('pi-plan-cycle-runtime', service)
        self.assertIn('../files/pi-extensions/plan-cycle', service)
        self.assertIn('.pi/agent/prompts/wait-what.md', service)
        self.assertIn('../files/pi-ruclaw/prompts/wait-what.md', service)
        self.assertNotIn('.pi/agent/extensions/plan-cycle', service)

    def test_legacy_is_explicit_and_does_not_load_plan_cycle(self):
        (self.extension_dir / 'index.ts').unlink()
        args = launch.make_plan(self.repo, self.config, self.env, legacy_cycles=True)[2]
        self.assertIn(str(self.config / 'extensions/work-cycles.ts'), args)
        self.assertNotIn(str(self.extension_dir / 'index.ts'), args)
        self.assertNotIn(str(self.profile / 'workflow.md'), args)
        self.assertIn(str(self.config / 'prompts/wait-what.md'), args)
        self.assertTrue(any('Legacy work-cycles recovery ONLY' in arg for arg in args))
        (self.config / 'extensions/work-cycles.ts').unlink()
        with self.assertRaisesRegex(ValueError, 'Work-cycle extension missing'):
            launch.make_plan(self.repo, self.config, self.env, legacy_cycles=True)

    def test_nested_repo_root_rejected(self):
        nested = self.repo / 'internal'; nested.mkdir()
        with self.assertRaisesRegex(ValueError, 'checkout root'):
            launch.make_plan(nested, self.config, self.env)

    def test_removed_worktree_option_fails_clearly(self):
        with patch.object(launch.sys, 'argv', ['launch.py', '--worktree', '/other']), patch('sys.stderr'):
            self.assertEqual(launch.main(), 1)

    def test_team_instruction_changes_do_not_change_launch_plan(self):
        expected = self.plan()
        (self.repo / 'CLAUDE.md').write_text('changed')
        (self.repo / 'docs/agents/workflow.md').write_text('changed workflow')
        for name in launch.CONTEXT_NAMES:
            (self.repo / name).write_text('NEW_TEAM_RULES')
        self.assertEqual(self.plan(), expected)

    def test_team_instruction_files_are_not_required(self):
        expected = self.plan()
        (self.repo / 'CLAUDE.md').unlink()
        (self.repo / 'docs/agents/workflow.md').unlink()
        self.assertEqual(self.plan(), expected)

    def test_required_profile_files_fail_closed(self):
        for name in (*launch.PROFILE_FILES, 'workflow.md'):
            with self.subTest(name=name):
                path = self.profile / name
                content = path.read_text()
                path.unlink()
                try:
                    with self.assertRaisesRegex(ValueError, 'Required profile file missing:') as raised:
                        self.plan()
                    self.assertIn(str(path), str(raised.exception))
                finally:
                    path.write_text(content)

    def test_check_reports_profile_files_without_source_audit(self):
        with patch.object(launch, 'make_plan', return_value=self.plan()), \
             patch.object(launch.os, 'execvpe') as execute, \
             patch.object(launch.sys, 'argv', ['launch.py', '--check']), \
             patch('sys.stdout', new_callable=StringIO) as output:
            self.assertEqual(launch.main(), 0)
        report = json.loads(output.getvalue())
        self.assertEqual(report['profile_files'], ['project.md', 'areas.md', 'testing.md', 'workflow.md'])
        self.assertFalse(report['project_context_autoload'])
        self.assertEqual(report['workflow'], 'structured-tasks')
        self.assertEqual(report['prompt_templates'], [str(self.config / 'prompts/wait-what.md')])
        self.assertNotIn('source_audit', report)
        execute.assert_not_called()

    def test_override_precedence_and_extra_dirs(self):
        override = self.agent_dir / 'AGENTS.override.md'
        override.write_text('override')
        self.env['PI_SUBAGENT_EXTRA_AGENT_DIRS'] = '/existing'
        _, env, _, personal = self.plan()
        self.assertIn(override, personal)
        self.assertNotIn(self.agent_dir / 'AGENTS.md', personal)
        self.assertTrue(env['PI_SUBAGENT_EXTRA_AGENT_DIRS'].endswith(os.pathsep + '/existing'))

    def test_missing_subagents_skill_fails_closed(self):
        (self.agent_dir / 'npm/node_modules/pi-subagents/skills/pi-subagents/SKILL.md').unlink()
        with self.assertRaisesRegex(ValueError, 'pi-subagents skill missing'):
            self.plan()

    def test_legacy_cli_flag_is_consumed_not_forwarded_to_pi(self):
        legacy = launch.make_plan(self.repo, self.config, self.env, legacy_cycles=True)
        with patch.object(launch, 'make_plan', return_value=legacy) as make, \
             patch.object(launch.sys, 'argv', ['launch.py', '--legacy-cycles', '--check']), \
             patch('sys.stdout', new_callable=StringIO) as output:
            self.assertEqual(launch.main(), 0)
        self.assertTrue(make.call_args.kwargs['legacy_cycles'])
        self.assertEqual(json.loads(output.getvalue())['workflow'], 'legacy-work-cycles')
        self.assertEqual(json.loads(output.getvalue())['forwarded_arguments'], 0)

    def test_execution_forwards_args_and_unsets_library_path_after_direnv(self):
        with patch.object(launch, 'DEFAULT_REPO', self.repo), \
             patch.object(launch, 'make_plan', return_value=self.plan()), \
             patch.object(launch.os, 'chdir') as chdir, \
             patch.object(launch.os, 'execvpe') as execute, \
             patch.object(launch.sys, 'argv', ['launch.py', '--print', 'read only']):
            launch.main()
        chdir.assert_called_once_with(self.repo)
        program, argv, env = execute.call_args.args
        self.assertEqual(program, 'direnv')
        self.assertEqual(argv[:6], ['direnv', 'exec', str(self.repo), 'env', '-u', 'LD_LIBRARY_PATH'])
        self.assertEqual(argv[-2:], ['--print', 'read only'])
        self.assertEqual(env['PI_RUCLAW_ROOT'], str(self.config))


if __name__ == '__main__':
    unittest.main()
