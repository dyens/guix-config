"""Ponytail is an explicit overlay, not a change to default or product files."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ponytail_prepare', ROOT / 'ponytail/prepare.py')
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PonytailTests(unittest.TestCase):
    def test_overlay_replaces_code_policies_and_preserves_engine_and_permissions(self):
        originals = {p: hashlib.sha256(p.read_bytes()).hexdigest()
                     for folder in ('profile', 'skills', 'agents', 'prompts')
                     for p in (ROOT / folder).rglob('*') if p.is_file()}
        with tempfile.TemporaryDirectory() as temp:
            runtime = module.prepare(Path(temp) / 'runtime')
            manifest = json.loads((runtime / 'ponytail-runtime.json').read_text())
            self.assertEqual(manifest['variant'], 'plan-cycle-v2-ponytail-full')
            self.assertEqual(manifest['upstream']['commit'],
                             '09c434ab73ca43761c5d8b0c5d341926c2fba710')
            for item in manifest['files']:
                self.assertEqual(module.digest(runtime.parent / item['path']), item['sha256'])
            for name in ('ponytail', 'ponytail-review'):
                self.assertEqual((runtime / f'skills/{name}/SKILL.md').read_bytes(),
                                 (ROOT / f'ponytail/vendor/skills/{name}/SKILL.md').read_bytes())
            for name in ('core.ts', 'index.ts', 'tasks.ts'):
                self.assertEqual((runtime.parent / f'pi-extensions/plan-cycle/{name}').read_bytes(),
                                 (ROOT.parent / f'pi-extensions/plan-cycle/{name}').read_bytes())
            for path in ('launch.py', 'profile/testing.md', 'agents/ops.md', 'prompts/wait-what.md',
                         'skills/git-workflow/SKILL.md', 'skills/retro/SKILL.md',
                         'skills/retro/scripts/session-summary.py'):
                self.assertEqual((runtime / path).read_bytes(), (ROOT / path).read_bytes())
            skill = (runtime / 'skills/implement/SKILL.md').read_text()
            self.assertIn('read `../ponytail/SKILL.md` IN FULL', skill)
            for token in ('task_plan', 'task_complete', 'task_block',
                          'ruclaw-plan-reviewer', 'Only publish when authorized',
                          'Standing implement permissions', 'Ordinary LOCAL commits',
                          'No default permission for push/MR publication'):
                self.assertIn(token, skill)
            workflow = (runtime / 'profile/workflow.md').read_text()
            self.assertIn('Standing USER permission for implement', workflow)
            self.assertIn('Do not ask again within these bounds', workflow)
            safeguards = (runtime / 'skills/implement/references/plan-cycle.md').read_text()
            self.assertNotIn('## Design and checks', safeguards)
            self.assertNotIn('Prefer deterministic negative', safeguards)
            self.assertIn('equivalence of ALL relevant inputs', safeguards)
            self.assertIn('global prune', safeguards)
            project = (runtime / 'profile/project.md').read_text()
            self.assertNotIn('## Architecture direction', project)
            self.assertNotIn('Put new business rules', project)
            review = (runtime / 'skills/code-review/SKILL.md').read_text()
            self.assertIn('../ponytail-review/SKILL.md', review)
            self.assertNotIn('Risk questions where applicable:', review)
            for role in ('plan-reviewer.md', 'reviewer.md'):
                text = (runtime / 'agents' / role).read_text()
                for token in ('inheritProjectContext: false', 'inheritGlobalContext: false',
                              'inheritSkills: false', 'defaultContext: fresh',
                              'tools: read, bash, write', 'output: false',
                              'outputMode: inline', 'ponytail-review/SKILL.md',
                              'No source edits', 'nested delegation'):
                    self.assertIn(token, text)
            with self.assertRaises(FileExistsError):
                module.prepare(runtime.parent)
            with patch.object(module, 'digest', return_value='modified'):
                with self.assertRaisesRegex(ValueError, 'Upstream content changed'):
                    module.prepare(Path(temp) / 'invalid')
            self.assertFalse((Path(temp) / 'invalid').exists())
        self.assertTrue(all(module.digest(path) == sha for path, sha in originals.items()))


if __name__ == '__main__':
    unittest.main()
