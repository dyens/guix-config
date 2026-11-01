import { createHash } from "node:crypto";
import { constants, createReadStream } from "node:fs";
import { open, realpath, stat } from "node:fs/promises";
import { resolve } from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";
import type { AgentMessage } from "@earendil-works/pi-agent-core";
import type { SessionEntry, SessionProjection } from "@earendil-works/pi-coding-agent";

export const STATE = "plan-cycle-state-v2";
const LEGACY_STATE = "plan-cycle-state-v1";
export const READ = "plan-cycle-read-v1";
export const PLAN_MESSAGE = "plan-cycle-current-plan";
export const MAX_PLAN_BYTES = 64 * 1024;

export interface BoundarySnapshot {
	plan: string;
	staleReads: { entryId: string; path: string; reason: string }[];
}
export interface CycleState {
	version: 2;
	enabled: boolean;
	cwd: string;
	planPath: string;
	checkpointId: string;
	cycle: number;
	mode: "planning" | "step";
	snapshot: BoundarySnapshot;
	// The state entry itself is the boundary. A tool's result arrives after it.
	skipToolCallId?: string;
}
export interface ReadRecord {
	toolCallId: string;
	path: string;
	fingerprint: string | null;
}
export interface ActiveState {
	entryId: string;
	state: CycleState;
}

export function activeState(branch: SessionEntry[]): ActiveState | undefined {
	for (const entry of [...branch].reverse()) {
		if (entry.type !== "custom" || ![STATE, LEGACY_STATE].includes(entry.customType)) continue;
		const state = entry.data as CycleState;
		if (state?.enabled === false) return undefined;
		if (entry.customType === LEGACY_STATE) throw new Error("Legacy plan-cycle v1: сохрани handoff; выключи режим и создай новый checkpoint, не меняй его незаметно при reload");
		if (state?.version !== 2 || state.enabled !== true || typeof state.snapshot?.plan !== "string" ||
			!Array.isArray(state.snapshot.staleReads) || state.snapshot.staleReads.some(read =>
				typeof read.entryId !== "string" || typeof read.path !== "string" || typeof read.reason !== "string")) {
			throw new Error("Повреждено состояние plan-cycle");
		}
		return { entryId: entry.id, state };
	}
}

// Match Pi's common read-path syntax without depending on private runtime modules.
// Unsupported platform-specific aliases conservatively become untracked/stale.
export function filePath(path: string, cwd: string): string {
	let normalized = path.replace(/[\u00A0\u2000-\u200A\u202F\u205F\u3000]/g, " ");
	if (normalized.startsWith("@")) normalized = normalized.slice(1);
	if (normalized === "~") normalized = homedir();
	else if (normalized.startsWith("~/")) normalized = resolve(homedir(), normalized.slice(2));
	if (normalized.startsWith("file://")) normalized = fileURLToPath(normalized);
	return resolve(cwd, normalized);
}

// Real path is part of identity: retargeting a symlink invalidates its old read.
export async function fingerprint(path: string): Promise<string | null> {
	try {
		const target = await realpath(path);
		if (!(await stat(target)).isFile()) return null;
		const hash = createHash("sha256").update(target).update("\0");
		for await (const chunk of createReadStream(target)) hash.update(chunk);
		return hash.digest("hex");
	} catch {
		// Missing, inaccessible and non-regular paths are all unsafe to reuse.
		return null;
	}
}

export async function readPlan(path: string): Promise<string> {
	const file = await open(path, constants.O_RDONLY | constants.O_NONBLOCK);
	try {
		if (!(await file.stat()).isFile()) throw new Error("План должен быть обычным файлом");
		// Bounded read also handles a file growing after stat.
		const buffer = Buffer.alloc(MAX_PLAN_BYTES + 1);
		let length = 0;
		while (length < buffer.length) {
			const { bytesRead } = await file.read(buffer, length, buffer.length - length, null);
			if (!bytesRead) break;
			length += bytesRead;
		}
		if (length > MAX_PLAN_BYTES) throw new Error("План превышает 64 KiB; вынеси подробности в отдельные файлы");
		return buffer.subarray(0, length).toString("utf8");
	} finally {
		await file.close();
	}
}

export function nextTask(plan: string): string | undefined {
	const tasks: { status: string; title: string }[] = [];
	let fence: string | undefined;
	for (const line of plan.split(/\r?\n/)) {
		const marker = /^\s*(`{3,}|~{3,})/.exec(line)?.[1];
		if (marker) {
			if (!fence) fence = marker;
			else if (marker[0] === fence[0] && marker.length >= fence.length) fence = undefined;
			continue;
		}
		if (fence) continue;
		const task = /^\s*(?:[-*]|\d+\.)\s+(TODO|INPROGRESS|DONE|BLOCKED)\s+(.+?)\s*$/.exec(line);
		if (task) tasks.push({ status: task[1], title: task[2] });
	}
	if (!tasks.length) throw new Error("В плане нет шагов: используй '- TODO Описание' (TODO / INPROGRESS / DONE / BLOCKED)");
	if (tasks.some(task => task.status === "INPROGRESS")) throw new Error("Есть INPROGRESS: сначала заверши шаг или перепланируй в текущем контексте");
	if (tasks.some(task => task.status === "BLOCKED")) throw new Error("Есть BLOCKED: разбери причину и обнови план без сброса контекста");
	return tasks.find(task => task.status === "TODO")?.title;
}

function userMessage(text: string, timestamp: number): AgentMessage {
	return { role: "user", content: [{ type: "text", text }], timestamp };
}

function questionnaireMessage(message: AgentMessage): boolean {
	return message.role === "toolResult" ? message.toolName === "ask_user_question"
		: message.role === "assistant" && message.content.some(block => block.type === "toolCall" && block.name === "ask_user_question");
}

export const PROTOCOL = [
	"Это последовательный plan-cycle workflow. Исходная задача уже находится в checkpoint 0.",
	"CURRENT PLAN AT STEP START — снимок плана на границе шага, заменяющий прежние шаги. Внутри шага более новые read/edit/write results и указания пользователя уточняют его; актуальный файл плана можно читать обычным read.",
	"Выполняй только первый незавершённый шаг. Статусы: TODO, INPROGRESS, DONE, BLOCKED.",
	"Перед TODO -> INPROGRESS перечитай необходимые изменённые/созданные файлы с диска; удалённые файлы не используй как существующие.",
	"Чтения checkpoint проверены только на границе шага. Внутри шага история не переписывается: учитывай новые edit/write/read results, перечитывай файл при сомнении. Цитаты, bash/search output и старые рассуждения могут устареть.",
	"DONE означает выполнение шага, не приёмку продукта; промежуточный код может не работать, если это отражено в плане.",
	"Сохраняй план коротким: шаги, краткие итоги, важные решения, changed/created/deleted пути, ограничения и следующий шаг. Логи — отдельно.",
	"После шага сохрани итог и план, сделай commit ТОЛЬКО при наличии разрешения, заверши инструменты/children, затем вызови plan_cycle_next ОТДЕЛЬНО.",
	"При ошибке плана поставь BLOCKED с причиной, оставайся в текущем контексте и перепланируй. Требования/полномочия сам не расширяй.",
	"Review — отдельный финальный шаг; его findings становятся новым планом. Ни reset контекста, ни DONE не разрешают push/merge/deployment.",
	"Сохранённые ask_user_question — исходные вопросы и результаты, не summary агента. Учитывай выбранные ответы/заметки и последующие поправки пользователя; отмена, ошибка, пропущенный вопрос или рекомендация без выбора НЕ означают согласие.",
].join("\n");

// Called exactly at start/next, never while assembling a request inside a step.
// Persist decisions, not copies of entire source messages, so reload is stable.
export async function makeSnapshot(branch: SessionEntry[], projection: SessionProjection,
	checkpointId: string, cwd: string, planPath: string, plan: string): Promise<BoundarySnapshot> {
	const checkpoint = branch.findIndex(entry => entry.id === checkpointId);
	if (checkpoint < 0) throw new Error("Checkpoint отсутствует");
	const prefixIds = new Set(branch.slice(0, checkpoint + 1).map(entry => entry.id));
	const records = new Map<string, ReadRecord>();
	const paths = new Map<string, string>();
	for (const entry of branch) {
		if (entry.type === "custom" && entry.customType === READ) {
			const record = entry.data as ReadRecord;
			records.set(record.toolCallId, record);
		}
		if (entry.type === "message" && entry.message.role === "assistant") {
			for (const block of entry.message.content) {
				if (block.type === "toolCall" && typeof block.arguments.path === "string") paths.set(block.id, filePath(block.arguments.path, cwd));
			}
		}
	}
	const current = new Map<string, Promise<string | null>>();
	const staleReads: BoundarySnapshot["staleReads"] = [];
	for (const item of projection.entries) {
		if (!prefixIds.has(item.sourceEntry.id)) continue;
		for (const message of item.messages) {
			if (message.role !== "toolResult" || message.toolName !== "read") continue;
			const record = records.get(message.toolCallId);
			const path = record?.path ?? paths.get(message.toolCallId);
			if (!path) throw new Error("Нельзя установить путь старого read result");
			let reason: string | undefined;
			if (path === planPath) reason = "План представлен отдельно в CURRENT PLAN AT STEP START";
			else {
				let value = current.get(path);
				if (!value) { value = fingerprint(path); current.set(path, value); }
				const hash = await value;
				if (!record?.fingerprint || !hash || hash !== record.fingerprint) reason = hash
					? "На границе шага файл изменён или исходная версия не была отслежена"
					: "На границе шага файл удалён, недоступен или больше не обычный файл";
			}
			if (reason) staleReads.push({ entryId: item.sourceEntry.id, path, reason });
		}
	}
	return { plan, staleReads };
}

export interface ContextInput {
	messages: AgentMessage[];
	branch: SessionEntry[];
	projection: SessionProjection;
	active: ActiveState;
	cwd: string;
}

// Work only with messages still present in the canonical projection. This preserves
// context_edit omissions/replacements and refuses to resurrect filtered history.
export async function cycleContext(input: ContextInput): Promise<AgentMessage[]> {
	const { messages, branch, projection, active, cwd } = input;
	const { state } = active;
	if (await realpath(cwd) !== state.cwd) throw new Error("Рабочий каталог отличается от checkpoint");
	const positions = new Map(branch.map((entry, index) => [entry.id, index]));
	const checkpoint = positions.get(state.checkpointId);
	const boundary = positions.get(active.entryId);
	if (checkpoint === undefined || boundary === undefined || boundary <= checkpoint) throw new Error("Checkpoint или граница шага отсутствует в активной ветке");
	if (branch.slice(checkpoint + 1).some(entry => entry.type === "compaction" || entry.type === "branch_summary")) {
		throw new Error("После checkpoint появилась compaction/branch summary; остановись и согласуй новый checkpoint");
	}

	const provenance = new Map<string, number[]>();
	for (const item of projection.entries) {
		const index = positions.get(item.sourceEntry.id);
		if (index === undefined) throw new Error("Неизвестный источник контекста");
		for (const message of item.messages) {
			if (message.role === "system") continue;
			const key = JSON.stringify(message);
			const queue = provenance.get(key) ?? [];
			queue.push(index);
			provenance.set(key, queue);
		}
	}
	const located = messages.map(message => {
		const index = provenance.get(JSON.stringify(message))?.shift();
		if (index === undefined) throw new Error("Контекст изменён другим расширением или источник сообщения не найден");
		return { message, index };
	});
	// A prior context filter must not silently remove original requirements,
	// newer user revocations or questionnaire evidence. Never resurrect omissions
	// from raw history; canonical context_edit still controls what is visible.
	const visible = new Set(located.map(item => item.index));
	for (const item of projection.entries) {
		const index = positions.get(item.sourceEntry.id)!;
		if (item.messages.some(message => message.role !== "system") &&
			(index <= checkpoint || item.messages.some(message => message.role === "user" || questionnaireMessage(message))) && !visible.has(index)) {
			throw new Error("Другое расширение исключило checkpoint, пользовательское сообщение или вопросник");
		}
	}

	const replacements = new Map(state.snapshot.staleReads.map(read => [read.entryId, read]));
	const refresh = (message: AgentMessage, entryId: string): AgentMessage => {
		const stale = replacements.get(entryId);
		if (!stale || message.role !== "toolResult" || message.toolName !== "read") return message;
		return { ...message, content: [{ type: "text", text: `[STALE READ] ${stale.path}\n${stale.reason}. Старое содержимое исключено. При необходимости перечитай файл.` }], details: undefined };
	};

	// Keep complete questionnaire exchanges at their original positions. Filter
	// sibling calls/text/thinking from carried assistant messages so unrelated
	// step work does not leak back or leave orphan tool results. Preserve the raw
	// result, including errors/cancellation/partial answers, rather than inventing
	// a user approval message. Pair by ordered call IDs, allowing later ID reuse.
	const pending = new Map<string, { message: AgentMessage; index: number }>();
	const questionCalls = new Map<AgentMessage, Set<string>>();
	const questionResults = new Set<AgentMessage>();
	for (const { message, index } of located) {
		if (index > boundary) continue;
		if (message.role === "assistant") {
			for (const block of message.content) {
				if (block.type !== "toolCall" || block.name !== "ask_user_question") continue;
				if (pending.has(block.id)) throw new Error("Повторный незавершённый вызов ask_user_question");
				pending.set(block.id, { message, index });
			}
		} else if (message.role === "toolResult") {
			const call = pending.get(message.toolCallId);
			if (!call && message.toolName !== "ask_user_question") continue;
			if (!call || message.toolName !== "ask_user_question") throw new Error("Нарушена пара вызов/ответ ask_user_question");
			pending.delete(message.toolCallId);
			if (index > checkpoint) {
				questionResults.add(message);
				if (call.index > checkpoint) {
					const ids = questionCalls.get(call.message) ?? new Set<string>();
					ids.add(message.toolCallId);
					questionCalls.set(call.message, ids);
				}
			}
		}
	}
	if (pending.size) throw new Error("Незавершённый ask_user_question на границе шага");

	const prefix: AgentMessage[] = [], carried: AgentMessage[] = [], tail: AgentMessage[] = [];
	for (const { message, index } of located) {
		if (message.role === "custom" && message.customType === PLAN_MESSAGE) continue;
		if (message.role === "toolResult" && message.toolCallId === state.skipToolCallId) continue;
		if (index <= checkpoint) prefix.push(refresh(message, branch[index].id));
		else if (index <= boundary) {
			// Keep actual newer user messages verbatim, not summaries inferred by an LLM.
			if (message.role === "user" || questionResults.has(message)) carried.push(message);
			else if (message.role === "assistant") {
				const ids = questionCalls.get(message);
				if (ids) carried.push({ ...message, content: message.content.filter(block => block.type === "toolCall" && ids.has(block.id)) });
			}
		} else tail.push(message);
	}
	const text = [PROTOCOL, `Режим: ${state.mode}; цикл: ${state.cycle}.`,
		state.mode === "planning" ? "Подготовь/согласуй короткий план. Не начинай реализацию до перехода plan_cycle_next." : "Продолжи первый незавершённый шаг плана.",
		state.snapshot.staleReads.length ? `На границе шага требовали актуального чтения при использовании:\n${[...new Set(state.snapshot.staleReads.map(read => read.path))].map(path => `- ${path}`).join("\n")}` : "На границе шага не обнаружено устаревших read results checkpoint.",
		`CURRENT PLAN AT STEP START (${state.planPath})\n${state.snapshot.plan}\nEND CURRENT PLAN`,
		"Дальнейшие сообщения текущего шага, включая обновления плана и новые пользовательские ограничения, имеют более свежий контекст.",
	].join("\n\n");
	return [...prefix, ...carried, userMessage(text, 0), ...tail];
}
