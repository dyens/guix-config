import importlib.util
import json
import shutil
from pathlib import Path
import tempfile
import unittest

PATH = Path(__file__).resolve().parents[1] / 'scripts/acceptance.py'
spec = importlib.util.spec_from_file_location('acceptance', PATH)
assert spec and spec.loader
acceptance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acceptance)


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.suite = self.root / 'suite'
        self.suite.mkdir()
        self.base = 'a' * 40
        self.seal = self.root / 'seal.json'
        for name in ('authority.md', 'run.md', 'control.log', 'failure.log', 'probe.py'):
            (self.suite / name).write_text('fixture ' + name)
        self.plan = {'baseSha': self.base, 'criteria': [{
            'id': 'R1', 'tier': 'requirement', 'boundary': 'producer -> consumer',
            'expected': 'observable contract', 'cases': [
                {'id': 'control', 'polarity': 'positive', 'baseline': 'pass', 'reason': 'valid input', 'evidence': 'control.log'},
                {'id': 'negative', 'polarity': 'negative', 'baseline': 'fail', 'reason': 'intended old defect', 'evidence': 'failure.log'},
            ]}]}
        self.save()

    def save(self):
        (self.suite / 'criteria.json').write_text(json.dumps(self.plan))

    def freeze(self):
        return acceptance.freeze(self.suite, self.seal, self.base)

    def test_freeze_and_verify_are_read_only_for_suite(self):
        before = acceptance.inventory(self.suite)
        anchor = self.freeze()
        self.assertEqual(acceptance.verify(self.seal, anchor, self.base), self.suite)
        self.assertEqual(acceptance.inventory(self.suite), before)

    def test_execution_copy_must_match_original_suite(self):
        anchor = self.freeze()
        copy = self.root / 'execution-copy'
        shutil.copytree(self.suite, copy)
        self.assertEqual(acceptance.verify(self.seal, anchor, self.base, copy), copy)
        (copy / 'probe.py').write_text('different test executed')
        with self.assertRaisesRegex(ValueError, 'execution copy differs'):
            acceptance.verify(self.seal, anchor, self.base, copy)

    def test_assertion_change_rejected(self):
        anchor = self.freeze()
        (self.suite / 'probe.py').write_text('weakened assertion')
        with self.assertRaisesRegex(ValueError, 'suite changed'):
            acceptance.verify(self.seal, anchor, self.base)

    def test_authority_change_rejected(self):
        anchor = self.freeze()
        (self.suite / 'authority.md').write_text('different grants')
        with self.assertRaisesRegex(ValueError, 'suite changed'):
            acceptance.verify(self.seal, anchor, self.base)

    def test_added_or_deleted_file_rejected(self):
        anchor = self.freeze()
        extra = self.suite / 'shadow.py'
        extra.write_text('new imported helper')
        with self.assertRaisesRegex(ValueError, 'suite changed'):
            acceptance.verify(self.seal, anchor, self.base)
        extra.unlink()
        (self.suite / 'probe.py').unlink()
        with self.assertRaisesRegex(ValueError, 'suite changed'):
            acceptance.verify(self.seal, anchor, self.base)

    def test_seal_cannot_be_overwritten_or_reanchored_silently(self):
        anchor = self.freeze()
        before = self.seal.read_bytes()
        with self.assertRaises(FileExistsError):
            self.freeze()
        self.assertEqual(before, self.seal.read_bytes())
        self.seal.write_text(before.decode() + ' ')
        with self.assertRaisesRegex(ValueError, 'seal SHA256 mismatch'):
            acceptance.verify(self.seal, anchor, self.base)

    def test_base_mismatch_rejected(self):
        anchor = self.freeze()
        with self.assertRaisesRegex(ValueError, 'base mismatch'):
            acceptance.verify(self.seal, anchor, 'b' * 40)

    def test_symlink_in_suite_rejected(self):
        (self.root / 'outside.py').write_text('outside')
        (self.suite / 'linked.py').symlink_to(self.root / 'outside.py')
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            self.freeze()

    def test_symlink_suite_or_seal_rejected(self):
        alias = self.root / 'alias'
        alias.symlink_to(self.suite, target_is_directory=True)
        with self.assertRaises(ValueError):
            acceptance.freeze(alias, self.seal, self.base)
        anchor = self.freeze()
        alias_seal = self.root / 'alias.json'
        alias_seal.symlink_to(self.seal)
        with self.assertRaises(ValueError):
            acceptance.verify(alias_seal, anchor, self.base)

    def test_required_documents_and_external_evidence_rejected(self):
        (self.suite / 'run.md').unlink()
        with self.assertRaisesRegex(ValueError, 'run.md'):
            self.freeze()
        (self.suite / 'run.md').write_text('replay')
        self.plan['criteria'][0]['cases'][0]['evidence'] = '../external.log'
        self.save()
        with self.assertRaisesRegex(ValueError, 'evidence inside suite'):
            self.freeze()

    def test_duplicate_ids_missing_controls_and_tiers_rejected(self):
        for change in ('duplicate', 'control', 'tier'):
            with self.subTest(change=change):
                plan = json.loads(json.dumps(self.plan))
                if change == 'duplicate':
                    plan['criteria'].append(plan['criteria'][0])
                elif change == 'control':
                    plan['criteria'][0]['cases'].pop()
                else:
                    plan['criteria'][0]['tier'] = 'whatever'
                (self.suite / 'criteria.json').write_text(json.dumps(plan))
                with self.assertRaises(ValueError):
                    self.freeze()

    def test_blocker_is_retained_not_rewritten_as_pass(self):
        case = self.plan['criteria'][0]['cases'][1]
        case.update(baseline='blocked', reason='fixture permission missing')
        self.save()
        anchor = self.freeze()
        acceptance.verify(self.seal, anchor, self.base)
        actual = json.loads((self.suite / 'criteria.json').read_text())
        self.assertEqual(actual['criteria'][0]['cases'][1]['baseline'], 'blocked')
        # A structurally valid seal is NOT an acceptance verdict.
        self.assertNotIn('accepted', json.loads(self.seal.read_text()))

    def outcomes(self, anchor):
        path = self.root / 'results.json'
        (self.root / 'executed.log').write_text('command, actual boundary and execution results')
        body = {'candidateSha': 'b' * 40, 'sealSha256': anchor, 'cases': [
            {'id': 'control', 'status': 'pass', 'evidence': 'executed.log'},
            {'id': 'negative', 'status': 'pass', 'evidence': 'executed.log'},
        ]}
        path.write_text(json.dumps(body))
        return path, body

    def test_judge_all_required_pass_is_not_production_ready(self):
        anchor = self.freeze()
        path, _ = self.outcomes(anchor)
        verdict = acceptance.judge(self.seal, anchor, self.base, 'b' * 40, path)
        self.assertEqual(verdict['requirement_acceptance'], 'met')
        self.assertEqual(verdict['production_readiness'], 'not_established')

    def test_failed_skipped_or_blocked_requirement_never_accepted(self):
        anchor = self.freeze()
        path, body = self.outcomes(anchor)
        for status in ('fail', 'skip', 'blocked'):
            body['cases'][1]['status'] = status
            path.write_text(json.dumps(body))
            verdict = acceptance.judge(self.seal, anchor, self.base, 'b' * 40, path)
            self.assertEqual(verdict['requirement_acceptance'], 'not_met')

    def test_subset_duplicate_or_wrong_candidate_cannot_be_judged(self):
        anchor = self.freeze()
        path, original = self.outcomes(anchor)
        for change in ('subset', 'duplicate', 'candidate', 'evidence'):
            with self.subTest(change=change):
                body = json.loads(json.dumps(original))
                if change == 'subset':
                    body['cases'].pop()
                elif change == 'duplicate':
                    body['cases'].append(body['cases'][0])
                elif change == 'candidate':
                    body['candidateSha'] = 'c' * 40
                else:
                    body['cases'][0]['evidence'] = '../outside'
                path.write_text(json.dumps(body))
                with self.assertRaises(ValueError):
                    acceptance.judge(self.seal, anchor, self.base, 'b' * 40, path)

    def test_pending_delivery_does_not_hide_passed_requirements(self):
        self.plan['criteria'].append({'id': 'D1', 'tier': 'delivery', 'boundary': 'pipeline', 'expected': 'green', 'cases': [
            {'id': 'd-control', 'polarity': 'positive', 'baseline': 'blocked', 'reason': 'no pipeline', 'evidence': 'control.log'},
            {'id': 'd-negative', 'polarity': 'negative', 'baseline': 'blocked', 'reason': 'no pipeline', 'evidence': 'failure.log'},
        ]})
        self.save()
        anchor = self.freeze()
        path, body = self.outcomes(anchor)
        body['cases'] += [{'id': name, 'status': 'blocked', 'evidence': 'executed.log'} for name in ('d-control', 'd-negative')]
        path.write_text(json.dumps(body))
        verdict = acceptance.judge(self.seal, anchor, self.base, 'b' * 40, path)
        self.assertEqual(verdict['requirement_acceptance'], 'met')
        self.assertEqual(verdict['declared_delivery_checks'], 'pending')
        self.assertEqual(verdict['production_readiness'], 'not_established')

    def test_seal_inside_suite_rejected(self):
        with self.assertRaisesRegex(ValueError, 'outside the suite'):
            acceptance.freeze(self.suite, self.suite / 'seal.json', self.base)


if __name__ == '__main__':
    unittest.main()
