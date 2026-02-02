#!/usr/bin/env python3
"""
TIM Design Standards: Unilateral Decision Patterns

Category T: Unilateral Decisions (patterns 160-180)
  Patterns that detect when AI makes consequential decisions without asking
  the user. Claude should use AskUserQuestion for decisions that affect scope,
  approach, or feature inclusion.

Philosophy:
  AI assistants should be collaborative, not autonomous decision-makers.
  When there are multiple valid approaches, the human should choose.
  "I decided" in text should be "I'm asking you to decide" via tool.

Key Insight from Real Example:
  Claude said: "DECISION: Option A - Remove menu items (Recommended)
  - Rationale: Implementing full features requires backend API work..."

  This is wrong. Claude should have used AskUserQuestion to present the
  options and let the user choose. The decision to remove vs implement
  features is consequential and belongs to the human.
"""

from patterns_core import ExcusePattern


# Category T: Unilateral Decision Patterns (patterns 160-180)
UNILATERAL_DECISION_PATTERNS = [
    # Direct decision declarations
    ExcusePattern(
        pattern=r"\bI\s+(?:decided|chose|selected|picked|went\s+with)\s+(?:to|option|approach)",
        description="Declaring a decision was made without asking",
        example="I decided to remove the feature instead of implementing it",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\bI(?:'ve|'m|ve|m)?\s+(?:made|making)\s+(?:a|the)\s+decision",
        description="Explicitly stating a decision was made",
        example="I made a decision to use Option A",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\bDECISION:\s*(?:Option|Approach|I|We)",
        description="Formal decision declaration header",
        example="DECISION: Option A - Remove menu items",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\bmy\s+decision\s+(?:is|was)\s+to",
        description="Claiming ownership of a decision",
        example="My decision is to skip the authentication",
        category="unilateral_decision",
    ),

    # Option selection without asking
    ExcusePattern(
        pattern=r"\bI(?:'m|'ll|m|ll)?\s+(?:go|going)\s+with\s+option",
        description="Selecting an option without user input",
        example="I'm going with option B since it's simpler",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\bchoosing\s+option\s+[A-Za-z0-9]",
        description="Selecting an option autonomously",
        example="Choosing option A for the implementation",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\b(?:I'll|let's|we'll)\s+(?:take|use|pick)\s+option\s+[A-Za-z0-9]",
        description="Selecting numbered/lettered option",
        example="I'll take option 2 since it requires less work",
        category="unilateral_decision",
    ),

    # Scope reduction decisions
    ExcusePattern(
        pattern=r"\brather\s+than\s+(?:implement|build|create|add|write)\b.*\bI(?:'ll|'m|ll|m)?\s+(?:just|simply)?",
        description="Deciding to do less without asking",
        example="Rather than implement the full feature, I'll just add a stub",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\binstead\s+of\s+(?:implementing|building|creating|adding)\b.*\blet(?:'s|s)?\b",
        description="Substituting simpler approach without asking",
        example="Instead of implementing real auth, let's use a mock",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\b(?:implementing|building|adding)\s+.{10,60}requires\s+.{10,60}(?:so|therefore)\s+I(?:'ll|'m|ll|m)?",
        description="Using complexity as justification for autonomous decision",
        example="Implementing full auth requires backend work so I'll skip it",
        category="unilateral_decision",
    ),

    # Ambiguity resolution without asking
    ExcusePattern(
        pattern=r"\bto\s+resolve\s+(?:the|this)\s+ambiguity",
        description="Resolving ambiguity without user input",
        example="To resolve the ambiguity, I'm going with approach A",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\bI\s+(?:made|took)\s+a\s+judgment\s+call",
        description="Making judgment calls without consulting user",
        example="I made a judgment call to remove the feature",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\bI\s+(?:interpreted|understood)\s+(?:this|that|it)\s+(?:as|to\s+mean)",
        description="Interpreting requirements without confirming",
        example="I interpreted this as meaning we should remove it",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\bI\s+took\s+the\s+liberty\s+of",
        description="Taking liberties without permission",
        example="I took the liberty of removing the unused feature",
        category="unilateral_decision",
    ),

    # Autonomous choice justification
    ExcusePattern(
        pattern=r"\b(?:since|because)\s+.{10,60}I(?:'ve|'m|ve|m)?\s+(?:decided|chosen|opted)",
        description="Justifying autonomous decision after the fact",
        example="Since it's complex, I've decided to simplify it",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\bthis\s+(?:is|was)\s+my\s+(?:decision|call|choice)\s+(?:during|to\s+make)",
        description="Claiming decision authority",
        example="This was my decision during the review process",
        category="unilateral_decision",
    ),

    # Feature removal/scope decisions
    ExcusePattern(
        pattern=r"\bI(?:'ll|'m|ll|m)?\s+(?:just\s+)?(?:remove|delete|drop|skip)\s+(?:the|this|that)\s+(?:feature|functionality|option)",
        description="Deciding to remove features without asking",
        example="I'll just remove the feature for now",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\b(?:removing|deleting|dropping)\s+(?:the|this|these)\s+.{3,30}(?:since|because|as)\s+(?:they|it)",
        description="Removing items with autonomous justification",
        example="Removing the menu items since they're not implemented",
        category="unilateral_decision",
    ),

    # AI-Ready review specific (where original example came from)
    ExcusePattern(
        pattern=r"\bduring\s+(?:the\s+)?(?:AI[- ]?Ready|review)\b.*\bI\s+(?:decided|made|chose)",
        description="Making decisions during review phases",
        example="During the AI-Ready review, I decided to remove it",
        category="unilateral_decision",
    ),
    ExcusePattern(
        pattern=r"\bI\s+should\s+not\s+have\s+(?:made|decided)\s+this\s+(?:decision\s+)?unilaterally",
        description="Admitting to unilateral decision (late recognition)",
        example="I should not have made this decision unilaterally",
        category="unilateral_decision",
    ),
]
