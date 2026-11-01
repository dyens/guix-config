import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import { resolve } from "node:path";
import type { TSchema } from "typebox";
import type { ExtensionAPI, ExtensionContext, ToolDefinition, ToolResultEvent, ToolResultEventResult } from "@earendil-works/pi-coding-agent";

type DiagnosticsHook = (event: ToolResultEvent, ctx: ExtensionContext) => ToolResultEventResult | undefined | Promise<ToolResultEventResult | undefined>;
type UpstreamFactory = (pi: ExtensionAPI) => void | Promise<void>;
const MAX_BYTES = 2 * 1024 * 1024;
const MAX_OUTPUT = 32000;
const textContent = (content: { type: string; text?: string }[] | undefined) =>
	(content ?? []).filter((part) => part.type === "text").map((part) => part.text ?? "").join("\n\n");
const fingerprint = (text: Buffer) => createHash("sha256").update(text).digest("hex");
const abort = (signal?: AbortSignal) => { if (signal?.aborted) throw new Error("LSP check cancelled."); };

/** Adapter for the pinned pi-lsp 0.1.7 registration contract, not a global API patch. */
export async function registerManualLsp(pi: ExtensionAPI, upstream: UpstreamFactory, parameters: TSchema) {
	let diagnosticsHook: DiagnosticsHook | undefined;
	let symbols: ToolDefinition | undefined;
	await upstream(new Proxy(pi, {
		get(target, property) {
			if (property === "on") return (event: string, handler: DiagnosticsHook) => {
				if (event === "tool_result") {
					if (diagnosticsHook) throw new Error("Unexpected pi-lsp contract: multiple tool_result hooks.");
					diagnosticsHook = handler;
					// Keep the collector private: ordinary write/edit results never run it.
					return () => {};
				}
				return Reflect.apply(target.on, target, [event, handler]);
			};
			// The collector emits a separate steer message. Explicit checks return their
			// diagnostics directly instead; never inject a duplicate unsolicited message.
			if (property === "sendMessage") return () => {};
			if (property === "registerTool") return (tool: ToolDefinition) => {
				if (tool.name === "lsp_symbols") symbols = tool;
				if (tool.name === "lsp_diagnostics") {
					const cached = tool;
					tool = {
						...tool,
						description: "Read cached LSP diagnostics only. They may be stale or empty; use lsp_check for a fresh check.",
						promptSnippet: "Read cached LSP diagnostics (not a fresh check)",
						promptGuidelines: ["lsp_diagnostics is only a potentially stale cache. If fresh editor diagnostics would add useful feedback, use lsp_check; it is not a mandatory post-edit gate."],
						async execute(...args) {
							const result = await cached.execute(...args);
							return { ...result, content: [{ type: "text", text: "Cached diagnostics — possibly stale or not collected. Use lsp_check for a fresh check." }, ...result.content] };
						},
					};
				}
				target.registerTool(tool);
			};
			return Reflect.get(target, property);
		},
	}));
	if (!diagnosticsHook || !symbols) throw new Error("Unsupported pi-lsp version: diagnostics collector or lsp_symbols missing.");
	const collect = diagnosticsHook;
	const sync = symbols;
	pi.registerTool({
		name: "lsp_check",
		label: "LSP Check",
		description: "On demand, sync saved files and request updated LSP diagnostics when quick editor feedback is useful. Not a mandatory post-edit gate or a replacement for compiler/typecheck, lint or tests. Does not modify files. Servers may still be analyzing when their configured wait expires.",
		promptSnippet: "Request fresh LSP diagnostics on demand when they add useful feedback",
		promptGuidelines: [
			"Use lsp_check for useful quick feedback, not as a mandatory post-edit gate. Do not duplicate a successful compiler/typecheck on the same relevant saved inputs and configuration unless LSP offers additional diagnostics or helps investigate a discrepancy.",
			"When checking, finish related edits first and batch the relevant saved files. Do not check after each intermediate edit or invoke checks in parallel with edits.",
			"Use LSP navigation when it helps investigate code: definition for declarations, references for semantic usages, hover for types/docs, symbols for file structure. References do not cover all config, reflection, generated or external consumers; use text search and boundary inspection too.",
			"LSP diagnostics can be delayed or incomplete and do not replace tests, security lint or independent review. Missing or failed servers are not a clean bill of health; avoid repeated calls to a known unavailable server until its environment changes. Required project checks still apply.",
		],
		executionMode: "sequential",
		parameters,
		async execute(toolCallId, params, signal, _onUpdate, ctx) {
			const input = (params as { paths?: unknown }).paths;
			if (!Array.isArray(input) || input.length < 1 || input.length > 20 || input.some((path) => typeof path !== "string" || !path.trim())) {
				throw new Error("lsp_check expects 1–20 nonempty file paths.");
			}
			abort(signal);
			const paths = [...new Set(input.map((path: string) => resolve(ctx.cwd, path)))];
			const snapshots = new Map<string, string>();
			for (const path of paths) {
				abort(signal);
				const info = await stat(path);
				if (!info.isFile() || info.size > MAX_BYTES) throw new Error(`Cannot check ${path}: expected a regular file no larger than 2 MiB.`);
				const text = await readFile(path);
				if (text.length > MAX_BYTES) throw new Error(`Cannot check ${path}: file exceeds 2 MiB.`);
				snapshots.set(path, fingerprint(text));
			}
			const context = new Proxy(ctx, { get: (target, property) => property === "signal" ? signal : Reflect.get(target, property) });
			const syncWarnings = new Map<string, string>();
			// Sync ALL requested documents before collecting diagnostics. Navigation
			// may previously have opened a dependent file whose saved contents changed.
			// pi-lsp's public symbols tool does didOpen/didChange; discard symbol output.
			for (const path of paths) {
				abort(signal);
				try { await sync.execute(`${toolCallId}:sync`, { path }, signal, undefined, context); }
				catch (error) { syncWarnings.set(path, `Document sync warning: ${error instanceof Error ? error.message : error}`); }
			}
			const sections: string[] = [];
			for (const [index, path] of paths.entries()) {
				abort(signal);
				// Reuse the private upstream collector without emitting a real Pi write
				// event or touching the file. Its result includes server/config failures.
				const result = await collect({
					type: "tool_result", toolName: "write", toolCallId: `${toolCallId}:${index}`,
					input: { path, content: "" }, content: [], details: undefined, isError: false,
				}, context);
				const summary = textContent(result?.content);
				sections.push([path, syncWarnings.get(path), summary.trim() || "Not checked: no matching LSP server/configuration."].filter(Boolean).join("\n\n"));
			}
			abort(signal);
			for (const path of paths) {
				const info = await stat(path);
				if (!info.isFile() || info.size > MAX_BYTES || fingerprint(await readFile(path)) !== snapshots.get(path)) {
					throw new Error("Files changed during LSP check. Results discarded; finish the edits and check again.");
				}
			}
			abort(signal);
			let output = sections.join("\n\n---\n\n");
			if (output.length > MAX_OUTPUT) output = output.slice(0, MAX_OUTPUT) + "\n\n[Output truncated; check a smaller set of files.]";
			return { content: [{ type: "text", text: output }], details: { paths } };
		},
	});
}
