#!/usr/bin/env python3
"""
Transcript Parsing Utilities for Excuse Detector.

Functions for extracting and processing text from Claude Code transcripts.
"""

import json
from pathlib import Path

from tim_loop_state import load_state


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


def extract_assistant_text(transcript: list[dict], max_messages: int = 0) -> str:
    """Extract assistant (Claude) text from transcript.

    Args:
        transcript: The conversation transcript
        max_messages: If > 0, only extract from the last N assistant messages.
                      If 0, extract from all messages (default for backwards compat).
    """
    texts = []
    message_count = 0

    # Process in reverse to get most recent first when limiting
    entries = reversed(transcript) if max_messages > 0 else transcript

    for entry in entries:
        role, content = _get_entry_role_and_content(entry)
        if role == "assistant":
            texts.extend(extract_text_from_content(content))
            message_count += 1
            if max_messages > 0 and message_count >= max_messages:
                break

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


def get_original_task_from_tim_loop() -> str:
    """Get the original task from tim-loop prompt file if active.

    When tim-loop is active, the prompt file contains the original task
    that was passed to tim-loop. This is more reliable than the latest
    user message which might just be "1" or a short reply.
    """
    state = load_state()
    if not state:
        return ""

    prompt_file = state.get("TIM_LOOP_PROMPT_FILE", "")
    if not prompt_file or not Path(prompt_file).exists():
        return ""

    try:
        with open(prompt_file, "r") as f:
            data = json.load(f)
            return data.get("prompt", "")
    except (json.JSONDecodeError, IOError):
        return ""
