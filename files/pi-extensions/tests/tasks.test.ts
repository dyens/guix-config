import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { SessionManager } from "@earendil-works/pi-coding-agent";
import planCycle from "../plan-cycle/index.ts";
import { activeState, STATE } from "../plan-cycle/core.ts";
import { taskState, TASKS, taskContext } from "../plan-cycle/tasks.ts";
let clock = 1;
const user = (content: string) => ({ role: "user", content, timestamp: clock++ }) as any;
const assistant = (content: any[]) => ({ role: "assistant", content, timestamp: clock++, api: "test", provider: "test", model: "test", stopReason: "stop", usage: {} }) as any;
function harness(root: string, session = SessionManager.inMemory(root)) {
	const tools: Record<string, any> = {}, commands: Record<string, any> = {}, events: Record<string, any> = {}, notes: string[] = [];
	let userCalls = 0;
	const ctx: any = { cwd: root, sessionManager: session, isIdle: () => true, hasPendingMessages: () => false, ui: { notify: (text: string) => notes.push(text) } };
	planCycle({ registerTool: (tool: any) => tools[tool.name] = tool, registerCommand: (name: string, command: any) => commands[name] = command.handler,
		on: (name: string, callback: any) => events[name] = callback, appendEntry: (type: string, data: any) => session.appendCustomEntry(type, data),
		sendUserMessage: () => userCalls++,
	} as any);
	async function call(name: string, args: any, siblings: any[] = [], signal?: AbortSignal) {
		const id = `call-${clock++}`;
		session.appendMessage(assistant([{ type: "toolCall", name, id, arguments: args }, ...siblings]));
		const result = await tools[name].execute(id, args, signal, undefined, ctx);
		session.appendMessage({ role: "toolResult", toolName: name, toolCallId: id, content: result.content, details: result.details, timestamp: clock++, isError: false } as any);
		return result;
	}
	async function context() { return (await events.context({ messages: session.buildSessionProjection().messages.filter(m => m.role !== "system") }, ctx)).messages; }
	async function read(path: string, content: string, extra: any[] = []) {
		const id = `read-${clock++}`;
		await writeFile(join(root, path), content);
		session.appendMessage(assistant([{ type: "text", text: "DISCARD_NARRATION" }, { type: "toolCall", name: "read", id, arguments: { path } }, ...extra]));
		await events.tool_call({ toolName: "read", toolCallId: id, input: { path } }, ctx);
		await events.tool_result({ toolName: "read", toolCallId: id, input: { path }, isError: false }, ctx);
		session.appendMessage({ role: "toolResult", toolName: "read", toolCallId: id, content: [{ type: "text", text: content }], timestamp: clock++, isError: false } as any);
		return id;
	}
	return { tools, commands, events, ctx, session, notes, call, context, read, userCalls: () => userCalls };
}
async function workspace(t: any) { const root = await mkdtemp(join(tmpdir(), "pi-tasks-")); t.after(() => rm(root, { recursive: true, force: true })); return root; }
const plan = { plan_path: ".scratch/task/plan.md", context: "Base: immutable abc; branch feature; local commits authorized, no push; required tests + independent review.", steps: [
	{ title: "Implement", instruction: "Add behavior" }, { title: "Test", needs: [1] }, { title: "Independent review + delivery" },
] };

test("structured plan starts directly, complete advances atomically, generated plan is not authoritative", async t => {
	const root = await workspace(t), h = harness(root); h.session.appendMessage(user("ORIGINAL no push"));
	await h.call("task_plan", plan);
	assert.equal(taskState(h.ctx)?.steps[0].status, "active");
	assert.ok(!JSON.stringify(await h.context()).includes('"name":"task_plan"'));
	h.session.appendMessage(assistant([{ type: "text", text: "DISCARD_STEP_REASONING" }]));
	h.session.appendMessage(user("REVOCATION no Docker"));
	await h.call("task_complete", { id: 1, result: "Behavior implemented", checks: "focused tests passed", handoff: "Uses raw bytes", notes: "Review still required" });
	const text = JSON.stringify(await h.context());
	for (const keep of ["ORIGINAL", "REVOCATION", "Behavior implemented", "Uses raw bytes", "Review still required"]) assert.ok(text.includes(keep), keep);
	assert.ok(!text.includes("DISCARD_STEP_REASONING"));
	assert.ok(!text.includes('"name":"task_complete"'));
	assert.equal(taskState(h.ctx)?.steps[1].status, "active");
	assert.match(await readFile(join(root, plan.plan_path), "utf8"), /DONE #1 Implement/);
	await writeFile(join(root, plan.plan_path), "MALICIOUS ALTERED PLAN");
	await h.call("task_complete", { id: 2, result: "Tests done" });
	assert.ok(!JSON.stringify(await h.context()).includes("MALICIOUS ALTERED PLAN"));
	await assert.rejects(h.call("task_complete", { id: 2, result: "duplicate" }), /текущий/);
	await h.call("task_complete", { id: 3, result: "Review complete; no authorized push" });
	assert.equal(taskState(h.ctx)?.steps.filter(s => s.status === "active").length, 0);
	assert.equal(activeState(h.session.getBranch())?.state.cycle, 4);
	await assert.rejects(h.call("task_complete", { id: 3, result: "again" }), /текущий/);
});

test("status is a user-only command and never calls LLM or appends conversation/state", async t => {
	const root = await workspace(t), h = harness(root); h.session.appendMessage(user("task")); await h.call("task_plan", plan);
	assert.equal(h.tools.task_get_status, undefined); assert.equal(h.tools.task_get_all, undefined);
	const before = h.session.getBranch();
	await h.commands.task_get_status("", h.ctx);
	assert.match(h.notes.at(-1)!, /Tasks: 0\/3\. Plan: .*plan.md/);
	assert.deepEqual(h.session.getBranch(), before); assert.equal(h.userCalls(), 0);
	await h.call("task_complete", { id: 1, result: "done" });
	await h.commands.task_get_status("", h.ctx); assert.match(h.notes.at(-1)!, /Tasks: 1\/3/);
});

test("blocking/replanning preserves debugging context, completed history immutable, IDs stable", async t => {
	const root = await workspace(t), h = harness(root); h.session.appendMessage(user("task")); await h.call("task_plan", plan);
	h.session.appendMessage(assistant([{ type: "text", text: "KEEP_DEBUG_CONTEXT" }]));
	const boundary = activeState(h.session.getBranch())?.entryId;
	await h.call("task_block", { id: 1, reason: "Wrong assumption; partial work exists" });
	assert.equal(activeState(h.session.getBranch())?.entryId, boundary);
	assert.ok(JSON.stringify(await h.context()).includes("KEEP_DEBUG_CONTEXT"));
	await assert.rejects(h.call("task_complete", { id: 1, result: "no" }), /blocked/);
	await h.call("task_replan", { reason: "Correct contract", steps: [{ id: 1, title: "Implement corrected" }, { id: 2, title: "Test", needs: [1] }, { title: "Review" }] });
	assert.equal(activeState(h.session.getBranch())?.entryId, boundary);
	assert.equal(taskState(h.ctx)?.steps.find(s => s.id === 3)?.status, "cancelled");
	assert.equal(taskState(h.ctx)?.steps.find(s => s.title === "Review")?.id, 4);
	assert.ok(JSON.stringify(await h.context()).includes("KEEP_DEBUG_CONTEXT"));
	await h.call("task_complete", { id: 1, result: "fixed" });
	await assert.rejects(h.call("task_replan", { reason: "rewrite history", steps: [{ id: 1, title: "Redo" }] }), /незавершённый/);
	await assert.rejects(h.call("task_replan", { reason: "bad dependencies", steps: [{ id: 2, title: "Test", needs: [999] }] }), /Зависимость/);
	assert.equal(taskState(h.ctx)?.steps.find(s => s.id === 1)?.result, "fixed");
});

test("bounded verified read carry avoids repeated guides, discards changed reads, reasoning and siblings", async t => {
	const root = await workspace(t), h = harness(root); h.session.appendMessage(user("task")); await h.call("task_plan", plan);
	const guide = await h.read("guide.md", "KEEP_GUIDE", [{ type: "toolCall", name: "bash", id: "sibling", arguments: { command: "DISCARD_COMMAND" } }]);
	h.session.appendMessage({ role: "toolResult", toolName: "bash", toolCallId: "sibling", content: [{ type: "text", text: "DISCARD_OUTPUT" }], timestamp: clock++ } as any);
	await h.read("source.ts", "OLD_SOURCE"); await writeFile(join(root, "source.ts"), "NEW_SOURCE");
	await h.read("large.txt", "X".repeat(30 * 1024));
	await h.call("task_complete", { id: 1, result: "done" });
	let text = JSON.stringify(await h.context());
	assert.ok(text.includes("KEEP_GUIDE"));
	for (const discard of ["OLD_SOURCE", "DISCARD_NARRATION", "DISCARD_COMMAND", "DISCARD_OUTPUT", "X".repeat(100)]) assert.ok(!text.includes(discard), discard.slice(0, 40));
	assert.equal((await h.context()).filter((m: any) => m.toolCallId === guide).length, 1);
	const stable = await h.context(); await writeFile(join(root, "guide.md"), "UPDATED_GUIDE");
	assert.deepEqual(await h.context(), stable);
	await h.call("task_complete", { id: 2, result: "checked" });
	text = JSON.stringify(await h.context()); assert.ok(!text.includes("KEEP_GUIDE"));
});

test("reopen and branch restore canonical tasks; no hidden migration from Markdown", async t => {
	const root = await workspace(t), storage = join(root, "sessions"); await mkdir(storage);
	const h = harness(root, SessionManager.create(root, storage)); const original = h.session.appendMessage(user("task"));
	await h.call("task_plan", plan); await h.call("task_complete", { id: 1, result: "persisted" });
	const restored = harness(root, SessionManager.open(h.session.getSessionFile()!));
	assert.equal(taskState(restored.ctx)?.steps[0].result, "persisted");
	assert.deepEqual(await restored.context(), await h.context());
	restored.session.branch(original); assert.equal(taskState(restored.ctx), undefined);
	await h.commands["plan-cycle"]("stop", h.ctx); assert.equal(taskState(h.ctx), undefined);
	await h.commands["plan-cycle"]("start old.md", h.ctx);
	await assert.rejects(h.call("task_complete", { id: 2, result: "no migration" }), /Markdown v2/);
});

test("transitions reject siblings/abort, malformed task data fails closed, legacy next cannot bypass", async t => {
	const root = await workspace(t), h = harness(root); h.session.appendMessage(user("task"));
	await assert.rejects(h.call("task_plan", plan, [{ type: "toolCall", name: "bash", id: "sibling", arguments: {} }]), /отдельно/);
	await h.call("task_plan", plan);
	await assert.rejects(h.call("plan_cycle_next", {}), /task_complete/);
	const before = taskState(h.ctx), abort = new AbortController(); abort.abort();
	await assert.rejects(h.call("task_complete", { id: 1, result: "aborted" }, [], abort.signal), /abort/i);
	assert.deepEqual(taskState(h.ctx), before);
	h.session.appendCustomEntry(TASKS, { version: 1, planPath: before!.planPath, steps: [{ id: 1, status: "oops" }] });
	assert.match(JSON.stringify(await h.context()), /PLAN-CYCLE STOP/);
	assert.equal((await h.events.tool_call({ toolName: "write", toolCallId: "x", input: {} }, h.ctx)).block, true);
});

test("completion is one durable entry and survives failed plan export without duplicate work", async t => {
	const root = await workspace(t), h = harness(root); h.session.appendMessage(user("task")); await h.call("task_plan", plan);
	assert.equal(h.session.getBranch().filter(e => e.type === "custom" && e.customType === TASKS).length, 0);
	await rm(join(root, plan.plan_path)); await mkdir(join(root, plan.plan_path));
	const answer = await h.call("task_complete", { id: 1, result: "saved despite export failure" });
	assert.match(answer.content[0].text, /Plan view unavailable/);
	const active = activeState(h.session.getBranch())!;
	assert.equal(active.state.tasks?.steps[0].result, "saved despite export failure");
	assert.equal(active.state.tasks?.steps[1].status, "active");
	assert.match(active.state.snapshot.plan, /saved despite export failure/);
	assert.equal(h.session.getBranch().filter(e => e.type === "custom" && e.customType === TASKS).length, 0);
	await assert.rejects(h.call("task_complete", { id: 1, result: "repeat" }), /текущий/);
	await rm(join(root, plan.plan_path), { recursive: true });
	await h.call("task_complete", { id: 2, result: "view repaired" });
	assert.match(await readFile(join(root, plan.plan_path), "utf8"), /view repaired/);
});

test("new task refuses to overwrite an existing plan; cancelled dependency groups can be replaced", async t => {
	const root = await workspace(t), h = harness(root); h.session.appendMessage(user("task"));
	await writeFile(join(root, "existing.md"), "UNRELATED_PLAN");
	await assert.rejects(h.call("task_plan", { ...plan, plan_path: "existing.md" }), /уже существует/);
	assert.equal(activeState(h.session.getBranch()), undefined);
	assert.equal(await readFile(join(root, "existing.md"), "utf8"), "UNRELATED_PLAN");
	await h.call("task_plan", plan);
	await h.call("task_replan", { reason: "Replace dependent implementation/test group, preserve required review", steps: [{ title: "Correct implementation and test" }, { id: 3, title: "Independent review + delivery" }] });
	assert.equal(taskState(h.ctx)?.steps.filter(s => s.status === "cancelled").length, 2);
	assert.equal(taskState(h.ctx)?.steps.find(s => s.status === "active")?.id, 4);
});

test("read carry respects canonical omissions, prioritizes guides and caps count", async t => {
	const root = await workspace(t), h = harness(root); h.session.appendMessage(user("task")); await h.call("task_plan", plan);
	await h.read("guide.md", "IMPORTANT_GUIDE");
	const omittedId = await h.read("omit.md", "OMITTED_BYTES");
	const resultEntry = h.session.getBranch().find(e => e.type === "message" && e.message.role === "toolResult" && e.message.toolCallId === omittedId)!;
	h.session.appendContextEdit(resultEntry.id, null);
	for (let i = 0; i < 12; i++) await h.read(`source-${i}.ts`, `SOURCE_${i}`);
	await h.call("task_complete", { id: 1, result: "done" });
	const messages = await h.context(), text = JSON.stringify(messages);
	assert.ok(text.includes("IMPORTANT_GUIDE")); assert.ok(!text.includes("OMITTED_BYTES"));
	assert.equal(messages.filter((m: any) => m.role === "toolResult" && m.toolName === "read").length, 8);
	const callIds = messages.filter((m: any) => m.role === "assistant").flatMap((m: any) => m.content.filter((b: any) => b.type === "toolCall").map((b: any) => b.id));
	for (const m of messages.filter((m: any) => m.role === "toolResult")) assert.ok(callIds.includes(m.toolCallId));
});

test("Git paths and commits are observed without manual model inventories or git writes", async t => {
	const root = await workspace(t), h = harness(root);
	const git = (...args: string[]) => execFileSync("git", args, { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
	git("init"); git("config", "user.name", "Test"); git("config", "user.email", "test@example.invalid");
	await writeFile(join(root, "a.ts"), "base"); git("add", "a.ts"); git("commit", "-m", "base");
	h.session.appendMessage(user("task")); await h.call("task_plan", plan);
	await writeFile(join(root, "a.ts"), "changed"); git("add", "a.ts"); git("commit", "-m", "owned implementation");
	await writeFile(join(root, "new.ts"), "untracked"); const head = git("rev-parse", "HEAD");
	await h.call("task_complete", { id: 1, result: "implemented" });
	const observed = taskState(h.ctx)?.steps[0].git;
	assert.equal(observed?.head, head); assert.ok(observed?.committedPaths.some(path => path.includes("a.ts")));
	assert.ok(observed?.paths.some(path => path.includes("new.ts"))); assert.equal(git("rev-parse", "HEAD"), head);
});

test("300-step archive does not become model context; fetch one old result only on demand", async t => {
	const root = await workspace(t), h = harness(root); h.session.appendMessage(user("task"));
	await h.call("task_plan", { ...plan, steps: Array.from({ length: 300 }, (_, i) => ({ title: `Step ${i + 1}` })) });
	const state = taskState(h.ctx)!;
	for (const step of state.steps.slice(0, 299)) { step.status = "done"; step.result = `ARCHIVED_${step.id}_` + "x".repeat(900); }
	state.steps[299].status = "active";
	const context = taskContext(state);
	assert.ok(context.length < 4000); assert.ok(!context.includes("ARCHIVED_1_")); assert.ok(context.includes("ARCHIVED_299_"));
	h.session.appendCustomEntry(TASKS, state);
	assert.match((await h.call("task_get", { id: 1 })).content[0].text, /ARCHIVED_1_/);
	assert.equal(h.session.getBranch().filter(e => e.type === "custom" && e.customType === STATE).length, 1);
});
