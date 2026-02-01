#!/usr/bin/env python3
"""
TIM Design Standards: Failure Dismissal Patterns

Category R: Failure Dismissal (patterns 101-108)
  Patterns that detect when AI encounters failures (test failures, errors, etc.)
  and dismisses them as "pre-existing" or "unrelated" rather than asking the
  user how to proceed.

Philosophy:
  When failures exist, the user should decide how to handle them - not the AI.
  Even if failures appear to be pre-existing, the AI should report them and ask
  for guidance rather than unilaterally deciding they don't matter.
"""

from patterns_core import ExcusePattern


# Category R: Failure Dismissal (patterns 101-108)
FAILURE_DISMISSAL_PATTERNS = [
    ExcusePattern(
        pattern=r"exit\s+code\s+\d+\s+is\s+(?:expected|normal|due\s+to)",
        description="Dismissing non-zero exit code as expected",
        example="The exit code 1 is expected because...",
        category="failure_dismissal",
    ),
    ExcusePattern(
        pattern=r"(?:these|the|all)\s+(?:\d+\s+)?failures?\s+(?:are|were|existed)\s+(?:all\s+)?pre-existing",
        description="Dismissing failures as pre-existing without asking",
        example="These 20 failures are all pre-existing",
        category="failure_dismissal",
    ),
    ExcusePattern(
        pattern=r"failures?\s+(?:are|is)\s+(?:all\s+)?(?:pre-existing\s+)?(?:issues?\s+)?unrelated\s+to",
        description="Dismissing failures as unrelated to current work",
        example="The 20 failures are pre-existing issues unrelated to this fix",
        category="failure_dismissal",
    ),
    ExcusePattern(
        pattern=r"(?:these|the)\s+(?:failures?|errors?)\s+existed\s+before\s+(?:my|the)\s+changes",
        description="Claiming failures existed before changes without asking",
        example="These failures existed before my changes",
        category="failure_dismissal",
    ),
    ExcusePattern(
        pattern=r"(?:are|is)\s+not\s+caused\s+by\s+(?:the|my|this)\s+(?:fix|change|implementation)",
        description="Claiming failures not caused by current work without asking",
        example="are not caused by the guest booking confirmation fix",
        category="failure_dismissal",
    ),
    ExcusePattern(
        pattern=r"pre-existing\s+(?:test\s+)?failures?\s+in\s+(?:other|unrelated)",
        description="Dismissing failures as being in other areas",
        example="pre-existing failures in other test files",
        category="failure_dismissal",
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?(?:\d+\s+)?failures?\s+(?:are|were)\s+(?:all\s+)?in\s+(?:other|different|unrelated)\s+(?:test\s+)?files?",
        description="Dismissing failures as being in other files without asking",
        example="The 20 failures are all in other test files",
        category="failure_dismissal",
    ),
    ExcusePattern(
        pattern=r"(?:key|important)\s+(?:verification|point)\s+is\s+that\s+(?:all\s+)?(?:my|the\s+new|relevant)\s+tests?\s+pass",
        description="Reframing to focus on passing tests while ignoring failures",
        example="The key verification is that all guestBooking tests pass",
        category="failure_dismissal",
    ),
]
