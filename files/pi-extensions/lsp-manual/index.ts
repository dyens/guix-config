import { createRequire } from "node:module";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { Type } from "typebox";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default async function (pi: ExtensionAPI) {
	// Guix installs individual source files as store symlinks. Resolve imports
	// from the writable deployed directory, not a canonicalized store filename.
	const agentDir = process.env.PI_CODING_AGENT_DIR ?? process.env.PI_AGENT_DIR ?? join(homedir(), ".pi", "agent");
	const directory = join(agentDir, "extensions", "lsp-manual");
	const require = createRequire(join(directory, "package.json"));
	const { default: piLsp } = await import(pathToFileURL(require.resolve("pi-lsp/extensions/pi-lsp/index.ts")).href);
	const { registerManualLsp } = await import(pathToFileURL(join(directory, "adapter.ts")).href);
	await registerManualLsp(pi, piLsp, Type.Object({
		paths: Type.Array(Type.String({ minLength: 1 }), {
			minItems: 1, maxItems: 20,
			description: "Saved files to check together, after completing a logical batch of edits",
		}),
	}));
}
