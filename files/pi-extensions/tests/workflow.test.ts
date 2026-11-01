import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { chmod, mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { registerWorkflow } from "../workflow/index.ts";
import { snapshot, statusReport, taskFiles } from "../workflow/core.ts";

async function repo(t: any) {
	const root = await mkdtemp(join(tmpdir(), "pi-workflow-test-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	const git = (...args: string[]) => execFileSync("git", ["-c", "user.name=Test", "-c", "user.email=test@example.invalid", ...args], { cwd: root, encoding: "utf8" });
	git("init", "-q");
	await writeFile(join(root, ".gitignore"), "ignored\n.scratch/\n");
	await writeFile(join(root, "a.txt"), "one\n");
	git("add", "."); git("commit", "-qm", "initial");
	return { root, git };
}

test("fingerprints cover staged, unstaged, untracked, permissions and symlinks without changing index", async (t) => {
	const { root, git } = await repo(t);
	const initial = await snapshot(root);
	assert.equal(initial.dirty, false);
	const originalIndex = await readFile(join(root, ".git", "index"));
	await snapshot(root);
	assert.deepEqual(await readFile(join(root, ".git", "index")), originalIndex);
	await writeFile(join(root, "a.txt"), "two\n");
	const unstaged = await snapshot(root);
	assert.notEqual(unstaged.fingerprint, initial.fingerprint);
	git("add", "a.txt");
	const staged = await snapshot(root);
	assert.notEqual(staged.fingerprint, unstaged.fingerprint);
	await writeFile(join(root, "a.txt"), "three\n");
	assert.notEqual((await snapshot(root)).fingerprint, staged.fingerprint);
	await writeFile(join(root, "new.txt"), "new\n");
	const untracked = await snapshot(root);
	await writeFile(join(root, "new.txt"), "NEW\n");
	assert.notEqual((await snapshot(root)).fingerprint, untracked.fingerprint);
	await symlink("a.txt", join(root, "link"));
	const linked = await snapshot(root);
	await rm(join(root, "link")); await symlink("new.txt", join(root, "link"));
	assert.notEqual((await snapshot(root)).fingerprint, linked.fingerprint);
	const beforeMode = await snapshot(root);
	await chmod(join(root, "a.txt"), 0o755);
	assert.notEqual((await snapshot(root)).fingerprint, beforeMode.fingerprint);
	const beforeIgnored = await snapshot(root);
	await writeFile(join(root, "ignored"), "outside snapshot");
	assert.equal((await snapshot(root)).fingerprint, beforeIgnored.fingerprint);
	await rm(join(root, "a.txt"));
	assert.notEqual((await snapshot(root)).fingerprint, beforeIgnored.fingerprint);
});

test("task status reads declared metadata only and does not report check receipts", async (t) => {
	const { root } = await repo(t);
	await assert.rejects(taskFiles(root, "../../other"), /Формат/);
	await mkdir(join(root, ".scratch", "RCL-123", "issues"), { recursive: true });
	const path = join(root, ".scratch", "RCL-123", "issues", "01-task.md");
	const text = "**Status:** ready\n**Blocked by:** 00\n";
	await writeFile(path, text);
	assert.deepEqual(await taskFiles(root, "RCL-123"), ["01-task.md: ready; Blocked by: 00"]);
	assert.equal(await readFile(path, "utf8"), text);
	const report = await statusReport(await snapshot(root), "RCL-123");
	assert.match(report, /UNKNOWN/);
	assert.doesNotMatch(report, /NOT RUN|PASSED|сохранённых проверок/);
});

function harness(root: string) {
	const commands: Record<string, any> = {}, events: Record<string, any> = {};
	const notes: string[] = [], editors: string[] = [];
	let leaf = "leaf", session = "session", idle = true, pending = false;
	const ctx: any = {
		cwd: root, mode: "tui", isIdle: () => idle, hasPendingMessages: () => pending,
		sessionManager: { getSessionId: () => session, getLeafId: () => leaf },
		ui: { notify: (text: string) => notes.push(text), editor: async (_title: string, text: string) => { editors.push(text); return text; } },
	};
	registerWorkflow({ on: (name: string, handler: any) => { events[name] = handler; }, registerCommand: (name: string, command: any) => { commands[name] = command.handler; } } as any);
	return { commands, events, ctx, notes, editors,
		changeLeaf: () => { leaf = "other"; }, changeSession: () => { session = "other"; }, becomeBusy: () => { idle = false; }, queueMessage: () => { pending = true; } };
}

test("only task-status is registered and it works without any model or session-creation API", async (t) => {
	const { root } = await repo(t); const h = harness(root);
	assert.deepEqual(Object.keys(h.commands), ["task-status"]);
	await h.commands["task-status"]("", h.ctx);
	assert.equal(h.editors.length, 1);
	assert.match(h.editors[0], /HEAD:/);
	assert.equal(h.notes.length, 0);
});

test("status guards busy/queued state, non-TUI and invalid ticket; errors release busy state", async (t) => {
	for (const scenario of ["busy", "pending", "rpc", "invalid-ticket"]) {
		await t.test(scenario, async (t) => {
			const { root } = await repo(t); const h = harness(root);
			if (scenario === "busy") h.becomeBusy();
			if (scenario === "pending") h.queueMessage();
			if (scenario === "rpc") h.ctx.mode = "rpc";
			await h.commands["task-status"](scenario === "invalid-ticket" ? "../bad" : "", h.ctx);
			assert.equal(h.editors.length, 0);
			assert.equal(h.notes.length, 1);
			if (scenario === "invalid-ticket") {
				await h.commands["task-status"]("", h.ctx);
				assert.equal(h.editors.length, 1);
			}
		});
	}
});

test("status does not display results in a changed session or after shutdown", async (t) => {
	for (const scenario of ["leaf", "session", "queued", "shutdown"]) {
		await t.test(scenario, async (t) => {
			const { root } = await repo(t); const h = harness(root);
			const running = h.commands["task-status"]("", h.ctx);
			if (scenario === "leaf") h.changeLeaf();
			if (scenario === "session") h.changeSession();
			if (scenario === "queued") h.queueMessage();
			if (scenario === "shutdown") await h.events.session_shutdown();
			await running;
			assert.equal(h.editors.length, 0);
		});
	}
});
