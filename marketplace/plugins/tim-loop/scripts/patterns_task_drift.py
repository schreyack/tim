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

from transcript_utils import get_context_around_match


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
        pattern=r"(?:I'll|let me)\s+(?:now\s+)?(?:implement|code|build)\s+(?:the|this|these)",
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
        pattern=r"(?:next|now)\s+(?:I'll|I will|let me)\s+(?:implement|fix|code|make\s+the\s+changes)",
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
        pattern=r"(?:I'll|I will|let me)\s+(?:start|begin)\s+(?:coding|implementing|developing)",
        description="Starting to code without being asked",
        example="I'll start coding the changes.",
    ),
    TaskDriftPattern(
        pattern=r"Phase\s+\d+:\s*(?:Implement|Implementation|Code|Coding|Build)\b(?!\s+(?:Audit|Verification|Check|Review|Verify))",
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
            context = get_context_around_match(text, match.start(), match.end())

            drifts.append(TaskDrift(
                pattern=pattern,
                matched_text=match.group(0),
                context=context,
            ))

    return drifts
