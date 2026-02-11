#!/usr/bin/env python3
"""
Mode Violation Pattern Detector

Catches when Claude attempts to do the wrong task for the current mode.
For example, trying to implement code during a review-only mode.

Review modes (should NOT implement):
- tech-review: Technical accuracy review only
- ai-ready: AI-readiness review only
- full-review: Comprehensive review only
- pm-review: Project management organization only
- verify: Verification audit only

Implementation modes (CAN implement):
- (empty): Full workflow
- implement: Implement existing plan
"""

import re
from dataclasses import dataclass

# Patterns that indicate Claude is trying to implement
# These should BLOCK during review modes
IMPLEMENTATION_PHRASES = [
    # Direct implementation statements
    r"(?:I'll|I will|let me|going to)\s+(?:now\s+)?(?:start|begin)\s+implement",
    r"(?:start|begin|commence)\s+(?:the\s+)?implementation",
    r"Phase\s+3:\s*Implement",  # The exact pattern from the example
    r"moving\s+(?:on\s+)?to\s+(?:the\s+)?implementation",
    r"proceed\s+(?:with|to)\s+(?:the\s+)?implementation",
    r"time\s+to\s+implement",
    r"now\s+implement(?:ing)?\s+(?:the|this)",
    # Code modification intent during review
    r"I'll\s+(?:create|write|add|modify|update|change)\s+(?:the\s+)?(?:code|file|function|class|module)",
    r"let\s+me\s+(?:create|write|add|modify|update|change)\s+(?:the\s+)?(?:code|file|function|class)",
    # Plan promotion during review (should be human action)
    r"mov(?:e|ing)\s+(?:the\s+)?plan\s+(?:from|to)\s+(?:drafts|active|completed)",
    r"promot(?:e|ing)\s+(?:the\s+)?plan\s+to\s+active",
]

# Compile patterns for efficiency
IMPLEMENTATION_PATTERNS = [re.compile(p, re.IGNORECASE) for p in IMPLEMENTATION_PHRASES]

# Review modes where implementation is NOT allowed
REVIEW_MODES = {"tech-review", "ai-ready", "full-review", "pm-review", "verify"}


@dataclass
class ModeViolation:
    """Represents a detected mode violation."""

    pattern: str
    matched_text: str
    context: str
    current_mode: str


def find_mode_violations(text: str, review_mode: str) -> list[ModeViolation]:
    """
    Find mode violations in the given text.

    Args:
        text: The assistant's output text to check
        review_mode: The current REVIEW_MODE from tim-loop state

    Returns:
        List of ModeViolation objects if violations found, empty list otherwise
    """
    # Only check in review modes
    if not review_mode or review_mode not in REVIEW_MODES:
        return []

    violations = []
    for pattern in IMPLEMENTATION_PATTERNS:
        match = pattern.search(text)
        if match:
            # Extract context around the match
            start = max(0, match.start() - 50)
            end = min(len(text), match.end() + 50)
            context = text[start:end].replace("\n", " ").strip()
            if start > 0:
                context = "..." + context
            if end < len(text):
                context = context + "..."

            violations.append(
                ModeViolation(
                    pattern=pattern.pattern,
                    matched_text=match.group(0),
                    context=context,
                    current_mode=review_mode,
                )
            )

    return violations


