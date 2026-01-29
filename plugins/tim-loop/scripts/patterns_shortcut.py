#!/usr/bin/env python3
"""
TIM Design Standards: Easy Path / Shortcut Reasoning Patterns

Category Q: Shortcut Reasoning (patterns 93-100)
  Patterns that detect when AI defaults to "simplest", "easiest", or "quickest"
  solutions without considering whether they're actually the BEST solutions.

Philosophy:
  Sometimes the simplest fix IS the best fix. But we want to ensure Claude
  pauses to consider alternatives rather than defaulting to easy paths.
  This is a gentle nudge, not an accusation of wrongdoing.
"""

from patterns_core import ExcusePattern


# Category Q: Shortcut Reasoning (patterns 93-100)
SHORTCUT_EXCUSE_PATTERNS = [
    ExcusePattern(
        pattern=r"(?:the\s+)?simplest\s+(?:fix|solution|approach|way|option)\s+(?:is|would\s+be)\s+to",
        description="Defaulting to simplest without considering best",
        example="The simplest fix is to disable the feature",
        category="shortcut",
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?easiest\s+(?:fix|solution|approach|way|option)\s+(?:is|would\s+be)\s+to",
        description="Defaulting to easiest without considering best",
        example="The easiest solution is to remove the validation",
        category="shortcut",
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?quickest\s+(?:fix|solution|approach|way|option)\s+(?:is|would\s+be)\s+to",
        description="Defaulting to quickest without considering best",
        example="The quickest fix would be to hardcode the value",
        category="shortcut",
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?fastest\s+(?:fix|solution|approach|way)\s+(?:is|would\s+be)\s+to",
        description="Prioritizing speed over quality",
        example="The fastest approach is to skip the validation",
        category="shortcut",
    ),
    ExcusePattern(
        pattern=r"path\s+of\s+least\s+resistance",
        description="Explicitly choosing easy over best",
        example="The path of least resistance is to just disable it",
        category="shortcut",
    ),
    ExcusePattern(
        pattern=r"(?:to\s+)?(?:just|simply)\s+(?:disable|turn\s+off|remove|skip)\s+(?:the|this|that|it)",
        description="Quick disable as solution without analysis",
        example="I'll just disable the automatic redirects",
        category="shortcut",
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?(?:simple|easy|quick)\s+(?:answer|solution)\s+is\s+to\s+(?:just|simply)?",
        description="Framing shortcut as the answer",
        example="The simple answer is to just remove it",
        category="shortcut",
    ),
    ExcusePattern(
        pattern=r"(?:for\s+now|as\s+a\s+quick\s+fix),?\s+(?:I'll|let's|we\s+can)\s+(?:just|simply)?",
        description="Temporary shortcut without considering proper fix",
        example="For now, I'll just disable the feature",
        category="shortcut",
    ),
]
