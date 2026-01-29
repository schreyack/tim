#!/usr/bin/env python3
"""
TIM Design Standards: Core Excuse Pattern Definitions

Original patterns (1-39) for detecting deflection of responsibility.
"""

from typing import NamedTuple


class ExcusePattern(NamedTuple):
    """An excuse pattern to detect."""
    pattern: str
    description: str
    example: str
    category: str = "general"  # "general", "posthook", or "redefine"


# Core excuse patterns (1-39)
CORE_EXCUSE_PATTERNS = [
    # Patterns 1-16: Pre-existing blame
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
        pattern=r"pre-existing\s+(?:\w+\s+)*(?:issue|problem|violation|structure|code|bug|error|test|files?)",
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
        pattern=r"not\s+caused\s+by\s+(?:my|the|our)\s+(?:changes|edits|modifications|work)",
        description="Denying causation (passive form)",
        example="not caused by my changes"
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
    ExcusePattern(
        pattern=r"(?:in|are)\s+unrelated\s+(?:\w+\s+)*(?:functionality|code|test|area|module|component)",
        description="Claiming failures are in unrelated code",
        example="failures are in unrelated login functionality"
    ),
    ExcusePattern(
        pattern=r"not\s+in\s+(?:the\s+)?(?:\w+\s+)*(?:code|workflow|feature|component)\s+I\s+(?:implemented|wrote|added|created)",
        description="Claiming issues are outside implemented code",
        example="not in the code I implemented"
    ),
    # Patterns 17-28: Synonym variations
    ExcusePattern(
        pattern=r"(?:originated|stems?|came)\s+(?:from|in)\s+(?:legacy|prior|previous)",
        description="Synonym for pre-existing attribution",
        example="originated in legacy work"
    ),
    ExcusePattern(
        pattern=r"predates?\s+(?:my|the|these)\s+(?:changes|modifications|work)",
        description="Claiming issue predates current work",
        example="predates my changes"
    ),
    ExcusePattern(
        pattern=r"(?:existed|was\s+present)\s+(?:before|prior\s+to)\s+(?:my|the)",
        description="Claiming pre-existence of issue",
        example="existed before my modifications"
    ),
    ExcusePattern(
        pattern=r"(?:isn't|is\s+not)\s+(?:within|in)\s+(?:the\s+)?scope",
        description="Claiming something is not in scope",
        example="isn't in scope"
    ),
    ExcusePattern(
        pattern=r"(?:separate|follow-?up|future)\s+(?:effort|task|ticket|work|pr)",
        description="Deferring to future work",
        example="follow-up task"
    ),
    ExcusePattern(
        pattern=r"(?:this\s+is|it's)\s+(?:just\s+)?technical\s+debt",
        description="Blaming technical debt",
        example="this is technical debt"
    ),
    ExcusePattern(
        pattern=r"i\s+(?:barely|hardly)\s+(?:touched|changed|modified)",
        description="Minimizing own involvement",
        example="I barely touched"
    ),
    ExcusePattern(
        pattern=r"(?:shouldn't|should\s+not)\s+(?:fix|change|refactor)",
        description="Claiming obligation not to fix",
        example="shouldn't fix"
    ),
    ExcusePattern(
        pattern=r"(?:someone\s+else's?|another\s+team's?)\s+(?:responsibility|issue)",
        description="Blaming other teams or people",
        example="another team's responsibility"
    ),
    ExcusePattern(
        pattern=r"(?:cleanup|refactoring)\s+(?:would|should)\s+be\s+(?:a\s+)?separate",
        description="Deferring cleanup to separate effort",
        example="cleanup would be separate"
    ),
    ExcusePattern(
        pattern=r"(?:leave|leaving)\s+(?:it|this)\s+(?:as-?is|alone|for\s+now)",
        description="Explicitly not taking action",
        example="leave it as-is"
    ),
    ExcusePattern(
        pattern=r"(?:outside|not)\s+(?:my|our)\s+(?:area|domain|expertise)",
        description="Claiming domain boundaries",
        example="outside my area"
    ),
    # Patterns 29-38: Scope reduction and constraint-based deflection
    ExcusePattern(
        pattern=r"(?:let\s+me\s+)?(?:simplify|revise|restructure|re-?structure)\s+(?:the\s+)?(?:tests?|approach|code)\s+to\s+(?:be\s+more\s+)?(?:practical|focus)",
        description="Reducing scope to avoid hard parts",
        example="Let me simplify the tests to be more practical"
    ),
    ExcusePattern(
        pattern=r"since\s+(?:the\s+)?(?:plan|task|instructions?|requirements?)\s+(?:says?|specifies?|requires?)",
        description="Using plan constraints as excuse to not solve problem",
        example="Since the plan says DO NOT modify..."
    ),
    ExcusePattern(
        pattern=r"(?:can'?t|cannot|can\s+not)\s+be\s+(?:skipped|bypassed|avoided|worked\s+around)",
        description="Claiming impossibility to avoid solving",
        example="photo requirements can't be skipped"
    ),
    ExcusePattern(
        pattern=r"work\s+within\s+(?:the\s+)?(?:existing\s+)?(?:\w+\s+)?(?:constraints?|limitations?|restrictions?)",
        description="Using constraints as excuse to reduce scope",
        example="I need to work within the existing workflow constraints"
    ),
    ExcusePattern(
        pattern=r"what'?s\s+actually\s+(?:testable|possible|achievable|doable)",
        description="Redefining success to exclude hard parts",
        example="focus on what's actually testable"
    ),
    ExcusePattern(
        pattern=r"(?:focus|concentrate)\s+on\s+what\s+(?:can|could)\s+(?:actually|really)\s+be\s+(?:tested|done|achieved)",
        description="Redefining scope to avoid difficult work",
        example="focus on what can actually be tested"
    ),
    ExcusePattern(
        pattern=r"(?:requires?|needs?)\s+(?:a\s+)?different\s+approach\s+since",
        description="Changing approach to avoid the actual requirement",
        example="I need a different approach since photo requirements..."
    ),
    ExcusePattern(
        pattern=r"(?:best|better|practical)\s+approach\s+is\s+to\s+(?:re-?structure|revise|simplify|skip)",
        description="Reframing avoidance as better approach",
        example="The best approach is to re-structure tests"
    ),
    ExcusePattern(
        pattern=r"(?:accepting|accept)\s+that\s+(?:some|certain)\s+(?:phases?|parts?|sections?)\s+require\s+prerequisites?",
        description="Accepting limitations instead of solving them",
        example="accepting that some phases require prerequisites"
    ),
    ExcusePattern(
        pattern=r"(?:this\s+)?means\s+I\s+(?:need|have)\s+to\s+either.*or\s+(?:change|modify|skip|simplify)",
        description="False dichotomy to justify easier path",
        example="This means I need to either upload photos (complex) or change the test approach"
    ),
    ExcusePattern(
        pattern=r"commit\s+(?:just|only)\s+(?:the|my)\s+changes?\s+(?:I\s+made\s+)?without",
        description="Selectively excluding problematic files from commit",
        example="commit just the changes I made without these problematic files"
    ),
]

# Mitigation patterns that indicate the speaker took corrective action
MITIGATION_PATTERNS = [
    # Original patterns (1-6)
    r"(?:but\s+)?(?:I'll|I\s+will|I'm\s+going\s+to)\s+(?:fix|address|resolve|refactor)",
    r"(?:so\s+)?I\s+(?:fixed|addressed|resolved|refactored)",
    r"I(?:'m|\s+am)\s+fixing\s+(?:it|this|that)",
    r"fixing\s+(?:it|this|that)\s+(?:now|anyway|regardless)",
    r"(?:but\s+)?I\s+(?:went\s+ahead\s+and|also)\s+(?:fixed|refactored)",
    r"I\s+(?:addressed|handled|took\s+care\s+of)\s+(?:it|this|that)",
    # Enhanced mitigation patterns (7-15)
    r"(?:so\s+)?let\s+me\s+(?:try|find|work)",
    r"(?:but\s+)?(?:I\s+can|I'll)\s+(?:still|work\s+around)",
    r"(?:nevertheless|despite\s+this|even\s+so|regardless),?\s+(?:I'll|let\s+me)",
    r"(?:however|but),?\s+I(?:'ll|\s+will)\s+(?:still|try|find)",
    r"(?:I'll|let\s+me)\s+(?:find\s+a\s+)?(?:work\s*around|alternative)",
    r"working\s+around\s+(?:this|that|it)\s+by",
    r"so\s+instead\s+(?:I'll|let\s+me)",
    r"here'?s?\s+how\s+(?:I'll|we\s+can|to)\s+(?:handle|address|fix)",
    r"(?:I'll|let\s+me)\s+(?:proceed|continue)\s+(?:with|by|to)",
    # Shortcut mitigation patterns (16-20) - when considering alternatives
    r"(?:but\s+)?let\s+me\s+(?:consider|explore|analyze)\s+(?:other\s+)?(?:options|alternatives|approaches)",
    r"(?:however|but),?\s+(?:I'll|let\s+me)\s+(?:first\s+)?(?:consider|think\s+about|evaluate)",
    r"(?:before\s+)?(?:doing\s+that|proceeding),?\s+let\s+me\s+(?:consider|check|explore)",
    r"(?:I'll|let\s+me)\s+(?:compare|weigh)\s+(?:the\s+)?(?:options|alternatives|approaches)",
    r"(?:but\s+)?(?:I\s+should|let\s+me)\s+(?:first\s+)?(?:analyze|investigate)\s+(?:the\s+)?(?:root\s+cause|underlying)",
]
