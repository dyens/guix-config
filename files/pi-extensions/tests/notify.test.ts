import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { registerNotifications, sendDesktopNotification } from "../notify.ts";

function fixture(send?: any) {
	const events: Record<string, any> = {}, sent: any[] = [], warnings: string[] = [];
	let session = "session-1";
	const ctx = { mode: "tui", cwd: "/home/user/project", sessionManager: { getSessionId: () => session },
		ui: { notify: (text: string) => warnings.push(text) } };
	registerNotifications({ on: (event: string, handler: any) => { events[event] = handler; } } as any,
		send ?? (async (cwd: string, outcome: string) => { sent.push({ cwd, outcome }); }));
	const fire = async (name: string, event: any = {}) => events[name]?.(event, ctx);
	return { events, ctx, sent, warnings, fire, switchSession: () => { session = "session-2"; } };
}

async function withDesktop(body: () => Promise<void>) {
	const display = process.env.DISPLAY, wayland = process.env.WAYLAND_DISPLAY;
	process.env.DISPLAY = ":test";
	delete process.env.WAYLAND_DISPLAY;
	try { await body(); }
	finally {
		if (display === undefined) delete process.env.DISPLAY; else process.env.DISPLAY = display;
		if (wayland === undefined) delete process.env.WAYLAND_DISPLAY; else process.env.WAYLAND_DISPLAY = wayland;
	}
}

test("notify once only on final settlement, not on tools, turns or agent_end", async () => withDesktop(async () => {
	const f = fixture();
	await f.fire("agent_settled"); assert.equal(f.sent.length, 0);
	await f.fire("agent_start");
	assert.equal(f.events.agent_end, undefined);
	assert.equal(f.events.tool_result, undefined);
	await f.fire("turn_end", { message: { role: "assistant", stopReason: "stop" } });
	assert.equal(f.sent.length, 0);
	await f.fire("agent_before_settle", { outcome: "completed" });
	assert.equal(f.sent.length, 0);
	// A queued continuation starts another low-level run before settling.
	await f.fire("agent_start");
	await f.fire("agent_before_settle", { outcome: "completed" });
	await f.fire("agent_settled"); await f.fire("agent_settled");
	assert.deepEqual(f.sent, [{ cwd: "/home/user/project", outcome: "completed" }]);
}));

test("errors notify, aborted runs and recovered intermediate errors do not mislabel completion", async () => withDesktop(async () => {
	const f = fixture();
	await f.fire("agent_start"); await f.fire("agent_before_settle", { outcome: "error" }); await f.fire("agent_settled");
	assert.equal(f.sent[0].outcome, "error");
	await f.fire("agent_start"); await f.fire("agent_before_settle", { outcome: "aborted" }); await f.fire("agent_settled");
	assert.equal(f.sent.length, 1);
	// Aborted activities may never enter agent_before_settle.
	await f.fire("agent_start"); await f.fire("turn_end", { message: { role: "assistant", stopReason: "aborted" } }); await f.fire("agent_settled");
	assert.equal(f.sent.length, 1);
	const controller = new AbortController();
	(f.ctx as any).signal = controller.signal;
	await f.fire("agent_start"); controller.abort(); delete (f.ctx as any).signal;
	await f.fire("agent_settled"); assert.equal(f.sent.length, 1);
	await f.fire("agent_start"); await f.fire("agent_before_settle", { outcome: "error" });
	await f.fire("agent_start"); await f.fire("agent_before_settle", { outcome: "completed" }); await f.fire("agent_settled");
	assert.equal(f.sent[1].outcome, "completed");
}));

test("headless and noninteractive runs stay quiet; Wayland is supported", async () => withDesktop(async () => {
	const f = fixture();
	for (const mode of ["json", "rpc", "print"]) {
		f.ctx.mode = mode; await f.fire("agent_start"); await f.fire("agent_settled");
	}
	assert.equal(f.sent.length, 0);
	f.ctx.mode = "tui"; delete process.env.DISPLAY;
	await f.fire("agent_start"); await f.fire("agent_settled"); assert.equal(f.sent.length, 0);
	process.env.WAYLAND_DISPLAY = "wayland-test";
	await f.fire("agent_start"); await f.fire("agent_settled"); assert.equal(f.sent.length, 1);
}));

test("session changes and shutdown invalidate pending notifications", async () => withDesktop(async () => {
	const f = fixture();
	await f.fire("agent_start"); f.switchSession(); await f.fire("agent_settled"); assert.equal(f.sent.length, 0);
	for (const event of ["session_start", "session_shutdown"]) {
		await f.fire("agent_start"); await f.fire(event); await f.fire("agent_settled");
	}
	assert.equal(f.sent.length, 0);
}));

test("notification failures do not fail the run and warn only once until recovery", async () => withDesktop(async () => {
	let fail = true;
	const f = fixture(async () => { if (fail) throw new Error("Sensitive process error must not be displayed"); });
	for (let i = 0; i < 2; i++) { await f.fire("agent_start"); await f.fire("agent_settled"); }
	assert.equal(f.warnings.length, 1); assert.doesNotMatch(f.warnings[0], /Sensitive/);
	fail = false; await f.fire("agent_start"); await f.fire("agent_settled");
	fail = true; await f.fire("agent_start"); await f.fire("agent_settled");
	assert.equal(f.warnings.length, 2);
}));

test("notify-send is invoked directly with bounded generic text and escaped project markup", async () => {
	const dir = await mkdtemp(join(tmpdir(), "pi-notify-test-"));
	const oldPath = process.env.PATH;
	try {
		const record = join(dir, "arguments");
		await writeFile(join(dir, "notify-send"), `#!${process.execPath}\nrequire('node:fs').writeFileSync(${JSON.stringify(record)}, JSON.stringify(process.argv.slice(2)));\n`, { mode: 0o700 });
		process.env.PATH = `${dir}:${oldPath}`;
		await sendDesktopNotification("/home/user/project<>&\n$(touch nope)", "completed");
		const args = JSON.parse(await readFile(record, "utf8"));
		assert.deepEqual(args, ["--app-name=Pi", "--urgency=normal", "--expire-time=5000", "--icon=dialog-information", "--", "Pi — готово", "Проект: project&lt;&gt;&amp; $(touch nope)"]);
		await sendDesktopNotification("/home/user/project", "error");
		const errorArgs = JSON.parse(await readFile(record, "utf8"));
		assert.ok(errorArgs.includes("--icon=dialog-error")); assert.ok(errorArgs.includes("Pi — ошибка"));
		process.env.PATH = join(dir, "missing");
		await assert.rejects(sendDesktopNotification("project", "completed"), { code: "ENOENT" });
	} finally { process.env.PATH = oldPath; await rm(dir, { recursive: true, force: true }); }
});
