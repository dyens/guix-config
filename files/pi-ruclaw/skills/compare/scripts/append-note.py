#!/usr/bin/env python3
"""Append one comparison note atomically with respect to cooperating writers (Linux)."""
import argparse
import fcntl
import os
from pathlib import Path
import re

DEFAULT_CORPUS = Path('/home/dyens/models-comapre.md')


def append_note(corpus, key, note):
    if not re.fullmatch(r'[0-9a-f]{64}', key):
        raise ValueError('case key must be a lowercase SHA-256 hex digest')
    marker = f'<!-- compare-key: {key} -->'
    if not note.strip() or marker not in note:
        raise ValueError('note must contain its compare-key marker')
    # Create privately, preserving permissions on an existing corpus.
    fd = os.open(corpus, os.O_RDWR | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, 'a+', encoding='utf-8') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        stream.seek(0)
        previous = stream.read()
        if marker in previous:
            return False
        stream.seek(0, os.SEEK_END)
        prefix = '# Сравнения моделей — корпус наблюдений\n' if not previous else ''
        stream.write(prefix + '\n\n' + note.strip() + '\n')
        stream.flush()
        os.fsync(stream.fileno())
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path, default=DEFAULT_CORPUS)
    parser.add_argument('--key', required=True)
    parser.add_argument('note', type=Path, help='UTF-8 Markdown note, already redacted')
    args = parser.parse_args()
    print('appended' if append_note(args.corpus, args.key, args.note.read_text(encoding='utf-8'))
          else 'already recorded')


if __name__ == '__main__':
    main()
