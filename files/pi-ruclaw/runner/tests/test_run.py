import importlib.util
import json
import os
from pathlib import Path
import subprocess
import shutil
import time
import tempfile
import unittest
from unittest.mock import Mock, patch

SCRIPT = Path(__file__).resolve().parents[1] / 'run.py'
spec = importlib.util.spec_from_file_location('runner', SCRIPT)
assert spec is not None and spec.loader is not None
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        (self.root / '.gitignore').write_text('.scratch/\n')
        self.directory = self.root / '.scratch/RCL-123'
        (self.directory / 'issues').mkdir(parents=True)
        for task_id, blocked in [('01', 'None'), ('02', '01 — first')]:
            self.task(task_id).write_text(f'# Test\n**Status:** ready-for-agent\n**Blocked by:** {blocked}\n')

    def task(self, task_id):
        return self.directory / 'issues' / f'{task_id}-task.md'

    def test_worker_uses_root_launcher(self):
        self.assertEqual(runner.LAUNCHER, SCRIPT.parents[1] / 'launch.py')
        self.assertTrue(runner.LAUNCHER.is_file())

    def test_dependencies_and_no_invented_work(self):
        tasks = runner.read_tasks(self.directory)
        self.assertEqual(runner.next_task(tasks, ['01', '02'], set()), '01')
        with self.assertRaises(RuntimeError):
            runner.next_task(tasks, ['02'], set())
        tasks['01']['status'] = 'done'
        self.assertEqual(runner.next_task(tasks, ['01', '02'], set()), '02')
        self.assertIsNone(runner.next_task(tasks, ['01'], set()))
        with self.assertRaises(RuntimeError):
            runner.next_task(tasks, ['99'], set())

    def test_bad_dependencies_fail_closed(self):
        self.task('02').write_text('**Status:** ready-for-agent\n**Blocked by:** nonsense 01\n')
        with self.assertRaises(ValueError):
            runner.read_tasks(self.directory)

    def test_kernel_lock_releases_without_stale_state(self):
        path = self.root / 'lock'
        with runner.lock(path):
            with self.assertRaises(RuntimeError):
                with runner.lock(path):
                    pass
        with runner.lock(path):
            pass

    def drive(self, outcome):
        launches = []
        def spawn(path, target, repo, below=None):
            job = json.loads(path.read_text())
            self.assertIn(runner.DEFAULT_DOCKER_AUTHORITY, job['mandate'])
            self.assertIn('User restrictions/resources: No new resources', job['mandate'])
            launches.append(job['id'])
            if outcome == 'done':
                task = self.task(job['id'])
                task.write_text(task.read_text().replace('ready-for-agent', 'done'))
            path.with_name('result.json').write_text(json.dumps(dict(status=outcome, summary='stub')))
            return '%stub'
        with patch('sys.argv', [str(SCRIPT), '.scratch/RCL-123']), patch.object(runner, 'DEFAULT_REPO', self.root), patch.dict(os.environ, TMUX_PANE='%origin'), patch('builtins.input', side_effect=['yes', 'No new resources']), patch.object(runner, 'spawn', side_effect=spawn):
            result = runner.main()
        return result, launches

    def test_two_tasks_and_no_automatic_pane_close(self):
        code, launches = self.drive('done')
        self.assertEqual(code, 0)
        self.assertEqual(launches, ['01', '02'])

    def test_blocker_stops_without_launching_next(self):
        code, launches = self.drive('blocked')
        self.assertEqual(code, 1)
        self.assertEqual(launches, ['01'])

    def test_finish_done_waits_for_worker_lock_handoff(self):
        (self.root / 'finish.json').write_text(json.dumps(dict(status='done', summary='stub')))
        with patch.object(runner, 'command', return_value=''):
            self.assertEqual(runner.wait_for_task(self.root, '%gone')['status'], 'failed')
        (self.root / 'result.json').write_text(json.dumps(dict(status='done', summary='stub')))
        self.assertEqual(runner.wait_for_task(self.root, '%gone')['status'], 'done')

    def test_blocker_keeps_pi_open_for_user(self):
        (self.root / 'finish.json').write_text(json.dumps(dict(status='blocked', summary='need decision')))
        with patch.object(runner, 'command', side_effect=AssertionError('Do not kill or poll Pi')):
            self.assertEqual(runner.wait_for_task(self.root, '%live')['status'], 'blocked')

    def test_worker_hands_off_done_while_pi_is_alive_and_lock_is_free(self):
        path = self.root / 'job.json'
        lock = self.root / 'worker.lock'
        path.write_text(json.dumps(dict(id='01', task='.scratch/RCL-123/issues/01-task.md', repo=str(self.root), mandate='test', worker_lock=str(lock))))
        process = Mock(); process.poll.return_value = None
        def pi(*args, **kwargs):
            Path(kwargs['env']['PI_RUCLAW_RUNNER_SIGNAL']).write_text(json.dumps(dict(status='done', summary='stub')))
            return process
        def wait():
            self.assertEqual(json.loads((self.root / 'result.json').read_text())['status'], 'done')
            with runner.lock(lock):
                pass  # Next worker may start while this Pi is still open.
            return 0
        process.wait.side_effect = wait
        with patch.object(runner.subprocess, 'Popen', side_effect=pi), patch.object(runner.os, 'execvp', side_effect=InterruptedError('shell')), patch.object(runner.os, 'chdir'):
            with self.assertRaises(InterruptedError):
                runner.worker(path)
        process.terminate.assert_not_called(); process.kill.assert_not_called()

    def test_worker_exit_without_signal_is_failure(self):
        path = self.root / 'job.json'
        path.write_text(json.dumps(dict(id='01', task='task.md', repo=str(self.root), mandate='test', worker_lock=str(self.root / 'worker.lock'))))
        for code in [0, 1]:
            process = Mock(); process.poll.return_value = code
            with patch.object(runner.subprocess, 'Popen', return_value=process), patch.object(runner.os, 'execvp', side_effect=InterruptedError('shell')), patch.object(runner.os, 'chdir'):
                with self.assertRaises(InterruptedError):
                    runner.worker(path)
            self.assertEqual(json.loads((self.root / 'result.json').read_text())['status'], 'failed')

    @unittest.skipUnless(shutil.which('tmux'), 'tmux is not installed')
    def test_real_private_tmux_split_keeps_panes(self):
        socket = str(self.root / 'tmux.sock')
        tmux = ['tmux', '-S', socket]
        subprocess.run([*tmux, '-f', '/dev/null', 'new-session', '-d', '-x', '180', '-y', '40', '-s', 'runner-test', 'bash --noprofile --norc'], check=True)
        self.addCleanup(lambda: subprocess.run([*tmux, 'kill-server'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        target = subprocess.check_output([*tmux, 'list-panes', '-F', '#{pane_id}'], text=True).strip()
        fake = self.root / 'fake'; fake.mkdir()
        (fake / 'run.py').write_text('import os,sys\nfrom pathlib import Path\nPath(sys.argv[2]).with_suffix(".started").write_text("started")\nos.execvp("bash", ["bash", "--noprofile", "--norc"])\n')
        path = self.root / 'job.json'; path.write_text('{}')
        def command(*args, **kwargs):
            return subprocess.check_output([*tmux, *args[1:]], text=True).strip()
        with patch.object(runner, 'HERE', fake), patch.object(runner, 'command', side_effect=command):
            pane = runner.spawn(path, target, self.root)
            second = runner.spawn(path, target, self.root, below=[pane])
        for _ in range(60):
            if path.with_suffix('.started').exists():
                break
            time.sleep(0.05)
        self.assertTrue(path.with_suffix('.started').exists())
        panes = command('tmux', 'list-panes', '-a', '-F', '#{pane_id}').splitlines()
        self.assertIn(target, panes); self.assertIn(pane, panes); self.assertIn(second, panes)
        self.assertEqual(len(panes), 3)
        def geometry():
            rows = command('tmux', 'list-panes', '-a', '-F', '#{pane_id} #{pane_left} #{pane_top}').splitlines()
            return {parts[0]: tuple(map(int, parts[1:])) for parts in map(str.split, rows)}
        positions = geometry()
        self.assertGreater(positions[pane][0], positions[target][0])
        self.assertEqual(positions[pane][0], positions[second][0])
        self.assertGreater(positions[second][1], positions[pane][1])
        # Simulate the user closing the latest pane, in this private server only.
        command('tmux', 'kill-pane', '-t', second)
        with patch.object(runner, 'HERE', fake), patch.object(runner, 'command', side_effect=command):
            replacement = runner.spawn(path, target, self.root, below=[pane, second])
        positions = geometry()
        self.assertEqual(positions[replacement][0], positions[pane][0])
        self.assertGreater(positions[replacement][1], positions[pane][1])

    def test_default_docker_authority_is_bounded(self):
        authority = runner.DEFAULT_DOCKER_AUTHORITY
        self.assertIn('create/start/restart/stop/remove containers', authority)
        self.assertIn('Verify ownership/isolation', authority)
        self.assertIn('No shared/production resource changes', authority)
        self.assertIn('volume deletion', authority)
        self.assertIn('User restrictions override', authority)

    def test_prompt_assigns_all_responsibility_to_executor(self):
        prompt = runner.task_prompt(dict(id='01', task='task.md', mandate='approved'))
        self.assertIn('You own this task end to end', prompt)
        self.assertIn('independent code review', prompt)
        self.assertIn('ruclaw-plan-reviewer', prompt)
        self.assertIn('task_plan ALONE', prompt)
        self.assertIn('task_complete ALONE', prompt)
        self.assertNotIn('plan_cycle_start', prompt)
        self.assertIn('No routine report files', prompt)
        self.assertIn('Plan-step DONE is not task done', prompt)
        self.assertIn('mark evidenced criteria and task done', prompt)
        self.assertIn('ask the USER directly', prompt)


if __name__ == '__main__':
    unittest.main()
