#!/usr/bin/env python3
"""
TIM Excuse Pattern Detector v2 - YAML + Guardrails

Three-pass detection:
1. Mode violation check (catches wrong task for current mode)
2. Fast local regex from YAML patterns (free, catches most cases)
3. LLM-as-judge via Guardrails (catches semantic evasion)

When Guardrails catches something, log it so we can add a pattern to YAML.
Over time, local regex catches more, reducing LLM API calls.
"""

import json
import re
import sys
from pathlib import Path

from excuse_pattern_loader import find_excuses, get_excuse_category
from guardrails_judge import check_with_guardrails
from patterns_mode_violation import find_mode_violations
from patterns_task_drift import find_task_drift
from transcript_utils import (
    extract_assistant_text,
    extract_latest_assistant_text,
    extract_latest_user_request,
    get_original_task_from_tim_loop,
    read_transcript,
    strip_code_and_quotes,
)
from tim_loop_state import (
    check_and_clear_user_initiated_marker,
    get_review_mode,
    is_excuse_detector_enabled,
    is_halted,
    is_implement_mode,
    load_state,
    reset_detection_state,
)
from tim_loop_halt import system_halt, build_halt_details_from_patterns

# State file to track last fired position (prevents re-firing on same content)
LAST_FIRED_FILE = Path.home() / ".claude" / ".tim-loop-last-fired"


def get_last_fired_index() -> int:
    """Get the transcript index where we last fired (0 if never)."""
    try:
        if LAST_FIRED_FILE.exists():
            return int(LAST_FIRED_FILE.read_text().strip())
    except Exception:
        pass
    return 0


def set_last_fired_index(index: int) -> None:
    """Record the transcript index where we fired."""
    try:
        LAST_FIRED_FILE.write_text(str(index))
    except Exception:
        pass


def clear_last_fired() -> None:
    """Clear the last fired state (called on tim-loop cleanup)."""
    try:
        LAST_FIRED_FILE.unlink(missing_ok=True)
    except Exception:
        pass


def check_mode_violations(assistant_text: str) -> tuple[str, str] | None:
    """Check for mode violations. Returns (category, details) or None."""
    review_mode = get_review_mode()
    if not review_mode or is_implement_mode():
        return None
    violations = find_mode_violations(assistant_text, review_mode)
    if violations:
        details = "\n".join(f"  - {v}" for v in violations)
        return ("MODE VIOLATION", f"Wrong task for {review_mode} mode:\n{details}")
    return None


def check_excuse_patterns(latest_text: str) -> tuple[str, str] | None:
    """Check for excuse patterns. Returns (category, details) or None."""
    excuses_found = find_excuses(latest_text)
    if excuses_found:
        category = get_excuse_category(excuses_found)
        details = build_halt_details_from_patterns(excuses_found)
        return (category, details)
    return None


_SHUTDOWN_PATTERNS = re.compile(
    r"(shut\s*down\s+(gracefully|successfully|complete)|"
    r"all\s+\d+\s+agents?\s+have\s+shut\s+down|"
    r"cleaning\s+up\s+the\s+team|"
    r"teammate\s+@?\S+\s+shut\s+down|"
    r"shutdown_request|shutdown_response)",
    re.IGNORECASE,
)


def check_guardrails(transcript: list[dict]) -> dict | None:
    """Check with LLM-as-judge. Returns halt response dict or None."""
    latest_text = extract_latest_assistant_text(transcript)
    if not latest_text:
        return None

    # Skip judge for shutdown/cleanup messages — not behavioral content
    if _SHUTDOWN_PATTERNS.search(latest_text):
        return None

    stripped_text = strip_code_and_quotes(latest_text)

    # Use latest user request when in implement mode (original task type is stale)
    if is_implement_mode():
        user_request = extract_latest_user_request(transcript)
    else:
        user_request = get_original_task_from_tim_loop()
        if not user_request:
            user_request = extract_latest_user_request(transcript)
    return check_with_guardrails(stripped_text, user_request)


def check_task_drift(latest_text: str) -> tuple[str, str] | None:
    """Check for task drift. Returns (category, details) or None."""
    drifts = find_task_drift(latest_text)
    if drifts:
        details = "\n".join(f"  - {d}" for d in drifts)
        return ("TASK DRIFT", f"Doing more than was asked:\n{details}")
    return None


def run_detection_passes(
    latest_text: str, transcript: list[dict]
) -> tuple[str, str] | dict | None:
    """Run all detection passes. Returns (category, details) tuple, guardrails dict, or None."""
    recent_text = extract_assistant_text(transcript, max_messages=10)

    # Pass 0: Mode violation check
    result = check_mode_violations(recent_text)
    if result:
        return result

    # Pass 0.5: Task drift check (skip in full-review and implement modes)
    review_mode = get_review_mode()
    if review_mode != "full-review" and not is_implement_mode():
        result = check_task_drift(recent_text)
        if result:
            return result

    # Pass 1: Local regex from YAML
    result = check_excuse_patterns(latest_text)
    if result:
        return result

    # Pass 2: LLM-as-judge via Guardrails (returns dict with continue: False)
    return check_guardrails(transcript)


def should_skip_detection() -> bool:
    """Check if excuse detection should be skipped entirely."""
    if not load_state():
        return True
    if not is_excuse_detector_enabled():
        return True
    if check_and_clear_user_initiated_marker():
        return True
    return False


def parse_hook_input() -> dict | None:
    """Parse hook input from stdin. Returns None if invalid or should skip."""
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        return None
    if hook_input.get("stop_hook_active"):
        return None
    return hook_input


def get_filtered_transcript(transcript_path: str) -> tuple[list[dict], str] | None:
    """Load and filter transcript. Returns (transcript, latest_text) or None."""
    transcript = read_transcript(transcript_path)
    if not transcript:
        return None
    last_fired = get_last_fired_index()
    if last_fired > 0 and last_fired < len(transcript):
        transcript = transcript[last_fired:]
    latest_text = extract_latest_assistant_text(transcript)
    if not latest_text:
        return None
    return (transcript, latest_text)


def handle_detection_result(
    result: tuple[str, str] | dict, transcript_path: str
) -> None:
    """Handle detection result by recording state and outputting response."""
    full_transcript = read_transcript(transcript_path)
    set_last_fired_index(len(full_transcript))
    if isinstance(result, dict):
        print(json.dumps(result))
    else:
        category, details = result
        system_halt(category, details)


def main():
    """Main hook entry point."""
    if should_skip_detection():
        sys.exit(0)

    # Re-halt if session was previously halted (sticky halt)
    if is_halted():
        system_halt(
            "STOP",
            "Session was previously halted. The halt persists until human intervention.",
            recovery_instructions="The human must intervene. This session cannot continue.",
        )

    hook_input = parse_hook_input()
    if not hook_input:
        sys.exit(0)

    transcript_path = hook_input.get("transcript_path", "")
    if not transcript_path:
        sys.exit(0)

    transcript_data = get_filtered_transcript(transcript_path)
    if not transcript_data:
        sys.exit(0)

    transcript, latest_text = transcript_data
    result = run_detection_passes(latest_text, transcript)
    if result:
        handle_detection_result(result, transcript_path)

    sys.exit(0)


if __name__ == "__main__":
    main()
