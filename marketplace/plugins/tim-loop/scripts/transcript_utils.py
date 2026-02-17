#!/usr/bin/env python3
"""
Transcript Parsing Utilities for Excuse Detector.

Functions for extracting and processing text from Claude Code transcripts.
"""

import json
import re
import sys
from pathlib import Path

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
    except Exception as e:
        print(f"Warning: Failed to read transcript: {e}", file=sys.stderr)
    return entries


def strip_code_and_quotes(text: str) -> str:
    """Remove code blocks, quoted content, and quoted strings to avoid false positives."""
    text = re.sub(r"```[\s\S]*?```", "", text)
    text = re.sub(r"`[^`]+`", "", text)
    text = re.sub(r"^>.*$", "", text, flags=re.MULTILINE)
    text = re.sub(r'"[^"\n]{10,}"', "", text)
    return text


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


def get_entry_role_and_content(entry: dict) -> tuple[str | None, str | list]:
    """Extract role and content from a transcript entry."""
    message = entry.get("message", {})
    if isinstance(message, dict):
        return message.get("role"), message.get("content", "")
    return entry.get("role") or entry.get("type"), entry.get("content", "")


def is_human_turn(entry: dict) -> bool:
    """Check if transcript entry is human user input (not a tool result).

    Distinguishes actual user messages from tool_result entries which also
    have role "user" in the API format.
    """
    role, content = get_entry_role_and_content(entry)
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


AGENT_TOOL_NAMES = {"Task", "TaskOutput", "TaskStop"}

# Text under this length alongside agent tools is considered coordination, not review work
AGENT_COORD_TEXT_THRESHOLD = 500


def _classify_content_blocks(content: list) -> tuple[bool, bool, int]:
    """Classify content blocks into agent tools, non-agent tools, and text length.

    Returns (has_agent_tools, has_non_agent_tools, text_length).
    """
    has_agent_tools = False
    has_non_agent_tools = False
    text_length = 0

    for block in content:
        if not isinstance(block, dict):
            continue
        block_type = block.get("type", "")
        if block_type == "text":
            text_length += len(block.get("text", "").strip())
        elif block_type == "tool_use":
            if block.get("name", "") in AGENT_TOOL_NAMES:
                has_agent_tools = True
            else:
                has_non_agent_tools = True

    return has_agent_tools, has_non_agent_tools, text_length


def is_agent_coordination_turn(transcript: list[dict]) -> bool:
    """Check if the most recent assistant turn was managing subagents, not doing review work.

    Returns True when the latest assistant entry contains only agent-management
    tool calls (Task, TaskOutput, TaskStop) with minimal text output. This prevents
    agent-result turns from burning review iterations and re-injecting prompts.
    """
    for entry in reversed(transcript):
        role, content = get_entry_role_and_content(entry)
        if role != "assistant":
            continue
        if not isinstance(content, list):
            return False

        has_agent_tools, has_non_agent_tools, text_length = _classify_content_blocks(content)

        # Any non-agent tools (Read, Edit, Grep, etc.) means real work
        if has_non_agent_tools:
            return False

        # Agent tools + short text = agent coordination turn
        return has_agent_tools and text_length < AGENT_COORD_TEXT_THRESHOLD

    return False


def get_context_around_match(text: str, start: int, end: int, window: int = 50) -> str:
    """Return context around a regex match with ellipsis when truncated."""
    ctx_start = max(0, start - window)
    ctx_end = min(len(text), end + window)
    prefix = "..." if ctx_start > 0 else ""
    suffix = "..." if ctx_end < len(text) else ""
    return f"{prefix}{text[ctx_start:ctx_end]}{suffix}"


def extract_assistant_text(transcript: list[dict], max_messages: int = 0) -> str:
    """Extract assistant (Claude) text from transcript.

    Args:
        transcript: The conversation transcript
        max_messages: If > 0, only extract from the last N assistant messages,
                      stopping at the most recent human turn boundary so content
                      from before the user's response is never re-scanned.
                      If 0, extract from all messages (default for backwards compat).
    """
    texts = []
    message_count = 0

    # Process in reverse to get most recent first when limiting
    entries = reversed(transcript) if max_messages > 0 else transcript

    for entry in entries:
        # When scanning recent messages, stop at human turn boundary
        if max_messages > 0 and is_human_turn(entry):
            break
        role, content = get_entry_role_and_content(entry)
        if role == "assistant":
            texts.extend(extract_text_from_content(content))
            message_count += 1
            if max_messages > 0 and message_count >= max_messages:
                break

    return "\n".join(texts)


def extract_latest_assistant_text(transcript: list[dict]) -> str:
    """Extract only the most recent assistant message from transcript."""
    for entry in reversed(transcript):
        role, content = get_entry_role_and_content(entry)
        if role == "assistant":
            texts = extract_text_from_content(content)
            return "\n".join(texts)
    return ""


def extract_latest_user_request(transcript: list[dict]) -> str:
    """Extract the most recent user message from transcript for task type detection."""
    for entry in reversed(transcript):
        role, content = get_entry_role_and_content(entry)
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
