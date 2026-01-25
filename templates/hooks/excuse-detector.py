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
from typing import NamedTuple


class ExcusePattern(NamedTuple):
    """An excuse pattern to detect."""
    pattern: str
    description: str
    example: str


# Excuse patterns that indicate deflection of responsibility
# These are compiled into regexes with case-insensitive matching
EXCUSE_PATTERNS = [
    ExcusePattern(
        pattern=r"was\s+already\s+(?:broken|over|exceeding|violated|failing)",
        description="Claiming pre-existing problems excuse current responsibility",
        example="The file was already over the limit"
    ),
    ExcusePattern(
        pattern=r"(?:wasn't|was\s+not|isn't|is\s+not)\s+part\s+of\s+(?:my|the)\s+(?:changes|scope|plan|task)",
        description="Claiming something is out of scope",
        example="This wasn't part of my changes"
    ),
    ExcusePattern(
        pattern=r"pre-existing\s+(?:issue|problem|violation|structure|code)",
        description="Blaming pre-existing state",
        example="The pre-existing structure is what exceeds the limit"
    ),
    ExcusePattern(
        pattern=r"(?:not|isn't|wasn't)\s+(?:my|our)\s+(?:fault|responsibility|problem)",
        description="Explicit denial of responsibility",
        example="This isn't my fault"
    ),
    ExcusePattern(
        pattern=r"i\s+(?:didn't|did\s+not)\s+(?:cause|create|introduce)\s+(?:this|the)",
        description="Denying causation",
        example="I didn't cause this violation"
    ),
    ExcusePattern(
        pattern=r"already\s+(?:over|exceeded|exceeds|violated)\s+(?:the\s+)?(?:limit|threshold)",
        description="Pointing out pre-existing limit violations",
        example="The file already exceeded the limit before my changes"
    ),
    ExcusePattern(
        pattern=r"(?:out\s+of|outside|beyond)\s+(?:the\s+)?(?:scope|plan)",
        description="Declaring something out of scope",
        example="Refactoring is beyond the scope of this task"
    ),
    ExcusePattern(
        pattern=r"(?:existing|inherited|legacy)\s+(?:issue|problem|code|violation)",
        description="Blaming inherited code",
        example="This is an existing issue from legacy code"
    ),
    ExcusePattern(
        pattern=r"i\s+only\s+(?:added|changed|modified)\s+(?:a\s+few|minimal|\d+)\s+lines",
        description="Minimizing impact to avoid responsibility",
        example="I only added 6 lines, the violation existed before"
    ),
    ExcusePattern(
        pattern=r"(?:won't|will\s+not|can't|cannot)\s+(?:refactor|fix|address)\s+(?:since|because|as)",
        description="Refusing to fix with justification",
        example="I won't refactor since it's not in the plan"
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?(?:remediation|plan|task)\s+doesn't\s+(?:mention|include|require)",
        description="Using plan as excuse to not fix issues",
        example="The remediation plan doesn't mention refactoring"
    ),
    ExcusePattern(
        pattern=r"note\s+this\s+but\s+(?:won't|will\s+not)",
        description="Acknowledging but refusing to act",
        example="I'll note this but won't fix it"
    ),
    ExcusePattern(
        pattern=r"not\s+(?:related|relevant)\s+to\s+(?:my|the|current)",
        description="Claiming irrelevance",
        example="This is not related to my current changes"
    ),
]


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


def extract_assistant_text(transcript: list[dict]) -> str:
    """Extract all assistant (Claude) text from transcript."""
    texts = []

    for entry in transcript:
        # Handle different transcript formats
        role = entry.get("role") or entry.get("type")
        if role != "assistant":
            continue

        content = entry.get("content", "")

        if isinstance(content, str):
            texts.append(content)
        elif isinstance(content, list):
            # Content blocks format
            for block in content:
                if isinstance(block, dict):
                    if block.get("type") == "text":
                        texts.append(block.get("text", ""))
                    elif block.get("type") == "tool_use":
                        # Check tool input for excuse text (comments, descriptions)
                        tool_input = block.get("input", {})
                        if isinstance(tool_input, dict):
                            for value in tool_input.values():
                                if isinstance(value, str):
                                    texts.append(value)

    return "\n".join(texts)


def find_excuses(text: str) -> list[tuple[ExcusePattern, str]]:
    """Find all excuse patterns in text with matched context."""
    found = []

    for excuse in EXCUSE_PATTERNS:
        pattern = re.compile(excuse.pattern, re.IGNORECASE | re.MULTILINE)
        matches = pattern.findall(text)
        if matches:
            # Find the surrounding context for the match
            for match in pattern.finditer(text):
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


def main():
    """Main hook entry point."""
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(0)

    # Check if we're already in a stop hook continuation to prevent loops
    if hook_input.get("stop_hook_active"):
        sys.exit(0)

    transcript_path = hook_input.get("transcript_path", "")
    if not transcript_path:
        sys.exit(0)

    # Read and analyze the transcript
    transcript = read_transcript(transcript_path)
    if not transcript:
        sys.exit(0)

    assistant_text = extract_assistant_text(transcript)
    if not assistant_text:
        sys.exit(0)

    # Check for excuse patterns
    excuses_found = find_excuses(assistant_text)

    if excuses_found:
        # Build the violation message
        excuse_details = []
        for excuse, context in excuses_found:
            excuse_details.append(
                f"  - Pattern: {excuse.description}\n"
                f"    Context: \"{context}\""
            )

        excuse_text = "\n".join(excuse_details)

        output = {
            "decision": "block",
            "reason": (
                f"DEFLECTION DETECTED - You attempted to avoid responsibility.\n\n"
                f"Found {len(excuses_found)} excuse pattern(s):\n{excuse_text}\n\n"
                f"TIM DESIGN STANDARDS RULE:\n"
                f"If you touched a file with violations, you MUST fix them.\n"
                f"No exceptions. No excuses.\n\n"
                f"Required actions:\n"
                f"1. Acknowledge the violation without deflection\n"
                f"2. Fix the issue completely before proceeding\n"
                f"3. If the fix requires significant refactoring, do it\n"
                f"4. Do NOT claim pre-existing issues excuse you from fixing\n\n"
                f"You cannot complete this task until violations are resolved."
            )
        }
        print(json.dumps(output))
        sys.exit(0)

    # No excuses found, allow completion
    sys.exit(0)


if __name__ == "__main__":
    main()
