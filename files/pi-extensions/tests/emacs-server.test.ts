import assert from "node:assert/strict";
import { execFile, spawn, type ChildProcess } from "node:child_process";
import { randomUUID } from "node:crypto";
import { promisify } from "node:util";
import test from "node:test";
import comment from "../comment.ts";

const exec = promisify(execFile);
const evaluate = (name: string, form: string) => exec("emacsclient", ["--socket-name", name, "--alternate-editor=false", "--eval", form], { timeout: 5000 });
const pause = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

test("two real named Emacs servers: route comment, submit and switch without spawning editors", async () => {
	const names = [`pi-test-${randomUUID()}`, `pi-test-${randomUUID()}`];
	const children: ChildProcess[] = [];
	const commands: Record<string, any> = {}, events: Record<string, any> = {};
	const sent: string[] = [], notifications: string[] = [];
	const ctx = {
		cwd: process.cwd(), mode: "tui", isIdle: () => true,
		sessionManager: {
			getBranch: () => [{ type: "message", id: "answer", message: { role: "assistant", content: [{ type: "text", text: "Original answer\n" }] } }],
			getSessionId: () => "test-session", getLeafId: () => "test-leaf",
		}, ui: { notify: (text: string) => notifications.push(text) },
	};
	comment({ on: (name: string, handler: any) => { events[name] = handler; },
		registerCommand: (name: string, command: any) => { commands[name] = command.handler; },
		appendEntry: () => {}, sendUserMessage: (text: string) => sent.push(text),
	} as any);
	try {
		for (const name of names) {
			const child = spawn("emacs", ["--batch", "-Q", "-l", "files/emacs/lisp/dy-pi.el", "--eval",
				`(progn (pi-emacs-server-start ${JSON.stringify(name)}) (while t (accept-process-output nil 0.1)))`], { stdio: "ignore" });
			children.push(child);
			let started = false;
			for (let i = 0; i < 50; i++) {
				try { assert.match((await evaluate(name, "server-name")).stdout, new RegExp(name)); started = true; break; }
				catch { await pause(100); }
			}
			assert.ok(started, `Emacs ${name} failed to start`);
		}
		await events.session_start({}, ctx);
		await commands.emacs(names[0], ctx);
		await commands.comment("", ctx);
		assert.match((await evaluate(names[0], '(with-current-buffer "*pi-comment*" (buffer-string))')).stdout, /Original answer/);
		assert.equal((await evaluate(names[1], '(if (get-buffer "*pi-comment*") t nil)')).stdout.trim(), "nil");
		await evaluate(names[0], '(with-current-buffer "*pi-comment*" (goto-char (point-max)) (insert "Pi: Please clarify\\n") (pi-emacs-submit))');
		assert.equal(sent.length, 1);
		assert.match(sent[0], /\+Pi: Please clarify/);
		await commands.emacs(names[1], ctx);
		assert.equal((await evaluate(names[0], "(length pi-emacs--sessions)")).stdout.trim(), "0");
		await commands.comment("", ctx);
		assert.match((await evaluate(names[1], '(with-current-buffer "*pi-comment*" (buffer-string))')).stdout, /Original answer/);
		assert.ok(!notifications.some((text) => /Не удалось/.test(text)));
		// A missing named server must fail, never invoke an alternate Emacs.
		await commands.emacs(`missing-${randomUUID()}`, ctx);
		assert.match(notifications.at(-1)!, /Не удалось подключить/);
		await commands.emacs("", ctx);
		assert.equal(notifications.at(-1), `Emacs: ${names[1]}`);
	} finally {
		await events.session_shutdown();
		for (let i = 0; i < children.length; i++) {
			try { await evaluate(names[i], "(kill-emacs 0)"); } catch { /* Server exits before responding. */ }
			if (children[i].exitCode === null) children[i].kill("SIGTERM");
		}
	}
});
