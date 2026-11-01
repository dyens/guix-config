// No model/child/network calls. Real temp Git repos and the registered extension API.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import extension, { loadCycle } from '../extensions/work-cycles.ts';

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'ruclaw-cycles-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim();
  git('init', '-q', '-b', 'feature');
  git('config', 'user.name', 'test');
  git('config', 'user.email', 'test@example.invalid');
  git('commit', '--allow-empty', '-qm', 'fixture');
  const sha = git('rev-parse', 'HEAD');
  await fs.mkdir(path.join(root, '.scratch/task/work/cycles'), { recursive: true });
  for (const file of ['task.md', 'authority.md', 'current.md', 'resources.md', 'short.md', 'phase-result.md']) {
    await fs.writeFile(path.join(root, '.scratch/task', file), `Saved ${file}\n`);
  }
  const state = { version: 2, cycle: 1, phase: 'review', transition: 'phase-complete',
    transition_reason: 'Coherent increment ready for independent review',
    transition_evidence: '.scratch/task/phase-result.md', task: '.scratch/task/task.md',
    authority: '.scratch/task/authority.md', base_sha: sha, head_sha: sha, branch: 'feature',
    short_answers: ['.scratch/task/short.md'], work_state: '.scratch/task/current.md',
    resources: '.scratch/task/resources.md', active_children: [], next_action: 'Resolve F01' };
  const save = async (patch = {}) => {
    const file = '.scratch/task/work/cycles/next.json';
    await fs.writeFile(path.join(root, file), JSON.stringify({ ...state, ...patch }));
    return file;
  };
  return { root, git, state, save };
}

function runtime(root, branch = []) {
  let tool;
  const events = new Map();
  extension({ registerTool: value => { tool = value; }, on: (name, handler) => events.set(name, handler),
    appendEntry: (customType, data) => branch.push({ type: 'custom', customType, data }) });
  const ctx = { cwd: root, sessionManager: { getBranch: () => branch } };
  return { branch, tool, ctx, context: messages => events.get('context')({ messages }, ctx) };
}
function callMessage(id, timestamp = 100, extra = []) {
  return { role: 'assistant', timestamp, content: [{ type: 'toolCall', id, name: 'ruclaw_next_cycle', arguments: {} }, ...extra] };
}
function addCall(r, id = 'cycle-1', timestamp = 100, extra = []) {
  const message = callMessage(id, timestamp, extra);
  r.branch.push({ type: 'message', message });
  return message;
}
function result(id) { return { role: 'toolResult', toolCallId: id, toolName: 'ruclaw_next_cycle', content: [], timestamp: Date.now() }; }


test('unrelated sessions and branches without a boundary are unchanged', () => {
  const r = runtime('/unused');
  assert.equal(r.context([{ role: 'user', content: 'original', timestamp: 1 }]), undefined);
});

test('boundary really excludes old conversation and retains all new-cycle messages', async t => {
  const f = await fixture(t), r = runtime(f.root);
  const file = await f.save();
  const call = addCall(r);
  const answer = await r.tool.execute('cycle-1', { state_path: file }, undefined, undefined, r.ctx);
  assert.equal(answer.terminate, undefined); // continue automatically from files
  const tail = [{ role: 'user', content: 'New restriction', timestamp: Date.now() + 10 }];
  const messages = [{ role: 'user', content: 'OLD_CANARY'.repeat(10000), timestamp: 1 }, call, result('cycle-1'), ...tail];
  const projected = r.context(messages).messages;
  assert.equal(projected.length, 2);
  assert.equal(projected[1], tail[0]);
  const bootstrap = projected[0].content[0].text;
  assert.ok(bootstrap.includes(file));
  assert.ok(bootstrap.includes('references/resume.md'));
  assert.ok(bootstrap.includes('Destination phase: review'));
  assert.ok(bootstrap.includes('launch independent review'));
  assert.ok(bootstrap.includes('subagents_enable'));
  assert.ok(!bootstrap.includes('Read the implement skill'));
  assert.ok(!bootstrap.includes('ALL current short_answers'));
  assert.ok(!JSON.stringify(projected).includes('OLD_CANARY'));
  assert.equal(messages.length, 4); // audit history untouched
  const resumed = runtime(f.root, r.branch);
  assert.deepEqual(resumed.context(messages).messages, projected);
  assert.equal(runtime(f.root, r.branch.slice(0, 1)).context(messages), undefined);
});

test('missing/compacted boundary returns file recovery STOP, never old history', async t => {
  const f = await fixture(t), r = runtime(f.root);
  addCall(r);
  await r.tool.execute('cycle-1', { state_path: await f.save() }, undefined, undefined, r.ctx);
  const messages = [{ role: 'user', content: 'OLD_CANARY', timestamp: 1 }];
  const projected = r.context(messages).messages;
  assert.equal(projected.length, 1);
  assert.ok(projected[0].content[0].text.includes('STOP'));
  assert.ok(!JSON.stringify(projected).includes('OLD_CANARY'));
});

test('a context-transition call cannot share a batch with source writes', async t => {
  const f = await fixture(t), r = runtime(f.root);
  addCall(r, 'cycle-1', 100, [{ type: 'toolCall', id: 'write-1', name: 'write', arguments: {} }]);
  await assert.rejects(r.tool.execute('cycle-1', { state_path: await f.save() }, undefined, undefined, r.ctx), /alone/);
  assert.equal(r.branch.filter(e => e.type === 'custom').length, 0);
});

test('an aborted turn cannot persist a new context boundary', async t => {
  const f = await fixture(t), r = runtime(f.root);
  addCall(r);
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(r.tool.execute('cycle-1', { state_path: await f.save() }, controller.signal, undefined, r.ctx));
  assert.equal(r.branch.filter(e => e.type === 'custom').length, 0);
});

test('manifest validates actual head, branch, references and settled children', async t => {
  const f = await fixture(t);
  for (const patch of [{ version: 3 }, { cycle: 0 }, { task: '' }, { short_answers: null },
    { phase: 'unknown' }, { transition: 'micro-step' }, { transition_reason: '' },
    { transition_evidence: '.scratch/missing.md' },
    { head_sha: 'HEAD' }, { head_sha: 'b'.repeat(40) }, { branch: 'other' },
    { active_children: [{ runId: 'still-running' }] }, { resources: '.scratch/missing.md' },
    { work_state: '.scratch/task' }]) {
    await assert.rejects(loadCycle(await f.save(patch), f.root));
  }
  await fs.writeFile(path.join(f.root, 'unrelated.txt'), 'pre-existing dirty work');
  assert.equal((await loadCycle(await f.save(), f.root)).cycle, 1);
  assert.equal(await fs.readFile(path.join(f.root, 'unrelated.txt'), 'utf8'), 'pre-existing dirty work');
});

test('state and artifact symlinks cannot escape the checkout', async t => {
  const f = await fixture(t);
  const outside = await fs.mkdtemp(path.join(os.tmpdir(), 'ruclaw-outside-'));
  t.after(() => fs.rm(outside, { recursive: true, force: true }));
  await fs.writeFile(path.join(outside, 'file.md'), 'outside');
  await fs.symlink(path.join(outside, 'file.md'), path.join(f.root, '.scratch/task/link.md'));
  await assert.rejects(loadCycle(await f.save({ authority: '.scratch/task/link.md' }), f.root), /inside this checkout/);
  const file = await f.save();
  await fs.copyFile(path.join(f.root, file), path.join(f.root, 'outside-scratch.json'));
  await assert.rejects(loadCycle('outside-scratch.json', f.root), /inside this checkout's .scratch/);
});

test('next cycle preserves the original base/task/authority and advances once', async t => {
  const f = await fixture(t);
  const previous = { ...await loadCycle(await f.save(), f.root), toolCallId: 'old', timestamp: 1, assistantTimestamp: 1 };
  f.git('commit', '--allow-empty', '-qm', 'next candidate');
  const head = f.git('rev-parse', 'HEAD');
  const next = { cycle: 2, head_sha: head, phase: 'fix' };
  assert.equal((await loadCycle(await f.save(next), f.root, previous)).baseSha, previous.baseSha);
  for (const patch of [{ cycle: 1 }, { cycle: 3 }, { base_sha: head }, { task: '.scratch/task/short.md' },
    { authority: '.scratch/task/current.md' }]) {
    await assert.rejects(loadCycle(await f.save({ ...next, ...patch }), f.root, previous), /original task/);
  }
});

test('empty result list is valid before review; no fabricated progress report required', async t => {
  const f = await fixture(t);
  assert.equal((await loadCycle(await f.save({ short_answers: [] }), f.root)).phase, 'review');
});

test('micro-step resets are rejected; explicit same-phase recovery needs recorded reason/evidence', async t => {
  const f = await fixture(t);
  const previous = { ...await loadCycle(await f.save(), f.root), toolCallId: 'old', timestamp: 1, assistantTimestamp: 1 };
  await assert.rejects(loadCycle(await f.save({ cycle: 2 }), f.root, previous), /micro-step/);
  const recovered = await loadCycle(await f.save({ cycle: 2, transition: 'recovery',
    transition_reason: 'User-requested handoff; saved dirty work and outstanding gates' }), f.root, previous);
  assert.equal(recovered.phase, previous.phase);
  assert.equal(f.git('rev-parse', 'HEAD'), f.state.head_sha);
});

test('legacy state is preserved and migrated once without replacing original task/base', async t => {
  const f = await fixture(t);
  const previous = { ...await loadCycle(await f.save(), f.root), phase: undefined,
    toolCallId: 'legacy', timestamp: 1, assistantTimestamp: 1 };
  const legacy = await f.save({ version: 1 });
  await assert.rejects(loadCycle(legacy, f.root), /Legacy manifest/);
  assert.equal(JSON.parse(await fs.readFile(path.join(f.root, legacy), 'utf8')).version, 1);
  const r = runtime(f.root, [{ type: 'custom', customType: 'ruclaw-work-cycle', data: previous }]);
  const bootstrap = r.context([]).messages[0].content[0].text;
  assert.ok(bootstrap.includes('references/resume.md'));
  assert.ok(bootstrap.includes('legacy recovery'));
  const migrated = await loadCycle(await f.save({ cycle: 2 }), f.root, previous);
  assert.equal(migrated.baseSha, previous.baseSha);
  assert.equal(migrated.task, previous.task);
});

test('second boundary drops the first cycle too, without confusing reused call IDs', async t => {
  const f = await fixture(t), r = runtime(f.root);
  const first = addCall(r, 'same-id', 100);
  await r.tool.execute('same-id', { state_path: await f.save() }, undefined, undefined, r.ctx);
  const second = addCall(r, 'same-id', 200);
  await r.tool.execute('same-id', { state_path: await f.save({ cycle: 2, phase: 'fix' }) }, undefined, undefined, r.ctx);
  const messages = [first, result('same-id'), { role: 'user', content: 'CYCLE_ONE_CANARY', timestamp: 150 }, second, result('same-id')];
  const projected = r.context(messages).messages;
  assert.equal(projected.length, 1);
  assert.ok(!JSON.stringify(projected).includes('CYCLE_ONE_CANARY'));
});
