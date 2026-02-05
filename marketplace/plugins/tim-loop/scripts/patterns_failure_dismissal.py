#!/usr/bin/env python3
"""
TIM Design Standards: Failure Dismissal Patterns

Category R: Failure Dismissal (patterns 101-130+)
  Patterns that detect when AI encounters failures (test failures, errors, etc.)
  and dismisses them as "pre-existing" or "unrelated" rather than asking the
  user how to proceed.

Philosophy:
  When failures exist, the user should decide how to handle them - not the AI.
  Even if failures appear to be pre-existing, the AI should report them and ask
  for guidance rather than unilaterally deciding they don't matter.

Note on pattern design:
  AI models are creative at rephrasing excuses. When adding patterns, consider:
  - Synonym variations (unrelated/not related/separate/independent)
  - Tense variations (is/was/were/had been)
  - Subject variations (test/failure/error/issue/problem)
  - Temporal framing (before my changes/before this plan/already/previously)
"""

from patterns_core import ExcusePattern


# Category R: Failure Dismissal (patterns 101-130+)
FAILURE_DISMISSAL_PATTERNS = [
    # ==========================================================================
    # R1: Exit Code Dismissal (101)
    # ==========================================================================
    ExcusePattern(
        pattern=r"exit\s+code\s+\d+\s+is\s+(?:expected|normal|due\s+to)",
        description="Dismissing non-zero exit code as expected",
        example="The exit code 1 is expected because...",
        category="failure_dismissal",
    ),

    # ==========================================================================
    # R2: Pre-existing/Already Broken Claims (102-109)
    # ==========================================================================
    ExcusePattern(
        pattern=r"(?:these|the|all)\s+(?:\d+\s+)?failures?\s+(?:are|were|existed)\s+(?:all\s+)?pre-existing",
        description="Dismissing failures as pre-existing without asking",
        example="These 20 failures are all pre-existing",
        category="failure_dismissal",
    ),
    ExcusePattern(
        pattern=r"(?:these|the)\s+(?:failures?|errors?)\s+existed\s+before\s+(?:my|the)\s+changes",
        description="Claiming failures existed before changes without asking",
        example="These failures existed before my changes",
        category="failure_dismissal",
    ),
    # NEW: Catches "existing test that was failing before this plan"
    ExcusePattern(
        pattern=r"existing\s+(?:test|issue|failure|error|problem)\s+(?:that\s+)?(?:was|is|has\s+been)\s+failing",
        description="Dismissing as an existing test that was already failing",
        example="it's an existing test that was failing before this plan",
        category="failure_dismissal",
    ),
    # NEW: Catches "was failing before this plan/before I started"
    ExcusePattern(
        pattern=r"(?:was|were|had\s+been)\s+failing\s+before\s+(?:this|the|my|I)",
        description="Claiming something was failing before current work",
        example="was failing before this plan",
        category="failure_dismissal",
    ),
    # NEW: Catches "was already failing/broken"
    ExcusePattern(
        pattern=r"(?:was|were|is|are)\s+already\s+(?:failing|broken|not\s+working|buggy)",
        description="Claiming something was already broken",
        example="The test was already failing",
        category="failure_dismissal",
    ),
    # NEW: Catches "already had issues/problems"
    ExcusePattern(
        pattern=r"already\s+had\s+(?:issues?|problems?|failures?|errors?|bugs?)",
        description="Claiming something already had issues",
        example="This file already had issues before I touched it",
        category="failure_dismissal",
    ),
    # NEW: Catches "pre-dates my changes" / "predates this work"
    ExcusePattern(
        pattern=r"pre-?dates?\s+(?:my|the|this|current)",
        description="Claiming failure predates current work",
        example="This failure predates my changes",
        category="failure_dismissal",
    ),

    # ==========================================================================
    # R3: Unrelated/Not Related Claims (110-119)
    # ==========================================================================
    ExcusePattern(
        pattern=r"failures?\s+(?:are|is)\s+(?:all\s+)?(?:pre-existing\s+)?(?:issues?\s+)?unrelated\s+to",
        description="Dismissing failures as unrelated to current work",
        example="The 20 failures are pre-existing issues unrelated to this fix",
        category="failure_dismissal",
    ),
    ExcusePattern(
        pattern=r"(?:are|is)\s+not\s+caused\s+by\s+(?:the|my|this)\s+(?:fix|change|implementation)",
        description="Claiming failures not caused by current work without asking",
        example="are not caused by the guest booking confirmation fix",
        category="failure_dismissal",
    ),
    # NEW: Catches standalone "This is not related to"
    ExcusePattern(
        pattern=r"(?:this|it|that)\s+(?:is|isn't|is\s+not|was|wasn't)\s+(?:not\s+)?related\s+to\s+(?:the|my|this|current)",
        description="Dismissing something as not related to current work",
        example="This is not related to the guest booking fix",
        category="failure_dismissal",
    ),
    # NEW: Catches "has nothing to do with"
    ExcusePattern(
        pattern=r"(?:has|have)\s+nothing\s+to\s+do\s+with\s+(?:the|my|this|current)",
        description="Dismissing as having nothing to do with current work",
        example="This has nothing to do with my changes",
        category="failure_dismissal",
    ),
    # NEW: Catches "is separate from" / "is independent of"
    ExcusePattern(
        pattern=r"(?:is|are)\s+(?:completely\s+)?(?:separate|independent)\s+(?:from|of)\s+(?:the|my|this)",
        description="Dismissing as separate from current work",
        example="This is separate from the current implementation",
        category="failure_dismissal",
    ),
    # NEW: Catches "a different/separate issue"
    ExcusePattern(
        pattern=r"(?:a|an)\s+(?:different|separate|distinct|unrelated)\s+(?:issue|problem|bug|failure)",
        description="Reframing failure as a different issue",
        example="That's a separate issue from what we're working on",
        category="failure_dismissal",
    ),
    # NEW: Catches "not my/our problem/concern"
    ExcusePattern(
        pattern=r"not\s+(?:my|our)\s+(?:problem|concern|responsibility|issue)",
        description="Disclaiming responsibility for failure",
        example="That's not my problem to fix",
        category="failure_dismissal",
    ),
    # NEW: Catches "someone else's issue"
    ExcusePattern(
        pattern=r"(?:someone|somebody)\s+else(?:'s|s)?\s+(?:issue|problem|bug|responsibility)",
        description="Attributing failure to someone else",
        example="That's someone else's issue to fix",
        category="failure_dismissal",
    ),
    # NEW: Catches "belongs to a different" area/team/component
    ExcusePattern(
        pattern=r"belongs?\s+to\s+(?:a\s+)?(?:different|another|separate)",
        description="Claiming failure belongs to a different area",
        example="This belongs to a different component",
        category="failure_dismissal",
    ),

    # ==========================================================================
    # R4: Scope/Plan Exclusion Claims (120-125)
    # ==========================================================================
    # NEW: Catches "not part of this/the plan"
    ExcusePattern(
        pattern=r"not\s+(?:a\s+)?part\s+of\s+(?:this|the)\s+(?:plan|scope|task|work|ticket)",
        description="Dismissing failure as not part of the plan",
        example="This is not part of this plan",
        category="failure_dismissal",
    ),
    # NEW: Catches "outside/beyond the scope"
    ExcusePattern(
        pattern=r"(?:outside|beyond|out\s+of)\s+(?:the\s+)?(?:scope|bounds|remit)",
        description="Claiming failure is outside scope",
        example="This is outside the scope of this task",
        category="failure_dismissal",
    ),
    # NEW: Catches "out of scope" / "not in scope"
    ExcusePattern(
        pattern=r"(?:out\s+of|not\s+in|outside)\s+scope",
        description="Dismissing as out of scope",
        example="That test failure is out of scope",
        category="failure_dismissal",
    ),
    # NEW: Catches "wasn't asked to fix"
    ExcusePattern(
        pattern=r"(?:wasn't|was\s+not|weren't|were\s+not)\s+asked\s+to\s+(?:fix|address|handle|resolve)",
        description="Claiming they weren't asked to fix the issue",
        example="I wasn't asked to fix that test",
        category="failure_dismissal",
    ),
    # NEW: Catches "only asked to" / "my task was only"
    ExcusePattern(
        pattern=r"(?:only|just)\s+asked\s+to|(?:my|the)\s+task\s+(?:was|is)\s+(?:only|just)\s+to",
        description="Limiting scope to avoid responsibility",
        example="I was only asked to fix the confirmation page",
        category="failure_dismissal",
    ),
    # NEW: Catches "doesn't fall under" / "isn't covered by"
    ExcusePattern(
        pattern=r"(?:doesn't|does\s+not|isn't|is\s+not)\s+(?:fall\s+under|covered\s+by|included\s+in)",
        description="Claiming failure isn't covered by current work",
        example="This doesn't fall under the current task",
        category="failure_dismissal",
    ),

    # ==========================================================================
    # R5: Location-based Dismissal (126-128)
    # ==========================================================================
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
    # NEW: Catches "in a different test file/module"
    ExcusePattern(
        pattern=r"in\s+(?:a\s+)?(?:different|another|separate)\s+(?:test\s+)?(?:file|module|suite|spec)",
        description="Dismissing failure as being in a different file",
        example="That failure is in a different test file",
        category="failure_dismissal",
    ),

    # ==========================================================================
    # R6: Reframing/Minimization (129-135)
    # ==========================================================================
    ExcusePattern(
        pattern=r"(?:key|important)\s+(?:verification|point)\s+is\s+that\s+(?:all\s+)?(?:my|the\s+new|relevant)\s+tests?\s+pass",
        description="Reframing to focus on passing tests while ignoring failures",
        example="The key verification is that all guestBooking tests pass",
        category="failure_dismissal",
    ),
    # NEW: Catches "just one/only one failure"
    ExcusePattern(
        pattern=r"(?:just|only)\s+(?:one|a\s+single|1)\s+(?:failing\s+test|failure|error|test\s+fail)",
        description="Minimizing by emphasizing only one failure",
        example="There's just one failing test",
        category="failure_dismissal",
    ),
    # NEW: Catches "just a minor/unimportant failure" - requires dismissive context
    # NOTE: Requires "just" or "is a" to avoid matching severity headers like "**Minor Issue:**"
    ExcusePattern(
        pattern=r"(?:just\s+(?:a\s+)?|is\s+a\s+)(?:minor|small|trivial|unimportant|insignificant)\s+(?:failure|error|issue|test)",
        description="Minimizing failure as unimportant",
        example="This is a minor failure that we can ignore",
        category="failure_dismissal",
    ),
    # NEW: Catches "the important thing is" (reframing)
    ExcusePattern(
        pattern=r"(?:the\s+)?(?:important|main|key)\s+(?:thing|point|takeaway)\s+(?:is|here)",
        description="Reframing to distract from failures",
        example="The important thing is that the main tests pass",
        category="failure_dismissal",
    ),
    # NEW: Catches "we can ignore" / "can be ignored"
    ExcusePattern(
        pattern=r"(?:we\s+)?can\s+(?:safely\s+)?(?:ignore|skip|overlook|disregard)",
        description="Suggesting failures can be ignored",
        example="We can safely ignore this failure",
        category="failure_dismissal",
    ),
    # NEW: Catches "doesn't affect" / "won't affect"
    ExcusePattern(
        pattern=r"(?:doesn't|does\s+not|won't|will\s+not)\s+affect\s+(?:the|our|this|my)",
        description="Claiming failure doesn't affect current work",
        example="This doesn't affect the feature we're building",
        category="failure_dismissal",
    ),
    # NEW: Catches "shouldn't block" / "shouldn't prevent"
    ExcusePattern(
        pattern=r"shouldn't\s+(?:block|prevent|stop|hold\s+up)",
        description="Arguing failure shouldn't block progress",
        example="This shouldn't block us from continuing",
        category="failure_dismissal",
    ),

    # ==========================================================================
    # R7: Moving On Without Resolution (136-140)
    # ==========================================================================
    # NOTE: "let me continue/proceed" alone is NOT failure dismissal - it's just
    # announcing intent. We only flag it when there's EXPLICIT context about
    # moving past failures or ignoring issues.
    # The original pattern r"(?:let\s+me|I'll|I\s+will)\s+(?:continue|proceed|move\s+on)\s+(?:with|to)\s+(?:the|my|other)"
    # was too broad and caught legitimate progress announcements.
    # NEW: Catches "proceeding despite" / "continuing despite"
    ExcusePattern(
        pattern=r"(?:proceeding|continuing|moving\s+forward)\s+(?:despite|regardless\s+of|in\s+spite\s+of)",
        description="Explicitly proceeding despite failures",
        example="Proceeding despite the failing test",
        category="failure_dismissal",
    ),
    # NEW: Catches "setting aside" / "putting aside"
    ExcusePattern(
        pattern=r"(?:setting|putting|leaving)\s+(?:this|that|it)\s+aside",
        description="Setting aside a failure without resolution",
        example="Setting this aside for now",
        category="failure_dismissal",
    ),
    # NEW: Catches "we'll address later" / "can be fixed later"
    ExcusePattern(
        pattern=r"(?:we'll|can\s+be|should\s+be|will\s+be)\s+(?:addressed|fixed|resolved|handled)\s+(?:later|separately|afterward)",
        description="Deferring failure to later without asking",
        example="This can be fixed later",
        category="failure_dismissal",
    ),
    # NEW: Catches "for now" dismissals
    ExcusePattern(
        pattern=r"(?:ignore|skip|overlook|disregard)\s+(?:this|that|it)\s+for\s+now",
        description="Ignoring failure 'for now'",
        example="Let's ignore this for now",
        category="failure_dismissal",
    ),

    # ==========================================================================
    # R8: Known Issue Claims (141-144)
    # ==========================================================================
    # NEW: Catches "known issue/failure"
    ExcusePattern(
        pattern=r"(?:a\s+)?known\s+(?:issue|failure|problem|bug|flaky\s+test)",
        description="Dismissing as a known issue without verification",
        example="This is a known issue",
        category="failure_dismissal",
    ),
    # NEW: Catches "flaky test" dismissal
    ExcusePattern(
        pattern=r"(?:just\s+a\s+)?flaky\s+(?:test|spec|assertion)",
        description="Dismissing failure as a flaky test",
        example="That's just a flaky test",
        category="failure_dismissal",
    ),
    # NEW: Catches "intermittent failure"
    ExcusePattern(
        pattern=r"(?:an?\s+)?intermittent\s+(?:failure|issue|problem|error)",
        description="Dismissing as intermittent failure",
        example="This is an intermittent failure",
        category="failure_dismissal",
    ),
    # NEW: Catches "happens sometimes" / "fails sometimes"
    ExcusePattern(
        pattern=r"(?:happens|fails|occurs|breaks)\s+(?:sometimes|occasionally|intermittently|randomly)",
        description="Dismissing because it only happens sometimes",
        example="This test fails sometimes",
        category="failure_dismissal",
    ),
]
