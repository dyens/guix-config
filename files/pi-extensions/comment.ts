import { execFile } from "node:child_process";
import { randomBytes, randomUUID } from "node:crypto";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { createServer, type Server, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import type { ExtensionAPI, ExtensionContext, SessionEntry } from "@earendil-works/pi-coding-agent";

const execFileAsync = promisify(execFile);
const MAX_BYTES = 2 * 1024 * 1024;
const script = join(dirname(fileURLToPath(import.meta.url)), "pi-emacs.el");

export function latestAnswer(branch: SessionEntry[]) {
	for (let i = branch.length - 1; i >= 0; i--) {
		const entry = branch[i];
		if (entry.type !== "message" || entry.message.role !== "assistant") continue;
		const text = entry.message.content.filter((part) => part.type === "text").map((part) => part.text).join("\n\n");
		if (text.trim()) return { id: entry.id, text };
	}
	return undefined;
}

export async function unifiedDiff(original: string, edited: string): Promise<string> {
	try {
		return (await execFileAsync("diff", ["-u", "--text", "--label", "answer.md", "--label", "commented.md", original, edited], { maxBuffer: MAX_BYTES })).stdout;
	} catch (error) {
		const failure = error as { code?: number; stdout?: string };
		if (failure.code === 1 && typeof failure.stdout === "string") return failure.stdout;
		throw error;
	}
}

export function serverName(args: string): string {
	const name = args.trim().replace(/^"([^"\n]+)"$/, "$1");
	if (!/^[a-zA-Z0-9_-]{1,64}$/.test(name)) throw new Error("Использование: /emacs server-name (буквы, цифры, _ и -).");
	return name;
}

export default function (pi: ExtensionAPI) {
	let ctx: ExtensionContext;
	let selected: string | undefined;
	let directory: string | undefined;
	let server: Server | undefined;
	let token = "";
	let busy = false;
	let pending: { id: string; session: string; leaf: string | null; answer: { id: string; text: string } } | undefined;
	const clients = new Set<Socket>();
	const lisp = (value: string) => JSON.stringify(value);
	const sessionId = () => ctx.sessionManager.getSessionId();
	const leafId = () => ctx.sessionManager.getLeafId();
	const evaluate = async (name: string, expression: string) => {
		try {
			await execFileAsync("emacsclient", ["--socket-name", name, "--alternate-editor=false", "--eval", expression], { timeout: 5000, maxBuffer: MAX_BYTES });
		} catch {
			// execFile errors include the expression, which contains the private token.
			throw new Error(`Сервер ${name} недоступен либо отклонил запрос. Проверь emacsclient и M-x pi-emacs-server-start.`);
		}
	};
	const endpoint = () => join(directory!, "bridge.sock");
	const metadata = () => JSON.stringify({ socket: endpoint(), token, session: sessionId(), cwd: ctx.cwd });
	const register = async (name: string) => {
		await evaluate(name, `(progn (load ${lisp(script)} nil t) (pi-emacs-register ${lisp(metadata())}))`);
	};
	const cleanup = async () => {
		pending = undefined;
		for (const client of clients) client.destroy();
		if (server) await new Promise<void>((resolve) => server!.close(() => resolve()));
		server = undefined;
		if (directory) await rm(directory, { recursive: true, force: true });
		directory = undefined;
	};
	const receive = async (request: any) => {
		if (request.token !== token || request.session !== sessionId()) throw new Error("Подключение устарело. Повтори /emacs в нужной сессии Pi.");
		if (busy || !ctx.isIdle()) throw new Error("Pi занят. Дождись завершения операции и повтори отправку.");
		if (request.kind === "cancel") {
			if (request.id === pending?.id) pending = undefined;
			return;
		}
		if (typeof request.text !== "string" || Buffer.byteLength(request.text) > MAX_BYTES) throw new Error("Некорректный текст или превышен лимит 2 MiB.");
		const session = sessionId();
		const leaf = leafId();
		busy = true;
		try {
			let message: string;
			if (request.kind === "comment") {
				const edit = pending;
				if (!edit || edit.id !== request.id || edit.session !== session || edit.leaf !== leaf) throw new Error("Ответ или ветка изменились. Повтори /comment; правки остались в Emacs.");
				if (edit.answer.text === request.text) { pending = undefined; return; }
				await writeFile(join(directory!, "original.md"), edit.answer.text, { mode: 0o600 });
				await writeFile(join(directory!, "edited.md"), request.text, { mode: 0o600 });
				const diff = await unifiedDiff(join(directory!, "original.md"), join(directory!, "edited.md"));
				message = [`Это мои правки и комментарии к твоему ответу (session ${session}, entry ${edit.answer.id}).`, "Учти изменения и ответь на замечания. Исходный ответ в истории не изменён.", "BEGIN USER DIFF", diff, "END USER DIFF"].join("\n\n");
			} else if (request.kind === "notes" && request.text.trim()) {
				message = ["Обсуди мои Pi:-комментарии по пунктам. Не изменяй файлы, не удаляй комментарии и не создавай коммиты без отдельного запроса. Можно читать код для дополнительного контекста.", "Ниже текст из открытых буферов Emacs; несохранённые изменения могут отличаться от файлов на диске.", "BEGIN USER CODE COMMENTS", request.text, "END USER CODE COMMENTS"].join("\n\n");
			} else if (request.kind === "snippet" && request.text.trim()) {
				message = ["Фрагмент из Emacs для обсуждения. Несохранённый буфер может отличаться от файла на диске. Не изменяй файлы и не создавай коммиты без отдельного запроса.", "BEGIN USER SNIPPET", request.text, "END USER SNIPPET"].join("\n\n");
			} else throw new Error("Неизвестный запрос или пустой текст.");
			if (!ctx.isIdle() || sessionId() !== session || leafId() !== leaf) throw new Error("Сессия изменилась. Ничего не отправлено.");
			pi.sendUserMessage(message);
			if (request.kind === "comment") pending = undefined;
		} finally { busy = false; }
	};
	const start = async () => {
		if (server) return;
		directory = await mkdtemp(join(tmpdir(), "pi-emacs-"));
		token = randomBytes(32).toString("hex");
		server = createServer((client) => {
			clients.add(client);
			client.on("close", () => clients.delete(client));
			client.on("error", () => {});
			client.setTimeout(30000, () => client.destroy());
			let input = "";
			let handled = false;
			client.setEncoding("utf8");
			client.on("data", (chunk) => {
				if (handled) return;
				input += chunk;
				if (Buffer.byteLength(input) > MAX_BYTES * 6 + 4096) { client.destroy(); return; }
				const end = input.indexOf("\n");
				if (end < 0) return;
				handled = true;
				void (async () => {
					try { await receive(JSON.parse(input.slice(0, end))); client.end(JSON.stringify({ ok: true }) + "\n"); }
					catch (error) { client.end(JSON.stringify({ error: error instanceof Error ? error.message : "Ошибка отправки." }) + "\n"); }
				})();
			});
		});
		try {
			await new Promise<void>((resolve, reject) => { server!.once("error", reject); server!.listen(endpoint(), resolve); });
		} catch (error) { await cleanup(); throw error; }
	};
	pi.on("session_start", async (_event, context) => {
		await cleanup();
		ctx = context;
		selected = undefined;
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type === "custom" && entry.customType === "emacs-server" && typeof (entry.data as any)?.name === "string") selected = (entry.data as any).name;
		}
		if (selected && ctx.mode === "tui") {
			try { await start(); await register(selected); }
			catch { ctx.ui.notify(`Emacs ${selected} недоступен. После запуска повтори /emacs ${selected}.`, "warning"); }
		}
	});
	pi.on("session_shutdown", cleanup);
	pi.registerCommand("emacs", {
		description: "Подключить сессию Pi к именованному серверу Emacs",
		handler: async (args, context) => {
			ctx = context;
			if (ctx.mode !== "tui") return;
			if (!args.trim()) { ctx.ui.notify(selected ? `Emacs: ${selected}` : "Emacs не выбран. Используй /emacs server-name.", "info"); return; }
			try {
				const name = serverName(args);
				await start();
				await register(name);
				if (selected && selected !== name) {
					try { await evaluate(selected, `(pi-emacs-unregister ${lisp(endpoint())})`); } catch { /* Old server may be gone. */ }
					pending = undefined;
				}
				selected = name;
				pi.appendEntry("emacs-server", { name });
				ctx.ui.notify(`Подключён Emacs ${name}.`, "info");
			} catch (error) { ctx.ui.notify(`Не удалось подключить Emacs: ${error instanceof Error ? error.message : error}`, "error"); }
		},
	});
	pi.registerCommand("comment", {
		description: "Править последний ответ в *pi-comment* выбранного Emacs",
		handler: async (args, context) => {
			ctx = context;
			if (ctx.mode !== "tui") return;
			if (args.trim()) { ctx.ui.notify("Использование: /comment", "warning"); return; }
			if (!selected) { ctx.ui.notify("Сначала выбери Emacs: /emacs server-name.", "warning"); return; }
			if (busy || !ctx.isIdle()) { ctx.ui.notify("Дождись завершения операции.", "warning"); return; }
			const answer = latestAnswer(ctx.sessionManager.getBranch());
			if (!answer) { ctx.ui.notify("В текущей ветке нет текстового ответа.", "warning"); return; }
			if (Buffer.byteLength(answer.text) > MAX_BYTES) { ctx.ui.notify("Ответ превышает лимит 2 MiB.", "warning"); return; }
			try {
				await start();
				await register(selected);
				const edit = { id: randomUUID(), session: sessionId(), leaf: leafId(), answer };
				const file = join(directory!, "answer.md");
				await writeFile(file, answer.text, { mode: 0o600 });
				await evaluate(selected, `(pi-emacs-open-comment ${lisp(metadata())} ${lisp(edit.id)} ${lisp(file)})`);
				pending = edit;
				ctx.ui.notify("Ответ в Emacs: C-c C-c — отправить; C-c C-k — отменить.", "info");
			} catch (error) { ctx.ui.notify(`Не удалось открыть /comment: ${error instanceof Error ? error.message : error}`, "error"); }
		},
	});
}
