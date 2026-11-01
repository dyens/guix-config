import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { AgentMessage } from "@earendil-works/pi-agent-core";
import { Type } from "typebox";
import { readFile, realpath, stat } from "node:fs/promises";
import { isAbsolute, relative, resolve, sep } from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ENTRY = "ruclaw-work-cycle";
const RESUME = fileURLToPath(new URL("../skills/implement/references/resume.md", import.meta.url));
const PHASES = ["implement", "review", "fix", "verify", "publish"];
type Boundary = {
  toolCallId: string; statePath: string; cycle: number; baseSha: string;
  task: string; authority: string; branch: string; timestamp: number; assistantTimestamp: number;
  phase?: string; // Absent on persisted v1 boundaries; recover without restarting the task.
};

function inside(root: string, path: string) {
  const rel = relative(root, path);
  return rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}

// Validation of references/provenance, not extraction or truncation of answers.
export async function loadCycle(path: string, cwd: string, previous?: Boundary) {
  const root = await realpath(cwd);
  const file = await realpath(resolve(root, path));
  if (!inside(resolve(root, ".scratch"), file)) throw new Error("Cycle state must be inside this checkout's .scratch");
  const state = JSON.parse(await readFile(file, "utf8"));
  if (!state || typeof state !== "object") throw new Error("Expected a cycle manifest object");
  if (state.version === 1) throw new Error("Legacy manifest: use resume.md to migrate current state once; do not restart implementation");
  if (state.version !== 2 || !Number.isSafeInteger(state.cycle) || state.cycle < 1) {
    throw new Error("Expected state version 2 and a positive cycle number");
  }
  if (!PHASES.includes(state.phase) || !["phase-complete", "recovery"].includes(state.transition)) {
    throw new Error("Choose a workflow phase and a phase-complete/recovery transition");
  }
  for (const key of ["task", "authority", "work_state", "resources", "branch", "next_action", "transition_reason", "transition_evidence"]) {
    if (typeof state[key] !== "string" || !state[key].trim()) throw new Error(`Missing ${key}`);
  }
  for (const key of ["base_sha", "head_sha"]) {
    if (typeof state[key] !== "string" || !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(state[key])) {
      throw new Error(`Resolve immutable ${key}`);
    }
  }
  if (!Array.isArray(state.active_children) || state.active_children.length !== 0) {
    throw new Error("Reconcile and settle all children before advancing a cycle");
  }
  if (!Array.isArray(state.short_answers)) {
    throw new Error("short_answers must list the results needed for the destination phase (may be empty before review)");
  }
  const references: Record<string, string> = {};
  for (const [key, value] of Object.entries({ task: state.task, authority: state.authority,
    work_state: state.work_state, resources: state.resources, transition_evidence: state.transition_evidence,
    ...Object.fromEntries(state.short_answers.map((p: unknown, i: number) => [`short_${i}`, p])) })) {
    if (typeof value !== "string" || !value.trim()) throw new Error("Invalid artifact reference");
    const target = await realpath(resolve(root, value));
    if (!inside(root, target) || !(await stat(target)).isFile()) throw new Error("Artifact must be a file inside this checkout");
    references[key] = target;
  }
  const git = (...args: string[]) => execFileSync("git", ["-C", root, ...args], {
    encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"],
  }).trim();
  if (await realpath(git("rev-parse", "--show-toplevel")) !== root) throw new Error("Use the checkout root");
  if (git("rev-parse", "HEAD") !== state.head_sha || git("symbolic-ref", "--short", "HEAD") !== state.branch) {
    throw new Error("Checkpoint head/branch differ from the checkout; reconcile before advancing");
  }
  git("merge-base", "--is-ancestor", state.base_sha, state.head_sha);
  if (previous && (state.cycle !== previous.cycle + 1 || state.base_sha !== previous.baseSha ||
      references.task !== previous.task || references.authority !== previous.authority || state.branch !== previous.branch)) {
    throw new Error("Keep the original task/base/authority/branch and advance exactly one cycle");
  }
  if (previous?.phase === state.phase && state.transition !== "recovery") {
    throw new Error("Stay in the current phase: a micro-step is not a context boundary; finish the phase or record explicit recovery");
  }
  return { statePath: file, cycle: state.cycle, baseSha: state.base_sha as string,
    task: references.task, authority: references.authority, branch: state.branch as string,
    phase: state.phase as string };
}

function lastBoundary(ctx: ExtensionContext): Boundary | undefined {
  // The ACTIVE branch only: abandoned/forked work must not set this branch's state.
  for (const entry of [...ctx.sessionManager.getBranch()].reverse()) {
    if (entry.type === "custom" && entry.customType === ENTRY) return entry.data as Boundary;
  }
}

export function cycleMessages(messages: AgentMessage[], boundary: Boundary): AgentMessage[] {
  const callIndex = messages.findIndex(m => m.role === "assistant" && m.timestamp === boundary.assistantTimestamp &&
    m.content.some(c => c.type === "toolCall" && c.id === boundary.toolCallId));
  const index = callIndex < 0 ? -1 : messages.findIndex((m, i) => i > callIndex &&
    m.role === "toolResult" && m.toolCallId === boundary.toolCallId);
  const text = [
    "Resume the authorized RuClaw task at a workflow phase boundary; earlier conversation is not in this request.",
    `Read ONLY the recovery entry point ${RESUME}, then manifest ${boundary.statePath}.`,
    `Destination phase: ${boundary.phase ?? "legacy recovery: reconcile the compact handoff first"}.`,
    "Read compact current work_state and authority; inspect current live resource/child inventory. Read only phase-relevant short answers and details.",
    "Do NOT restart implement onboarding, reload all policy references, expand an unrelated audit or concatenate historical evidence into current state.",
    "Preserve original base, permissions, unresolved gates and verified decisions. Continue to the phase exit condition, not one micro-step then another reset.",
    index < 0 ? "The cycle boundary is missing (e.g. compaction/interrupted tool). STOP execution: reconcile saved state with the user before proceeding." : "Review phase: call subagents_enable if needed, then subagent to launch independent review on the committed increment now; verify phase: use isolated ops where useful. Never substitute self-review or tool success for acceptance.",
  ].join("\n");
  const bootstrap: AgentMessage = { role: "user", content: [{ type: "text", text }], timestamp: boundary.timestamp };
  // On a missing boundary never silently put old history back. Preserve newer user
  // instructions, but stop automated execution rather than guess unsaved progress.
  const tail = index < 0 ? messages.filter(m => m.role === "user" && m.timestamp > boundary.timestamp) : messages.slice(index + 1);
  return [bootstrap, ...tail];
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "ruclaw_next_cycle",
    label: "Advance persisted RuClaw workflow phase",
    description: "At a completed workflow phase (implement/review/fix/verify/publish), persist its evidence and compact current state; settle children. Call ALONE with a v2 .scratch manifest naming the destination phase. No reset per micro-fix/test. Explicit recovery is allowed without forcing a commit. Not compaction, acceptance or runner_finish.",
    parameters: Type.Object({ state_path: Type.String() }),
    executionMode: "sequential",
    async execute(toolCallId, params, signal, _update, ctx) {
      signal?.throwIfAborted();
      const branch = ctx.sessionManager.getBranch();
      const assistant = [...branch].reverse().find(e => e.type === "message" && e.message.role === "assistant");
      if (!assistant || assistant.type !== "message" || assistant.message.role !== "assistant") throw new Error("Missing tool-call message");
      const calls = assistant.message.content.filter(c => c.type === "toolCall");
      if (calls.length !== 1 || calls[0].id !== toolCallId) throw new Error("Call ruclaw_next_cycle alone, after other work settles");
      const state = await loadCycle(params.state_path, ctx.cwd, lastBoundary(ctx));
      signal?.throwIfAborted();
      const boundary: Boundary = { ...state, toolCallId, timestamp: Date.now(), assistantTimestamp: assistant.message.timestamp };
      pi.appendEntry(ENTRY, boundary);
      return { content: [{ type: "text", text: `Cycle ${state.cycle} saved; the next request restores from ${state.statePath}.` }], details: boundary };
    },
  });
  pi.on("context", (event, ctx) => {
    const boundary = lastBoundary(ctx);
    if (boundary) return { messages: cycleMessages(event.messages, boundary) };
  });
}
