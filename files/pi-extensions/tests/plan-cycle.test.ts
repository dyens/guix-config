import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";
import { DefaultResourceLoader, ExtensionRunner, SessionManager, SettingsManager } from "@earendil-works/pi-coding-agent";
import planCycle from "../plan-cycle/index.ts";
import { activeState, filePath, MAX_PLAN_BYTES, nextTask, readPlan, STATE } from "../plan-cycle/core.ts";

let clock = 1;
function user(content: string) { return { role: "user", content, timestamp: clock++ } as any; }
function assistant(content: any[]) { return { role: "assistant", content, timestamp: clock++, api: "test", provider: "test", model: "test", stopReason: "stop", usage: {} } as any; }
function toolResult(id: string, name: string, text: string) {
	return { role: "toolResult", toolCallId: id, toolName: name, content: [{ type: "text", text }], isError: false, timestamp: clock++ } as any;
}
async function workspace(t: any) {
	const root = await mkdtemp(join(tmpdir(), "pi-plan-cycle-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	return root;
}
function harness(root: string, session = SessionManager.inMemory(root)) {
	const events: Record<string, any> = {}, commands: Record<string, any> = {}, tools: Record<string, any> = {};
	const notes: string[] = [];
	let idle = true, queued = false;
	const ctx: any = { cwd: root, sessionManager: session, isIdle: () => idle, hasPendingMessages: () => queued,
		ui: { notify: (message: string) => notes.push(message) } };
	planCycle({ on: (name: string, handler: any) => { events[name] = handler; },
		registerTool: (tool: any) => { tools[tool.name] = tool; },
		registerCommand: (name: string, command: any) => { commands[name] = command.handler; },
		appendEntry: (type: string, data: any) => session.appendCustomEntry(type, data),
		sendUserMessage: (text: string) => session.appendMessage(user(text)),
	} as any);
	async function command(text: string) { await commands["plan-cycle"](text, ctx); }
	async function context(override?: any[]) {
		return (await events.context({ messages: override ?? session.buildSessionContext().messages.filter(message => message.role !== "system") }, ctx))?.messages;
	}
	async function read(path: string, id: string, capture = true, error = false) {
		session.appendMessage(assistant([{ type: "toolCall", id, name: "read", arguments: { path } }]));
		if (capture) await events.tool_call({ toolName: "read", toolCallId: id, input: { path } }, ctx);
		const content = error ? "read failed" : await readFile(filePath(path, root), "utf8");
		if (capture) await events.tool_result({ toolName: "read", toolCallId: id, input: { path }, isError: error }, ctx);
		const result = toolResult(id, "read", content); result.isError = error;
		session.appendMessage(result);
	}
	async function start(path = "plan.md", siblings: any[] = []) {
		const id = `start-${clock}`;
		session.appendMessage(assistant([{ type: "toolCall", id, name: "plan_cycle_start", arguments: { plan_path: path } }, ...siblings]));
		const result = await tools.plan_cycle_start.execute(id, { plan_path: path }, undefined, undefined, ctx);
		session.appendMessage(toolResult(id, "plan_cycle_start", result.content[0].text));
	}
	async function next(siblings: any[] = []) {
		const id = `next-${clock}`;
		session.appendMessage(assistant([{ type: "toolCall", id, name: "plan_cycle_next", arguments: {} }, ...siblings]));
		const result = await tools.plan_cycle_next.execute(id, {}, undefined, undefined, ctx);
		session.appendMessage({ ...toolResult(id, "plan_cycle_next", result.content[0].text), details: result.details });
		return result;
	}
	return { ctx, events, notes, session, command, context, read, start, next,
		busy: () => { idle = false; }, queued: () => { queued = true; } };
}

const plan = "# План\n- TODO Первый шаг\n- TODO Review\n";

test("model start saves intake checkpoint without an orphan pending tool call; runner needs no slash commands", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("APPROVED_TASK"));
	await writeFile(join(root, "input.txt"), "INTAKE_EVIDENCE"); await h.read("input.txt", "input");
	await h.start();
	let messages = await h.context();
	assert.match(JSON.stringify(messages), /APPROVED_TASK/);
	assert.match(JSON.stringify(messages), /INTAKE_EVIDENCE/);
	assert.ok(!JSON.stringify(messages).includes('"name":"plan_cycle_start"'));
	assert.ok(!JSON.stringify(messages).includes('"toolName":"plan_cycle_start"'));
	await writeFile(join(root, "plan.md"), plan); await h.next();
	messages = await h.context();
	assert.ok(!JSON.stringify(messages).includes('"name":"plan_cycle_start"'));
	assert.equal(activeState(h.session.getBranch())?.state.cycle, 1);
	await assert.rejects(h.start(), /уже включён/);
	const other = harness(root);
	other.session.appendMessage(user("task"));
	await assert.rejects(other.start("plan.md", [{ type: "toolCall", id: "write", name: "write", arguments: {} }]), /отдельно/);
});

test("legacy work-cycles session fails closed under default runtime, requires explicit legacy launcher", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("legacy task")); h.session.appendCustomEntry("ruclaw-work-cycle", {});
	assert.match(JSON.stringify(await h.context()), /--legacy-cycles/);
	assert.equal((await h.events.tool_call({ toolName: "write", toolCallId: "x", input: {} }, h.ctx)).block, true);
	await assert.rejects(h.start(), /Legacy work-cycles/);
});

test("checkpoint + step-frozen plan + only current step; newer user revocations survive every reset", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("ORIGINAL TASK; no automatic commits"));
	h.session.appendMessage(assistant([{ type: "text", text: "BASE KNOWLEDGE" }]));
	await h.command("start plan.md");
	assert.equal(activeState(h.session.getBranch())?.state.mode, "planning");
	assert.match(JSON.stringify(await h.context()), /Файл пока не создан/);
	await writeFile(join(root, "plan.md"), plan);
	h.session.appendMessage(assistant([{ type: "text", text: "PLANNING DETAILS TO DISCARD" }]));
	h.session.appendMessage(user("REVOCATION: do not use Docker"));
	await h.command("next");
	let text = JSON.stringify(await h.context());
	for (const keep of ["ORIGINAL TASK", "BASE KNOWLEDGE", "REVOCATION", "CURRENT PLAN"]) assert.ok(text.includes(keep), keep);
	assert.ok(!text.includes("PLANNING DETAILS TO DISCARD"));
	h.session.appendMessage(assistant([{ type: "text", text: "STEP ONE INTERNAL DETAILS" }]));
	await writeFile(join(root, "plan.md"), "- DONE Первый шаг\n  Итог: created a.ts\n- TODO Review\n");
	await h.next();
	h.session.appendMessage(assistant([{ type: "text", text: "CURRENT STEP DETAILS" }]));
	text = JSON.stringify(await h.context());
	assert.ok(!text.includes("STEP ONE INTERNAL DETAILS"));
	assert.ok(text.includes("CURRENT STEP DETAILS"));
	assert.ok(text.includes("REVOCATION"));
	assert.ok(text.includes("created a.ts"));
	assert.ok(!text.includes("- TODO Первый шаг"));
	assert.ok(!text.includes('"toolName":"plan_cycle_next"'));
	assert.equal(activeState(h.session.getBranch())?.state.cycle, 2);
});

test("questionnaire call/result pairs survive steps and reopen without sibling work or forged user consent", async t => {
	const root = await workspace(t), storage = join(root, "sessions");
	await mkdir(storage);
	const h = harness(root, SessionManager.create(root, storage));
	h.session.appendMessage(user("ORIGINAL_TASK"));
	await h.command("start plan.md"); await writeFile(join(root, "plan.md"), plan); await h.command("next");
	const before = await h.context();
	const call = { type: "toolCall", id: "question", name: "ask_user_question", arguments: {
		questions: [{ header: "Q1", question: "May we push?", options: [
			{ label: "No", description: "Local only" }, { label: "Yes", description: "Publish" }], multiSelect: false }],
	} };
	h.session.appendMessage(assistant([{ type: "text", text: "DISCARD_EXPLANATION" }, call,
		{ type: "toolCall", id: "sibling", name: "bash", arguments: { command: "DISCARD_COMMAND" } }]));
	h.session.appendMessage(toolResult("sibling", "bash", "DISCARD_OUTPUT"));
	const result = { ...toolResult("question", "ask_user_question", "User has answered: No; user notes: never force push"),
		details: { answers: [{ questionIndex: 0, question: "May we push?", kind: "option", answer: "No", notes: "never force push" }], cancelled: false } };
	h.session.appendMessage(result);
	const live = await h.context();
	assert.deepEqual(live.slice(0, before.length), before);
	await h.next();
	h.session.appendMessage(user("Later correction: no commits either"));
	await h.next();
	const restored = harness(root, SessionManager.open(h.session.getSessionFile()!));
	const messages = await restored.context(), text = JSON.stringify(messages);
	for (const value of ["DISCARD_EXPLANATION", "DISCARD_COMMAND", "DISCARD_OUTPUT"]) assert.ok(!text.includes(value), value);
	assert.deepEqual(messages.find((m: any) => m.role === "assistant" && m.content.some((b: any) => b.id === "question")).content, [call]);
	assert.deepEqual(messages.find((m: any) => m.role === "toolResult" && m.toolCallId === "question"), result);
	assert.equal(messages.filter((m: any) => m.role === "toolResult" && m.toolName === "ask_user_question").length, 1);
	assert.ok(messages.findIndex((m: any) => m.toolCallId === "question") < messages.findIndex((m: any) => m.role === "user" && JSON.stringify(m).includes("Later correction")));
	assert.ok(!messages.some((m: any) => m.role === "user" && JSON.stringify(m).includes("User has answered")));
	assert.deepEqual(await restored.context(), messages);
});

test("questionnaire cancellations, failures, partial/custom/multi answers and notes stay exact, not approval", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("task")); await h.command("start plan.md");
	await writeFile(join(root, "plan.md"), plan);
	const cases = [
		{ answers: [], cancelled: true },
		{ answers: [], cancelled: true, error: "no_ui" },
		{ answers: [], cancelled: false, globalNote: "Investigate only", unanswered: [0] },
		{ answers: [{ questionIndex: 0, kind: "custom", answer: "Do not deploy" }], cancelled: false, unanswered: [1] },
		{ answers: [{ questionIndex: 0, kind: "multi", answer: "custom", selected: ["Unit", "Integration"], notes: "isolated" }], cancelled: false },
	];
	const results: any[] = [];
	for (const [i, details] of cases.entries()) {
		h.session.appendMessage(assistant([{ type: "toolCall", id: "reused-id", name: "ask_user_question", arguments: { questions: [{ question: `Q${i}?` }] } }]));
		const result = { ...toolResult("reused-id", "ask_user_question", `EXACT_ENVELOPE_${i}`), details, isError: i === 1 };
		h.session.appendMessage(result); results.push(result);
		await h.next();
	}
	const messages = await h.context();
	assert.deepEqual(messages.filter((m: any) => m.role === "toolResult" && m.toolName === "ask_user_question"), results);
	assert.equal(messages.filter((m: any) => m.role === "assistant").length, cases.length);
	assert.match(JSON.stringify(messages), /НЕ означают согласие/);
});

test("canonical omissions are not resurrected; missing questionnaire half or external filter stops safely", async t => {
	for (const scenario of ["omit-both", "omit-call", "omit-result", "filter-call", "filter-result", "pending"]) {
		await t.test(scenario, async t => {
			const root = await workspace(t), h = harness(root);
			h.session.appendMessage(user("task")); await h.command("start plan.md");
			await writeFile(join(root, "plan.md"), plan);
			const callId = h.session.appendMessage(assistant([{ type: "toolCall", id: "q", name: "ask_user_question", arguments: { questions: [{ question: "ORIGINAL_QUESTION?" }] } }]));
			const resultId = scenario === "pending" ? undefined : h.session.appendMessage(toolResult("q", "ask_user_question", "ORIGINAL_ANSWER"));
			if (["omit-both", "omit-call"].includes(scenario)) h.session.appendContextEdit(callId, null);
			if (["omit-both", "omit-result"].includes(scenario)) h.session.appendContextEdit(resultId!, null);
			await h.next();
			const override = scenario.startsWith("filter-") ? h.session.buildSessionContext().messages.filter(m =>
				scenario === "filter-call" ? m.role !== "assistant" : m.role !== "toolResult" || m.toolName !== "ask_user_question") : undefined;
			const text = JSON.stringify(await h.context(override));
			if (scenario === "omit-both") {
				assert.ok(!text.includes("ORIGINAL_QUESTION")); assert.ok(!text.includes("ORIGINAL_ANSWER"));
				assert.ok(!text.includes("PLAN-CYCLE STOP"));
			} else {
				assert.match(text, /PLAN-CYCLE STOP/);
				assert.equal((await h.events.tool_call({ toolName: "write", toolCallId: "x", input: {} }, h.ctx)).block, true);
			}
		});
	}
});

test("parallel questionnaire results keep order and abandoned branch answers never leak", async t => {
	const root = await workspace(t), h = harness(root);
	const original = h.session.appendMessage(user("task"));
	await h.command("start plan.md"); await writeFile(join(root, "plan.md"), plan);
	h.session.appendMessage(assistant(["q1", "q2"].map(id => ({ type: "toolCall", id, name: "ask_user_question", arguments: { questions: [{ question: id }] } }))));
	h.session.appendMessage(toolResult("q2", "ask_user_question", "ANSWER_SECOND_FIRST"));
	h.session.appendMessage(user("Correction between answers"));
	h.session.appendMessage(toolResult("q1", "ask_user_question", "ANSWER_FIRST_LAST"));
	await h.next();
	const messages = await h.context();
	assert.deepEqual(messages.filter((m: any) => m.role === "toolResult").map((m: any) => m.toolCallId), ["q2", "q1"]);
	assert.deepEqual(messages.find((m: any) => m.role === "assistant").content.map((b: any) => b.id), ["q1", "q2"]);
	h.session.branch(original);
	h.session.appendMessage(user("ALTERNATIVE_TASK"));
	await h.command("start plan.md"); await h.next();
	const text = JSON.stringify(await h.context());
	assert.match(text, /ALTERNATIVE_TASK/);
	assert.ok(!text.includes("ANSWER_SECOND_FIRST")); assert.ok(!text.includes("ANSWER_FIRST_LAST"));
});

test("questionnaire already in checkpoint is retained once with its original assistant message", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("task"));
	const original = assistant([{ type: "text", text: "CHECKPOINT_CONTEXT" }, { type: "toolCall", id: "q", name: "ask_user_question", arguments: {} }]);
	h.session.appendMessage(original);
	const result = toolResult("q", "ask_user_question", "CHECKPOINT_ANSWER"); h.session.appendMessage(result);
	await h.command("start plan.md"); await writeFile(join(root, "plan.md"), plan);
	await h.next(); await h.next();
	const messages = await h.context();
	assert.deepEqual(messages.find((m: any) => m.role === "assistant"), original);
	assert.deepEqual(messages.filter((m: any) => m.toolCallId === "q"), [result]);
});

test("changed/deleted/untracked reads invalidated, unchanged ranges retained, old plan replaced", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("task"));
	for (const [path, text] of Object.entries({ "a.txt": "OLD_A", "gone.txt": "OLD_GONE", "same.txt": "KEEP_SAME", "unknown.txt": "OLD_UNKNOWN", "plan.md": plan })) await writeFile(join(root, path), text);
	await h.read("a.txt", "read-a");
	await h.read("gone.txt", "read-gone");
	await h.read("same.txt", "range-1"); await h.read("same.txt", "range-2");
	await h.read("unknown.txt", "read-unknown", false);
	await h.read("plan.md", "read-plan");
	await h.command("start plan.md");
	await writeFile(join(root, "a.txt"), "NEW_A"); await rm(join(root, "gone.txt"));
	await h.command("next");
	const messages = await h.context(), text = JSON.stringify(messages);
	for (const old of ["OLD_A", "OLD_GONE", "OLD_UNKNOWN"]) assert.ok(!text.includes(old), old);
	assert.ok(text.includes("KEEP_SAME"));
	assert.ok(text.includes("STALE READ"));
	assert.match(text, /удалён, недоступен/);
	assert.equal(messages.filter((m: any) => m.role === "toolResult" && m.toolCallId === "read-a").length, 1);
	assert.match(messages.find((m: any) => m.toolCallId === "read-plan").content[0].text, /План представлен отдельно/);
	// Re-reading current bytes supplies a new valid result, never resurrecting old bytes.
	await h.read("a.txt", "fresh-a");
	const fresh = JSON.stringify(await h.context());
	assert.ok(fresh.includes("NEW_A")); assert.ok(!fresh.includes("OLD_A"));
});

test("symlink retarget and changes between pre/post read are not trusted", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("task"));
	await writeFile(join(root, "one"), "OLD_TARGET"); await writeFile(join(root, "two"), "NEW_TARGET");
	await symlink("one", join(root, "link")); await h.read("link", "symlink-read");
	await writeFile(join(root, "plan.md"), plan);
	await rm(join(root, "link")); await symlink("two", join(root, "link"));
	await h.events.tool_call({ toolName: "read", toolCallId: "racy", input: { path: "two" } }, h.ctx);
	await writeFile(join(root, "two"), "AFTER_RACE");
	await h.events.tool_result({ toolName: "read", toolCallId: "racy", input: { path: "two" }, isError: false }, h.ctx);
	h.session.appendMessage(assistant([{ type: "toolCall", id: "racy", name: "read", arguments: { path: "two" } }]));
	h.session.appendMessage(toolResult("racy", "read", "RACY_RESULT"));
	await h.command("start plan.md");
	const text = JSON.stringify(await h.context());
	assert.ok(!text.includes("OLD_TARGET")); assert.ok(!text.includes("RACY_RESULT"));
});

test("read aliases resolve to the same file and stale results lose image/details payloads", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("task"));
	await writeFile(join(root, "a.txt"), "ALIAS_OLD");
	await h.read("@a.txt", "at-read");
	await h.read(new URL(`file://${root}/a.txt`).href, "url-read");
	h.session.appendMessage(assistant([{ type: "toolCall", id: "image", name: "read", arguments: { path: "a.txt" } }]));
	h.session.appendMessage({ ...toolResult("image", "read", "OLD_IMAGE_TEXT"),
		content: [{ type: "image", data: "OLD_IMAGE_BYTES", mimeType: "image/png" }], details: { old: "OLD_DETAILS" } });
	await h.command("start plan.md"); await writeFile(join(root, "plan.md"), plan);
	await writeFile(join(root, "a.txt"), "ALIAS_NEW"); await h.command("next");
	const text = JSON.stringify(await h.context());
	for (const old of ["ALIAS_OLD", "OLD_IMAGE_TEXT", "OLD_IMAGE_BYTES", "OLD_DETAILS"]) assert.ok(!text.includes(old));
	assert.ok(text.includes("STALE READ"));
});

test("INPROGRESS/BLOCKED refuse next without discarding useful debugging context; all DONE does not loop", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("task")); await h.command("start plan.md");
	for (const status of ["INPROGRESS", "BLOCKED"]) {
		await writeFile(join(root, "plan.md"), `- ${status} Debug\n- TODO Review\n`);
		h.session.appendMessage(assistant([{ type: "text", text: `KEEP_${status}` }]));
		await assert.rejects(h.next(), new RegExp(status));
		assert.equal(activeState(h.session.getBranch())?.state.cycle, 0);
		assert.ok(JSON.stringify(await h.context()).includes(`KEEP_${status}`));
	}
	await writeFile(join(root, "plan.md"), "- DONE All\n");
	assert.equal((await h.next()).details.changed, false);
	assert.equal(activeState(h.session.getBranch())?.state.cycle, 0);
	await writeFile(join(root, "plan.md"), plan);
	await assert.rejects(h.next([{ type: "toolCall", id: "sibling", name: "write", arguments: {} }]), /отдельно/);
});

test("state and read provenance survive actual session reopen; only active branch controls state", async t => {
	const root = await workspace(t), storage = join(root, "sessions");
	await mkdir(storage);
	const session = SessionManager.create(root, storage), h = harness(root, session);
	const original = session.appendMessage(user("ORIGINAL_PERSISTED"));
	await writeFile(join(root, "a.txt"), "PERSISTED_OLD"); await h.read("a.txt", "persist-read");
	await h.command("start plan.md"); await writeFile(join(root, "plan.md"), plan); await h.command("next");
	session.appendMessage(assistant([{ type: "text", text: "DISCARD_AFTER_RESTART" }]));
	await writeFile(join(root, "a.txt"), "PERSISTED_NEW");
	await h.next();
	const reopened = SessionManager.open(session.getSessionFile()!);
	const restored = harness(root, reopened);
	const text = JSON.stringify(await restored.context());
	assert.ok(text.includes("ORIGINAL_PERSISTED"));
	assert.ok(!text.includes("PERSISTED_OLD")); assert.ok(!text.includes("DISCARD_AFTER_RESTART"));
	assert.equal(activeState(reopened.getBranch())?.state.cycle, 2);
	const stable = await restored.context();
	await writeFile(join(root, "a.txt"), "CHANGED_AFTER_BOUNDARY");
	await writeFile(join(root, "plan.md"), "- INPROGRESS Первый шаг\n- TODO Review\n");
	const again = harness(root, SessionManager.open(session.getSessionFile()!));
	assert.deepEqual(await again.context(), stable);
	reopened.branch(original);
	assert.equal(activeState(reopened.getBranch()), undefined);
	assert.equal(await restored.context(), undefined);
});

test("unknown transform or external compaction fail closed and block tool execution", async t => {
	for (const scenario of ["transform", "removed-user", "compaction", "missing-boundary"]) {
		await t.test(scenario, async t => {
			const root = await workspace(t), h = harness(root);
			h.session.appendMessage(user("KEEP_USER")); await writeFile(join(root, "plan.md"), plan);
			await h.command("start plan.md"); await h.command("next");
			h.session.appendMessage(assistant([{ type: "text", text: "SHOULD_NOT_LEAK" }]));
			let override: any[] | undefined;
			if (scenario === "transform") override = [user("unknown message")];
			if (scenario === "removed-user") override = h.session.buildSessionContext().messages.filter(m => m.role !== "user");
			if (scenario === "compaction") h.session.appendCompaction("OLD_SUMMARY", h.session.getLeafId()!, 1000);
			if (scenario === "missing-boundary") {
				const active = activeState(h.session.getBranch())!;
				h.session.appendCustomEntry(STATE, { ...active.state, checkpointId: "absent" });
			}
			const messages = await h.context(override), text = JSON.stringify(messages);
			assert.match(text, /PLAN-CYCLE STOP/); assert.ok(!text.includes("SHOULD_NOT_LEAK"));
			const blocked = await h.events.tool_call({ toolName: "write", toolCallId: "x", input: {} }, h.ctx);
			assert.equal(blocked.block, true);
			await h.command("stop");
			assert.equal(await h.context(), undefined);
			assert.equal(await h.events.tool_call({ toolName: "write", toolCallId: "x", input: {} }, h.ctx), undefined);
		});
	}
});

test("honors context_edit omissions/replacements; original raw history is untouched", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("TASK"));
	const omitted = h.session.appendMessage(assistant([{ type: "text", text: "OMITTED" }]));
	const replaced = h.session.appendMessage(user("BEFORE_EDIT"));
	h.session.appendContextEdit(omitted, null);
	h.session.appendContextEdit(replaced, { content: "AFTER_EDIT" });
	await writeFile(join(root, "plan.md"), plan); await h.command("start plan.md"); await h.command("next");
	const text = JSON.stringify(await h.context());
	assert.ok(!text.includes("OMITTED")); assert.ok(!text.includes("BEFORE_EDIT")); assert.ok(text.includes("AFTER_EDIT"));
	assert.ok(JSON.stringify(h.session.getEntries()).includes("OMITTED"));
});

test("commands guard empty/busy/queued sessions; compaction cancelled only while enabled", async t => {
	const root = await workspace(t), h = harness(root);
	await h.command("start plan.md"); assert.match(h.notes.at(-1)!, /исходную задачу/);
	h.session.appendMessage(user("task")); h.busy(); await h.command("start plan.md");
	assert.match(h.notes.at(-1)!, /Дождись/);
	const queued = harness(root, h.session); queued.queued(); await queued.command("start plan.md");
	assert.equal(activeState(h.session.getBranch()), undefined);
	const ready = harness(root, h.session);
	assert.equal(await ready.events.session_before_compact({}, ready.ctx), undefined);
	await ready.command("start plan.md");
	assert.deepEqual(await ready.events.session_before_compact({}, ready.ctx), { cancel: true });
});

test("stop recovers corrupt state and aborted transitions never append a boundary", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("task"));
	h.session.appendCustomEntry(STATE, { version: 99, enabled: true });
	assert.match(JSON.stringify(await h.context()), /PLAN-CYCLE STOP/);
	await h.command("stop");
	assert.equal(await h.context(), undefined);
	assert.equal(await h.events.session_before_compact({}, h.ctx), undefined);
	await h.command("start plan.md"); await writeFile(join(root, "plan.md"), plan);
	const id = "aborted-next";
	h.session.appendMessage(assistant([{ type: "toolCall", id, name: "plan_cycle_next", arguments: {} }]));
	const controller = new AbortController(); controller.abort();
	const tools: any[] = [];
	planCycle({ on: () => {}, registerCommand: () => {}, registerTool: (tool: any) => tools.push(tool) } as any);
	await assert.rejects(tools.find(tool => tool.name === "plan_cycle_next").execute(id, {}, controller.signal, undefined, h.ctx), /abort/i);
	assert.equal(activeState(h.session.getBranch())?.state.cycle, 0);
});

test("prefix stays byte-identical across plan/source edits, deletes, fresh reads and reload within a step", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("task"));
	await writeFile(join(root, "a.txt"), "BASE_SOURCE");
	await h.read("a.txt", "base-read");
	await writeFile(join(root, "plan.md"), plan);
	await h.command("start plan.md"); await h.command("next");
	const before = await h.context();
	await h.read("a.txt", "step-read");
	await writeFile(join(root, "a.txt"), "NEW_SOURCE");
	await writeFile(join(root, "plan.md"), "- INPROGRESS Первый шаг\n- TODO Review\n");
	await h.read("plan.md", "current-plan");
	await h.read("a.txt", "new-source");
	const after = await h.context();
	assert.deepEqual(after.slice(0, before.length), before);
	assert.equal(after.find((m: any) => m.toolCallId === "current-plan").content[0].text, "- INPROGRESS Первый шаг\n- TODO Review\n");
	assert.equal(after.find((m: any) => m.toolCallId === "step-read").content[0].text, "BASE_SOURCE");
	assert.equal(after.find((m: any) => m.toolCallId === "new-source").content[0].text, "NEW_SOURCE");
	await rm(join(root, "a.txt"));
	const reloaded = harness(root, h.session);
	assert.deepEqual(await reloaded.context(), after);
	await writeFile(join(root, "plan.md"), "- DONE Первый шаг\n  Итог: deleted a.txt\n- TODO Review\n");
	await reloaded.next();
	const next = await reloaded.context(), text = JSON.stringify(next);
	assert.match(text, /STALE READ/); assert.match(text, /удалён, недоступен/);
	assert.ok(!text.includes("BASE_SOURCE")); assert.ok(!text.includes("NEW_SOURCE"));
	assert.ok(text.includes("deleted a.txt"));
	assert.ok(!text.includes('"toolCallId":"current-plan"'));
});

test("missing plan inside a step preserves prefix but next refuses it; legacy state never migrates silently", async t => {
	const root = await workspace(t), h = harness(root);
	h.session.appendMessage(user("task")); await writeFile(join(root, "plan.md"), plan);
	await h.command("start plan.md"); await h.command("next");
	const before = await h.context();
	await rm(join(root, "plan.md"));
	assert.deepEqual(await h.context(), before);
	await assert.rejects(h.next(), /ENOENT/);
	assert.equal(activeState(h.session.getBranch())?.state.cycle, 1);
	await h.command("stop");
	h.session.appendCustomEntry("plan-cycle-state-v1", { version: 1, enabled: true });
	assert.match(JSON.stringify(await h.context()), /Legacy plan-cycle v1/);
	await h.command("stop");
	assert.equal(await h.context(), undefined);
});

test("plan parser ignores fenced examples and bounded reader refuses oversized plans", async t => {
	const root = await workspace(t);
	assert.equal(nextTask("```markdown\n- BLOCKED example\n```\n- DONE architecture\n2. TODO implement\n- TODO Review"), "implement");
	assert.throws(() => nextTask("# Empty"), /нет шагов/);
	await writeFile(join(root, "big.md"), "x".repeat(MAX_PLAN_BYTES + 1));
	await assert.rejects(readPlan(join(root, "big.md")), /64 KiB/);
});

test("native loader and ExtensionRunner preserve system/tool state and transform actual projected context", async t => {
	const root = await workspace(t), agentDir = join(root, "agent"); await mkdir(agentDir);
	const loader = new DefaultResourceLoader({ cwd: root, agentDir, settingsManager: SettingsManager.inMemory(),
		noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true, noContextFiles: true,
		additionalExtensionPaths: [resolve("files/pi-extensions/plan-cycle/index.ts")] });
	await loader.reload();
	const loaded = loader.getExtensions(); assert.deepEqual(loaded.errors, []);
	const session = SessionManager.inMemory(root);
	const checkpointId = session.appendMessage(user("NATIVE_TASK"));
	session.appendMessage(assistant([{ type: "text", text: "NATIVE_DISCARD" }]));
	await writeFile(join(root, "plan.md"), plan);
	session.appendCustomEntry(STATE, { version: 2, enabled: true, cwd: root, planPath: join(root, "plan.md"), checkpointId, mode: "step", cycle: 1, snapshot: { plan, staleReads: [] } });
	session.appendMessage(user("NATIVE_CURRENT"));
	const runner = new ExtensionRunner(loaded.extensions, loaded.runtime, root, session, undefined as any);
	const errors: unknown[] = []; runner.onError(e => errors.push(e));
	const transformed = await runner.emitContext([{ role: "system", content: "NATIVE_SYSTEM", timestamp: 0 },
		...session.buildSessionContext().messages,
		{ role: "system", content: "NATIVE_TOOLS", timestamp: clock++ }] as any);
	assert.deepEqual(errors, []);
	const text = JSON.stringify(transformed);
	for (const keep of ["NATIVE_SYSTEM", "NATIVE_TOOLS", "NATIVE_TASK", "NATIVE_CURRENT", "CURRENT PLAN"]) assert.ok(text.includes(keep));
	assert.ok(!text.includes("NATIVE_DISCARD"));
	assert.ok(runner.getToolDefinition("plan_cycle_start"));
	assert.ok(runner.getToolDefinition("plan_cycle_next"));
	assert.ok(runner.getCommand("plan-cycle"));
	await writeFile(join(root, "plan.md"), "- INPROGRESS Первый шаг\n- TODO Review\n");
	session.appendMessage(assistant([{ type: "text", text: "NATIVE_NEW_TAIL" }]));
	const updated = await runner.emitContext([{ role: "system", content: "NATIVE_SYSTEM", timestamp: 0 },
		...session.buildSessionContext().messages] as any);
	const prefix = transformed.filter(m => m.role !== "system");
	assert.deepEqual(updated.filter(m => m.role !== "system").slice(0, prefix.length), prefix);
	assert.deepEqual(errors, []);
});
