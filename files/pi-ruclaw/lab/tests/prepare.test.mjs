import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const run = new AsyncFunction('args', 'runs', fs.readFileSync(new URL('../workflows/prepare.js', import.meta.url), 'utf8'));
const args = { repo: '/repo', task: '/repo/task.md', authority: '/repo/.scratch/pi-lite/authority.md',
  baseSha: 'a'.repeat(40), resultDir: '/repo/.scratch/pi-lite/acceptance/first' };

test('prepare delegates only original base and explicit authority before any candidate', async () => {
  const result = await run({ ...args, headSha: 'b'.repeat(40) }, { all: async tasks => {
    assert.equal(tasks.length, 1);
    const child = tasks[0];
    assert.equal(child.agent, 'ruclaw-lite-evaluator');
    assert.equal(child.context, 'fresh');
    assert.equal(child.output, false);
    assert.equal(child.outputMode, 'inline');
    for (const value of [args.baseSha, args.task, args.authority]) assert.ok(child.task.includes(value));
    assert.ok(child.task.includes('Mode: PREPARE'));
    assert.ok(child.task.includes('NO candidate implementation'));
    assert.ok(child.task.includes('Do NOT seal your own output'));
    assert.ok(!child.task.includes('b'.repeat(40)));
    return [{ ok: true, runId: 'prepare', output: 'BODY_CANARY'.repeat(1000) }];
  } });
  assert.equal(result.ok, true);
  assert.equal(result.suite, `${args.resultDir}/suite`);
  assert.ok(!JSON.stringify(result).includes('BODY_CANARY'));
});

test('missing/failed preparation cannot complete successfully', async () => {
  for (const children of [[], [{ ok: false, error: 'blocked' }]]) {
    const result = await run(args, { all: async () => children });
    assert.equal(result.ok, false);
  }
});

test('invalid or absent authority/ref/path stops before launch', async () => {
  for (const patch of [{ authority: undefined }, { authority: '/other/grants' },
    { task: '/repo/../other' }, { baseSha: 'HEAD' }, { resultDir: '/elsewhere' }]) {
    await assert.rejects(run({ ...args, ...patch }, { all: () => { throw new Error('must not launch'); } }),
      error => !error.message.includes('must not launch'));
  }
});
