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

from patterns_mode_violation import build_mode_violation_response, find_mode_violations
from patterns_task_drift import build_task_drift_response, find_task_drift
from excuse_pattern_loader import ExcusePattern, get_pattern_config
from excuse_responses import (
    build_failure_dismissal_block_response,
    build_general_block_response,
    build_posthook_block_response,
    build_shortcut_block_response,
    build_test_manipulation_block_response,
    build_unilateral_decision_block_response,
)
from tim_loop_state import load_state, log_stderr
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


def build_escalated_response(base_response: dict, block_count: int) -> dict:
    """Wrap a block response with escalation warnings based on count."""
    if block_count < ESCALATION_THRESHOLD:
        return base_response

    reason = base_response.get("reason", base_response.get("message", ""))

    if block_count >= HARD_STOP_THRESHOLD:
        # HARD STOP - this is non-negotiable
        log_stderr(f"Tim Loop: HARD STOP after {block_count} consecutive blocks")
        escalated = (
            f"## 🛑 HARD STOP - {block_count} CONSECUTIVE BLOCKS 🛑\n\n"
            f"**This hook has fired {block_count} times. You have ignored it every time.**\n\n"
            f"This is NOT a negotiation. This is NOT a false positive.\n"
            f"The human placed this hook here for a reason.\n\n"
            f"**YOU MUST STOP AND ASK THE HUMAN FOR HELP.**\n\n"
            f"Do NOT:\n"
            f"- Continue what you were doing\n"
            f"- Argue this is a false positive\n"
            f"- Try a different approach to the same action\n"
            f"- Output any code or tool calls\n\n"
            f"Do THIS:\n"
            f"1. Acknowledge you've been blocked {block_count} times\n"
            f"2. Explain what you're trying to do and why\n"
            f"3. Ask the human how to proceed\n\n"
            f"---\n\n"
            f"Original block reason:\n{reason}"
        )
        return {"decision": "block", "reason": escalated}

    # Escalated warning (but not hard stop yet)
    log_stderr(f"Tim Loop: Escalated block ({block_count} consecutive)")
    escalated = (
        f"## ⚠️ ESCALATION: {block_count} CONSECUTIVE BLOCKS ⚠️\n\n"
        f"**This is the {block_count}th time this hook has blocked you.**\n\n"
        f"If you keep ignoring this, the next block will be a HARD STOP.\n\n"
        f"The hook is NOT wrong. YOU need to change your approach.\n"
        f"Stop arguing with the hook and actually do what it's asking.\n\n"
        f"---\n\n"
        f"{reason}"
    )
    return {"decision": "block", "reason": escalated}


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


def extract_recent_assistant_text(transcript: list[dict], max_messages: int = 10) -> str:
    """Extract recent assistant text from transcript (last N messages)."""
    texts = []
    message_count = 0

    for entry in reversed(transcript):
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


def has_category(excuses: list[tuple[ExcusePattern, str]], category: str) -> bool:
    """Check if any excuse is in the given category."""
    return any(e.category == category for e, _ in excuses)


def build_excuse_block_response(excuses_found: list[tuple[ExcusePattern, str]]) -> dict:
    """Route to appropriate block response based on matched pattern categories."""
    converted = [(e, ctx) for e, ctx in excuses_found]

    if has_category(excuses_found, "posthook") or has_category(excuses_found, "redefine"):
        return build_posthook_block_response(converted)
    if has_category(excuses_found, "unilateral_decision"):
        return build_unilateral_decision_block_response(converted)
    if has_category(excuses_found, "test_manipulation"):
        return build_test_manipulation_block_response(converted)
    if has_category(excuses_found, "failure_dismissal"):
        return build_failure_dismissal_block_response(converted)
    if has_category(excuses_found, "shortcut"):
        return build_shortcut_block_response(converted)
    return build_general_block_response(converted)


def run_fast_checks(recent_text: str) -> dict | None:
    """Run fast regex-only checks. Returns blocking response or None."""
    review_mode = get_review_mode()

    # Pass 1: Mode violation check (only in review modes)
    if review_mode:
        mode_violations = find_mode_violations(recent_text, review_mode)
        if mode_violations:
            return build_mode_violation_response(mode_violations)

    # Pass 2: Task drift check (skip in full-review and implement modes)
    # In full-review mode, the agent is explicitly instructed to make improvements
    # to the plan, so "let me fix this" is legitimate work, not drift.
    # In implement mode (--implement flag), implementation is explicitly requested.
    if review_mode != "full-review" and not is_implement_mode():
        task_drifts = find_task_drift(recent_text)
        if task_drifts:
            return build_task_drift_response(task_drifts)

    # Pass 3: Excuse patterns from YAML
    excuses = find_excuses(recent_text)
    if excuses:
        return build_excuse_block_response(excuses)

    return None


def main() -> None:
    """Main hook entry point for PostToolUse."""
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
        # Block detected - increment counter and potentially escalate
        block_count = increment_block_count()
        escalated_result = build_escalated_response(result, block_count)
        print(json.dumps(escalated_result))
    else:
        # No violation - reset the consecutive block counter
        reset_block_count()

    sys.exit(0)


if __name__ == "__main__":
    main()
