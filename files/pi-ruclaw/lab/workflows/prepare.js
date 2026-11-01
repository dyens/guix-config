// One pre-implementation evaluator, not an implementation worker or reset phase.
if (!args || typeof args !== 'object') throw new Error('Preparation arguments required');
for (const key of ['repo', 'task', 'authority', 'resultDir']) {
  if (typeof args[key] !== 'string' || !args[key].startsWith('/') ||
      /[\n\r\0]/.test(args[key]) || args[key].split('/').includes('..')) {
    throw new Error(`${key} must be an explicit absolute path without traversal`);
  }
}
for (const key of ['task', 'authority']) {
  if (!args[key].startsWith(`${args.repo}/`)) throw new Error(`${key} must belong to this experiment`);
}
if (!args.resultDir.startsWith(`${args.repo}/.scratch/pi-lite/`)) throw new Error('Use owned task-local preparation directory');
if (!/^(?:[0-9a-f]{40}|[0-9a-f]{64})$/.test(args.baseSha ?? '')) throw new Error('Resolve baseSha');
const children = await runs.all([{ key: 'prepare', label: 'Prepare behavioral acceptance before implementation',
  agent: 'ruclaw-lite-evaluator', cwd: args.repo, context: 'fresh', output: false, outputMode: 'inline',
  task: `Mode: PREPARE. Repository: ${args.repo}\nOriginal base: ${args.baseSha}\n` +
    `Approved request: ${args.task}\nExplicit operator authority record: ${args.authority}\n` +
    `Result directory: ${args.resultDir}\n` +
    'There is NO candidate implementation. Inspect only original request and exact base. ' +
    'Prepare suite/criteria.json, suite/authority.md, suite/run.md, probes and baseline evidence. ' +
    'Use the minimum real boundary with positive and negative controls for every original ID. ' +
    'Run permitted baseline cases; distinguish intended failure from build/prerequisite errors. ' +
    'Do not silently reclassify mandatory behavior as delivery-only. Record genuine blockers. ' +
    'No product edits, implementation fixes, prior attempts, remote/stand actions or nested delegation. ' +
    'Do NOT seal your own output: parent inspects and freezes the agreed contract. Write short.md last; final status/paths only.' }]);
return { ok: children.length === 1 && children.every(child => child.ok),
  runs: children.map(child => ({ runId: child.runId ?? null, ok: child.ok, error: child.error ?? null })),
  index: `${args.resultDir}/short.md`, suite: `${args.resultDir}/suite`,
  notice: 'Preparation receipt is not approval, a frozen contract or demonstrated candidate behavior.' };
