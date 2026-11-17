// Offline integration test against the installed Pi + pi-subagents runtimes.
// No model calls, credentials, Docker, real project edits or child processes.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { registerHooks } from 'node:module';

const root = path.resolve(process.env.PI_RUCLAW_TEST_PROFILE_ROOT ?? path.join(path.dirname(fileURLToPath(import.meta.url)), '..'));
const ponytail = fs.existsSync(path.join(root, 'ponytail-runtime.json'));
const piRoot = process.env.PI_RUCLAW_TEST_PI_ROOT ?? path.join(os.homedir(), '.pi/agent/install/releases/0.87.1/node_modules/@earendil-works/pi-coding-agent');
const subRoot = process.env.PI_RUCLAW_TEST_SUBAGENTS_ROOT ?? path.join(os.homedir(), '.pi/agent/npm/node_modules/pi-subagents');
for (const p of [piRoot, subRoot]) {
  if (!fs.existsSync(path.join(p, 'package.json'))) throw new Error(`Runtime missing: ${p}; set PI_RUCLAW_TEST_PI_ROOT / PI_RUCLAW_TEST_SUBAGENTS_ROOT`);
}
// Pi supplies peer packages through its extension loader. Reproduce that alias
// only inside this standalone test, without installing or symlinking packages.
const hostURL = pathToFileURL(path.join(piRoot, 'dist/index.js')).href;
const hooks = registerHooks({
  resolve(specifier, context, nextResolve) {
    try { return nextResolve(specifier, context); }
    catch (error) {
      if (!specifier.startsWith('@earendil-works/') && specifier !== 'typebox' && !specifier.startsWith('typebox/')) throw error;
      return nextResolve(specifier, { ...context, parentURL: hostURL });
    }
  },
});
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'pi-ruclaw-test-'));
process.env.PI_OFFLINE = '1';
process.env.PI_CODING_AGENT_DIR = path.join(tmp, 'agent');
process.env.PI_SUBAGENT_EXTRA_AGENT_DIRS = path.join(root, 'agents');
process.env.PI_RUCLAW_ROOT = root;
process.env.PI_RUCLAW_GLOBALS = path.join(tmp, 'personal.md');

try {
  const { DefaultResourceLoader, SettingsManager, ExtensionRunner, SessionManager } = await import(pathToFileURL(path.join(piRoot, 'dist/index.js')));
  const { discoverAgents } = await import(pathToFileURL(path.join(subRoot, 'src/agents/agents.js')));
  const { buildInProcessChildLaunch } = await import(pathToFileURL(path.join(subRoot, 'src/runs/shared/child-launch.js')));
  const { rewriteSubagentPrompt } = await import(pathToFileURL(path.join(subRoot, 'src/runs/shared/subagent-prompt-runtime.js')));
  fs.mkdirSync(process.env.PI_CODING_AGENT_DIR, { recursive: true });
  fs.writeFileSync(process.env.PI_RUCLAW_GLOBALS, 'PERSONAL_CANARY');
  const cwd = path.join(tmp, 'project');
  fs.mkdirSync(cwd);
  fs.writeFileSync(path.join(cwd, 'CLAUDE.md'), 'TEAM_CONTEXT_CANARY');
  fs.writeFileSync(path.join(process.env.PI_CODING_AGENT_DIR, 'AGENTS.md'), 'GLOBAL_AUTOLOAD_CANARY');
  const options = {
    cwd, agentDir: process.env.PI_CODING_AGENT_DIR,
    settingsManager: SettingsManager.inMemory(),
    noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true,
    noContextFiles: true,
    additionalSkillPaths: [path.join(root, 'skills')],
    additionalExtensionPaths: [path.join(subRoot, 'index.js'), path.join(root, '../pi-extensions/plan-cycle/index.ts')],
    appendSystemPrompt: [process.env.PI_RUCLAW_GLOBALS, path.join(root, 'profile/project.md'), path.join(root, 'profile/workflow.md')],
  };
  const parent = new DefaultResourceLoader(options);
  await parent.reload();
  assert.equal(parent.getAgentsFiles().agentsFiles.length, 0);
  const loadedExtensions = parent.getExtensions();
  assert.deepEqual(loadedExtensions.errors, []);
  for (const tool of ['task_plan', 'task_get', 'task_complete', 'task_block', 'task_replan']) assert.ok(loadedExtensions.extensions.some(extension => extension.tools.has(tool)));
  assert.ok(!loadedExtensions.extensions.some(extension => extension.tools.has('ruclaw_next_cycle')));
  // Real Pi request-time hook, including restoration of system/tool state.
  const session = SessionManager.inMemory(cwd);
  const checkpoint = session.appendMessage({ role: 'user', content: 'ORIGINAL_TASK_CANARY', timestamp: 1 });
  session.appendMessage({ role: 'assistant', content: [{ type: 'text', text: 'OLD_CONTEXT_CANARY' }], timestamp: 10 });
  session.appendCustomEntry('plan-cycle-state-v2', { version: 2, enabled: true, cwd, checkpointId: checkpoint,
    planPath: path.join(cwd, '.scratch/task/plan.md'), cycle: 1, mode: 'step',
    snapshot: { plan: '- TODO Implement\n- TODO Final review\n', staleReads: [] } });
  session.appendMessage({ role: 'user', content: 'NEW_USER_DECISION_CANARY', timestamp: 23 });
  const runner = new ExtensionRunner(loadedExtensions.extensions, loadedExtensions.runtime, cwd, session, undefined);
  const hookErrors = [];
  runner.onError(error => hookErrors.push(error));
  const projected = await runner.emitContext([
    { role: 'system', content: 'SYSTEM_CANARY', timestamp: 0 },
    ...session.buildSessionContext().messages,
    { role: 'system', content: 'CURRENT_TOOL_STATE_CANARY', timestamp: 24 },
  ]);
  assert.deepEqual(hookErrors, []);
  assert.equal(projected[0].role, 'system');
  const projectedText = JSON.stringify(projected);
  for (const canary of ['SYSTEM_CANARY', 'CURRENT_TOOL_STATE_CANARY', 'NEW_USER_DECISION_CANARY', 'ORIGINAL_TASK_CANARY']) assert.ok(projectedText.includes(canary));
  assert.ok(!projectedText.includes('OLD_CONTEXT_CANARY'));
  assert.ok(projectedText.includes('CURRENT PLAN AT STEP START'));
  assert.ok(projectedText.includes('Final review'));
  const appended = parent.getAppendSystemPrompt().join('\n');
  assert.ok(appended.includes('PERSONAL_CANARY'));
  assert.ok(appended.includes('RuClaw Pi — project profile'));
  assert.ok(appended.includes('Default implementation workflow: structured tasks'));
  assert.ok(!appended.includes('TEAM_CONTEXT_CANARY'));
  assert.ok(!appended.includes('GLOBAL_AUTOLOAD_CANARY'));
  const skills = parent.getSkills().skills.map(s => s.name);
  if (ponytail) {
    for (const name of ['ponytail', 'ponytail-review']) assert.ok(skills.includes(name), `Pinned skill ${name}`);
    assert.ok(appended.includes('These REPLACE the default profile'));
    assert.ok(!appended.includes('Put new business rules'));
    const implement = fs.readFileSync(path.join(root, 'skills/implement/SKILL.md'), 'utf8');
    assert.ok(implement.includes('read `../ponytail/SKILL.md` IN FULL'));
  }
  for (const name of ['implement', 'grill-with-docs', 'to-spec', 'to-tickets',
    'code-review', 'git-workflow', 'jira', 'gitlab', 'retro']) assert.ok(skills.includes(name), `Loaded skill ${name}`);
  for (const relative of ['implement/references/plan-cycle.md', 'implement/references/executor-contract.md',
    'implement/references/result-contract.md', 'implement/references/work-cycles.md',
    'implement/references/resume.md',
    'code-review/references/follow-up.md',
    'code-review/references/bundled-review.md']) {
    assert.ok(fs.existsSync(path.join(root, 'skills', relative)), `Skill reference exists: ${relative}`);
  }
  for (const name of ['implement-with-orchestrator', 'fix-mr']) assert.ok(!skills.includes(name));

  const found = discoverAgents(cwd, 'both', undefined, { globalNpmRoot: null });
  const { planChildLaunch } = await import(pathToFileURL(path.join(subRoot, 'src/runs/shared/child-launch-plan.js')));
  const { injectOutputPathSystemPrompt, injectSingleOutputInstruction, validateFileOnlyOutputMode } =
    await import(pathToFileURL(path.join(subRoot, 'src/runs/shared/single-output.js')));
  const { validateWorkflowScript } = await import(pathToFileURL(path.join(subRoot, 'src/workflows/scripted-workflow.js')));
  const contract = fs.readFileSync(path.join(root, 'skills/implement/references/result-contract.md'), 'utf8');
  const recipe = contract.match(/```js\n([\s\S]*?)\n```/)[1];
  const validation = validateWorkflowScript(recipe, {
    agentNameError: name => found.agents.some(agent => agent.name === name) ? undefined : `Missing ${name}`,
  });
  assert.equal(validation.ok, true, JSON.stringify(validation.errors));
  for (const name of ['ruclaw-plan-reviewer', 'ruclaw-reviewer', 'ruclaw-ops']) {
    const agent = found.agents.find(a => a.name === name);
    assert.ok(agent, `Discovered ${name}`);
    if (ponytail && name !== 'ruclaw-ops') {
      assert.ok(agent.systemPrompt.includes('skills/ponytail-review/SKILL.md'));
      assert.ok(!agent.systemPrompt.includes('negative cases, concurrency, tenant/auth boundaries'));
    }
    for (const key of ['inheritProjectContext', 'inheritGlobalContext', 'inheritSkills']) assert.equal(agent[key], false, `${name}: ${key}`);
    assert.equal(agent.defaultContext, 'fresh');
    assert.ok(agent.tools.includes('write'));
    // Real native planner: disabled single-output + inline does not inject the
    // authoritative-path instruction that conflicts with multi-file reporting.
    for (const stepOverrides of [{}, { output: false, outputMode: 'inline' }]) {
      const plan = planChildLaunch({ agentConfig: agent, stepOverrides, runnerCwd: cwd,
        runtimeCwd: cwd, task: 'Review exact source; write only assigned result artifacts' });
      assert.equal(plan.behavior.output, false);
      assert.equal(plan.behavior.outputMode, 'inline');
      assert.equal(plan.outputPath, undefined);
      assert.equal(validateFileOnlyOutputMode(plan.behavior.outputMode, plan.outputPath, name), undefined);
      assert.equal(injectOutputPathSystemPrompt(agent.systemPrompt, plan.outputPath), agent.systemPrompt);
      assert.equal(injectSingleOutputInstruction('TASK_CANARY', plan.outputPath), 'TASK_CANARY');
    }
    // Negative control demonstrates why even a file-only *receipt* caused T15R38-G01.
    const conflicting = planChildLaunch({ agentConfig: agent, runnerCwd: cwd, runtimeCwd: cwd,
      task: 'Review', stepOverrides: { output: 'receipt.md', outputMode: 'file-only' } });
    assert.ok(injectOutputPathSystemPrompt(agent.systemPrompt, conflicting.outputPath)
      .includes('Ignore any other output filename or output path'));
    assert.ok(validateFileOnlyOutputMode('file-only', undefined, name));
    assert.ok(agent.systemPrompt.includes('result-contract.md'));
    assert.ok(agent.systemPrompt.includes(name === 'ruclaw-reviewer' || (ponytail && name !== 'ruclaw-ops') ? 'short.md' : 'result.md'));
    assert.ok(!agent.systemPrompt.includes('2,500'));
    assert.ok(agent.systemPrompt.includes('PI_RUCLAW_GLOBALS'));
    assert.ok(agent.systemPrompt.includes('$PI_RUCLAW_ROOT/profile/project.md'));
    assert.ok(agent.systemPrompt.includes('$PI_RUCLAW_ROOT/profile/areas.md'));
    const launch = buildInProcessChildLaunch({
      cwd, host: 'parent', sessionEnabled: false, childAgentName: name, childIndex: 0,
      systemPromptMode: agent.systemPromptMode, systemPrompt: agent.systemPrompt,
      inheritProjectContext: agent.inheritProjectContext,
      inheritGlobalContext: agent.inheritGlobalContext, inheritSkills: agent.inheritSkills,
      tools: agent.tools,
    });
    assert.equal(launch.session.noContextFiles, true);
    const child = new DefaultResourceLoader({ ...options, appendSystemPrompt: [],
      noContextFiles: launch.session.noContextFiles, additionalSkillPaths: [], additionalExtensionPaths: [] });
    await child.reload();
    assert.equal(child.getAgentsFiles().agentsFiles.length, 0);
    const rewritten = rewriteSubagentPrompt('Base prompt\n\n<project_context>\n\n<project_instructions path="CLAUDE.md">TEAM_CONTEXT_CANARY</project_instructions>\n</project_context>', agent);
    assert.ok(!rewritten.includes('TEAM_CONTEXT_CANARY'));
  }
  // Negative control: the original loader still discovers project + global files.
  const normal = new DefaultResourceLoader({ ...options, noContextFiles: false, appendSystemPrompt: [] });
  await normal.reload();
  assert.ok(normal.getAgentsFiles().agentsFiles.some(f => f.content.includes('TEAM_CONTEXT_CANARY')));
  assert.ok(normal.getAgentsFiles().agentsFiles.some(f => f.content.includes('GLOBAL_AUTOLOAD_CANARY')));
  console.log('PASS: real Pi parent loading, personal context, explicit skills, reviewer/ops compact results and default structured tasks, child launch noContextFiles, prompt stripping and unchanged normal loading');
} finally {
  hooks.deregister();
  fs.rmSync(tmp, { recursive: true, force: true });
}
