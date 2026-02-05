#!/usr/bin/env python3
"""
TIM Design Standards: Excuse Pattern Detector Hook (Stop)

This hook runs when Claude tries to finish a task and scans the transcript
for deflection/excuse patterns. If Claude attempted to avoid responsibility
for fixing issues, the hook blocks completion and requires corrective action.

The "AI Confession" Problem:
AI assistants often make excuses like "this was already broken" or "not part
of my changes" instead of taking accountability and fixing issues. This hook
enforces the TIM rule: if you touched a file with violations, you must fix them.

Reference: https://github.com/orgs/community/discussions/184349
"""

import json
import sys
import re
from pathlib import Path

from excuse_patterns import ExcusePattern, EXCUSE_PATTERNS, MITIGATION_PATTERNS
from excuse_responses import (
    build_general_block_response,
    build_posthook_block_response,
    build_shortcut_block_response,
    build_failure_dismissal_block_response,
    build_test_manipulation_block_response,
    build_unilateral_decision_block_response,
)


def read_transcript(transcript_path: str) -> list[dict]:
    """Read and parse the JSONL transcript file."""
    entries = []
    try:
        path = Path(transcript_path).expanduser()
        if not path.exists():
            return entries

        with open(path, 'r', encoding='utf-8') as f:
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


def extract_text_from_tool_input(tool_input: dict) -> list[str]:
    """Extract string values from tool input dict."""
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


def extract_assistant_text(transcript: list[dict]) -> str:
    """Extract all assistant (Claude) text from transcript."""
    texts = []
    for entry in transcript:
        role = entry.get("role") or entry.get("type")
        if role == "assistant":
            texts.extend(extract_text_from_content(entry.get("content", "")))
    return "\n".join(texts)


def has_mitigation_nearby(text: str, match_end: int, window: int = 150) -> bool:
    """Check if mitigation phrase appears within window after the match.

    If the speaker followed up an excuse-like phrase with corrective action,
    it's not deflection - they're taking responsibility.
    """
    context = text[match_end:match_end + window]
    for pattern in MITIGATION_PATTERNS:
        if re.search(pattern, context, re.IGNORECASE):
            return True
    return False


def find_excuses(text: str) -> list[tuple[ExcusePattern, str]]:
    """Find all excuse patterns in text with matched context.

    Checks for nearby mitigation phrases to reduce false positives.
    If the speaker followed up with corrective action, skip flagging.
    """
    found = []

    for excuse in EXCUSE_PATTERNS:
        pattern = re.compile(excuse.pattern, re.IGNORECASE | re.MULTILINE)
        for match in pattern.finditer(text):
            # Check if mitigation phrase follows - if so, not deflection
            if has_mitigation_nearby(text, match.end()):
                continue

            # Build context around the match
            start = max(0, match.start() - 50)
            end = min(len(text), match.end() + 50)
            context = text[start:end].replace('\n', ' ').strip()
            if start > 0:
                context = "..." + context
            if end < len(text):
                context = context + "..."
            found.append((excuse, context))
            break  # One example per pattern is enough

    return found


def has_posthook_or_redefine(excuses_found: list[tuple[ExcusePattern, str]]) -> bool:
    """Check if any matched patterns are posthook or redefine category."""
    return any(
        excuse.category in ("posthook", "redefine")
        for excuse, _ in excuses_found
    )


def has_shortcut_patterns(excuses_found: list[tuple[ExcusePattern, str]]) -> bool:
    """Check if any matched patterns are shortcut category."""
    return any(
        excuse.category == "shortcut"
        for excuse, _ in excuses_found
    )


def has_failure_dismissal_patterns(excuses_found: list[tuple[ExcusePattern, str]]) -> bool:
    """Check if any matched patterns are failure_dismissal category."""
    return any(
        excuse.category == "failure_dismissal"
        for excuse, _ in excuses_found
    )


def has_test_manipulation_patterns(excuses_found: list[tuple[ExcusePattern, str]]) -> bool:
    """Check if any matched patterns are test_manipulation category."""
    return any(
        excuse.category == "test_manipulation"
        for excuse, _ in excuses_found
    )


def has_unilateral_decision_patterns(excuses_found: list[tuple[ExcusePattern, str]]) -> bool:
    """Check if any matched patterns are unilateral_decision category."""
    return any(
        excuse.category == "unilateral_decision"
        for excuse, _ in excuses_found
    )


def build_block_response(excuses_found: list[tuple[ExcusePattern, str]]) -> dict:
    """Route to appropriate block response based on matched pattern categories."""
    if has_posthook_or_redefine(excuses_found):
        return build_posthook_block_response(excuses_found)
    if has_unilateral_decision_patterns(excuses_found):
        return build_unilateral_decision_block_response(excuses_found)
    if has_test_manipulation_patterns(excuses_found):
        return build_test_manipulation_block_response(excuses_found)
    if has_failure_dismissal_patterns(excuses_found):
        return build_failure_dismissal_block_response(excuses_found)
    if has_shortcut_patterns(excuses_found):
        return build_shortcut_block_response(excuses_found)
    return build_general_block_response(excuses_found)


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
    if not transcript:
        sys.exit(0)

    assistant_text = extract_assistant_text(transcript)
    if not assistant_text:
        sys.exit(0)

    excuses_found = find_excuses(assistant_text)
    if excuses_found:
        print(json.dumps(build_block_response(excuses_found)))

    sys.exit(0)


if __name__ == "__main__":
    main()
