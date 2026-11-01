// Native loaders/validator only: no model calls, Docker, remote APIs or child runs.
import '../../tests/peers.mjs';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const shared = path.dirname(root);
const pi = process.env.PI_RUCLAW_TEST_PI_ROOT ?? path.join(os.homedir(), '.pi/agent/install/releases/0.87.1/node_modules/@earendil-works/pi-coding-agent');
const sub = process.env.PI_RUCLAW_TEST_SUBAGENTS_ROOT ?? path.join(os.homedir(), '.pi/agent/npm/node_modules/pi-subagents');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ruclaw-lite-smoke-'));
process.env.PI_OFFLINE = '1';
process.env.PI_CODING_AGENT_DIR = path.join(tmp, 'agent');
process.env.PI_RUCLAW_ROOT = shared;
process.env.PI_RUCLAW_LAB_ROOT = root;
process.env.PI_RUCLAW_GLOBALS = '';
process.env.PI_SUBAGENT_EXTRA_AGENT_DIRS = path.join(root, 'agents');
try {
  const { DefaultResourceLoader, SettingsManager } = await import(pathToFileURL(path.join(pi, 'dist/index.js')));
  const { discoverAgents } = await import(pathToFileURL(path.join(sub, 'src/agents/agents.js')));
  const { validateWorkflowScript } = await import(pathToFileURL(path.join(sub, 'src/workflows/scripted-workflow.js')));
  const { planChildLaunch } = await import(pathToFileURL(path.join(sub, 'src/runs/shared/child-launch-plan.js')));
  const { injectOutputPathSystemPrompt } = await import(pathToFileURL(path.join(sub, 'src/runs/shared/single-output.js')));
  const cwd = path.join(tmp, 'project');
  fs.mkdirSync(cwd); fs.mkdirSync(process.env.PI_CODING_AGENT_DIR);
  fs.writeFileSync(path.join(cwd, 'CLAUDE.md'), 'TEAM_CANARY');
  const loader = new DefaultResourceLoader({ cwd, agentDir: process.env.PI_CODING_AGENT_DIR,
    settingsManager: SettingsManager.inMemory(), noContextFiles: true, noSkills: true,
    noExtensions: true, noPromptTemplates: true, noThemes: true,
    additionalSkillPaths: [path.join(root, 'skills')],
    additionalPromptTemplatePaths: [path.join(root, 'prompts/lite-review.md'), path.join(root, 'prompts/lite-acceptance.md')],
    additionalExtensionPaths: [path.join(sub, 'index.js')],
    appendSystemPrompt: [path.join(shared, 'profile/project.md'), path.join(root, 'policy.md')] });
  await loader.reload();
  assert.deepEqual(loader.getExtensions().errors, []);
  assert.deepEqual(loader.getSkills().skills.map(s => s.name).sort(), ['lite-implement', 'lite-spec']);
  assert.deepEqual(loader.getPrompts().prompts.map(p => p.name).sort(), ['lite-acceptance', 'lite-review']);
  assert.equal(loader.getAgentsFiles().agentsFiles.length, 0);
  assert.ok(!loader.getAppendSystemPrompt().join('\n').includes('TEAM_CANARY'));
  const extensions = loader.getExtensions().extensions;
  // Outside a real Pi host the runtime intentionally exposes subagent eagerly.
  assert.ok(extensions.some(e => e.tools.has('subagents_enable') || e.tools.has('subagent')));
  assert.ok(extensions.every(e => !e.tools.has('ruclaw_next_cycle')));
  const found = discoverAgents(cwd, 'both', undefined, { globalNpmRoot: null });
  const names = ['ruclaw-lite-reviewer', 'ruclaw-lite-evaluator'];
  for (const name of names) {
    const role = found.agents.find(a => a.name === name);
    assert.ok(role, name);
    for (const key of ['inheritProjectContext', 'inheritGlobalContext', 'inheritSkills']) assert.equal(role[key], false);
    assert.equal(role.defaultContext, 'fresh');
    const plan = planChildLaunch({ agentConfig: role, stepOverrides: {}, runnerCwd: cwd, runtimeCwd: cwd, task: 'Review' });
    assert.equal(plan.outputPath, undefined);
    assert.equal(plan.behavior.outputMode, 'inline');
    assert.equal(injectOutputPathSystemPrompt(role.systemPrompt, plan.outputPath), role.systemPrompt);
  }
  for (const script of ['prepare.js', 'review.js']) {
    const validation = validateWorkflowScript(fs.readFileSync(path.join(root, 'workflows', script), 'utf8'), {
      agentNameError: name => names.includes(name) ? undefined : `Unexpected role ${name}` });
    assert.equal(validation.ok, true, JSON.stringify(validation.errors));
  }
  assert.ok(!fs.existsSync(path.join(cwd, '.pi')));
  console.log('PASS: isolated Lite resources, acceptance-first and frozen-suite review recipes, both native workflows valid, no cycle tool or inherited team context');
} finally { fs.rmSync(tmp, { recursive: true, force: true }); }
