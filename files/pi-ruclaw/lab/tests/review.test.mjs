import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const source = fs.readFileSync(new URL('../workflows/review.js', import.meta.url), 'utf8');
const run = new AsyncFunction('args', 'runs', source);
const args = { repo: '/repo', task: '/repo/task.md', evidence: '/repo/checks.md',
  resultDir: '/repo/.scratch/pi-lite/reviews/candidate', baseSha: 'a'.repeat(40),
  headSha: 'b'.repeat(40), critical: true,
  acceptanceSeal: '/repo/.scratch/pi-lite/acceptance/prepared/seal.json', sealSha256: 'd'.repeat(64) };

for (const critical of [false, true]) {
  test(`named review: critical=${critical}, artifact-only writes, compact receipt`, async () => {
    const result = await run({ ...args, critical }, { all: async tasks => {
      assert.equal(tasks.length, 2);
      assert.equal(tasks[0].agent, 'ruclaw-lite-reviewer');
      assert.equal(tasks[1].agent, 'ruclaw-lite-evaluator');
      assert.deepEqual(tasks.map(t => t.key), ['primary', 'acceptance']);
      for (const child of tasks) {
        assert.equal(child.context, 'fresh');
        assert.equal(child.output, false);
        assert.equal(child.outputMode, 'inline');
        assert.equal(child.cwd, args.repo);
        assert.ok(child.task.includes(args.baseSha) && child.task.includes(args.headSha));
        assert.ok(child.task.includes(args.task) && child.task.includes(args.evidence));
        assert.ok(child.task.includes(args.acceptanceSeal) && child.task.includes(args.sealSha256));
        assert.ok(child.task.includes('sealed authority.md'));
      }
      assert.ok(tasks.every(t => t.task.includes('Read no peer findings')));
      assert.ok(tasks[0].task.includes('No tests or script execution'));
      assert.ok(tasks[1].task.includes('Mode: VERIFY'));
      assert.ok(tasks[1].task.includes('already frozen pre-implementation suite'));
      assert.ok(tasks[1].task.includes('owned exact-ref exports'));
      assert.ok(tasks[1].task.includes('Do not weaken assertions'));
      assert.equal(tasks[1].task.includes('Prioritize critical authority'), critical);
      return tasks.map(t => ({ ok: true, runId: t.key, output: 'BODY_CANARY'.repeat(10000) }));
    } });
    assert.equal(result.ok, true);
    assert.deepEqual(result.indexes, [`${args.resultDir}/primary/short.md`, `${args.resultDir}/acceptance/short.md`]);
    assert.ok(!JSON.stringify(result).includes('BODY_CANARY'));
  });
}
test('failed child stays failed and keeps its error', async () => {
  const result = await run(args, { all: async () => [{ ok: false, runId: 'r', error: 'scope unavailable' }] });
  assert.equal(result.ok, false);
  assert.equal(result.runs[0].error, 'scope unavailable');
});
test('missing evaluator completion is not successful process completion', async () => {
  const result = await run(args, { all: async () => [{ ok: true, runId: 'primary-only' }] });
  assert.equal(result.ok, false);
  assert.equal(result.indexes.length, 2);
});
test('follow-up records immutable prior reviewed head', async () => {
  const previousHead = 'c'.repeat(40);
  await run({ ...args, previousHead }, { all: async tasks => {
    assert.ok(tasks.every(t => t.task.includes(previousHead) && t.task.includes('delta plus affected invariants')));
    return tasks.map(() => ({ ok: true }));
  } });
});
test('invalid refs/paths/critical fail before children launch', async () => {
  for (const patch of [{ headSha: 'HEAD' }, { baseSha: 'a'.repeat(41) }, { critical: null },
    { repo: '/repo/../other' }, { task: 'relative.md' }, { task: '/primary/task.md' },
    { evidence: '/other/checks.md' }, { resultDir: '/elsewhere' }, { previousHead: 'HEAD~1' },
    { acceptanceSeal: undefined }, { acceptanceSeal: '/other/seal.json' }, { sealSha256: undefined },
    { sealSha256: 'current hash' }]) {
    await assert.rejects(run({ ...args, ...patch }, { all: () => { throw new Error('must not launch'); } }),
      error => !error.message.includes('must not launch'));
  }
});
