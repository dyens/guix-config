import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { rename, writeFile } from "node:fs/promises";

// A lifecycle signal, NOT an acceptance gate or a review/receipt validator.
export default function (pi: ExtensionAPI) {
	const path = process.env.PI_RUCLAW_RUNNER_SIGNAL;
	if (!path) return;
	let pending: { status: "done" | "blocked" | "failed"; summary: string } | undefined;
	pi.registerTool({
		name: "runner_finish",
		label: "Notify task runner",
		description: "Notify the simple tmux runner: done only after the whole task (not just plan steps) completes implementation, checks, final independent review, required non-force push, task status and owned-resource cleanup. blocked/failed stops further tasks and leaves this Pi open for the user. No receipt/evidence schema. Call alone, after all children finish.",
		parameters: Type.Object({ status: Type.Union([Type.Literal("done"), Type.Literal("blocked"), Type.Literal("failed")]), summary: Type.String({ maxLength: 400 }) }),
		async execute(_id, params) {
			pending = params;
			return { content: [{ type: "text", text: "Runner will be notified when this turn settles. Stop here." }], details: undefined, terminate: true };
		},
	});
	pi.on("agent_settled", async (_event, ctx) => {
		if (!pending) return; // Async review yields are not task completion.
		const outcome = pending; pending = undefined;
		await writeFile(`${path}.tmp`, JSON.stringify({ ...outcome, sessionFile: ctx.sessionManager.getSessionFile() }), { mode: 0o600 });
		await rename(`${path}.tmp`, path);
	});
}
