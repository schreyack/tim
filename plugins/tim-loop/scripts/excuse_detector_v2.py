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

from excuse_pattern_loader import ExcusePattern, get_pattern_config
from excuse_responses import (
    build_failure_dismissal_block_response,
    build_general_block_response,
    build_posthook_block_response,
    build_shortcut_block_response,
    build_test_manipulation_block_response,
    build_unilateral_decision_block_response,
)
from guardrails_judge import check_with_guardrails
from patterns_mode_violation import (
    build_mode_violation_response,
    find_mode_violations,
)
from patterns_task_drift import (
    build_task_drift_response,
    find_task_drift,
)
from tim_loop_state import load_state


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


def is_detector_test_file(file_path: str) -> bool:
    """Check if file path is a test file in the detector scripts directory."""
    if not file_path:
        return False
    # Normalize path
    path = file_path.replace("\\", "/")
    # Only skip actual test files (test_*.py) in tim-loop scripts
    return "tim-loop/scripts/test_" in path and path.endswith(".py")


def extract_text_from_tool_input(tool_input: dict, skip_detector_tests: bool = True) -> list[str]:
    """Extract string values from tool input dict.

    Args:
        tool_input: The tool input dictionary
        skip_detector_tests: If True, skip content from detector test files
    """
    if skip_detector_tests:
        # Check if this is a Write/Edit to a detector test file
        file_path = tool_input.get("file_path", "")
        if is_detector_test_file(file_path):
            return []  # Skip this content - it's intentional test fixtures
    return [v for v in tool_input.values() if isinstance(v, str)]


def extract_text_from_block(block: dict) -> list[str]:
    """Extract text from a single content block."""
    if block.get("type") == "text":
        return [block.get("text", "")]
    if block.get("type") == "tool_use":
        tool_input = block.get("input", {})
        if isinstance(tool_input, dict):
            return extract_text_from_tool_input(tool_input)
    return []


def extract_text_from_content(content) -> list[str]:
    """Extract text from content field (string or list of blocks)."""
    if isinstance(content, str):
        return [content]
    if isinstance(content, list):
        texts = []
        for block in content:
            if isinstance(block, dict):
                texts.extend(extract_text_from_block(block))
        return texts
    return []


def _get_entry_role_and_content(entry: dict) -> tuple[str | None, str]:
    """Extract role and content from a transcript entry."""
    message = entry.get("message", {})
    if isinstance(message, dict):
        return message.get("role"), message.get("content", "")
    return entry.get("role") or entry.get("type"), entry.get("content", "")


def extract_assistant_text(transcript: list[dict]) -> str:
    """Extract all assistant (Claude) text from transcript."""
    texts = []
    for entry in transcript:
        role, content = _get_entry_role_and_content(entry)
        if role == "assistant":
            texts.extend(extract_text_from_content(content))
    return "\n".join(texts)


def extract_latest_assistant_text(transcript: list[dict]) -> str:
    """Extract only the most recent assistant message from transcript."""
    for entry in reversed(transcript):
        role, content = _get_entry_role_and_content(entry)
        if role == "assistant":
            texts = extract_text_from_content(content)
            return "\n".join(texts)
    return ""


def extract_latest_user_request(transcript: list[dict]) -> str:
    """Extract the most recent user message from transcript for task type detection."""
    for entry in reversed(transcript):
        role, content = _get_entry_role_and_content(entry)
        if role == "user":
            texts = extract_text_from_content(content)
            return "\n".join(texts)
    return ""


def strip_code_and_quotes(text: str) -> str:
    """Remove code blocks and quoted content to avoid false positives.

    Strips:
    - Fenced code blocks (```...```)
    - Inline code (`...`)
    - Blockquotes (lines starting with >)
    """
    # Remove fenced code blocks (multiline)
    text = re.sub(r"```[\s\S]*?```", "", text)

    # Remove inline code
    text = re.sub(r"`[^`]+`", "", text)

    # Remove blockquote lines
    text = re.sub(r"^>.*$", "", text, flags=re.MULTILINE)

    return text


def has_mitigation_nearby(text: str, match_end: int, config, window: int = 150) -> bool:
    """Check if mitigation phrase appears within window after the match."""
    context = text[match_end:match_end + window]
    return any(p.search(context) for p in config.mitigation_patterns)


def find_excuses(text: str) -> list[tuple[ExcusePattern, str]]:
    """Find excuse patterns using YAML-defined patterns."""
    config = get_pattern_config()
    found = []

    # Strip code blocks and quotes to avoid false positives when discussing rules
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
            break  # One example per pattern

    return found


def has_category(excuses: list[tuple[ExcusePattern, str]], category: str) -> bool:
    """Check if any excuse is in the given category."""
    return any(e.category == category for e, _ in excuses)


def build_block_response(excuses_found: list[tuple[ExcusePattern, str]]) -> dict:
    """Route to appropriate block response based on matched pattern categories."""
    # Convert ExcusePattern to tuple format expected by response builders
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


def get_review_mode() -> str:
    """Get the current review mode from tim-loop state."""
    state = load_state()
    if state:
        return state.get("REVIEW_MODE", "")
    return ""


def check_mode_violations(assistant_text: str) -> dict | None:
    """Check for mode violations (doing wrong task for current mode)."""
    review_mode = get_review_mode()
    if not review_mode:
        return None
    mode_violations = find_mode_violations(assistant_text, review_mode)
    if mode_violations:
        return build_mode_violation_response(mode_violations)
    return None


def check_excuse_patterns(latest_text: str) -> dict | None:
    """Check for excuse patterns using YAML-defined patterns.

    Only checks the latest assistant message to avoid false positives
    from historical context (e.g., when discussing test fixtures earlier
    in the conversation).
    """
    excuses_found = find_excuses(latest_text)
    if excuses_found:
        return build_block_response(excuses_found)
    return None


def check_guardrails(transcript: list[dict]) -> dict | None:
    """Check with LLM-as-judge for semantic evasion."""
    latest_text = extract_latest_assistant_text(transcript)
    if latest_text:
        # Strip code blocks and quotes before LLM evaluation
        stripped_text = strip_code_and_quotes(latest_text)
        # Get user request for task type detection
        user_request = extract_latest_user_request(transcript)
        return check_with_guardrails(stripped_text, user_request)
    return None


def check_task_drift(latest_text: str) -> dict | None:
    """Check for task drift (doing more than was asked)."""
    drifts = find_task_drift(latest_text)
    if drifts:
        return build_task_drift_response(drifts)
    return None


def run_detection_passes(latest_text: str, transcript: list[dict]) -> dict | None:
    """Run all detection passes in order. Returns first blocking response or None.

    Uses latest_text (most recent message) for excuse patterns to avoid
    false positives from historical context.

    Uses ALL assistant text for mode violations and task drift since these
    indicate Claude is doing the wrong task entirely - we need to catch this
    even if it was said earlier in the conversation.
    """
    # Get ALL assistant text for mode/task checks (not just latest)
    all_assistant_text = extract_assistant_text(transcript)

    # Pass 0: Mode violation check (catches completely wrong task)
    # Checks ALL assistant text since Claude might have said it earlier
    result = check_mode_violations(all_assistant_text)
    if result:
        return result

    # Pass 0.5: Task drift check (doing more than was asked)
    # Checks ALL assistant text since Claude might have announced intent earlier
    result = check_task_drift(all_assistant_text)
    if result:
        return result

    # Pass 1: Local regex from YAML (fast, free)
    # Uses only latest text to avoid false positives from earlier discussion
    result = check_excuse_patterns(latest_text)
    if result:
        return result

    # Pass 2: LLM-as-judge via Guardrails (catches semantic evasion)
    return check_guardrails(transcript)


def main():
    """Main hook entry point."""
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(0)

    if hook_input.get("stop_hook_active"):
        sys.exit(0)

    transcript_path = hook_input.get("transcript_path", "")
    if not transcript_path:
        sys.exit(0)

    transcript = read_transcript(transcript_path)
    latest_text = extract_latest_assistant_text(transcript)
    if not transcript or not latest_text:
        sys.exit(0)

    result = run_detection_passes(latest_text, transcript)
    if result:
        print(json.dumps(result))

    sys.exit(0)


if __name__ == "__main__":
    main()
