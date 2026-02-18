#!/usr/bin/env python3
"""
Tim Loop Context Pressure Detection.

Detects context window exhaustion by tracking compaction count and response
degradation. Provides pressure levels that control how aggressively the
stop hook trims re-injected content.

Pressure levels:
- NORMAL (0 compactions): full prompt injection on first iteration
- WARNING (1 compaction): skip full prompt, use compact context only
- CRITICAL (2+ compactions): use minimal context (~30 tokens)
- FORCE_STOP (3+ compactions): graceful shutdown, no more iterations
"""

import re

# Pressure levels
PRESSURE_NORMAL = 0
PRESSURE_WARNING = 1
PRESSURE_CRITICAL = 2
PRESSURE_FORCE_STOP = 3

# State keys
_KEY_COMPACTION_COUNT = "COMPACTION_COUNT"
_KEY_RESPONSE_LENGTHS = "RESPONSE_LENGTHS"
_KEY_MAX_COMPACTIONS = "MAX_COMPACTIONS"

# Defaults
_DEFAULT_MAX_COMPACTIONS = 3
_MAX_TRACKED_LENGTHS = 5
_DEGRADATION_THRESHOLD = 0.5
_MIN_DATAPOINTS = 3


def get_context_pressure(state: dict) -> int:
    """Return the current pressure level based on compaction count."""
    count = int(state.get(_KEY_COMPACTION_COUNT, "0"))
    max_compactions = int(state.get(_KEY_MAX_COMPACTIONS, str(_DEFAULT_MAX_COMPACTIONS)))
    if count >= max_compactions:
        return PRESSURE_FORCE_STOP
    if count >= 2:
        return PRESSURE_CRITICAL
    if count >= 1:
        return PRESSURE_WARNING
    return PRESSURE_NORMAL


def increment_compaction_count(state: dict) -> int:
    """Increment compaction counter and return the new count."""
    count = int(state.get(_KEY_COMPACTION_COUNT, "0")) + 1
    state[_KEY_COMPACTION_COUNT] = str(count)
    return count


def track_response_length(state: dict, text: str) -> None:
    """Store the length of the latest response, keeping last N entries."""
    length = len(text.strip())
    existing = state.get(_KEY_RESPONSE_LENGTHS, "")
    lengths = [x for x in existing.split(",") if x.strip()]
    lengths.append(str(length))
    # Keep only the last N
    if len(lengths) > _MAX_TRACKED_LENGTHS:
        lengths = lengths[-_MAX_TRACKED_LENGTHS:]
    state[_KEY_RESPONSE_LENGTHS] = ",".join(lengths)


def detect_response_degradation(state: dict) -> bool:
    """Return True if latest response is <50% of prior average.

    Needs at least 3 data points to make a judgement. This catches the
    pattern where context exhaustion causes progressively shorter outputs.
    """
    raw = state.get(_KEY_RESPONSE_LENGTHS, "")
    parts = [x.strip() for x in raw.split(",") if x.strip()]
    if len(parts) < _MIN_DATAPOINTS:
        return False
    try:
        lengths = [int(x) for x in parts]
    except ValueError:
        return False
    latest = lengths[-1]
    prior = lengths[:-1]
    if not prior:
        return False
    avg = sum(prior) / len(prior)
    if avg == 0:
        return False
    return latest < avg * _DEGRADATION_THRESHOLD


_COMPLETION_PATTERNS = [
    r"implementation is complete",
    r"all objectives have been met",
    r"all tasks (?:are |have been )?completed",
    r"work is (?:now )?complete",
    r"everything (?:has been |is )implemented",
    r"all changes (?:are |have been )?made",
]

_COMPILED_PATTERNS = [re.compile(p, re.IGNORECASE) for p in _COMPLETION_PATTERNS]


def check_soft_completion(text: str, review_mode: str) -> bool:
    """Check if the conclusion suggests work is complete without the promise tag.

    Returns False for full-review mode (has its own phase signal system).
    Only examines the last 500 characters to focus on the conclusion.
    """
    if review_mode == "full-review":
        return False
    conclusion = text[-500:] if len(text) > 500 else text
    return any(p.search(conclusion) for p in _COMPILED_PATTERNS)
