import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createConnection } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import test from "node:test";
import comment, { latestAnswer, serverName, unifiedDiff } from "../comment.ts";

const exec = promisify(execFile);
const answer = (id: string, text: string) => ({ type: "message", id, message: { role: "assistant", content: [{ type: "text", text }] } });

test("latestAnswer follows branch and excludes thinking/tools", () => {
	assert.deepEqual(latestAnswer([answer("old", "old"), answer("new", "new"),
		{ type: "message", message: { role: "assistant", content: [{ type: "thinking", thinking: "secret" }] } },
	] as any), { id: "new", text: "new" });
	assert.equal(latestAnswer([]), undefined);
});

test("server names are explicit, allow quoted names and reject paths", () => {
	assert.equal(serverName('"work"'), "work");
	assert.equal(serverName("personal-2"), "personal-2");
	for (const name of ["", "../server", "a b", "x\ny", "x".repeat(65)]) assert.throws(() => serverName(name));
});

test("diff handles unchanged, changed, no newline and errors", async () => {
	const dir = await mkdtemp(join(tmpdir(), "pi-diff-test-"));
	try {
		const a = join(dir, "a"), b = join(dir, "b");
		await writeFile(a, "Привет"); await writeFile(b, "Привет");
		assert.equal(await unifiedDiff(a, b), "");
		await writeFile(b, "Привет\n> COMMENT: исправь\n");
		assert.match(await unifiedDiff(a, b), /\+> COMMENT: исправь/);
		assert.match(await unifiedDiff(a, b), /No newline at end of file/);
		await assert.rejects(unifiedDiff(a, join(dir, "missing")));
	} finally { await rm(dir, { recursive: true, force: true }); }
});

function request(target: any, payload: any): Promise<any> {
	return new Promise((resolve, reject) => {
		const socket = createConnection(target.socket);
		let raw = "";
		socket.on("error", reject);
		socket.on("connect", () => socket.write(JSON.stringify({ token: target.token, session: target.session, ...payload }) + "\n"));
		socket.on("data", (chunk) => { raw += chunk; });
		socket.on("end", () => { try { resolve(JSON.parse(raw)); } catch (error) { reject(error); } });
	});
}

test("named client, nonblocking comment, authentication, stale branches, notes and cleanup", async () => {
	const dir = await mkdtemp(join(tmpdir(), "pi-client-test-"));
	const oldPath = process.env.PATH;
	const record = join(dir, "calls");
	const commands: Record<string, any> = {}, events: Record<string, any> = {};
	const sent: string[] = [], notifications: string[] = [], entries: any[] = [];
	let leaf = "leaf", idle = true;
	const ctx = {
		cwd: dir, mode: "tui", isIdle: () => idle,
		sessionManager: { getBranch: () => [answer("answer-1", "Original\n"), ...entries], getSessionId: () => "session-1", getLeafId: () => leaf },
		ui: { notify: (text: string) => notifications.push(text) },
	};
	comment({
		registerCommand: (name: string, command: any) => { commands[name] = command.handler; },
		on: (name: string, handler: any) => { events[name] = handler; },
		appendEntry: (customType: string, data: any) => entries.push({ type: "custom", customType, data }),
		sendUserMessage: (text: string) => sent.push(text),
	} as any);
	try {
		await writeFile(join(dir, "emacsclient"), `#!${process.execPath}\nrequire('fs').appendFileSync(${JSON.stringify(record)}, JSON.stringify(process.argv.slice(2))+'\\n');\n`, { mode: 0o700 });
		process.env.PATH = `${dir}:${oldPath}`;
		await events.session_start({}, ctx);
		await commands.comment("", ctx);
		assert.match(notifications.pop()!, /Сначала выбери/);
		await commands.emacs('"work"', ctx);
		await commands.comment("", ctx);
		const calls = (await readFile(record, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
		assert.ok(calls.every((args) => args[1] === "work" && args[2] === "--alternate-editor=false"));
		const expression = calls.at(-1).at(-1);
		const fields = [...expression.matchAll(/"(?:[^"\\]|\\.)*"/g)].map((match: any) => JSON.parse(match[0]));
		const target = JSON.parse(fields[0]), id = fields[1];
		assert.deepEqual(await request(target, { kind: "comment", id, text: "Changed\n", token: "wrong" }).then((r) => !!r.error), true);
		leaf = "other";
		assert.match((await request(target, { kind: "comment", id, text: "Changed\n" })).error, /ветка изменились/);
		leaf = "leaf"; idle = false;
		assert.match((await request(target, { kind: "comment", id, text: "Changed\n" })).error, /занят/);
		idle = true;
		assert.deepEqual(await request(target, { kind: "comment", id, text: "Changed\n" }), { ok: true });
		assert.equal(sent.length, 1); assert.match(sent[0], /\+Changed/);
		assert.ok((await request(target, { kind: "comment", id, text: "Again" })).error);
		assert.deepEqual(await request(target, { kind: "notes", text: "a.ts:2\nPi: Почему?" }), { ok: true });
		assert.match(sent[1], /Не изменяй файлы/);
		// Real Emacs speaks the same protocol and observes acknowledgement.
		await exec("emacs", ["--batch", "-Q", "-l", "files/emacs/lisp/dy-pi.el", "--eval",
			`(pi-emacs--send (pi-emacs--decode ${JSON.stringify(JSON.stringify(target))}) "snippet" "sample.el:2-7\\n\\nReal Emacs snippet")`]);
		assert.equal(sent.length, 3);
		assert.match(sent[2], /BEGIN USER SNIPPET/);
		assert.match(sent[2], /sample.el:2-7/);
		assert.match(sent[2], /Не изменяй файлы/);
		assert.ok((await request(target, { kind: "snippet", text: "  " })).error);
		await commands.emacs("personal", ctx);
		assert.equal(entries.at(-1).data.name, "personal");
		await events.session_start({}, ctx);
		await commands.emacs("", ctx);
		assert.equal(notifications.at(-1), "Emacs: personal");
		await assert.rejects(request(target, { kind: "notes", text: "old endpoint" }));
		await commands.comment("", ctx);
		const lastCall = JSON.parse((await readFile(record, "utf8")).trim().split("\n").at(-1)!);
		const nextFields = [...lastCall.at(-1).matchAll(/"(?:[^"\\]|\\.)*"/g)].map((match: any) => JSON.parse(match[0]));
		const nextTarget = JSON.parse(nextFields[0]), nextId = nextFields[1];
		assert.deepEqual(await request(nextTarget, { kind: "comment", id: nextId, text: "Original\n" }), { ok: true });
		assert.equal(sent.length, 3);
		await commands.comment("", ctx);
		const cancelCall = JSON.parse((await readFile(record, "utf8")).trim().split("\n").at(-1)!);
		const cancelFields = [...cancelCall.at(-1).matchAll(/"(?:[^"\\]|\\.)*"/g)].map((match: any) => JSON.parse(match[0]));
		assert.deepEqual(await request(nextTarget, { kind: "cancel", id: cancelFields[1] }), { ok: true });
		assert.ok((await request(nextTarget, { kind: "comment", id: cancelFields[1], text: "Cancelled draft" })).error);
		assert.equal(sent.length, 3);
		await events.session_shutdown();
		await assert.rejects(readFile(fields[2]));
		await assert.rejects(request(target, { kind: "notes", text: "stale" }));
	} finally {
		await events.session_shutdown(); process.env.PATH = oldPath;
		await rm(dir, { recursive: true, force: true });
	}
});
