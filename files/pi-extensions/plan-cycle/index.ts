import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { realpath } from "node:fs/promises";
import {
	activeState, cycleContext, filePath, fingerprint, makeSnapshot, nextTask, readPlan, READ, STATE,
	type CycleState, type ReadRecord,
} from "./core.ts";

function alone(ctx: ExtensionContext, toolCallId: string) {
	const assistant = [...ctx.sessionManager.getBranch()].reverse().find(entry => entry.type === "message" && entry.message.role === "assistant");
	if (!assistant || assistant.type !== "message" || assistant.message.role !== "assistant") throw new Error("Нет сообщения с tool call");
	const calls = assistant.message.content.filter(block => block.type === "toolCall");
	if (calls.length !== 1 || calls[0].id !== toolCallId) throw new Error("Вызывай переход plan-cycle отдельно, после завершения всех инструментов и children");
	return assistant;
}

export default function planCycle(pi: ExtensionAPI) {
	const pending = new Map<string, ReadRecord & { sessionId: string }>();
	const failures = new Map<string, string>();
	const compactionNotices = new Set<string>();
	const sessionKey = (ctx: ExtensionContext) => ctx.sessionManager.getSessionId();

	async function begin(ctx: ExtensionContext, path: string, toolCallId?: string) {
		const call = toolCallId ? alone(ctx, toolCallId) : undefined;
		const branch = ctx.sessionManager.getBranch();
		if (activeState(branch)) throw new Error("Plan-cycle уже включён; сначала проверь /plan-cycle status");
		if (!path.trim()) throw new Error("Укажи путь к plan.md в scratch задачи");
		if (!branch.some(entry => entry.type === "message" && entry.message.role === "user")) throw new Error("Сначала задай исходную задачу в этой сессии");
		if (branch.some(entry => entry.type === "custom" && entry.customType === "ruclaw-work-cycle")) throw new Error("Legacy work-cycles: продолжи через pi-ruclaw --legacy-cycles --session <id>, либо сохрани handoff и создай новую сессию");
		const leaf = ctx.sessionManager.getLeafId(), sessionId = sessionKey(ctx);
		// Never retain a pending start-tool call without its future result in checkpoint.
		const checkpointId = call ? branch[branch.findIndex(entry => entry.id === call.id) - 1]?.id : leaf;
		if (!checkpointId) throw new Error("Пустая история checkpoint");
		const cwd = await realpath(ctx.cwd), planPath = filePath(path, cwd);
		let plan: string;
		try { plan = await readPlan(planPath); }
		catch (error) {
			if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
			plan = "Файл пока не создан. Подготовь короткий план в указанном пути.";
		}
		const snapshot = await makeSnapshot(branch, ctx.sessionManager.buildSessionProjection(), checkpointId, cwd, planPath, plan);
		if (sessionKey(ctx) !== sessionId || ctx.sessionManager.getLeafId() !== leaf ||
			(!toolCallId && (!ctx.isIdle() || ctx.hasPendingMessages()))) throw new Error("Сессия изменилась во время сохранения checkpoint");
		ctx.signal?.throwIfAborted();
		pi.appendEntry<CycleState>(STATE, { version: 2, enabled: true, cwd, planPath,
			checkpointId, cycle: 0, mode: "planning", snapshot, skipToolCallId: toolCallId });
		failures.delete(sessionId);
	}

	async function advance(ctx: ExtensionContext, toolCallId?: string) {
		if (toolCallId) alone(ctx, toolCallId);
		const branch = ctx.sessionManager.getBranch();
		const active = activeState(branch);
		if (!active) throw new Error("Сначала /plan-cycle start <plan.md>");
		const sessionId = sessionKey(ctx), leaf = ctx.sessionManager.getLeafId();
		if (await realpath(ctx.cwd) !== active.state.cwd) throw new Error("Рабочий каталог изменился");
		const plan = await readPlan(active.state.planPath);
		const task = nextTask(plan);
		if (sessionKey(ctx) !== sessionId || ctx.sessionManager.getLeafId() !== leaf) throw new Error("История изменилась во время перехода; повтори после reconcile");
		if (!task) return false;
		// Before discarding any history, verify boundaries and compatibility too.
		await cycleContext({ messages: ctx.sessionManager.buildSessionProjection().messages.filter(message => message.role !== "system"),
			branch, projection: ctx.sessionManager.buildSessionProjection(), active, cwd: ctx.cwd });
		const snapshot = await makeSnapshot(branch, ctx.sessionManager.buildSessionProjection(), active.state.checkpointId,
			ctx.cwd, active.state.planPath, plan);
		if (await readPlan(active.state.planPath) !== plan) throw new Error("План изменился во время перехода; проверь его и повтори");
		if (sessionKey(ctx) !== sessionId || ctx.sessionManager.getLeafId() !== leaf) throw new Error("История изменилась во время перехода");
		if (!toolCallId && (!ctx.isIdle() || ctx.hasPendingMessages())) throw new Error("Появилась работа или очередь сообщений; переход отменён");
		ctx.signal?.throwIfAborted();
		pi.appendEntry<CycleState>(STATE, { ...active.state, snapshot, mode: "step", cycle: active.state.cycle + 1, skipToolCallId: toolCallId });
		failures.delete(sessionId);
		return true;
	}

	pi.registerCommand("plan-cycle", {
		description: "Context checkpoint + step-frozen plan: start <path>, next, status, stop",
		handler: async (args, ctx) => {
			try {
				if (!ctx.isIdle() || ctx.hasPendingMessages()) throw new Error("Дождись завершения агента и очереди сообщений");
				const [command, ...rest] = args.trim().split(/\s+/);
				if (command === "stop") {
					// A minimal tombstone also recovers malformed prior state.
					pi.appendEntry<Pick<CycleState, "version" | "enabled">>(STATE, { version: 2, enabled: false });
					failures.delete(sessionKey(ctx));
					ctx.ui.notify("Plan-cycle выключен. Следующий запрос снова использует обычную историю активной ветки.", "info");
					return;
				}
				const active = activeState(ctx.sessionManager.getBranch());
				if (command === "start") {
					await begin(ctx, rest.join(" "));
					ctx.ui.notify("Checkpoint 0 сохранён. Попроси агента подготовить короткий план, затем /plan-cycle next.", "info");
				} else if (command === "next") {
					if (rest.length) throw new Error("У next нет аргументов");
					if (await advance(ctx)) pi.sendUserMessage("Начни следующий шаг актуального плана. Перед INPROGRESS перечитай нужные изменённые файлы.");
					else ctx.ui.notify("Все шаги DONE. Новый переход не создан.", "info");
				} else if (command === "status" || !command) {
					ctx.ui.notify(active ? `Plan-cycle: ${active.state.mode}, цикл ${active.state.cycle}\nCheckpoint: ${active.state.checkpointId}\nПлан: ${active.state.planPath}` : "Plan-cycle выключен", "info");
				} else throw new Error("Используй /plan-cycle start <path> | next | status | stop");
			} catch (error) { ctx.ui.notify(String(error), "error"); }
		},
	});

	pi.registerTool({
		name: "plan_cycle_start",
		label: "Save original task checkpoint",
		description: "For an authorized NEW task: after reading the task/scope/permissions and necessary inputs, BEFORE planning or product edits, call ALONE with a task-local scratch plan_path. Saves checkpoint 0 without the pending tool call, then enters planning. Does not grant Git/Docker/publication authority. Existing tasks resume their saved plan instead.",
		parameters: Type.Object({ plan_path: Type.String({ minLength: 1 }) }),
		executionMode: "sequential",
		async execute(toolCallId, params, signal, _update, ctx) {
			signal?.throwIfAborted();
			await begin(ctx, params.plan_path, toolCallId);
			return { content: [{ type: "text", text: "Checkpoint 0 сохранён. Создай короткий последовательный план, затем вызови plan_cycle_next отдельно." }], details: undefined };
		},
	});

	pi.registerTool({
		name: "plan_cycle_next",
		label: "Next plan step with clean context",
		description: "After saving the current step result and short plan, finish all tools/children and call ALONE. Refuses INPROGRESS/BLOCKED. Keeps checkpoint 0, current plan and later user instructions, discards prior step conversation. No Git rollback, commit, acceptance or publication. Do not call when no TODO remains.",
		parameters: Type.Object({}),
		executionMode: "sequential",
		async execute(toolCallId, _params, signal, _update, ctx) {
			signal?.throwIfAborted();
			const changed = await advance(ctx, toolCallId);
			return { content: [{ type: "text", text: changed ? "Граница сохранена. Следующий запрос использует checkpoint 0 и актуальный план." : "Все шаги DONE. Не вызывай переход повторно; сообщи итог и оставшиеся риски пользователю." }], details: { changed } };
		},
	});

	// Track reads even before start, so a checkpoint can retain verified old reads.
	pi.on("tool_call", async (event, ctx) => {
		const failure = failures.get(sessionKey(ctx));
		if (failure) return { block: true, reason: `Plan-cycle STOP: ${failure}. Пользователь должен восстановить состояние или выполнить /plan-cycle stop.` };
		const input = event.input as Record<string, unknown>;
		if (event.toolName !== "read" || typeof input.path !== "string") return;
		const record = { toolCallId: event.toolCallId, path: filePath(input.path, ctx.cwd),
			fingerprint: null as string | null, sessionId: sessionKey(ctx) };
		record.fingerprint = await fingerprint(record.path);
		pending.set(event.toolCallId, record);
	});
	pi.on("tool_result", async (event, ctx) => {
		if (event.toolName !== "read") return;
		const before = pending.get(event.toolCallId);
		pending.delete(event.toolCallId);
		if (!before || before.sessionId !== sessionKey(ctx) || event.isError) return;
		const path = typeof event.input.path === "string" ? filePath(event.input.path, ctx.cwd) : before.path;
		const after = await fingerprint(path);
		pi.appendEntry<ReadRecord>(READ, { toolCallId: before.toolCallId, path,
			fingerprint: path === before.path && before.fingerprint === after ? after : null });
	});
	pi.on("context", async (event, ctx) => {
		try {
			const branch = ctx.sessionManager.getBranch(), active = activeState(branch);
			if (!active) {
				if (branch.some(entry => entry.type === "custom" && entry.customType === "ruclaw-work-cycle")) throw new Error("Legacy work-cycles: используй pi-ruclaw --legacy-cycles --session <id>; автоматическая миграция запрещена");
				failures.delete(sessionKey(ctx)); return;
			}
			const messages = await cycleContext({ messages: event.messages, branch,
				projection: ctx.sessionManager.buildSessionProjection(), active, cwd: ctx.cwd });
			failures.delete(sessionKey(ctx));
			return { messages };
		} catch (error) {
			// Pi normally catches handler errors and uses the unfiltered context.
			// Return an explicit safe STOP instead, never silently restore old history.
			const reason = String(error);
			failures.set(sessionKey(ctx), reason);
			return { messages: [...event.messages.filter(message => message.role === "user"),
				{ role: "user" as const, content: `PLAN-CYCLE STOP: ${reason}\nНе выполняй инструменты или изменения. Сообщи блокер пользователю. Для обычной истории пользователь может выполнить /plan-cycle stop.`, timestamp: 0 }] };
		}
	});
	pi.on("session_before_compact", (_event, ctx) => {
		const active = activeState(ctx.sessionManager.getBranch());
		if (active) {
			const key = `${sessionKey(ctx)}:${active.entryId}`;
			if (!compactionNotices.has(key)) {
				compactionNotices.add(key);
				ctx.ui.notify("Plan-cycle сохраняет точный checkpoint: compaction отменена. Заверши/раздели шаг или выключи режим.", "warning");
			}
			return { cancel: true };
		}
	});
	pi.on("session_shutdown", () => { pending.clear(); failures.clear(); compactionNotices.clear(); });
}
