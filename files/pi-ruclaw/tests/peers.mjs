// Test-only peer aliases: Pi's extension loader normally supplies these.
import { registerHooks } from 'node:module';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
const root = process.env.PI_RUCLAW_TEST_PI_ROOT ?? join(homedir(), '.pi/agent/install/releases/0.87.1/node_modules/@earendil-works/pi-coding-agent');
registerHooks({ resolve(specifier, context, next) {
  try { return next(specifier, context); }
  catch (error) {
    if (!specifier.startsWith('@earendil-works/') && specifier !== 'typebox' && !specifier.startsWith('typebox/')) throw error;
    return next(specifier, { ...context, parentURL: pathToFileURL(join(root, 'dist/index.js')).href });
  }
} });
