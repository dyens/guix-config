"""GitLab polling: mocked HTTP and clock, no credentials/network/real sleeps."""
import argparse
import importlib.util
from io import StringIO
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch

SCRIPT = Path(__file__).resolve().parents[1] / 'skills/gitlab/scripts/gitlab.py'
spec = importlib.util.spec_from_file_location('gitlab_helper', SCRIPT)
assert spec is not None and spec.loader is not None
gitlab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gitlab)


class Clock:
    now = 0.0

    def sleep(self, seconds):
        self.now += seconds


class GitLabWaitTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.http = self.enterContext(patch.object(gitlab, 'request'))
        self.sleep = self.enterContext(patch.object(gitlab.time, 'sleep', side_effect=self.clock.sleep))
        self.enterContext(patch.object(gitlab.time, 'monotonic', side_effect=lambda: self.clock.now))
        self.output = self.enterContext(patch('sys.stdout', new_callable=StringIO))
        self.errors = self.enterContext(patch('sys.stderr', new_callable=StringIO))

    def wait(self, kind='job', interval=2, timeout=60):
        return gitlab.wait_ci('42', kind, 'group/project', interval, timeout)

    def test_polls_exact_target_and_prints_only_changes(self):
        self.http.side_effect = [{'status': s} for s in ('created', 'pending', 'running', 'running', 'success')]
        self.assertEqual(self.wait(), 0)
        self.assertEqual(self.http.call_count, 5)
        self.assertEqual(self.sleep.call_count, 4)
        self.assertEqual(self.output.getvalue().count('] running'), 1)
        for call in self.http.call_args_list:
            self.assertEqual(call.args, ('/projects/group%2Fproject/jobs/42',))
            self.assertEqual(call.kwargs, {'timeout': 30})

    def test_all_stopping_states_for_both_resources(self):
        for kind in ('job', 'pipeline'):
            for status in sorted(gitlab.CI_STOPPED):
                with self.subTest(kind=kind, status=status):
                    self.http.reset_mock(side_effect=True)
                    self.sleep.reset_mock()
                    self.http.return_value = {'status': status}
                    self.assertEqual(self.wait(kind), 0 if status == 'success' else 1)
                    self.http.assert_called_once_with(f'/projects/group%2Fproject/{kind}s/42', timeout=30)
                    self.sleep.assert_not_called()

    def test_waits_through_all_active_states(self):
        self.http.side_effect = [{'status': s} for s in sorted(gitlab.CI_PENDING)] + [{'status': 'success'}]
        self.assertEqual(self.wait(timeout=120), 0)
        self.assertEqual(self.sleep.call_count, len(gitlab.CI_PENDING))

    def test_timeout_caps_sleep_and_request_and_does_not_poll_again(self):
        self.http.return_value = {'status': 'running'}
        self.assertEqual(self.wait(interval=30, timeout=5), 124)
        self.http.assert_called_once_with('/projects/group%2Fproject/jobs/42', timeout=5)
        self.sleep.assert_called_once_with(5)
        self.assertIn('last status: running', self.errors.getvalue())

    def test_request_exhausting_deadline_returns_timeout(self):
        def expired(*args, **kwargs):
            self.clock.now = 5
            raise SystemExit('request timed out')
        self.http.side_effect = expired
        self.assertEqual(self.wait(timeout=5), 124)
        self.sleep.assert_not_called()

    def test_api_errors_fail_without_retry(self):
        self.http.side_effect = SystemExit('GitLab HTTP 403')
        with self.assertRaisesRegex(SystemExit, 'HTTP 403'):
            self.wait()
        self.http.assert_called_once()
        self.sleep.assert_not_called()

    def test_unknown_or_malformed_status_fails_without_waiting(self):
        for result in (None, {}, {'status': 'unknown'}, {'status': []}):
            with self.subTest(result=result):
                self.http.return_value = result
                self.assertEqual(self.wait(), 1)
        self.sleep.assert_not_called()

    def test_target_urls_and_numeric_ids(self):
        for kind in ('job', 'pipeline'):
            self.assertEqual(gitlab.parse_ci_target('42', kind, 'default'), ('default', 42))
            self.assertEqual(gitlab.parse_ci_target(
                f'https://gitlab.croc.ru/group/sub%20project/-/{kind}s/42?x=1#L2', kind, 'default'),
                ('group/sub project', 42))
        for value in ('0', '-1', '４２', 'https://other.invalid/a/-/jobs/42',
                      'https://gitlab.croc.ru.evil/a/-/jobs/42',
                      'https://user@gitlab.croc.ru/a/-/jobs/42',
                      'http://gitlab.croc.ru/a/-/jobs/42',
                      'https://gitlab.croc.ru/a/-/pipelines/42'):
            with self.subTest(value=value), self.assertRaises(SystemExit):
                gitlab.parse_ci_target(value, 'job', 'default')
        self.http.assert_not_called()

    def test_positive_seconds_rejects_nonfinite_and_nonpositive_values(self):
        self.assertEqual(gitlab.positive_seconds('0.5'), 0.5)
        for value in ('0', '-1', 'nan', 'inf', '-inf'):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                gitlab.positive_seconds(value)

    def test_cli_options_and_interrupt(self):
        with patch.object(gitlab, 'wait_ci', return_value=0) as wait, \
             patch('sys.argv', ['gitlab.py', 'wait-pipeline', '123', '--project', 'g/p',
                                '--interval', '10', '--timeout', '600']):
            with self.assertRaises(SystemExit) as result:
                gitlab.main()
            self.assertEqual(result.exception.code, 0)
            wait.assert_called_once_with('123', 'pipeline', 'g/p', 10, 600)
        with patch.object(gitlab, 'wait_ci', side_effect=KeyboardInterrupt), \
             patch('sys.argv', ['gitlab.py', 'wait-job', '123']):
            with self.assertRaises(SystemExit) as result:
                gitlab.main()
            self.assertEqual(result.exception.code, 130)
        self.http.assert_not_called()

    def test_cli_invalid_interval_fails_before_http(self):
        with patch('sys.argv', ['gitlab.py', 'wait-job', '123', '--interval', '0']):
            with self.assertRaises(SystemExit) as result:
                gitlab.main()
            self.assertEqual(result.exception.code, 2)
        self.http.assert_not_called()


class GitLabRequestTimeoutTests(unittest.TestCase):
    def test_timeout_is_forwarded_without_changing_get_or_auth(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'{"status":"running"}'
        with patch.object(gitlab, 'load_token', return_value='test-only-token'), \
             patch.object(gitlab, 'tls_context') as tls, \
             patch.object(gitlab.urllib.request, 'urlopen', return_value=response) as http:
            self.assertEqual(gitlab.request('/projects/a/jobs/1', timeout=2.5), {'status': 'running'})
            self.assertEqual(http.call_args.kwargs, {'timeout': 2.5, 'context': tls.return_value})
            req = http.call_args.args[0]
            self.assertEqual(req.get_method(), 'GET')
            self.assertEqual(req.full_url, gitlab.BASE_URL + '/api/v4/projects/a/jobs/1')

    def test_trace_uses_the_same_tls_context(self):
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'test trace'
        with patch.object(gitlab, 'load_token', return_value='test-only-token'), \
             patch.object(gitlab, 'tls_context') as tls, \
             patch.object(gitlab, 'request', side_effect=[{}, [{'id': 7}], [{'id': 8, 'status': 'failed'}]]), \
             patch.object(gitlab.urllib.request, 'urlopen', return_value=response) as http, \
             patch('sys.stdout', new_callable=StringIO):
            gitlab.print_ci('1', 'g/p', False, True, 1000)
            self.assertEqual(http.call_args.kwargs, {'timeout': 30, 'context': tls.return_value})
            self.assertTrue(http.call_args.args[0].full_url.endswith('/jobs/8/trace'))


class GitLabTLSTests(unittest.TestCase):
    def test_loads_first_existing_host_bundle(self):
        with patch.dict(gitlab.os.environ, {}, clear=True), \
             patch.object(gitlab.ssl, 'create_default_context') as create, \
             patch.object(Path, 'is_file', side_effect=[False, True]):
            self.assertIs(gitlab.tls_context(), create.return_value)
            create.return_value.load_verify_locations.assert_called_once_with(
                cafile=str(gitlab.SYSTEM_CA_FILES[1]))

    def test_explicit_trust_environment_is_not_overridden(self):
        for key in ('SSL_CERT_FILE', 'SSL_CERT_DIR'):
            with self.subTest(key=key), patch.dict(gitlab.os.environ, {key: '/custom/trust'}, clear=True), \
                 patch.object(gitlab.ssl, 'create_default_context') as create, \
                 patch.object(Path, 'is_file') as exists:
                gitlab.tls_context()
                exists.assert_not_called()
                create.return_value.load_verify_locations.assert_not_called()

    def test_no_host_bundle_preserves_python_defaults(self):
        with patch.dict(gitlab.os.environ, {}, clear=True), \
             patch.object(gitlab.ssl, 'create_default_context') as create, \
             patch.object(Path, 'is_file', return_value=False):
            self.assertIs(gitlab.tls_context(), create.return_value)
            create.return_value.load_verify_locations.assert_not_called()

    def test_real_context_keeps_certificate_and_hostname_verification(self):
        with patch.dict(gitlab.os.environ, {}, clear=True), \
             patch.object(gitlab, 'SYSTEM_CA_FILES', ()):
            context = gitlab.tls_context()
            self.assertEqual(context.verify_mode, gitlab.ssl.CERT_REQUIRED)
            self.assertTrue(context.check_hostname)


if __name__ == '__main__':
    unittest.main()
