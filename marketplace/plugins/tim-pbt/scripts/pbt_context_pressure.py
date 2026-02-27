"""Context pressure tracking for PBT loop.

Monitors compaction count and response degradation to decide
how much context to re-inject when the stop hook blocks exit.

Pressure levels:
  NORMAL (0)     — full prompt re-injection
  WARNING (1)    — compact context only (~200 tokens remaining work)
  CRITICAL (2)   — minimal context (~30 tokens: "Continue PBT. X modules remain.")
  FORCE_STOP (3) — save state, allow exit, print resume instructions
"""

from __future__ import annotations

PRESSURE_NORMAL = 0
PRESSURE_WARNING = 1
PRESSURE_CRITICAL = 2
PRESSURE_FORCE_STOP = 3

# Minimum datapoints before degradation detection kicks in
MIN_RESPONSE_SAMPLES = 3
# Threshold: latest response < this fraction of prior average = degradation
DEGRADATION_THRESHOLD = 0.5


def get_context_pressure(state: dict) -> int:
    """Return current pressure level based on compaction count."""
    count = state.get("compaction_count", 0)
    if count >= 3:
        return PRESSURE_FORCE_STOP
    if count >= 2:
        return PRESSURE_CRITICAL
    if count >= 1:
        return PRESSURE_WARNING
    return PRESSURE_NORMAL


def increment_compaction_count(state: dict) -> int:
    """Increment and return the new compaction count."""
    count = state.get("compaction_count", 0) + 1
    state["compaction_count"] = count
    return count


def track_response_length(state: dict, text: str) -> None:
    """Store response length for degradation tracking."""
    lengths = state.get("response_lengths", [])
    lengths.append(len(text))
    # Keep last 10 samples
    state["response_lengths"] = lengths[-10:]


def detect_response_degradation(state: dict) -> bool:
    """Returns True if latest response is significantly shorter than average.

    Requires at least MIN_RESPONSE_SAMPLES datapoints.
    """
    lengths = state.get("response_lengths", [])
    if len(lengths) < MIN_RESPONSE_SAMPLES:
        return False

    latest = lengths[-1]
    prior = lengths[:-1]
    avg = sum(prior) / len(prior)

    if avg == 0:
        return False

    return latest < avg * DEGRADATION_THRESHOLD
