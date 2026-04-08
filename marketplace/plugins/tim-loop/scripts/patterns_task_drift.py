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

# Action verbs used across drift patterns. Used by fast_pattern_detector to
# cross-reference drifts against the active task list: if a drift's verb
# appears in an in-progress/pending task subject, the assistant is executing
# planned work, not drifting.
DRIFT_ACTION_VERBS = frozenset(
    {
        "fix",
        "correct",
        "address",
        "resolve",
        "implement",
        "code",
        "build",
        "refactor",
        "rewrite",
    }
)

# Phrases that indicate the assistant is *discovering* work (not executing
# approved work). Used to gate generic "let me fix X" patterns so they only
# fire when drift context is present in the surrounding text.
DRIFT_CONTEXT_INDICATORS = re.compile(
    r"(?:\bI\s+(?:found|noticed|see|spotted|discovered|came\s+across)\b"
    r"|\bwhile\s+I(?:'m|\s+am)(?:\s+(?:here|at\s+it))?\b"
    r"|\bas\s+well\b"
    r"|\btoo\b"
    r"|\balso\b"
    r"|\badditionally\b"
    r"|\bby\s+the\s+way\b"
    r"|\bturns?\s+out\b"
    r"|\bI\s+(?:also|just)\s+(?:noticed|saw|see|spotted)\b)",
    re.IGNORECASE,
)

DRIFT_CONTEXT_WINDOW = 120


@dataclass
class TaskDriftPattern:
    """A pattern that indicates task drift."""
    pattern: str
    description: str
    example: str
    category: str = "task_drift"
    # When True, the regex match is only a drift if a DRIFT_CONTEXT_INDICATORS
    # phrase also appears within DRIFT_CONTEXT_WINDOW chars of the match. This
    # gates otherwise-generic patterns (e.g. "let me fix the issues") so they
    # don't fire on legitimate on-task continuations.
    requires_drift_context: bool = False


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

    # Unsolicited fixes after analysis. Gated by drift context so bare
    # continuations like "Let me fix those lint errors" on a pre-approved
    # "fix the lint errors" task don't fire.
    TaskDriftPattern(
        pattern=r"(?:let me|I'll|I will)\s+(?:go ahead and\s+)?(?:fix|correct|address|resolve)\s+(?:the|these|those|this)",
        description="Offering to fix without being asked",
        example="Let me fix the issues I found.",
        requires_drift_context=True,
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
    # "Next/now let me implement/fix" — removed from regex; too many false positives
    # on natural continuations like "Now let me fix it". The LLM judge in the Stop
    # hook handles this with full context instead.

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


def _has_drift_context(text: str, match_start: int, match_end: int) -> bool:
    """Return True if a drift indicator phrase is within DRIFT_CONTEXT_WINDOW of the match."""
    window_start = max(0, match_start - DRIFT_CONTEXT_WINDOW)
    window_end = min(len(text), match_end + DRIFT_CONTEXT_WINDOW)
    window = text[window_start:window_end]
    return DRIFT_CONTEXT_INDICATORS.search(window) is not None


def extract_drift_action_verbs(matched_text: str) -> set[str]:
    """Return the set of DRIFT_ACTION_VERBS that appear in the matched drift text.

    Used to cross-reference drifts against the active task list.
    """
    lowered = matched_text.lower()
    return {v for v in DRIFT_ACTION_VERBS if re.search(rf"\b{re.escape(v)}\b", lowered)}


def drift_covered_by_active_task(drift: TaskDrift, active_tasks: list[str]) -> bool:
    """Return True if the drift's action verb appears in any active task's text.

    The active task list is the authoritative scope: if a non-completed task's
    subject or description references the same action verb the assistant is
    narrating (fix, implement, refactor, etc.), the assistant is executing
    planned work, not drifting.
    """
    verbs = extract_drift_action_verbs(drift.matched_text)
    if not verbs:
        return False
    for task_text in active_tasks:
        for verb in verbs:
            if re.search(rf"\b{re.escape(verb)}\b", task_text):
                return True
    return False


def find_task_drift(text: str) -> list[TaskDrift]:
    """Find task drift patterns in the given text."""
    drifts = []

    for pattern, compiled in COMPILED_DRIFT_PATTERNS:
        match = compiled.search(text)
        if not match:
            continue

        if pattern.requires_drift_context and not _has_drift_context(text, match.start(), match.end()):
            continue

        context = get_context_around_match(text, match.start(), match.end())
        drifts.append(TaskDrift(
            pattern=pattern,
            matched_text=match.group(0),
            context=context,
        ))

    return drifts
