"""Retro summaries are structural, read-only and safe to print; no model/network."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'skills/retro/scripts/session-summary.py'
spec = importlib.util.spec_from_file_location('retro_summary', SCRIPT)
assert spec is not None and spec.loader is not None
retro = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retro)


class RetroSummaryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'session.jsonl'

    def save(self, entries, tail=b''):
        raw = b''.join(json.dumps(row).encode() + b'\n' for row in entries) + tail
        self.path.write_bytes(raw)
        return raw

    def message(self, role, **fields):
        return {'type': 'message', 'message': {'role': role, **fields}}

    def call(self, name, **args):
        return self.message('assistant', content=[{'type': 'toolCall', 'name': name, 'arguments': args}])

    def test_metrics_and_citations_without_printing_content_arguments_or_paths(self):
        secret = 'PRIVATE_VALUE_DO_NOT_PRINT'
        raw = self.save([
            self.message('user', content=secret),
            self.call('read', path='/private/' + secret),
            self.call('read', path='/private/' + secret),
            self.call('bash', command='curl -H Authorization:' + secret),
            self.message('toolResult', toolName='bash', content=[{'type': 'text', 'text': secret}], isError=True),
            self.message('assistant', content=[{'type': 'text', 'text': secret}], usage={
                'input': 20, 'cacheRead': 80, 'cacheWrite': 0, 'output': 5, 'totalTokens': 105,
                'cost': {'input': 0.1, 'cacheRead': 0.2, 'output': 0.3, 'total': 0.6}}),
            {'type': 'custom', 'customType': 'plan-cycle-state-v2', 'data': {
                'cycle': 1, 'checkpointId': secret, 'planPath': '/private/' + secret,
                'snapshot': {'plan': '- TODO ' + secret}}},
        ])
        result = retro.summarize(self.path)
        self.assertEqual(self.path.read_bytes(), raw)
        self.assertNotIn(secret, json.dumps(result))
        self.assertNotIn('/private/', json.dumps(result))
        self.assertEqual(result['snapshot']['sha256_read'], hashlib.sha256(raw).hexdigest())
        self.assertEqual(result['tool_calls'], {'read': 2, 'bash': 1})
        self.assertEqual(result['tool_error_results'], {'bash': 1})
        self.assertEqual(result['repeated_reads'][0]['first_line'], 2)
        self.assertEqual(result['repeated_reads'][0]['last_line'], 3)
        self.assertEqual(result['user_messages']['sample_lines'], [1])
        self.assertEqual(result['usage']['reported_tokens']['input'], 20)
        self.assertEqual(result['usage']['reported_tokens']['cacheRead'], 80)
        self.assertEqual(result['usage']['context_estimate_input_plus_cache']['median'], 100)
        self.assertEqual(result['usage']['reported_cost']['total'], 0.6)
        self.assertEqual(result['plan_snapshots']['samples'][0]['line'], 7)

    def test_delegation_dispatch_is_not_reported_as_number_of_reviewers(self):
        self.save([self.call('subagent', action='list'), self.call('subagent', action='resume', id='old'),
                   self.call('subagent', agent='reviewer'), self.call('subagent', workflowScript='many runs'),
                   self.call('subagent', parallel=[{}, {}])])
        result = retro.summarize(self.path)
        self.assertEqual(result['tool_calls']['subagent'], 5)
        self.assertEqual(result['delegation_calls_not_reviewer_runs'], {
            'management': 1, 'direct_resume': 1, 'direct_launch': 1,
            'workflow_dispatch': 1, 'other_dispatch': 1})

    def test_missing_usage_is_not_zero_cost_and_unknown_tools_are_hashed(self):
        self.save([self.call('PRIVATE_TOOL_NAME'), self.message('assistant', usage={
            'input': -1, 'output': True, 'cacheRead': float('nan')})])
        result = retro.summarize(self.path)
        self.assertNotIn('PRIVATE_TOOL_NAME', json.dumps(result))
        self.assertEqual(result['usage']['messages_with_usage'], 0)
        self.assertEqual(result['usage']['reported_cost'], {})
        self.assertIsNone(result['usage']['context_estimate_input_plus_cache']['median'])

    def test_incomplete_tail_is_explicit_but_malformed_middle_is_an_error(self):
        self.save([self.message('user', content='ok')], tail=b'{"private":"SECRET')
        result = retro.summarize(self.path)
        self.assertEqual(result['warnings'], ['incomplete_tail_ignored'])
        self.assertEqual(result['messages']['user'], 1)
        self.path.write_bytes(b'{"private":"SECRET\n{}\n')
        with self.assertRaisesRegex(ValueError, '^Invalid JSONL at line 1$'):
            retro.summarize(self.path)
        run = subprocess.run([sys.executable, str(SCRIPT), str(self.path)], capture_output=True, text=True)
        self.assertEqual(run.returncode, 1)
        self.assertNotIn('SECRET', run.stderr)
        self.assertEqual(run.stdout, '')

    def test_all_branches_are_disclosed_and_large_indexes_are_bounded(self):
        self.save([self.message('user', content='hidden') for _ in range(50)] + [
            {'type': 'custom', 'customType': 'plan-cycle-state-v2', 'data': {
                'cycle': n, 'checkpointId': 'same', 'planPath': 'same', 'snapshot': {'plan': 'x' * n}}}
            for n in range(40)])
        result = retro.summarize(self.path)
        self.assertIn('all branches', result['scope'])
        self.assertEqual(result['user_messages']['count'], 50)
        self.assertEqual(len(result['user_messages']['sample_lines']), 20)
        samples = result['plan_snapshots']['samples']
        self.assertEqual(len(samples), 20)
        self.assertEqual(samples[0]['cycle'], 0)
        self.assertEqual(samples[-1]['cycle'], 39)
        self.assertEqual(len({s['checkpoint_key'] for s in samples}), 1)

    def test_running_session_is_bounded_to_initial_size_and_marks_growth(self):
        raw = self.save([self.message('user', content='first')])
        real_fstat = retro.os.fstat
        calls = 0

        def growing(fd):
            nonlocal calls
            info = real_fstat(fd)
            calls += 1
            if calls == 1:
                with self.path.open('ab') as stream:
                    stream.write(json.dumps(self.message('user', content='later')).encode() + b'\n')
            return info

        with patch.object(retro.os, 'fstat', side_effect=growing):
            result = retro.summarize(self.path)
        self.assertEqual(result['messages']['user'], 1)
        self.assertEqual(result['snapshot']['initial_bytes'], len(raw))
        self.assertEqual(result['snapshot']['sha256_read'], hashlib.sha256(raw).hexdigest())
        self.assertIn('source_changed_during_read', result['warnings'])

    def test_unknown_schema_and_cost_only_usage_are_explicit(self):
        self.save([{'type': 'future'}, self.message('future'),
                   self.message('assistant', usage={'cost': {'total': 0.4}})])
        result = retro.summarize(self.path)
        self.assertIn('unrecognized_entry_types', result['warnings'])
        self.assertIn('unrecognized_message_roles', result['warnings'])
        self.assertIn('token_usage_unavailable', result['warnings'])
        self.assertEqual(result['usage']['messages_with_cost'], 1)
        self.assertEqual(result['usage']['reported_cost']['total'], 0.4)

    def test_valid_final_line_without_newline_and_invalid_non_object(self):
        self.save([], tail=json.dumps(self.message('user', content='ok')).encode())
        self.assertEqual(retro.summarize(self.path)['warnings'], [])
        self.save([], tail=b'[]\n')
        with self.assertRaisesRegex(ValueError, '^Expected object at line 1$'):
            retro.summarize(self.path)


if __name__ == '__main__':
    unittest.main()
