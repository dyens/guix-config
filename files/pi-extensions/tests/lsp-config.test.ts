import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const config = JSON.parse(await readFile(new URL("../../pi-lsp.json", import.meta.url), "utf8"));

test("LSP config has unique servers, explicit commands and file language mappings", () => {
	assert.equal(config.version, 1);
	assert.equal(config.servers.length, 5);
	assert.equal(new Set(config.servers.map((server: any) => server.id)).size, 5);
	for (const server of config.servers) {
		assert.equal(typeof server.bin, "string");
		assert.ok(Array.isArray(server.args));
		assert.ok(server.args.every((arg: unknown) => typeof arg === "string"));
		assert.equal(server.cwd, "{root}");
		assert.ok(server.rootMarkers.length > 0);
		assert.ok(server.include.length > 0);
		assert.ok(server.startupTimeoutMs > 0);
		assert.ok(server.diagnosticsWaitMs > 0);
		for (const extension of Object.keys(server.languageIdByExtension)) {
			assert.ok(server.include.includes(`**/*${extension}`), `${server.id}: missing include for ${extension}`);
		}
	}
});

test("Pyright receives initial configuration notification and speaks stdio", () => {
	const pyright = config.servers.find((server: any) => server.id === "pyright");
	assert.equal(pyright.bin, "pyright-langserver");
	assert.deepEqual(pyright.args, ["--stdio"]);
	// pi-lsp sends didChangeConfiguration only if settings is explicitly present.
	// Without it Pyright 1.1.408 waits for configuration and hover times out.
	assert.deepEqual(pyright.settings, {});
});

test("Guix Home loads only the manual adapter and pins its private dependency", async () => {
	const home = await readFile(new URL("../../../home/pi.scm", import.meta.url), "utf8");
	const manifest = JSON.parse(await readFile(new URL("../lsp-manual/package.json", import.meta.url), "utf8"));
	assert.equal(manifest.dependencies["pi-lsp"], "0.1.7");
	assert.deepEqual(manifest.pi.extensions, ["./index.ts"]);
	const activeSources = home.split("(define %pi-package-sources")[1].split("(define %pi-retired-package-sources")[0];
	assert.doesNotMatch(activeSources, /"npm:pi-lsp"/);
	assert.match(home, /"\.pi\/agent\/lsp\.json"/);
	assert.match(home, /local-file "\.\.\/files\/pi-lsp\.json"/);
	for (const file of ["package.json", "index.ts", "adapter.ts"]) {
		assert.ok(home.includes(`.pi/agent/extensions/lsp-manual/${file}`));
	}
	assert.match(home, /"--ignore-scripts"/);
	assert.match(home, /"--omit=peer"/);
});
