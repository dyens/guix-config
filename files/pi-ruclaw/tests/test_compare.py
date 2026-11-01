import concurrent.futures
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'skills/compare/scripts/append-note.py'
spec = importlib.util.spec_from_file_location('compare_append', SCRIPT)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def key(text):
    return hashlib.sha256(text.encode()).hexdigest()


def note(case):
    return f'## Test case\n<!-- compare-key: {case} -->\nТестовая заметка.'


class CompareNotesTests(unittest.TestCase):
    def test_append_preserves_history_and_deduplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            corpus = Path(directory) / 'corpus.md'
            first, second = key('first'), key('second')
            self.assertTrue(module.append_note(corpus, first, note(first)))
            original = corpus.read_bytes()
            self.assertFalse(module.append_note(corpus, first, note(first)))
            self.assertEqual(corpus.read_bytes(), original)
            self.assertTrue(module.append_note(corpus, second, note(second)))
            self.assertTrue(corpus.read_bytes().startswith(original))
            self.assertEqual(corpus.stat().st_mode & 0o777, 0o600)

    def test_invalid_note_does_not_create_corpus(self):
        with tempfile.TemporaryDirectory() as directory:
            corpus = Path(directory) / 'corpus.md'
            for case, text in [('invalid', 'text'), (key('case'), 'missing marker')]:
                with self.assertRaises(ValueError):
                    module.append_note(corpus, case, text)
            self.assertFalse(corpus.exists())

    def test_concurrent_writers_do_not_duplicate_or_lose_notes(self):
        with tempfile.TemporaryDirectory() as directory:
            corpus = Path(directory) / 'corpus.md'
            keys = [key(str(index)) for index in range(8)]
            def append(case):
                return module.append_note(corpus, case, note(case))
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(append, keys * 4))
            self.assertEqual(sum(results), len(keys))
            text = corpus.read_text()
            for case in keys:
                self.assertEqual(text.count(f'<!-- compare-key: {case} -->'), 1)
            self.assertEqual(text.count('# Сравнения моделей'), 1)


if __name__ == '__main__':
    unittest.main()
