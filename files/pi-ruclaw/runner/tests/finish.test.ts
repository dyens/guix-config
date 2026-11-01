import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import extension from '../finish.ts';

for (const status of ['done', 'blocked', 'failed'] as const) {
	test(`finish ${status}: signal only after settle; Pi stays open`, async t => {
		const folder = await mkdtemp(join(tmpdir(), 'pi-runner-signal-'));
		const prior = process.env.PI_RUCLAW_RUNNER_SIGNAL;
		process.env.PI_RUCLAW_RUNNER_SIGNAL = join(folder, 'finish.json');
		t.after(async () => { if (prior === undefined) delete process.env.PI_RUCLAW_RUNNER_SIGNAL; else process.env.PI_RUCLAW_RUNNER_SIGNAL = prior; await rm(folder, { recursive: true, force: true }); });
		let tool: any, shutdown = 0;
		const events: any = {};
		extension({ registerTool: (v: any) => { tool = v; }, on: (name: string, fn: any) => { events[name] = fn; } } as any);
		const ctx: any = { shutdown: () => { shutdown++; }, sessionManager: { getSessionFile: () => '/session.jsonl' } };
		await events.agent_settled({}, ctx); // Waiting for async review: no finish signal.
		await assert.rejects(readFile(join(folder, 'finish.json')), { code: 'ENOENT' });
		assert.equal((await tool.execute('id', { status, summary: 'short' })).terminate, true);
		await assert.rejects(readFile(join(folder, 'finish.json')), { code: 'ENOENT' });
		await events.agent_settled({}, ctx);
		const signal = JSON.parse(await readFile(join(folder, 'finish.json'), 'utf8'));
		assert.deepEqual(signal, { status, summary: 'short', sessionFile: '/session.jsonl' });
		assert.equal(shutdown, 0);
	});
}
