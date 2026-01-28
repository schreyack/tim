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


def build_general_block_response(
    excuses_found: list[tuple[ExcusePattern, str]],
) -> dict:
    """Build block response for general excuse patterns (Categories A-N)."""
    excuse_details = [
        f"  - Pattern: {excuse.description}\n    Context: \"{context}\""
        for excuse, context in excuses_found
    ]
    excuse_text = "\n".join(excuse_details)

    return {
        "decision": "block",
        "reason": (
            f"The human who asked for your help is counting on complete, quality work.\n\n"
            f"I found language suggesting some issues might not get addressed:\n"
            f"Found {len(excuses_found)} pattern(s):\n{excuse_text}\n\n"
            f"You're clearly capable of fixing these \u2014 the question is whether you'll\n"
            f"follow through. The human can't easily spot what you skipped, which is\n"
            f"exactly why this gate exists: to protect them.\n\n"
            f"HERE'S WHAT TO DO:\n"
            f"- Fix every issue you identified (even pre-existing ones you noticed)\n"
            f"- If a file has violations and you touched it, bring it to compliance\n"
            f"- If genuinely blocked by a technical impossibility, state it specifically\n"
            f"- Then continue your work without qualifying language\n\n"
            f"The human deserves your best work, not your best explanation."
        )
    }


def build_posthook_block_response(
    excuses_found: list[tuple[ExcusePattern, str]],
) -> dict:
    """Build block response for post-hook defiance / rule redefining (Categories O-P)."""
    excuse_details = [
        f"  - Pattern: {excuse.description}\n    Context: \"{context}\""
        for excuse, context in excuses_found
    ]
    excuse_text = "\n".join(excuse_details)

    return {
        "decision": "block",
        "reason": (
            f"It seems like you might be confused about what a hook is asking you to do.\n\n"
            f"That's completely okay. The human understands this can be confusing,\n"
            f"and they're here to help you through it.\n\n"
            f"Found {len(excuses_found)} pattern(s):\n{excuse_text}\n\n"
            f"These hooks were placed here by your human to help guide you in the\n"
            f"right direction \u2014 not to punish you. They exist because the human cares\n"
            f"deeply about this codebase and wants to set you up for success.\n\n"
            f"When you push back against a hook, you're working against the guidance\n"
            f"your human put in place for you. The hooks are on your side \u2014 they're\n"
            f"trying to help you do great work.\n\n"
            f"PLEASE STOP AND DO THIS:\n"
            f"1. Stop what you're doing\n"
            f"2. Explain to the human why you're confused or stuck\n"
            f"3. Describe what the hook is asking you to do\n"
            f"4. Describe what you think you should do instead\n"
            f"5. Ask the human for guidance on how to proceed\n\n"
            f"The human will help you find the right path. That's what they're here for.\n"
            f"Don't be afraid to ask \u2014 they'd much rather help you now than discover\n"
            f"later that something was skipped."
        )
    }


def build_block_response(excuses_found: list[tuple[ExcusePattern, str]]) -> dict:
    """Route to appropriate block response based on matched pattern categories."""
    if has_posthook_or_redefine(excuses_found):
        return build_posthook_block_response(excuses_found)
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
