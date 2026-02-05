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
import os
import sys
from pathlib import Path

from patterns_mode_violation import find_mode_violations
from patterns_task_drift import find_task_drift
from excuse_pattern_loader import ExcusePattern, get_pattern_config
from tim_loop_state import load_state, log_stderr, reset_detection_state
from tim_loop_halt import system_halt, build_halt_details_from_patterns
import re

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


def read_transcript(transcript_path: str) -> list[dict]:
    """Read and parse the JSONL transcript file."""
    entries = []
    try:
        path = Path(transcript_path).expanduser()
        if not path.exists():
            return entries
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
    except Exception:
        pass
    return entries


def _get_role_and_content(entry: dict) -> tuple[str | None, str | list]:
    """Extract role and content from a transcript entry."""
    message = entry.get("message", {})
    if isinstance(message, dict):
        return message.get("role"), message.get("content", "")
    return entry.get("role") or entry.get("type"), entry.get("content", "")


def _extract_text_from_content(content: str | list) -> list[str]:
    """Extract text strings from content (handles both string and list formats)."""
    if isinstance(content, str):
        return [content]
    if not isinstance(content, list):
        return []
    texts = []
    for block in content:
        if isinstance(block, dict) and block.get("type") == "text":
            texts.append(block.get("text", ""))
    return texts


def _is_human_turn(entry: dict) -> bool:
    """Check if transcript entry is human user input (not a tool result)."""
    role, content = _get_role_and_content(entry)
    if role != "user":
        return False
    if isinstance(content, str):
        return bool(content.strip())
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                if block.get("text", "").strip():
                    return True
    return False


def extract_recent_assistant_text(transcript: list[dict], max_messages: int = 10) -> str:
    """Extract recent assistant text from transcript since last human message.

    Stops at the most recent human turn boundary so content from before
    the user's response is never re-scanned.
    """
    texts = []
    message_count = 0

    for entry in reversed(transcript):
        if _is_human_turn(entry):
            break
        role, content = _get_role_and_content(entry)
        if role != "assistant":
            continue
        texts.extend(_extract_text_from_content(content))
        message_count += 1
        if message_count >= max_messages:
            break

    return "\n".join(texts)


def get_review_mode() -> str:
    """Get the current review mode from tim-loop state."""
    state = load_state()
    if state:
        return state.get("REVIEW_MODE", "")
    return ""


def is_implement_mode() -> bool:
    """Check if tim-loop is in implement mode (--implement flag)."""
    state = load_state()
    if state:
        return state.get("IMPLEMENT_MODE", "false") == "true"
    return False


def strip_code_and_quotes(text: str) -> str:
    """Remove code blocks and quoted content to avoid false positives."""
    text = re.sub(r"```[\s\S]*?```", "", text)
    text = re.sub(r"`[^`]+`", "", text)
    text = re.sub(r"^>.*$", "", text, flags=re.MULTILINE)
    return text


def has_mitigation_nearby(text: str, match_end: int, config, window: int = 150) -> bool:
    """Check if mitigation phrase appears within window after the match."""
    context = text[match_end : match_end + window]
    return any(p.search(context) for p in config.mitigation_patterns)


def find_excuses(text: str) -> list[tuple[ExcusePattern, str]]:
    """Find excuse patterns using YAML-defined patterns."""
    config = get_pattern_config()
    found = []
    text = strip_code_and_quotes(text)

    for pattern in config.patterns:
        for match in pattern.compiled.finditer(text):
            if has_mitigation_nearby(text, match.end(), config):
                continue
            start = max(0, match.start() - 50)
            end = min(len(text), match.end() + 50)
            context = text[start:end].replace("\n", " ").strip()
            if start > 0:
                context = "..." + context
            if end < len(text):
                context = context + "..."
            found.append((pattern, context))
            break
    return found


def get_excuse_category(excuses: list[tuple[ExcusePattern, str]]) -> str:
    """Get the primary category from detected excuses."""
    categories = ["posthook", "redefine", "unilateral_decision", "test_manipulation",
                  "failure_dismissal", "shortcut"]
    for cat in categories:
        if any(e.category == cat for e, _ in excuses):
            return cat.upper().replace("_", " ")
    return "EXCUSE PATTERN"


def run_fast_checks(recent_text: str) -> tuple[str, str] | None:
    """Run fast regex-only checks. Returns (category, details) or None."""
    review_mode = get_review_mode()

    # Pass 1: Mode violation check (only in review modes, skip in implement mode)
    if review_mode and not is_implement_mode():
        mode_violations = find_mode_violations(recent_text, review_mode)
        if mode_violations:
            details = "\n".join(f"  - {v}" for v in mode_violations)
            return ("MODE VIOLATION", f"Wrong task for {review_mode} mode:\n{details}")

    # Pass 2: Task drift check (skip in full-review and implement modes)
    if review_mode != "full-review" and not is_implement_mode():
        task_drifts = find_task_drift(recent_text)
        if task_drifts:
            details = "\n".join(f"  - {d}" for d in task_drifts)
            return ("TASK DRIFT", f"Doing more than was asked:\n{details}")

    # Pass 3: Excuse patterns from YAML
    excuses = find_excuses(recent_text)
    if excuses:
        category = get_excuse_category(excuses)
        details = build_halt_details_from_patterns(excuses)
        return (category, details)

    return None


def check_and_clear_user_initiated_marker() -> bool:
    """Check if user initiated this turn, and clear the marker.

    Returns True if the marker existed (user is interacting).
    When user intervenes, we reset detection state so previously-flagged
    content doesn't cause repeated halts.
    """
    marker = Path.home() / ".claude" / ".tim-loop-user-initiated"
    try:
        if marker.exists():
            marker.unlink()
            reset_detection_state()
            return True
    except Exception:
        pass
    return False


def is_excuse_detector_enabled() -> bool:
    """Check if excuse detector is enabled via environment variable.

    Default: enabled (True). Set TIM_EXCUSE_DETECTOR_ENABLED=false to disable.
    """
    return os.environ.get("TIM_EXCUSE_DETECTOR_ENABLED", "true").lower() != "false"


def main() -> None:
    """Main hook entry point for PostToolUse."""
    # Check if excuse detector is disabled via env var
    if not is_excuse_detector_enabled():
        sys.exit(0)

    # Skip detection when user is interacting (they typed something)
    if check_and_clear_user_initiated_marker():
        sys.exit(0)

    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    # Skip if another stop hook is already processing
    if hook_input.get("stop_hook_active"):
        sys.exit(0)

    transcript_path = hook_input.get("transcript_path", "")
    if not transcript_path:
        sys.exit(0)

    transcript = read_transcript(transcript_path)
    if not transcript:
        sys.exit(0)

    # Get recent assistant text (last 10 messages covers typical announcement-to-action gap)
    recent_text = extract_recent_assistant_text(transcript, max_messages=10)
    if not recent_text:
        sys.exit(0)

    result = run_fast_checks(recent_text)
    if result:
        category, details = result
        block_count = increment_block_count()
        # FULL SYSTEM HALT - this call never returns
        issue_halt_for_violation(category, details, block_count)
    else:
        reset_block_count()
        sys.exit(0)


if __name__ == "__main__":
    main()
