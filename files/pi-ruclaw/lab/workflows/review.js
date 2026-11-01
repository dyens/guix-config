// Native pi-subagents workflowScriptPath body. No imports or hidden scheduler.
if (!args || typeof args !== 'object') throw new Error('Review arguments required');
for (const key of ['repo', 'task', 'evidence', 'resultDir', 'acceptanceSeal']) {
  if (typeof args[key] !== 'string' || !args[key].startsWith('/') ||
      /[\n\r\0]/.test(args[key]) || args[key].split('/').includes('..')) {
    throw new Error(`${key} must be an explicit absolute path without traversal`);
  }
}
for (const key of ['task', 'evidence', 'acceptanceSeal']) {
  if (!args[key].startsWith(`${args.repo}/`)) throw new Error(`${key} must belong to the experiment checkout`);
}
for (const key of ['baseSha', 'headSha']) {
  if (!/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(args[key] ?? '')) throw new Error(`Resolve ${key}`);
}
if (!/^[0-9a-f]{64}$/.test(args.sealSha256 ?? '')) throw new Error('Provide the original frozen acceptance anchor');
if (typeof args.critical !== 'boolean') throw new Error('Choose critical true/false explicitly');
if (!args.resultDir.startsWith(`${args.repo}/.scratch/pi-lite/`)) throw new Error('Use an owned task-local result directory');
if (args.previousHead !== undefined && !/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(args.previousHead)) {
  throw new Error('previousHead must be an immutable SHA');
}
const common = `Repository: ${args.repo}\nOriginal fix base: ${args.baseSha}\nCandidate: ${args.headSha}\n` +
  `Approved request: ${args.task}\nCheck evidence: ${args.evidence}\n` +
  `Frozen acceptance seal: ${args.acceptanceSeal}\nOriginal seal SHA256: ${args.sealSha256}\n` +
  'Verify the original anchor/base and every suite file with lab/scripts/acceptance.py before using this contract. ' +
  'Read the sealed authority.md: these are the explicit current-run grants, not inherited session authority; no expansion beyond your role. ' +
  (args.previousHead ? `Prior reviewed head: ${args.previousHead}; delta plus affected invariants, preserve verified unchanged coverage.\n` : '') +
  'Evaluate the cumulative fix scope and approved criteria, including unchanged consumers, not a new whole-feature audit. ' +
  'No product source mutations or remote actions. Read no peer findings before your own first pass. ' +
  'Status/paths only in final completion; process success does not close behavioral or CI/E2E gaps.\n';
const tasks = [{ key: 'primary', label: 'Review approved change and regressions',
  agent: 'ruclaw-lite-reviewer', cwd: args.repo, context: 'fresh', output: false, outputMode: 'inline',
  task: common + `Result directory: ${args.resultDir}/primary\n` +
    'Account for every changed path, every original finding/criterion, test validity and behavior/integration regressions. ' +
    (args.critical ? 'Follow critical tenant/auth, concurrency/lifetime and send/retry uncertainty invariants. ' : '') +
    'No tests or script execution in this source-only role. Write short.md plus details/coverage/checks.' }];
tasks.push({ key: 'acceptance', label: 'Challenge approved behavior independently',
  agent: 'ruclaw-lite-evaluator', cwd: args.repo, context: 'fresh', output: false, outputMode: 'inline',
  task: common + `Result directory: ${args.resultDir}/acceptance\n` +
    'Mode: VERIFY. Replay the already frozen pre-implementation suite, not a newly chosen subset of candidate tests. ' +
    'Verify the sealed suite before and after the run; execute verified copies in owned exact-ref exports. ' +
    'Keep required behavior and delivery gates separate. Do not weaken assertions, change tier or skip a required case to obtain green. ' +
    'New counterexamples can be supplementary findings but do not replace the frozen tests. No live checkout writes or stand operations. ' +
    (args.critical ? 'Prioritize critical authority, lifetime and mutation uncertainty boundaries. ' : '') +
    'Write results.json for ALL frozen case IDs with exact candidate/anchor and execution evidence, then run acceptance.py judge. ' +
    'Write short.md plus criteria.md, checks.md and finding details; a green subset is not acceptance.' });
const children = await runs.all(tasks);
return { ok: children.length === tasks.length && children.every(child => child.ok),
  runs: children.map(child => ({ runId: child.runId ?? null, ok: child.ok, error: child.error ?? null })),
  indexes: tasks.map(task => `${args.resultDir}/${task.key}/short.md`),
  notice: 'Process completion is not an acceptance verdict; inspect indexes, findings and coverage.' };
