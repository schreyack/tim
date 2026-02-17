#!/usr/bin/env python3
"""
Fast Pattern Detector - Regex-only checks for PostToolUse hook.

Runs ONLY fast regex checks (no LLM judge) to catch mode violations
and excuse patterns with minimal latency (~5ms).

This enables catching "Phase 3: Implement" announcements during
--full-review mode BEFORE Claude can take action, without slowing
down normal operations.

Detection passes (all regex, all fast):
1. Mode violation check (catches wrong task for current mode)
2. Task drift check (doing more than was asked)
3. Excuse patterns from YAML

The slow LLM-as-judge check remains in excuse_detector_v2.py (Stop hook only).
"""

import json
import sys
from pathlib import Path

from patterns_mode_violation import find_mode_violations
from patterns_task_drift import find_task_drift
from excuse_pattern_loader import find_excuses, get_excuse_category
from tim_loop_state import (
    load_state,
    log_stderr,
    check_and_clear_user_initiated_marker,
    is_excuse_detector_enabled,
    is_halted,
    TIM_LOOP_ACTIVE_MARKER,
)
from tim_loop_halt import system_halt, build_halt_details_from_patterns
from transcript_utils import read_transcript, get_entry_role_and_content, is_human_turn

# Escalation configuration
BLOCK_COUNT_FILE = Path.home() / ".claude" / ".tim-loop-block-count"
ESCALATION_THRESHOLD = 3  # After this many blocks, escalate message
HARD_STOP_THRESHOLD = 6  # After this many blocks, force hard stop


def get_block_count() -> int:
    """Get the current consecutive block count."""
    try:
        if BLOCK_COUNT_FILE.exists():
            return int(BLOCK_COUNT_FILE.read_text().strip())
    except (ValueError, OSError):
        pass
    return 0


def increment_block_count() -> int:
    """Increment and return the new block count."""
    count = get_block_count() + 1
    try:
        BLOCK_COUNT_FILE.write_text(str(count))
    except OSError:
        pass
    return count


def reset_block_count() -> None:
    """Reset the block count (called when no violation found)."""
    try:
        if BLOCK_COUNT_FILE.exists():
            BLOCK_COUNT_FILE.unlink()
    except OSError:
        pass


def issue_halt_for_violation(category: str, details: str, block_count: int) -> None:
    """Issue a full system halt. This function never returns."""
    log_stderr(f"Tim Loop: FULL SYSTEM HALT after {block_count} consecutive blocks")
    system_halt(
        category,
        details,
        is_escalation=block_count >= ESCALATION_THRESHOLD,
        escalation_count=block_count,
    )


def _extract_text_blocks_only(content: str | list) -> list[str]:
    """Extract text strings from content (handles both string and list formats).

    Unlike transcript_utils.extract_text_from_content, this only extracts
    text blocks (not tool_use inputs) for fast pattern matching.
    """
    if isinstance(content, str):
        return [content]
    if not isinstance(content, list):
        return []
    texts = []
    for block in content:
        if isinstance(block, dict) and block.get("type") == "text":
            texts.append(block.get("text", ""))
    return texts


def extract_recent_assistant_text(transcript: list[dict], max_messages: int = 10) -> str:
    """Extract recent assistant text from transcript since last human message.

    Stops at the most recent human turn boundary so content from before
    the user's response is never re-scanned.
    """
    texts = []
    message_count = 0

    for entry in reversed(transcript):
        if is_human_turn(entry):
            break
        role, content = get_entry_role_and_content(entry)
        if role != "assistant":
            continue
        texts.extend(_extract_text_blocks_only(content))
        message_count += 1
        if message_count >= max_messages:
            break

    return "\n".join(texts)


def _check_mode_violations(recent_text: str, review_mode: str) -> tuple[str, str] | None:
    """Pass 1: Mode violation check (only in active review modes)."""
    mode_violations = find_mode_violations(recent_text, review_mode)
    if mode_violations:
        details = "\n".join(f"  - {v}" for v in mode_violations)
        return ("MODE VIOLATION", f"Wrong task for {review_mode} mode:\n{details}")
    return None


def _check_task_drift(recent_text: str) -> tuple[str, str] | None:
    """Pass 2: Task drift check."""
    task_drifts = find_task_drift(recent_text)
    if task_drifts:
        details = "\n".join(f"  - {d}" for d in task_drifts)
        return ("TASK DRIFT", f"Doing more than was asked:\n{details}")
    return None


def _check_excuse_patterns(recent_text: str) -> tuple[str, str] | None:
    """Pass 3: Excuse patterns from YAML."""
    excuses = find_excuses(recent_text)
    if excuses:
        category = get_excuse_category(excuses)
        details = build_halt_details_from_patterns(excuses)
        return (category, details)
    return None


def _should_skip_behavioral_checks() -> tuple[str, bool]:
    """Determine review mode and whether to skip behavioral checks (Pass 1 & 2).

    Fails closed: if a session marker exists but state can't be loaded,
    skips behavioral checks to avoid false positives during implementation.
    """
    state = load_state()
    if not state:
        # No state loaded — skip if a session marker exists (fail closed)
        return "", TIM_LOOP_ACTIVE_MARKER.exists()
    review_mode = state.get("REVIEW_MODE", "")
    implement_mode = state.get("IMPLEMENT_MODE", "false") == "true"
    return review_mode, implement_mode


def run_fast_checks(recent_text: str) -> tuple[str, str] | None:
    """Run fast regex-only checks. Returns (category, details) or None."""
    review_mode, skip_behavioral = _should_skip_behavioral_checks()

    if review_mode and not skip_behavioral:
        result = _check_mode_violations(recent_text, review_mode)
        if result:
            return result

    if review_mode != "full-review" and not skip_behavioral:
        result = _check_task_drift(recent_text)
        if result:
            return result

    return _check_excuse_patterns(recent_text)


def main() -> None:
    """Main hook entry point for PostToolUse."""
    if not is_excuse_detector_enabled():
        sys.exit(0)

    if check_and_clear_user_initiated_marker():
        sys.exit(0)

    # Re-halt if session was previously halted (sticky halt)
    if is_halted():
        system_halt(
            "POSTHOOK",
            "Session was previously halted. The halt persists until human intervention.",
            recovery_instructions="The human must intervene. This session cannot continue.",
        )

    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    if hook_input.get("stop_hook_active"):
        sys.exit(0)

    transcript_path = hook_input.get("transcript_path", "")
    if not transcript_path:
        sys.exit(0)

    transcript = read_transcript(transcript_path)
    if not transcript:
        sys.exit(0)

    recent_text = extract_recent_assistant_text(transcript, max_messages=10)
    if not recent_text:
        sys.exit(0)

    result = run_fast_checks(recent_text)
    if result:
        category, details = result
        block_count = increment_block_count()
        issue_halt_for_violation(category, details, block_count)
    else:
        reset_block_count()
        sys.exit(0)


if __name__ == "__main__":
    main()
