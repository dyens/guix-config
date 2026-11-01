import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { registerManualLsp } from "../lsp-manual/adapter.ts";

async function fixture(options: { change?: boolean; noServer?: boolean; syncError?: boolean; cancelOnSync?: AbortController } = {}) {
	const dir = await mkdtemp(join(tmpdir(), "pi-lsp-unit-"));
	await writeFile(join(dir, "a.py"), "saved a\n");
	await writeFile(join(dir, "b.py"), "saved b\n");
	const tools = new Map<string, any>(), events = new Map<string, any>();
	const calls: string[] = [], messages: unknown[] = [];
	const ctx = { cwd: dir };
	const pi = {
		registerTool: (tool: any) => tools.set(tool.name, tool),
		on: (event: string, handler: any) => { events.set(event, handler); return () => events.delete(event); },
		sendMessage: (...args: unknown[]) => messages.push(args),
	};
	const originalOn = pi.on;
	await registerManualLsp(pi as any, (api: any) => {
		api.on("tool_result", async (event: any, context: any) => {
			calls.push(`check:${event.input.path}`);
			assert.equal(context.cwd, dir);
			assert.equal(event.toolName, "write");
			if (options.change) await writeFile(event.input.path, "external edit\n");
			if (options.noServer) return undefined;
			api.sendMessage({ content: "Should not steer the agent" }, { deliverAs: "steer" });
			return { content: [{ type: "text", text: "LSP diagnostics:\nerror: intentional issue" }] };
		});
		api.on("session_shutdown", () => calls.push("shutdown"));
		api.registerTool({ name: "lsp_symbols", execute: async (_id: any, params: any) => {
			calls.push(`sync:${params.path}`);
			options.cancelOnSync?.abort();
			if (options.syncError) throw new Error("Missing binary");
			return { content: [{ type: "text", text: "symbols" }], details: {} };
		} });
		for (const name of ["lsp_hover", "lsp_definition", "lsp_references", "lsp_diagnostics"]) {
			api.registerTool({ name, execute: async () => ({ content: [{ type: "text", text: "cached" }], details: {} }) });
		}
	}, {} as any);
	assert.equal(pi.on, originalOn, "real Pi API must not be patched");
	const check = (paths: unknown, signal?: AbortSignal) => tools.get("lsp_check").execute("check-id", { paths }, signal, undefined, ctx);
	return { dir, tools, events, calls, messages, check, cleanup: () => rm(dir, { recursive: true, force: true }) };
}

test("no automatic tool_result hook; navigation and shutdown remain registered", async () => {
	const f = await fixture();
	try {
		assert.equal(f.tools.size, 6);
		assert.equal(f.events.has("tool_result"), false);
		assert.deepEqual(f.calls, []);
		assert.equal(f.tools.get("lsp_check").executionMode, "sequential");
		await f.events.get("session_shutdown")();
		assert.deepEqual(f.calls, ["shutdown"]);
	} finally { await f.cleanup(); }
});

test("guidance makes diagnostics conditional, keeps semantic navigation and mandatory verification distinct", async () => {
	const f = await fixture();
	try {
		const check = f.tools.get("lsp_check");
		assert.match(check.description, /Not a mandatory post-edit gate/);
		const guidance = check.promptGuidelines.join("\n");
		assert.match(guidance, /Do not duplicate a successful compiler\/typecheck/);
		assert.match(guidance, /same relevant saved inputs and configuration/);
		assert.match(guidance, /finish related edits first/);
		assert.match(guidance, /References do not cover all config/);
		assert.match(guidance, /known unavailable server/);
		assert.match(guidance, /Required project checks still apply/);
		assert.match(f.tools.get("lsp_diagnostics").promptGuidelines.join("\n"), /not a mandatory post-edit gate/);
		for (const name of ["lsp_definition", "lsp_references", "lsp_hover", "lsp_symbols"]) {
			assert.equal(typeof f.tools.get(name).execute, "function");
		}
		await f.tools.get("lsp_definition").execute("nav", { path: "a.py", line: 0, character: 0 }, undefined, undefined, { cwd: f.dir });
		assert.deepEqual(f.calls, [], "navigation must not invoke the diagnostic collector");
	} finally { await f.cleanup(); }
});

test("manual check syncs the whole batch first, deduplicates paths and returns diagnostics only once", async () => {
	const f = await fixture();
	try {
		const result = await f.check(["a.py", "b.py", "./a.py"]);
		assert.deepEqual(f.calls, ["sync", "sync", "check", "check"].map((kind, i) => `${kind}:${join(f.dir, i % 2 ? "b.py" : "a.py")}`));
		assert.equal(f.messages.length, 0);
		assert.match(result.content[0].text, /error: intentional issue/);
		assert.deepEqual(result.details.paths, [join(f.dir, "a.py"), join(f.dir, "b.py")]);
	} finally { await f.cleanup(); }
});

test("cache tool explicitly warns that diagnostics are stale and is not a fresh check", async () => {
	const f = await fixture();
	try {
		const result = await f.tools.get("lsp_diagnostics").execute("id", { path: "a.py" }, undefined, undefined, { cwd: f.dir });
		assert.match(result.content[0].text, /possibly stale/);
		assert.match(result.content[0].text, /lsp_check/);
		assert.deepEqual(f.calls, []);
	} finally { await f.cleanup(); }
});

test("changed files invalidate the complete check, not just one result", async () => {
	const f = await fixture({ change: true });
	try { await assert.rejects(f.check(["a.py", "b.py"]), /Files changed/); }
	finally { await f.cleanup(); }
});

test("unconfigured and failed servers are reported, not treated as clean", async () => {
	const f = await fixture({ noServer: true, syncError: true });
	try {
		const result = await f.check(["a.py"]);
		assert.match(result.content[0].text, /Missing binary/);
		assert.match(result.content[0].text, /Not checked/);
	} finally { await f.cleanup(); }
});

test("abort prevents checks from starting and is respected between sync and diagnostics", async () => {
	const controller = new AbortController();
	const f = await fixture({ cancelOnSync: controller });
	try {
		await assert.rejects(f.check(["a.py"], controller.signal), /cancelled/);
		assert.ok(f.calls.every((call) => call.startsWith("sync:")));
		const count = f.calls.length;
		await assert.rejects(f.check(["a.py"], controller.signal), /cancelled/);
		assert.equal(f.calls.length, count);
	} finally { await f.cleanup(); }
});

test("invalid requests and missing/oversized files fail before LSP calls", async () => {
	const f = await fixture();
	try {
		for (const paths of [[], [" "], [12], "a.py", Array(21).fill("a.py")]) {
			await assert.rejects(f.check(paths), /expects/);
		}
		await assert.rejects(f.check(["missing.py"]), { code: "ENOENT" });
		await writeFile(join(f.dir, "big.py"), "x".repeat(2 * 1024 * 1024 + 1));
		await assert.rejects(f.check(["big.py"]), /2 MiB/);
		assert.deepEqual(f.calls, []);
	} finally { await f.cleanup(); }
});

test("unexpected upstream registration contract fails closed", async () => {
	const pi = { registerTool: () => {}, on: () => () => {} };
	await assert.rejects(registerManualLsp(pi as any, () => {}, {} as any), /Unsupported/);
	await assert.rejects(registerManualLsp(pi as any, (api: any) => {
		api.on("tool_result", () => {}); api.on("tool_result", () => {});
	}, {} as any), /multiple/);
});
