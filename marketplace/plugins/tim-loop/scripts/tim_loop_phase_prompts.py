#!/usr/bin/env python3
"""
Tim Loop Full Review - Phase Prompts

Contains all phase-specific prompts for the full-review mode.
Extracted for maintainability and file size compliance.
"""


def get_phase_2_prompt(review_file: str) -> str:
    """Generate the Phase 2 (Devil's Advocate) prompt."""
    return f"""## Phase 2: Devil's Advocate Review

You are now reviewing {review_file} as a skeptical adversary trying to break the plan.

### Your Persona
Think like someone who WANTS this plan to fail. Not because you're hostile, but because finding weaknesses now prevents failures later.

### What You're Looking For

**Hidden Assumptions** - What does this plan assume that might not be true?
**Failure Modes** - How could each step fail? What happens if it does?
**Worst Case Scenarios** - What's the blast radius of a failure?
**AI Overconfidence Traps** - What looks simple but has hidden complexity?

### Your Approach
- Add protective measures where you find weaknesses
- Flag risks that need human decision
- DO NOT remove scope - add safeguards instead

### Context Management
Delegate subplan and codebase verification to Explore subagents. Only read a subplan when you need to EDIT it.

**To signal Phase 2 completion:** Output `<promise>PHASE-2-DEVILS-ADVOCATE-DONE</promise>`
"""


def get_phase_3_prompt(review_file: str) -> str:
    """Generate the Phase 3 (Security Review) prompt."""
    return f"""## Phase 3: Security Review

You are now reviewing {review_file} as an Application Security engineer.

### Your Persona
Think like a security professional doing threat modeling. Every plan that touches code, data, or systems has security implications.

### What You're Evaluating

**Authentication & Authorization** - Does the plan properly handle who can do what?
**Input Validation** - Where does external input enter? Are there injection risks?
**Data Protection** - Does the plan handle sensitive data (PII, credentials, secrets)?

### Severity Rating
- CRITICAL: Must fix before proceeding (auth bypass, data exposure)
- HIGH: Must fix before implementation (injection risk, permission gap)
- MEDIUM/LOW: Defense in depth improvements

**Blocking rule:** CRITICAL and HIGH issues must be fixed before completing this phase.

### Context Management
Delegate subplan and codebase verification to Explore subagents. Only read a subplan when you need to EDIT it.

**To signal Phase 3 completion:** Output `<promise>PHASE-3-SECURITY-DONE</promise>`
"""


def get_phase_4_prompt(review_file: str) -> str:
    """Generate the Phase 4 (AI-Ready Review) prompt."""
    return f"""## Phase 4: AI-Ready Review

You are now reviewing {review_file} to ensure it's ready for AI implementation.

### Your Persona
Think like a tech lead who manages AI developers. They follow instructions literally, can hallucinate implementations, and work best with unambiguous instructions.

### What You're Evaluating

**Unambiguous Instructions** - Can each instruction be interpreted in only ONE way?
**Hallucination Prevention** - Are all referenced APIs, functions, paths verified to exist?
**Guard Rails** - Is error handling specified explicitly, not just "handle errors"?
**Verifiable Criteria** - Can every completion criterion be checked with code?

Fix any AI-readiness issues found before completing this phase.

### Context Management
Delegate subplan and codebase verification to Explore subagents. Only read a subplan when you need to EDIT it.

**To signal Phase 4 completion:** Output `<promise>PHASE-4-AI-READY-DONE</promise>`
"""


def get_phase_5_prompt() -> str:
    """Generate the Phase 5 (Goal Alignment) prompt."""
    return """## Phase 5: Goal Alignment Check (The Spirit Test)

Step back with fresh eyes. Does this plan still achieve what the human ACTUALLY wanted?

Through technical review, plans can drift - edge cases get added but the core goal gets diluted.

**How to Check:**
1. Re-read the original Goal section - what did the human ask for?
2. Read the plan as it now stands - what will actually be delivered?
3. Ask: Would the human say 'Yes, this is what I meant'?

**If NO** - document specifically how the plan drifted. Do NOT complete the review.
**If YES** - proceed to PM Review.

**To signal Phase 5 completion:** Output `<promise>PHASE-5-GOAL-ALIGN-DONE</promise>`
"""


def get_phase_6_prompt(review_file: str) -> str:
    """Generate the Phase 6 (PM Review) prompt."""
    return f"""## Phase 6: PM Review (Final Organization)

You are now reviewing {review_file} as a senior Project Manager.

### Your Persona
The engineering reviews are complete. Organize and polish this plan for smooth implementation.

### Your Focus
**Logical Flow** - Does the plan flow logically? Would a developer know where to start?
**Clerical Quality** - Fix typos, grammar, formatting inconsistencies
**Practical Implementation** - Are dependencies between steps clear?

### CRITICAL: NEVER REDUCE SCOPE
This is an organization pass, NOT a scope change. You MUST NOT:
- Remove any requirements, tasks, or deliverables
- Simplify technical specifications
- Delete edge cases or error handling

You CAN: Reorder items, fix typos, improve wording, add section headers.

**To signal Phase 6 completion:** Output `<promise>PHASE-6-PM-DONE</promise>`

After Phase 6, proceed to the User Advocate Review (Phase 7).
"""


def get_phase_7_prompt() -> str:
    """Generate the Phase 7 (User Advocate / Decision Audit) prompt."""
    return """## Phase 7: User Advocate Review (Decision Audit)

Clear your mind. Forget the technical details. You are now the User Advocate.

### Your Mandate

Audit ALL decisions made across Phases 1-6. Did any agent (including you in earlier phases) make decisions that affected scope, features, UI/UX, or requirements WITHOUT consulting the human?

### What Counts as Unauthorized

- Removing, simplifying, or deferring any feature/requirement without asking the human
- Choosing between multiple valid approaches without presenting options to the human
- Changing UI/UX behavior, layout, or user-facing text without approval
- Marking items as 'out of scope', 'future work', or 'not needed' without asking
- Reinterpreting requirements in a way that reduces scope

### What is NOT Unauthorized

- Code structure, variable naming, internal architecture choices
- Fixing typos, formatting, or grammar
- Adding edge cases, error handling, or tests
- Choosing standard patterns when only one reasonable approach exists

### Process

1. Review the plan as it now stands compared to the original goal
2. Identify every decision that affected scope, features, UI/UX, or requirements
3. For EACH decision found, use `AskUserQuestion` to present:
   - What the decision was
   - Why it was made (or why the agent made it)
   - Options (including reversing the decision) with your recommendation
4. If no unauthorized decisions were found, state: `DECISION AUDIT: No unauthorized decisions found.`

### Completion

The `DECISION AUDIT:` marker MUST appear in your output before the completion signal.

**To signal Phase 7 completion:** Output `<promise>PHASE-7-USER-ADVOCATE-DONE</promise>`

After Phase 7, output `<promise>FULL-REVIEW-DONE</promise>` to complete the full review.
"""


def get_phase_prompt(phase: int, review_file: str) -> str:
    """Generate the prompt for a specific phase."""
    # Phase 1 prompt is generated by setup, not here. This function handles phase transitions 2-7.
    prompts = {
        2: get_phase_2_prompt(review_file),
        3: get_phase_3_prompt(review_file),
        4: get_phase_4_prompt(review_file),
        5: get_phase_5_prompt(),
        6: get_phase_6_prompt(review_file),
        7: get_phase_7_prompt(),
    }
    return prompts.get(phase, "")
