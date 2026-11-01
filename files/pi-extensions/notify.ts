import { execFile } from "node:child_process";
import { basename } from "node:path";
import { promisify } from "node:util";
import type { AgentActivityOutcome, ExtensionAPI } from "@earendil-works/pi-coding-agent";

const exec = promisify(execFile);
const escapeMarkup = (text: string) => text.replace(/[\x00-\x1f\x7f]/g, " ").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

export async function sendDesktopNotification(cwd: string, outcome: "completed" | "error") {
	await exec("notify-send", [
		"--app-name=Pi", "--urgency=normal", "--expire-time=5000",
		`--icon=${outcome === "error" ? "dialog-error" : "dialog-information"}`,
		"--", outcome === "error" ? "Pi — ошибка" : "Pi — готово",
		`Проект: ${escapeMarkup(basename(cwd) || cwd)}`,
	], { timeout: 3000, maxBuffer: 16 * 1024 });
}

export function registerNotifications(pi: ExtensionAPI, send = sendDesktopNotification) {
	let pending: { session: string; outcome: AgentActivityOutcome; signal?: AbortSignal } | undefined;
	let warned = false;
	pi.on("session_start", () => { pending = undefined; });
	pi.on("session_shutdown", () => { pending = undefined; });
	pi.on("agent_start", (_event, ctx) => {
		pending = ctx.mode === "tui" ? { session: ctx.sessionManager.getSessionId(), outcome: "completed", signal: ctx.signal } : undefined;
	});
	pi.on("turn_end", (event, ctx) => {
		// An aborted run can skip agent_before_settle entirely.
		if (pending?.session === ctx.sessionManager.getSessionId() && event.message.role === "assistant") {
			pending.outcome = event.message.stopReason === "aborted" ? "aborted"
				: event.message.stopReason === "error" ? "error" : "completed";
		}
	});
	pi.on("agent_before_settle", (event, ctx) => {
		if (pending?.session === ctx.sessionManager.getSessionId()) pending.outcome = event.outcome;
	});
	// agent_end can be followed by retries, compaction or queued continuation.
	// Notify once, only after the whole activity has finally settled.
	pi.on("agent_settled", async (_event, ctx) => {
		const run = pending;
		pending = undefined;
		if (!run || run.session !== ctx.sessionManager.getSessionId() || run.outcome === "aborted" || run.signal?.aborted || ctx.signal?.aborted
			|| ctx.mode !== "tui" || !(process.env.DISPLAY || process.env.WAYLAND_DISPLAY)) return;
		try {
			await send(ctx.cwd, run.outcome);
			warned = false;
		} catch {
			if (!warned) {
				ctx.ui.notify("Не удалось вызвать notify-send. Проверь D-Bus и desktop notification daemon.", "warning");
				warned = true;
			}
		}
	});
}

export default function (pi: ExtensionAPI) {
	registerNotifications(pi);
}
