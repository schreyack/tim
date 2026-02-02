#!/usr/bin/env python3
"""
TIM Excuse Pattern Detector v2 - YAML + Guardrails

Two-pass detection:
1. Fast local regex from YAML patterns (free, catches most cases)
2. LLM-as-judge via Guardrails (catches semantic evasion)

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


def has_mitigation_nearby(text: str, match_end: int, config, window: int = 150) -> bool:
    """Check if mitigation phrase appears within window after the match."""
    context = text[match_end:match_end + window]
    return any(p.search(context) for p in config.mitigation_patterns)


def find_excuses(text: str) -> list[tuple[ExcusePattern, str]]:
    """Find excuse patterns using YAML-defined patterns."""
    config = get_pattern_config()
    found = []

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

    # Pass 1: Local regex from YAML (fast, free) - check full transcript
    excuses_found = find_excuses(assistant_text)
    if excuses_found:
        print(json.dumps(build_block_response(excuses_found)))
        sys.exit(0)

    # Pass 2: LLM-as-judge via Guardrails (catches semantic evasion)
    # Only evaluate the latest response to avoid confusion from old context
    latest_text = extract_latest_assistant_text(transcript)
    if latest_text:
        guardrails_result = check_with_guardrails(latest_text)
        if guardrails_result:
            print(json.dumps(guardrails_result))
            sys.exit(0)

    # Clean - no issues detected
    sys.exit(0)


if __name__ == "__main__":
    main()
