#!/usr/bin/env python3
"""Read-only structural Pi JSONL summary. Never print message text or tool arguments."""
import argparse
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import sys

KNOWN_TOOLS = frozenset((
    'read', 'bash', 'edit', 'write', 'grep', 'find', 'ls', 'subagent',
    'subagents_enable', 'subagent_supervisor', 'bg_wait', 'ask_user_question',
    'plan_cycle_start', 'plan_cycle_next', 'ruclaw_next_cycle', 'runner_finish',
    'lsp_check', 'lsp_diagnostics', 'lsp_hover', 'lsp_definition', 'lsp_references',
    'lsp_symbols', 'mcp', 'web_enable', 'web_search', 'fetch_content',
))
USAGE_KEYS = ('input', 'cacheRead', 'cacheWrite', 'output', 'totalTokens')
COST_KEYS = ('input', 'cacheRead', 'cacheWrite', 'output', 'total')


def key(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()[:16]


def tool_name(value):
    if not isinstance(value, str):
        return 'unknown'
    return value if value in KNOWN_TOOLS else 'tool-' + key(value)


def number(value):
    return (type(value) is int and value >= 0) or (type(value) is float and math.isfinite(value) and value >= 0)


def sample(items, limit=20):
    if len(items) <= limit:
        return items
    return [items[0], *items[-(limit - 1):]]


def summarize(path):
    entries, roles, tools, results, errors, delegation = (Counter() for _ in range(6))
    tokens, costs = Counter(), Counter()
    reads = {}
    contexts, user_lines, snapshots = [], [], []
    usage_messages = cost_messages = lines = 0
    warnings = []
    digest = hashlib.sha256()
    with Path(path).expanduser().open('rb') as stream:
        before = os.fstat(stream.fileno())
        remaining = before.st_size
        while remaining:
            raw = stream.readline(remaining)
            if not raw:
                warnings.append('source_shortened_during_read')
                break
            remaining -= len(raw)
            lines += 1
            digest.update(raw)
            try:
                entry = json.loads(raw)
            except (ValueError, UnicodeError):
                if not remaining and not raw.endswith(b'\n'):
                    warnings.append('incomplete_tail_ignored')
                    break
                raise ValueError(f'Invalid JSONL at line {lines}') from None
            if not isinstance(entry, dict):
                raise ValueError(f'Expected object at line {lines}')
            kind = entry.get('type')
            entries[kind if kind in ('session', 'message', 'custom', 'custom_message',
                    'context_edit', 'compaction', 'branch_summary', 'model_change',
                    'thinking_level_change') else 'other'] += 1
            if kind == 'custom' and entry.get('customType') == 'plan-cycle-state-v2':
                data = entry.get('data')
                if isinstance(data, dict):
                    snapshot = data.get('snapshot')
                    plan = snapshot.get('plan') if isinstance(snapshot, dict) else None
                    snapshots.append({
                        'line': lines,
                        'cycle': data.get('cycle') if number(data.get('cycle')) else None,
                        'checkpoint_key': key(str(data.get('checkpointId', ''))),
                        'plan_key': key(str(data.get('planPath', ''))),
                        'plan_chars': len(plan) if isinstance(plan, str) else None,
                        'plan_lines': len(plan.splitlines()) if isinstance(plan, str) else None,
                    })
            message = entry.get('message') if kind == 'message' else None
            if not isinstance(message, dict):
                continue
            role = message.get('role')
            roles[role if role in ('user', 'assistant', 'toolResult', 'system') else 'other'] += 1
            if role == 'user':
                user_lines.append(lines)
            if role == 'toolResult':
                name = tool_name(message.get('toolName'))
                results[name] += 1
                if message.get('isError') is True:
                    errors[name] += 1
            usage = message.get('usage') if role == 'assistant' else None
            if isinstance(usage, dict) and any(number(usage.get(k)) for k in USAGE_KEYS):
                usage_messages += 1
                for name in USAGE_KEYS:
                    if number(usage.get(name)):
                        tokens[name] += usage[name]
                if all(number(usage.get(k)) for k in ('input', 'cacheRead', 'cacheWrite')):
                    contexts.append(sum(usage[k] for k in ('input', 'cacheRead', 'cacheWrite')))
            cost = usage.get('cost') if isinstance(usage, dict) else None
            if isinstance(cost, dict) and any(number(cost.get(k)) for k in COST_KEYS):
                cost_messages += 1
                for name in COST_KEYS:
                    if number(cost.get(name)):
                        costs[name] += cost[name]
            content = message.get('content')
            if role != 'assistant' or not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict) or block.get('type') != 'toolCall':
                    continue
                name = tool_name(block.get('name'))
                tools[name] += 1
                args = block.get('arguments')
                if not isinstance(args, dict):
                    continue
                if name == 'read' and isinstance(args.get('path'), str):
                    read = reads.setdefault(key(args['path']), {'count': 0, 'first_line': lines, 'last_line': lines})
                    read['count'] += 1
                    read['last_line'] = lines
                if name == 'subagent':
                    action = args.get('action')
                    if action == 'resume':
                        delegation['direct_resume'] += 1
                    elif action is not None:
                        delegation['management'] += 1
                    elif 'workflowScript' in args:
                        delegation['workflow_dispatch'] += 1
                    elif 'agent' in args:
                        delegation['direct_launch'] += 1
                    else:
                        delegation['other_dispatch'] += 1
        after = os.fstat(stream.fileno())
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            warnings.append('source_changed_during_read')
    if entries['other']:
        warnings.append('unrecognized_entry_types')
    if roles['other']:
        warnings.append('unrecognized_message_roles')
    if roles['assistant'] and not usage_messages:
        warnings.append('token_usage_unavailable')
    return {
        'scope': 'serialized entries in initial file-size snapshot; all branches, not projected model context',
        'snapshot': {'initial_bytes': before.st_size, 'lines_read': lines, 'sha256_read': digest.hexdigest()},
        'warnings': warnings,
        'entries': dict(entries), 'messages': dict(roles),
        'tool_calls': dict(tools), 'tool_results': dict(results), 'tool_error_results': dict(errors),
        'delegation_calls_not_reviewer_runs': dict(delegation),
        'usage': {'messages_with_usage': usage_messages, 'reported_tokens': dict(tokens),
                  'messages_with_cost': cost_messages, 'reported_cost': dict(costs),
                  'context_estimate_input_plus_cache': {
                      'samples': len(contexts), 'median': statistics.median(contexts) if contexts else None,
                      'max': max(contexts) if contexts else None}},
        'user_messages': {'count': len(user_lines), 'sample_lines': sample(user_lines)},
        'plan_snapshots': {'count': len(snapshots), 'samples': sample(snapshots)},
        'repeated_reads': [{'path_key': name, **data} for name, data in
                           sorted(reads.items(), key=lambda item: -item[1]['count'])[:15] if data['count'] > 1],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session', type=Path)
    args = parser.parse_args()
    try:
        result = summarize(args.session)
    except (OSError, ValueError) as error:
        # Do not echo paths, raw records or exception payloads from the transcript.
        reason = str(error) if isinstance(error, ValueError) else type(error).__name__
        print(f'Session summary failed: {reason}', file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
