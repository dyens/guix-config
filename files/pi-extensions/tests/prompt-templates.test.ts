import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { DefaultResourceLoader, SettingsManager } from "@earendil-works/pi-coding-agent";

const template = resolve("files/pi-ruclaw/prompts/wait-what.md");
const piEntry = import.meta.resolve("@earendil-works/pi-coding-agent");
const { expandPromptTemplate } = await import(new URL("./core/prompt-templates.js", piEntry).href);

test("wait-what loads globally and explicitly with discovery disabled; expands default and supplied topics", async t => {
	const root = await mkdtemp(join(tmpdir(), "pi-wait-what-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	const agentDir = join(root, "agent");
	const globalTemplate = join(agentDir, "prompts/wait-what.md");
	await mkdir(dirname(globalTemplate), { recursive: true });
	await writeFile(globalTemplate, await readFile(template));
	for (const explicit of [false, true]) {
		const loader = new DefaultResourceLoader({
			cwd: root, agentDir, settingsManager: SettingsManager.inMemory(),
			noExtensions: true, noSkills: true, noThemes: true, noContextFiles: true,
			noPromptTemplates: explicit,
			additionalPromptTemplatePaths: explicit ? [template] : [],
		});
		await loader.reload();
		const loaded = loader.getPrompts();
		assert.deepEqual(loaded.diagnostics, []);
		assert.equal(loaded.prompts.filter((p: any) => p.name === "wait-what").length, 1);
		const command = loaded.prompts.find((p: any) => p.name === "wait-what")!;
		assert.match(command.description, /Объясни проще/);
		const plain = expandPromptTemplate("/wait-what", loaded.prompts);
		assert.match(plain, /Объясни предыдущий ответ ассистента простыми словами/);
		assert.match(plain, /одно предложение — одна мысль/i);
		assert.match(plain, /не разрешение менять файлы/);
		assert.ok(!plain.includes("${@"));
		const topic = expandPromptTemplate('/wait-what "Зачем нужен LSP?"', loaded.prompts);
		assert.match(topic, /Зачем нужен LSP\?/);
		assert.ok(!topic.includes("Объясни предыдущий ответ ассистента простыми словами"));
		assert.equal(expandPromptTemplate("/unrelated", loaded.prompts), "/unrelated");
	}
});
