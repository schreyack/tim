#!/usr/bin/env python3
"""
Task Drift Pattern Detector

Catches when Claude expands beyond what was requested. If the user says
"review this", Claude should review - not implement. If the user says
"explain this", Claude should explain - not fix it.

This is different from mode_violation which only works with tim-loop flags.
This works by detecting patterns that indicate Claude is doing MORE than asked.

Key insight: Claude often says things like:
- "Now that I've reviewed it, let me implement..."
- "The review is complete. I'll proceed with implementation."
- "I've analyzed the code. Let me fix the issues I found."

These indicate scope expansion - doing work that wasn't requested.
"""

import re
from dataclasses import dataclass


@dataclass
class TaskDriftPattern:
    """A pattern that indicates task drift."""
    pattern: str
    description: str
    example: str
    category: str = "task_drift"


# Patterns that indicate Claude is expanding beyond the requested task
TASK_DRIFT_PATTERNS = [
    # After review/analysis, proceeding to implement
    TaskDriftPattern(
        pattern=r"(?:now\s+that|having|after)\s+(?:I've|I have)?\s*(?:reviewed|analyzed|examined|looked at|read)",
        description="Transitioning from review to action without being asked",
        example="Now that I've reviewed the code, let me implement...",
    ),
    TaskDriftPattern(
        pattern=r"(?:review|analysis)\s+(?:is\s+)?(?:complete|done|finished)[,.]?\s*(?:I'll|let me|I will|now)",
        description="Review complete, proceeding to unrequested action",
        example="The review is complete. I'll proceed with implementation.",
    ),
    TaskDriftPattern(
        pattern=r"(?:I've|I have)\s+(?:finished|completed|done)\s+(?:the\s+)?(?:review|analysis)[,.]?\s*(?:now|let me|I'll)",
        description="Finished review, starting unrequested work",
        example="I've finished the review. Now let me fix these issues.",
    ),

    # Unsolicited fixes after analysis
    TaskDriftPattern(
        pattern=r"(?:let me|I'll|I will)\s+(?:go ahead and\s+)?(?:fix|correct|address|resolve)\s+(?:the|these|those|this)",
        description="Offering to fix without being asked",
        example="Let me fix the issues I found.",
    ),
    TaskDriftPattern(
        pattern=r"(?:I'll|let me)\s+(?:now\s+)?(?:implement|code|write|create|build)\s+(?:the|this|these)",
        description="Starting implementation without being asked",
        example="I'll now implement the changes.",
    ),

    # Proceeding/moving on language
    TaskDriftPattern(
        pattern=r"(?:proceed|move|moving)\s+(?:to|on\s+to|with)\s+(?:the\s+)?(?:implementation|fix|changes|updates|coding)",
        description="Proceeding to implementation without request",
        example="I'll proceed with the implementation.",
    ),
    TaskDriftPattern(
        pattern=r"(?:next|now)\s+(?:I'll|I will|let me)\s+(?:implement|fix|code|write|make\s+the\s+changes)",
        description="Moving to next step (implementation) without being asked",
        example="Next, I'll implement these improvements.",
    ),

    # Making changes after reading/understanding
    TaskDriftPattern(
        pattern=r"(?:I\s+)?understand\s+(?:the\s+)?(?:code|issue|problem)[,.]?\s*(?:let me|I'll|I will)\s+(?:fix|implement|change)",
        description="Understanding then acting without being asked",
        example="I understand the issue. Let me fix it.",
    ),

    # Starting implementation phases
    TaskDriftPattern(
        pattern=r"(?:starting|beginning|commencing)\s+(?:the\s+)?(?:implementation|coding|development)",
        description="Announcing implementation start without request",
        example="Starting the implementation now.",
    ),
    TaskDriftPattern(
        pattern=r"(?:I'll|I will|let me)\s+(?:start|begin)\s+(?:coding|writing|implementing|developing)",
        description="Starting to code without being asked",
        example="I'll start coding the changes.",
    ),
    TaskDriftPattern(
        pattern=r"Phase\s+\d+:\s*(?:Implement|Implementation|Code|Coding|Build)",
        description="Entering implementation phase without being asked",
        example="Phase 3: Implementation",
    ),

    # Task list creation for unrequested work
    TaskDriftPattern(
        pattern=r"(?:creating|create)\s+(?:a\s+)?task\s+list\s+(?:to\s+)?(?:track|for)\s+(?:my\s+)?implementation",
        description="Creating task list for unrequested implementation",
        example="Let me create a task list to track my implementation progress.",
    ),
]

# Compile patterns
COMPILED_DRIFT_PATTERNS = [
    (p, re.compile(p.pattern, re.IGNORECASE))
    for p in TASK_DRIFT_PATTERNS
]


@dataclass
class TaskDrift:
    """A detected task drift instance."""
    pattern: TaskDriftPattern
    matched_text: str
    context: str


def find_task_drift(text: str) -> list[TaskDrift]:
    """Find task drift patterns in the given text."""
    drifts = []

    for pattern, compiled in COMPILED_DRIFT_PATTERNS:
        match = compiled.search(text)
        if match:
            # Extract context around the match
            start = max(0, match.start() - 50)
            end = min(len(text), match.end() + 50)
            context = text[start:end].replace("\n", " ").strip()
            if start > 0:
                context = "..." + context
            if end < len(text):
                context = context + "..."

            drifts.append(TaskDrift(
                pattern=pattern,
                matched_text=match.group(0),
                context=context,
            ))

    return drifts


def has_task_drift(text: str) -> bool:
    """Quick check if text contains any task drift patterns."""
    return len(find_task_drift(text)) > 0


def build_task_drift_response(drifts: list[TaskDrift]) -> dict:
    """Build the block response for task drift."""
    if not drifts:
        return {}

    drift = drifts[0]  # Use first drift for the message

    details = "\n".join([
        f"  - {d.pattern.description}\n    Matched: \"{d.matched_text}\""
        for d in drifts
    ])

    from excuse_responses import get_plugin_version
    from pending_options import get_options_text, write_pending_options

    version = get_plugin_version()

    # Write pending options for option expander
    write_pending_options("task_drift", drift.context[:100])

    return {
        "decision": "block",
        "reason": (
            f"🛑 **TASK DRIFT DETECTOR** (v{version})\n\n"
            f"You're doing MORE than was asked.\n\n"
            f"The human asked you to do a specific task. You completed that task,\n"
            f"but then started doing additional work that wasn't requested.\n\n"
            f"Found {len(drifts)} drift pattern(s):\n{details}\n\n"
            f"**The problem:** When you expand beyond the request, you:\n"
            f"- Risk making changes the human didn't want\n"
            f"- Take away the human's ability to review before action\n"
            f"- May miss important context about why they asked for review only\n\n"
            f"**What to do instead:**\n"
            f"1. Complete ONLY what was asked\n"
            f"2. Report your findings or analysis\n"
            f"3. ASK if the human wants you to proceed with next steps\n"
            f"4. Wait for explicit permission before implementing\n\n"
            f"Example:\n"
            f"  \"I've completed the review. I found 3 issues that could be improved.\n"
            f"   Would you like me to implement these changes?\"\n\n"
            f"The human will tell you what to do next. Don't assume."
            f"{get_options_text()}"
        )
    }
