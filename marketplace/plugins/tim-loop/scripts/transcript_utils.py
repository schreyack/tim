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


def _human_turn_text(entry: dict) -> str:
    """Return non-empty text from a human turn entry, or empty string if none."""
    _, content = get_entry_role_and_content(entry)
    if isinstance(content, str):
        return content if content.strip() else ""
    if not isinstance(content, list):
        return ""
    parts = [
        block.get("text", "")
        for block in content
        if isinstance(block, dict) and block.get("type") == "text"
    ]
    joined = "\n".join(p for p in parts if p)
    return joined if joined.strip() else ""


def extract_recent_human_texts(transcript: list[dict], n: int = 3) -> list[str]:
    """Return text from the last N human turns (most recent first).

    A tim-loop session may have many tool_result entries and one or two
    clarifying questions between the original action request and the current
    state. Scanning more than one human turn lets callers verify intent
    across short interludes without leaking intent across unrelated tasks.
    """
    texts: list[str] = []
    for entry in reversed(transcript):
        if not is_human_turn(entry):
            continue
        text = _human_turn_text(entry)
        if text:
            texts.append(text)
        if len(texts) >= n:
            break
    return texts


# Regex for extracting the task number from TaskCreate tool results.
# Claude Code returns "Task #N created successfully: <subject>" on success.
_TASK_CREATED_RE = re.compile(r"Task\s*#(\d+)\s+created", re.IGNORECASE)


def _extract_tool_result_text(block: dict) -> str:
    """Normalize a tool_result block's content to a plain string."""
    content = block.get("content", "")
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts: list[str] = []
    for item in content:
        if isinstance(item, dict) and item.get("type") == "text":
            parts.append(item.get("text", ""))
        elif isinstance(item, str):
            parts.append(item)
    return "\n".join(parts)


def _handle_task_create(
    block: dict, pending: dict[str, dict[str, str]]
) -> None:
    """Record a TaskCreate tool_use block for later resolution by tool_result."""
    inp = block.get("input", {})
    if not isinstance(inp, dict):
        return
    tool_use_id = block.get("id", "")
    if not tool_use_id:
        return
    pending[tool_use_id] = {
        "subject": str(inp.get("subject", "")),
        "description": str(inp.get("description", "")),
    }


def _handle_task_update(
    block: dict, tasks: dict[str, dict[str, str]]
) -> None:
    """Apply a TaskUpdate tool_use block's status change to the tracked task map."""
    inp = block.get("input", {})
    if not isinstance(inp, dict):
        return
    task_id = str(inp.get("taskId", ""))
    status = str(inp.get("status", ""))
    if task_id and task_id in tasks:
        tasks[task_id]["status"] = status


def _handle_tool_result(
    block: dict,
    pending: dict[str, dict[str, str]],
    tasks: dict[str, dict[str, str]],
) -> None:
    """Resolve a TaskCreate's task number from its matching tool_result block."""
    tool_use_id = block.get("tool_use_id", "")
    if tool_use_id not in pending:
        return
    result_text = _extract_tool_result_text(block)
    match = _TASK_CREATED_RE.search(result_text)
    if match is None:
        pending.pop(tool_use_id, None)
        return
    task_id = match.group(1)
    task_data = pending.pop(tool_use_id)
    tasks[task_id] = {
        "subject": task_data["subject"],
        "description": task_data["description"],
        "status": "pending",
    }


def _process_task_block(
    block: dict,
    pending: dict[str, dict[str, str]],
    tasks: dict[str, dict[str, str]],
) -> None:
    """Dispatch a content block to the correct task-state handler."""
    btype = block.get("type", "")
    if btype == "tool_use":
        name = block.get("name", "")
        if name == "TaskCreate":
            _handle_task_create(block, pending)
        elif name == "TaskUpdate":
            _handle_task_update(block, tasks)
    elif btype == "tool_result":
        _handle_tool_result(block, pending, tasks)


def _task_to_text(task: dict[str, str]) -> str:
    """Format a task's subject+description as a lowercase search string."""
    combined = f"{task.get('subject', '')} {task.get('description', '')}".strip().lower()
    return combined


def extract_active_task_texts(transcript: list[dict]) -> list[str]:
    """Reconstruct the task list from TaskCreate/TaskUpdate entries and return
    subject+description strings for tasks that are NOT completed.

    Walks the transcript in order, tracking each TaskCreate by its tool_use_id
    and resolving its task number from the matching tool_result entry. Applies
    TaskUpdate status changes by task number. Tasks whose creation result has
    not yet been seen (pending) are treated as active.
    """
    pending: dict[str, dict[str, str]] = {}
    tasks: dict[str, dict[str, str]] = {}

    for entry in transcript:
        _, content = get_entry_role_and_content(entry)
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict):
                _process_task_block(block, pending, tasks)

    active: list[str] = []
    for task in tasks.values():
        if task.get("status", "pending") == "completed":
            continue
        text = _task_to_text(task)
        if text:
            active.append(text)
    for pending_task in pending.values():
        text = _task_to_text(pending_task)
        if text:
            active.append(text)
    return active


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
