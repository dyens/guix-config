#!/usr/bin/env python3
"""Sequential tmux launcher. No model, receipts, acceptance checks or recovery state."""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
LAUNCHER = HERE.parent / 'launch.py'
DEFAULT_REPO = Path.home() / 'dev/croc/ruclaw'
DEFAULT_DOCKER_AUTHORITY = (
    'Local Docker/Compose is authorized by default for isolated task/ticket-owned stands '
    'and dependencies: build/pull images, create/start/restart/stop/remove containers and '
    'their owned networks. Verify ownership/isolation before changing existing resources. '
    'No shared/production resource changes, global prune, volume deletion or '
    'persistent data resets without separate permission. Disposable task containers may be removed. '
    'User restrictions override these defaults.'
)


def command(*args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


@contextmanager
def lock(path):
    # Kernel releases this on exit; no stale PID/token recovery protocol.
    with open(path, 'a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Другой runner/исполнитель ещё работает; сначала закончи его') from None
        yield


def read_tasks(directory):
    result = {}
    for path in sorted((directory / 'issues').glob('*.md')):
        match = re.fullmatch(r'(\d{2})-[a-zA-Z0-9-]+\.md', path.name)
        if not match:
            raise ValueError(f'Неизвестное имя задачи: {path.name}')
        text = path.read_text()
        statuses = re.findall(r'^\*\*Status:\*\*\s*([^\r\n]+)$', text, re.M)
        dependencies = re.findall(r'^\*\*Blocked by:\*\*\s*([^\r\n]+)$', text, re.M)
        if len(statuses) != 1 or len(dependencies) != 1:
            raise ValueError(f'Нужны однозначные Status/Blocked by: {path}')
        status, blocked = statuses[0].strip(), dependencies[0].strip()
        if status not in ('done', 'ready-for-agent', 'ready-for-human', 'blocked', 'deferred'):
            raise ValueError(f'Неизвестный статус: {path}')
        blockers = []
        if not re.match(r'^(None\b|нет\b|—$|-$)', blocked, re.I):
            prefix = re.split('[—–]', blocked, maxsplit=1)[0].strip()
            if not re.fullmatch(r'\d{2}(?:\s*,\s*\d{2})*', prefix):
                raise ValueError(f'Не разбираю зависимости: {path}')
            blockers = re.split(r'\s*,\s*', prefix)
        task_id = match[1]
        if task_id in result:
            raise ValueError(f'Повторяющийся ID: {task_id}')
        result[task_id] = dict(path=path, status=status, blockers=blockers)
    if not result:
        raise ValueError('Задачи не найдены')
    for task_id, task in result.items():
        if any(b not in result or b == task_id for b in task['blockers']):
            raise ValueError(f'Неверные зависимости: {task_id}')
    return result


def next_task(tasks, selected, finished):
    if any(i not in tasks for i in selected):
        raise RuntimeError('Выбранная задача исчезла; запуск остановлен')
    pending = [i for i in selected if i not in finished and tasks[i]['status'] != 'done']
    for task_id in pending:
        task = tasks[task_id]
        if task['status'] == 'ready-for-agent' and all(tasks[b]['status'] == 'done' for b in task['blockers']):
            return task_id
    if pending:
        raise RuntimeError(f'Нет доступной задачи: {", ".join(pending)}. Решение принимает человек, не runner')
    return None


def task_prompt(job):
    return (
        f'/skill:implement {job["task"]}\n\n'
        f'Simple tmux runner; ONLY task {job["id"]}. You own this task end to end.\n'
        f'User mandate: {job["mandate"]}\n'
        'You own the whole task: inspect existing committed progress before editing; implement, '
        'test, arrange final independent code review using ruclaw-plan-reviewer, fix findings, non-force push, '
        'verify publication, mark evidenced criteria and task done, and clean up ONLY your owned '
        'temporary resources. Wait for all your children. Preserve required checks/security contracts. '
        'Do not repeat finished work or suites solely for ceremony; verify provenance/input equivalence '
        'when reusing evidence. Keep logs/review in files and report briefly. '
        'The launcher does not review or approve your work. Resolve ordinary issues yourself within '
        'the mandate. For an actual blocker, ask the USER directly in this pane, not the runner. '
        'Do not read previous transcripts/all old reports by default. '
        'Use default plan-cycle v2: after intake call plan_cycle_start ALONE, save a short sequential '
        'plan, then plan_cycle_next between completed steps. Keep publication/status/cleanup in '
        'the plan. Plan-step DONE is not task done. Review is a final planned step; findings '
        'become a new fix plan. Do not use ruclaw_next_cycle or old phase manifests.\n'
        'Finish by calling runner_finish ALONE with status done, blocked or failed and a short summary. '
        'done is your declaration that the complete task is finished, NOT just the code. '
        'blocked/failed stops subsequent launches and leaves this Pi available for the user. '
        'done leaves Pi idle and open in this pane after the turn settles. '
        'Do not continue editing after done: the next executor may already be working in this checkout.\n'
    )


def worker(job_path):
    job_path = Path(job_path).resolve()
    job = json.loads(job_path.read_text())
    outcome = dict(status='failed', summary='Pi завершился без runner_finish')
    process = None
    try:
        with lock(job['worker_lock']):
            signal = job_path.parent / 'finish.json'
            env = dict(os.environ, PI_RUCLAW_RUNNER_SIGNAL=str(signal))
            process = subprocess.Popen([sys.executable, str(LAUNCHER),
                                        '--extension', str(HERE / 'finish.ts'), task_prompt(job)], env=env, cwd=job['repo'])
            while True:
                code = process.poll()
                reported = json.loads(signal.read_text()) if signal.exists() else None
                if code is not None:
                    if reported:
                        outcome = reported
                    if code != 0:
                        outcome = dict(status='failed', summary=f'Pi завершился с кодом {code}')
                    break
                if reported and reported['status'] == 'done':
                    outcome = reported
                    break
                time.sleep(0.2)
    except Exception as exc:
        outcome = dict(status='failed', summary=str(exc))
    result = job_path.parent / 'result.json'
    temporary = result.with_suffix('.tmp')
    temporary.write_text(json.dumps(outcome, ensure_ascii=False)); temporary.replace(result)
    print(f'\n{job["id"]}: {outcome["status"]} — {outcome["summary"]}', flush=True)
    if outcome.get('sessionFile'):
        print('Session:', outcome['sessionFile'], flush=True)
    # Result is published AFTER releasing the work lock. Pi stays open and idle;
    # the next worker can acquire the lock without racing this handoff.
    if process is not None:
        process.wait()
    print('Pane оставлен открытым; закрывай его самостоятельно.', flush=True)
    os.chdir(job['repo'])
    os.execvp('bash', ['bash', '-i'])


def spawn(job_path, target, repo, below=None):
    shell_command = shlex.join([sys.executable, str(HERE / 'run.py'), '--job', str(job_path)])
    split_target, direction = target, '-h'
    if below:
        alive = command('tmux', 'list-panes', '-a', '-F', '#{pane_id}').splitlines()
        previous = next((pane for pane in reversed(below) if pane in alive), None)
        if previous:
            split_target, direction = previous, '-v'
    try:
        return command('tmux', 'split-window', direction, '-d', '-P', '-F', '#{pane_id}', '-t', split_target, '-c', str(repo), shell_command)
    except subprocess.CalledProcessError:
        # Kept panes eventually fill a window. Never close one to make room.
        session = command('tmux', 'display-message', '-p', '-t', target, '#{session_id}')
        return command('tmux', 'new-window', '-d', '-P', '-F', '#{pane_id}', '-t', session, '-c', str(repo), shell_command)


def wait_for_task(folder, pane):
    while True:
        for name in ('result.json', 'finish.json'):
            path = folder / name
            if path.exists():
                outcome = json.loads(path.read_text())
                if outcome.get('status') not in ('done', 'blocked', 'failed'):
                    raise RuntimeError(f'Неизвестный сигнал исполнителя: {path}')
                # done advances after the settled signal AND work-lock release.
                if name == 'result.json' or outcome['status'] != 'done':
                    return outcome
        panes = command('tmux', 'list-panes', '-a', '-F', '#{pane_id}').splitlines()
        if pane not in panes:
            return dict(status='failed', summary='Pane закрыт без завершения задачи')
        time.sleep(0.5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ticket', nargs='?', help='.scratch/RCL-123')
    parser.add_argument('--only', help='08,09 (без флага — все незавершённые задачи)')
    parser.add_argument('--job', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.job:
        worker(args.job)
        return 0
    if not os.environ.get('TMUX_PANE'):
        parser.error('Запусти runner внутри tmux')
    if not args.ticket or not re.fullmatch(r'\.scratch/RCL-\d+/?', args.ticket):
        parser.error('Укажи .scratch/RCL-123')
    repo = DEFAULT_REPO.expanduser().resolve()
    common = Path(command('git', 'rev-parse', '--path-format=absolute', '--git-common-dir', cwd=repo))
    directory = repo / args.ticket
    command('git', 'check-ignore', '-q', '--', str(directory / 'runner'), cwd=repo)
    with lock(common / 'pi-ruclaw-runner.lock'):
        tasks = read_tasks(directory)
        if args.only and not re.fullmatch(r'\d{2}(,\d{2})*', args.only):
            parser.error('--only: ожидается 08,09')
        selected = args.only.split(',') if args.only else [i for i, t in tasks.items() if t['status'] != 'done']
        if len(set(selected)) != len(selected) or any(i not in tasks for i in selected):
            parser.error('Неизвестные/повторяющиеся task IDs')
        print(f'Repo: {repo}; ticket: {args.ticket}')
        print('Последовательно:', ', '.join(selected) or 'все задачи уже done')
        if not selected:
            return 0
        print('Каждый исполнитель сам делает checks/review/push/status. Pane НЕ закрываются.')
        print('Docker/Compose для своих локальных стендов и зависимостей разрешён, включая stop/rm контейнеров.')
        print('Чужие/shared/prod ресурсы, удаление volumes/persistent-данных и global prune — только отдельно.')
        print('Сначала останови другие реализации в этом repo.')
        if input('Scope задач, обычные commits и non-force push согласованы? [yes/no] ').strip().lower() != 'yes':
            return 0
        hints = input('Дополнительные ограничения/ресурсы (без секретов; пусто = Docker defaults): ')
        if len(hints) > 2000:
            raise ValueError('Ограничения: максимум 2000 символов')
        mandate = (f'Только задачи {",".join(selected)}; scope/spec, обычные commits и non-force push текущей ticket-ветки согласованы. '
                   f'{DEFAULT_DOCKER_AUTHORITY} User restrictions/resources: {hints or "none"}')
        run = directory / 'runner' / str(uuid.uuid4()); run.mkdir(parents=True, mode=0o700)
        finished = set()
        target = os.environ['TMUX_PANE']
        right_panes = []
        while True:
            tasks = read_tasks(directory)
            task_id = next_task(tasks, selected, finished)
            if task_id is None:
                print('Все выбранные задачи завершены. Pane оставлены открытыми.')
                return 0
            folder = run / task_id; folder.mkdir(mode=0o700)
            job = dict(id=task_id, task=str(tasks[task_id]['path'].relative_to(repo)), repo=str(repo),
                       mandate=mandate, worker_lock=str(common / 'pi-ruclaw-runner-worker.lock'))
            path = folder / 'job.json'; path.write_text(json.dumps(job, ensure_ascii=False)); path.chmod(0o600)
            pane = spawn(path, target, repo, below=right_panes)
            right_panes.append(pane)
            print(f'{task_id}: pane {pane}; ожидание исполнителя…', flush=True)
            outcome = wait_for_task(folder, pane)
            print(f'{task_id}: {outcome["status"]} — {outcome["summary"]}', flush=True)
            if outcome['status'] != 'done':
                print('Остановлено. Общайся с исполнителем в его pane; автоматического повтора нет.')
                return 1
            finished.add(task_id)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print('\nRunner остановлен. Исполнитель в pane НЕ остановлен; закончи/останови его перед новым запуском.', file=sys.stderr)
        sys.exit(130)
    except (RuntimeError, ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'runner: {error}', file=sys.stderr)
        sys.exit(1)
