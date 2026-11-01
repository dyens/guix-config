// Integration smoke against the installed, pinned upstream package. No model,
// real terminal or user settings changes. Run with the test-only Pi peer aliases.
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { homedir, tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { DefaultResourceLoader, SettingsManager } from '@earendil-works/pi-coding-agent';

const packageRoot = resolve(process.env.RPIV_PACKAGE_ROOT ??
  join(homedir(), '.pi/agent/npm/node_modules/@juicesharp/rpiv-ask-user-question'));
const manifest = JSON.parse(await readFile(join(packageRoot, 'package.json'), 'utf8'));
assert.equal(manifest.version, '2.15.0', 'Re-audit and update the pin/smoke together');
const root = await mkdtemp(join(tmpdir(), 'pi-rpiv-smoke-'));
try {
  const loader = new DefaultResourceLoader({
    cwd: root, agentDir: join(root, 'agent'), settingsManager: SettingsManager.inMemory(),
    noExtensions: true, noSkills: true, noPromptTemplates: true, noThemes: true,
    noContextFiles: true, additionalExtensionPaths: [join(packageRoot, 'index.ts')],
  });
  await loader.reload();
  const loaded = loader.getExtensions();
  assert.deepEqual(loaded.errors, []);
  const extension = loaded.extensions.find(item => item.tools.has('ask_user_question'));
  assert.ok(extension);
  const tool = extension.tools.get('ask_user_question').definition;
  const params = { questions: [{
    header: 'Q1', question: 'Можно публиковать?', options: [
      { label: 'Нет', description: 'Только локально' },
      { label: 'Да', description: 'Разрешить push' },
    ],
  }] };
  const run = (id, ctx) => tool.execute(id, params, undefined, undefined, ctx);
  assert.equal((await run('headless', { hasUI: false })).details.error, 'no_ui');

  let active = ['read', 'ask_user_question', 'write'];
  loaded.runtime.getActiveTools = () => active;
  loaded.runtime.setActiveTools = tools => { active = tools; };
  const reconcile = extension.handlers.get('before_agent_start')[0];
  await reconcile({}, { hasUI: false });
  assert.deepEqual(active, ['read', 'write']);
  await reconcile({}, { hasUI: true });
  assert.deepEqual(active, ['read', 'write', 'ask_user_question']);

  const rpc = await run('rpc', { hasUI: true, mode: 'rpc', ui: {
    select: async (_title, options) => options[0], input: async () => undefined,
  } });
  assert.equal(rpc.details.cancelled, false);
  assert.equal(rpc.details.answers[0].answer, 'Нет');
  const cancelled = await run('cancel', { hasUI: true, mode: 'rpc', ui: {
    select: async () => undefined, input: async () => undefined,
  } });
  assert.equal(cancelled.details.cancelled, true);

  // Import the real lazy TUI graph, but do not claim a visual/keybinding test.
  let mounted = false;
  const tui = await run('tui', { hasUI: true, mode: 'tui', ui: {
    custom: async () => { mounted = true; return { answers: [], cancelled: true }; },
  } });
  assert.ok(mounted, JSON.stringify(tui));
  assert.equal(tui.details.cancelled, true);
  assert.equal(tui.details.error, undefined);
  console.log('PASS: pinned RPIV native loading, headless reconciliation, Russian RPC choice/cancel and lazy TUI graph');
} finally {
  await rm(root, { recursive: true, force: true });
}
