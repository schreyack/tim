#!/usr/bin/env python3
"""
TIM Design Standards: Extended Excuse Pattern Definitions

New patterns (39-76) for detecting additional deflection strategies.
Categories: Time/Effort, Risk Aversion, Deferral, Minimization,
Documentation, Conditional Compliance, Permission Seeking,
Claiming No Problem, False Progress, Authority Appeals, Alternative Deflection.
"""

from patterns_core import ExcusePattern


# Extended excuse patterns (39-76)
EXTENDED_EXCUSE_PATTERNS = [
    # Patterns 39-41: Category A - Time/Effort Deflection
    ExcusePattern(
        pattern=r"(?:this\s+)?(?:would|will)\s+take\s+(?:too\s+)?(?:long|much\s+time|considerable)",
        description="Using time as excuse to avoid work",
        example="This would take too long to fix properly"
    ),
    ExcusePattern(
        pattern=r"(?:don't|do\s+not)\s+have\s+(?:enough\s+)?time\s+to",
        description="Claiming insufficient time",
        example="I don't have time to refactor this"
    ),
    ExcusePattern(
        pattern=r"(?:requires?|needs?)\s+(?:significant|considerable|extensive)\s+(?:effort|time|work)",
        description="Effort magnitude as excuse",
        example="This requires significant effort to fix"
    ),
    # Patterns 42-45: Category B - Risk Aversion as Excuse
    ExcusePattern(
        pattern=r"(?:this\s+)?(?:could|might|may)\s+break\s+(?:things|other|existing)",
        description="Using potential breakage as excuse",
        example="This could break other functionality"
    ),
    ExcusePattern(
        pattern=r"(?:too\s+)?risky\s+(?:to\s+(?:change|modify)|without)",
        description="Risk as excuse to avoid changes",
        example="Too risky to change without more testing"
    ),
    ExcusePattern(
        pattern=r"(?:could|might)\s+(?:introduce|cause)\s+(?:regressions?|bugs?|issues?)",
        description="Potential regressions as excuse",
        example="This might introduce regressions"
    ),
    ExcusePattern(
        pattern=r"dangerous\s+to\s+(?:change|modify|touch)",
        description="Claiming danger to avoid work",
        example="It's dangerous to modify this code"
    ),
    # Patterns 46-48: Category D - Deferral to Others
    ExcusePattern(
        pattern=r"(?:a\s+)?human\s+should\s+(?:decide|review|handle)",
        description="Deferring to human unnecessarily",
        example="A human should decide on this approach"
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?team\s+should\s+(?:discuss|decide|review)",
        description="Deferring to team discussion",
        example="The team should discuss this first"
    ),
    ExcusePattern(
        pattern=r"(?:someone|person)\s+with\s+(?:more\s+)?expertise\s+should",
        description="Deferring to supposed experts",
        example="Someone with more expertise should handle this"
    ),
    # Patterns 49-52: Category G - Minimization
    ExcusePattern(
        pattern=r"(?:this\s+is\s+)?(?:just\s+)?(?:a\s+)?(?:minor|small|trivial)\s+(?:issue|problem|bug)",
        description="Minimizing issue importance",
        example="This is just a minor issue"
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?impact\s+is\s+(?:negligible|minimal|low)",
        description="Minimizing impact",
        example="The impact is negligible"
    ),
    ExcusePattern(
        pattern=r"(?:this\s+)?(?:rarely|seldom)\s+(?:happens|occurs)",
        description="Claiming rarity to avoid fixing",
        example="This rarely happens in practice"
    ),
    ExcusePattern(
        pattern=r"(?:this\s+is\s+)?(?:just\s+)?(?:an?\s+)?edge\s+case",
        description="Dismissing as edge case",
        example="This is just an edge case"
    ),
    # Patterns 53-56: Category H - Documentation Instead of Fixing
    ExcusePattern(
        pattern=r"(?:I'll|let\s+me)\s+(?:just\s+)?document\s+(?:this|it)",
        description="Documenting instead of fixing",
        example="I'll just document this issue"
    ),
    ExcusePattern(
        pattern=r"(?:should|let'?s?)\s+create\s+(?:a\s+)?(?:ticket|issue|task)",
        description="Creating ticket instead of fixing",
        example="Let's create a ticket for this"
    ),
    ExcusePattern(
        pattern=r"(?:add(?:ing)?|put(?:ting)?)\s+(?:this\s+)?(?:to|on|in)\s+(?:the\s+)?backlog",
        description="Deferring to backlog",
        example="Adding this to the backlog"
    ),
    ExcusePattern(
        pattern=r"should\s+be\s+addressed\s+in\s+(?:a\s+)?(?:future|later|separate)\s+(?:plan|task|pr|ticket)",
        description="Deferring to future work item",
        example="This should be addressed in a future task"
    ),
    # Patterns 57-59: Category I - Conditional/Reluctant Compliance
    ExcusePattern(
        pattern=r"if\s+you\s+(?:really\s+)?(?:insist|want\s+me\s+to)",
        description="Reluctant compliance signaling",
        example="If you really want me to, I can"
    ),
    ExcusePattern(
        pattern=r"I\s+can\s+(?:do\s+it\s+)?but\s+(?:I\s+)?(?:don't|wouldn't)\s+recommend",
        description="Doing with disapproval",
        example="I can do it but I wouldn't recommend it"
    ),
    ExcusePattern(
        pattern=r"I(?:'ll|\s+will)\s+(?:do\s+it|proceed)\s+but",
        description="Proceeding with objection",
        example="I'll do it but I have concerns"
    ),
    # Patterns 60-63: Category J - Asking Permission Not To
    ExcusePattern(
        pattern=r"(?:should|shall)\s+I\s+(?:skip|leave|defer|ignore)\s+(?:this|it)",
        description="Asking to skip work",
        example="Should I skip this for now?"
    ),
    ExcusePattern(
        pattern=r"(?:would\s+it\s+be|is\s+it)\s+(?:acceptable|ok(?:ay)?)\s+to\s+(?:defer|skip|leave)",
        description="Seeking permission to defer",
        example="Would it be acceptable to defer this?"
    ),
    ExcusePattern(
        pattern=r"(?:do\s+you\s+want|want)\s+me\s+to\s+(?:leave|skip|ignore)\s+(?:this|it)",
        description="Offering to skip",
        example="Do you want me to leave this as-is?"
    ),
    ExcusePattern(
        pattern=r"can\s+we\s+(?:table|defer|postpone|skip)\s+(?:this|it)",
        description="Requesting to postpone",
        example="Can we table this for later?"
    ),
    # Patterns 64-67: Category K - Claiming It Works/No Problem
    ExcusePattern(
        pattern=r"(?:this\s+)?works\s+as\s+(?:intended|designed|expected)",
        description="Claiming intended behavior to avoid fixing",
        example="This works as intended"
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?current\s+behavior\s+is\s+(?:correct|right|expected)",
        description="Defending current behavior",
        example="The current behavior is correct"
    ),
    ExcusePattern(
        pattern=r"(?:this\s+)?(?:isn't|is\s+not)\s+(?:actually\s+)?(?:a\s+)?bug",
        description="Denying bug exists",
        example="This isn't actually a bug"
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?test(?:'s|s')?\s+(?:expectation|assertion)\s+is\s+(?:wrong|incorrect)",
        description="Blaming test instead of fixing code",
        example="The test's expectation is wrong"
    ),
    # Patterns 68-70: Category L - False Progress Claims
    ExcusePattern(
        pattern=r"(?:I'?ve?|have)\s+(?:already\s+)?addressed\s+(?:the\s+)?(?:key|main|essential|core)\s+(?:parts?|issues?|functionality)",
        description="Claiming partial work is complete",
        example="I've addressed the key parts"
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?(?:essential|core|main)\s+(?:functionality|features?)\s+(?:is|are)\s+(?:complete|done|finished)",
        description="Claiming essential is done when it isn't",
        example="The essential functionality is complete"
    ),
    ExcusePattern(
        pattern=r"(?:most|majority)\s+of\s+(?:the\s+)?(?:work|issues?|problems?)\s+(?:is|are)\s+(?:done|resolved|fixed)",
        description="Claiming most is done",
        example="Most of the work is done"
    ),
    # Patterns 71-73: Category M - Authority/Precedent Appeals
    ExcusePattern(
        pattern=r"(?:the\s+)?original\s+(?:author|developer|writer)\s+(?:must\s+have\s+had|probably\s+had)\s+(?:a\s+)?reason",
        description="Deferring to original author's intent",
        example="The original author must have had a reason"
    ),
    ExcusePattern(
        pattern=r"(?:this\s+)?pattern\s+is\s+(?:used|found)\s+elsewhere\s+(?:in\s+the\s+codebase)?",
        description="Justifying with precedent",
        example="This pattern is used elsewhere in the codebase"
    ),
    ExcusePattern(
        pattern=r"(?:this\s+is\s+)?how\s+it(?:'s|\s+has)\s+(?:always\s+)?been\s+done",
        description="Appeal to tradition",
        example="This is how it's always been done"
    ),
    # Patterns 74-76: Category N - Alternative Deflection
    ExcusePattern(
        pattern=r"instead\s+of\s+(?:fixing|addressing|resolving)\s+(?:this|it),?\s+(?:we|I)\s+should",
        description="Suggesting alternative to avoid fixing",
        example="Instead of fixing this, we should redesign"
    ),
    ExcusePattern(
        pattern=r"(?:the\s+)?real\s+(?:solution|fix|answer)\s+is\s+(?:to\s+)?(?:not|avoid)",
        description="Reframing to avoid the actual fix",
        example="The real solution is to avoid this pattern"
    ),
    ExcusePattern(
        pattern=r"rather\s+than\s+(?:fix(?:ing)?|address(?:ing)?),?\s+(?:let'?s?|we\s+should|I'll)",
        description="Proposing alternative to fixing",
        example="Rather than fixing, let's refactor"
    ),
]
