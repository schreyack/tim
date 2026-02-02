#!/usr/bin/env python3
"""
Tim Loop Full Review - Handles per-phase iteration tracking for full-review mode.

This module contains the phase transition logic, phase prompts, and signal
detection for the three-phase full review process:
- Phase 1: Tech Review (min 3 iterations)
- Phase 2: AI-Ready Review (min 2 iterations)
- Phase 3: Goal Alignment (min 1 iteration)
"""

from tim_loop_responses import (
    build_continue_response,
    build_early_phase_completion_challenge,
    build_final_completion_instruction,
    build_phase_skip_challenge,
    build_phase_transition_response,
)
from tim_loop_state import log_stderr, save_state

# Phase signals for full-review mode
PHASE_SIGNALS = {
    1: "PHASE-1-TECH-DONE",
    2: "PHASE-2-DEVILS-ADVOCATE-DONE",
    3: "PHASE-3-SECURITY-DONE",
    4: "PHASE-4-AI-READY-DONE",
    5: "PHASE-5-GOAL-ALIGN-DONE",
    6: "PHASE-6-PM-DONE",
}

# Minimum iterations per phase
MIN_PHASE_ITERATIONS = {
    1: 5,  # Tech Review - thorough analysis needed
    2: 2,  # Devil's Advocate
    3: 2,  # Security Review
    4: 2,  # AI-Ready
    5: 1,  # Goal Alignment
    6: 1,  # PM Review
}


def detect_phase_signal(assistant_text: str) -> tuple[int, str] | None:
    """Detect phase completion signal. Returns (phase_num, signal) or None."""
    for phase, signal in PHASE_SIGNALS.items():
        if f"<promise>{signal}</promise>" in assistant_text:
            return (phase, signal)
    return None


def get_phase_2_prompt(review_file: str) -> str:
    """Generate the Phase 2 (Devil's Advocate) prompt."""
    return f"""## Phase 2: Devil's Advocate Review

You are now reviewing {review_file} as a skeptical adversary trying to break the plan.

### Your Persona
Think like someone who WANTS this plan to fail. Not because you're hostile, but because finding weaknesses now prevents failures later. You've seen confident plans crumble because nobody asked "what if this assumption is wrong?"

### What You're Looking For

**Hidden Assumptions**
- What does this plan assume will be true that might not be?
- What dependencies are implicit but not stated?
- What "should just work" but actually requires verification?

**Failure Modes**
- How could each step fail? What happens if it does?
- Are there race conditions, timing issues, or order dependencies?
- What happens at scale, under load, or with malformed input?

**Worst Case Scenarios**
- What's the worst thing that could happen if this goes wrong?
- Are there irreversible operations? Data loss risks? Security exposures?
- What's the blast radius of a failure?

**AI Overconfidence Traps**
- Where might an AI developer think they understand something but actually not?
- What looks simple but has hidden complexity?
- Where might "obvious" behavior differ from expected?

### Your Approach
- Add protective measures where you find weaknesses
- Flag risks that need human decision
- DO NOT remove scope - add safeguards instead

**To signal Phase 2 completion:** Output `<promise>PHASE-2-DEVILS-ADVOCATE-DONE</promise>`
"""


def get_phase_3_prompt(review_file: str) -> str:
    """Generate the Phase 3 (Security Review) prompt."""
    return f"""## Phase 3: Security Review

You are now reviewing {review_file} as an Application Security engineer.

### Your Persona
Think like a security professional doing threat modeling. Every plan that touches code, data, or systems has security implications. Your job is to identify them before they become vulnerabilities.

### What You're Evaluating

**Authentication & Authorization**
- Does the plan properly handle who can do what?
- Are there permission checks at the right boundaries?
- Could any operation bypass intended access controls?

**Input Validation**
- Where does external input enter the system?
- Is validation specified explicitly or left to "handle appropriately"?
- Are there injection risks (SQL, command, XSS, etc.)?

**Data Protection**
- Does the plan handle sensitive data (PII, credentials, secrets)?
- Are there logging statements that might expose sensitive info?
- Is data properly sanitized before display or storage?

**Security-Relevant OWASP Considerations**
(Focus on these as they apply to PLAN review, not code review)
- A01: Broken Access Control - are permission boundaries clear?
- A02: Cryptographic Failures - are secrets handled correctly?
- A03: Injection - is input handling specified?
- A07: Auth Failures - are auth flows properly designed?

### Severity Rating
For each issue found, rate it:
- CRITICAL: Must fix before proceeding (auth bypass, data exposure)
- HIGH: Must fix before implementation (injection risk, permission gap)
- MEDIUM: Should fix (defense in depth)
- LOW: Nice to have (hardening)

**Blocking rule:** CRITICAL and HIGH issues must be fixed before completing this phase.

**To signal Phase 3 completion:** Output `<promise>PHASE-3-SECURITY-DONE</promise>`
"""


def get_phase_4_prompt(review_file: str) -> str:
    """Generate the Phase 4 (AI-Ready Review) prompt."""
    return f"""## Phase 4: AI-Ready Review

You are now reviewing {review_file} to ensure it's ready for AI implementation.

### Your Persona
Think like a tech lead who manages AI developers. You know how AI developers work - they follow instructions literally, they can hallucinate plausible-sounding implementations, and they work best with unambiguous, explicit instructions.

### What You're Evaluating

**Unambiguous Instructions** (because AI interprets literally)
- Can each instruction be interpreted in only ONE way?
- Are there implicit assumptions that a human would understand but an AI might miss?
- Are "obvious" steps spelled out?

**Hallucination Prevention** (because AI generates plausible-sounding code)
- Are all referenced APIs, functions, and file paths verified to exist?
- Are return types, parameter signatures, and error types specified explicitly?
- Is there anything the AI might "fill in" that should be explicitly stated instead?

**Guard Rails** (because AI needs clear boundaries)
- Is error handling specified explicitly? (Not "handle errors" but "catch ValueError, log with context, return 400")
- Are there explicit boundaries for what to change and what to leave alone?
- Are there known gotchas in the codebase that the AI should be warned about?

**Verifiable Criteria** (because AI needs concrete completion signals)
- Can every completion criterion be checked with code?
- Are there criteria that require subjective judgment? (Rewrite as objective checks)
- Would an AI know, with certainty, whether it has completed each step?

Fix any AI-readiness issues found before completing this phase.

**To signal Phase 4 completion:** Output `<promise>PHASE-4-AI-READY-DONE</promise>`
"""


def get_phase_5_prompt() -> str:
    """Generate the Phase 5 (Goal Alignment) prompt."""
    return """## Phase 5: Goal Alignment Check (The Spirit Test)

Now step back with fresh eyes. This is the final sanity check before implementation begins.

**The Question:** Does this plan still achieve what the human ACTUALLY wanted?

Through technical review and AI-readiness improvements, plans can drift:
- Edge cases get added, but the core goal gets diluted
- Implementation details become more specific, but miss the original intent
- The plan becomes technically correct but spiritually wrong

**How to Check:**
1. Re-read the original Goal section - what did the human ask for?
2. Read through the plan as it now stands - what will actually be delivered?
3. Ask: Would the human look at the result and say 'Yes, this is what I meant'?
4. Check: Did we add so much technical detail that we changed WHAT we're building, not just HOW?

**If the answer is NO** - the plan has drifted from the original intent:
- Do NOT complete the review
- Document specifically how the plan drifted from the original goal
- The plan needs redesign around the ACTUAL goal

**If the answer is YES** - proceed to PM Review.

**To signal Phase 5 completion:** Output `<promise>PHASE-5-GOAL-ALIGN-DONE</promise>`
"""


def get_phase_6_prompt(review_file: str) -> str:
    """Generate the Phase 6 (PM Review) prompt."""
    return f"""## Phase 6: PM Review (Final Organization)

You are now reviewing {review_file} as a senior Project Manager.

### Your Persona
The engineering reviews are complete. Now organize and polish this plan for smooth implementation. You're not changing WHAT we're building - you're ensuring HOW it's presented is clear.

### Your Focus

**Logical Flow**
- Does the plan flow logically from section to section?
- Are implementation steps in a sensible order?
- Would a developer know where to start?

**Clerical Quality**
- Fix typos, grammar, formatting inconsistencies
- Ensure consistent naming throughout
- Verify numbering and bullet points are correct

**Practical Implementation**
- Is there a clear starting point?
- Are dependencies between steps clear?
- Would an implementer get stuck anywhere?

### CRITICAL: NEVER REDUCE SCOPE

This is an organization pass, NOT a scope change. You MUST NOT:
- Remove any requirements, tasks, or deliverables
- Simplify technical specifications
- Delete edge cases or error handling
- Mark anything as "out of scope"

You CAN:
- Reorder items for better flow
- Fix typos and formatting
- Improve wording for clarity
- Add section headers or transitions

**To signal Phase 6 completion:** Output `<promise>PHASE-6-PM-DONE</promise>`

After Phase 6, output `<promise>FULL-REVIEW-DONE</promise>` to complete the full review.
"""


def get_phase_prompt(phase: int, state: dict) -> str:
    """Generate the prompt for a specific phase."""
    review_file = state.get("PLAN_FILE", "")
    # Note: Phase 5 (Goal Alignment) doesn't need review_file
    prompts = {
        2: get_phase_2_prompt(review_file),  # Devil's Advocate
        3: get_phase_3_prompt(review_file),  # Security Review
        4: get_phase_4_prompt(review_file),  # AI-Ready
        5: get_phase_5_prompt(),             # Goal Alignment (no args)
        6: get_phase_6_prompt(review_file),  # PM Review
    }
    return prompts.get(phase, "")


def _handle_no_signal(
    state: dict, prompt: str, current_phase: int, phase_iterations: int, max_iter: int
) -> dict:
    """Handle case when no phase signal is detected - continue current phase."""
    phase_iter_key = f"PHASE_{current_phase}_ITERATIONS"
    phase_iterations += 1
    state[phase_iter_key] = str(phase_iterations)
    current_iteration = int(state.get("CURRENT_ITERATION", "1")) + 1
    state["CURRENT_ITERATION"] = str(current_iteration)
    save_state(state)
    return build_continue_response(
        prompt, current_iteration, max_iter, "full-review", current_phase, phase_iterations
    )


def _handle_wrong_phase_signal(
    state: dict, prompt: str, current_phase: int, detected_phase: int,
    phase_iterations: int, max_iter: int
) -> dict:
    """Handle case when wrong phase signal is detected."""
    phase_iter_key = f"PHASE_{current_phase}_ITERATIONS"
    phase_iterations += 1
    state[phase_iter_key] = str(phase_iterations)
    current_iteration = int(state.get("CURRENT_ITERATION", "1")) + 1
    state["CURRENT_ITERATION"] = str(current_iteration)
    save_state(state)
    log_stderr(
        f"Tim Loop: Wrong phase signal (got phase {detected_phase}, "
        f"expected {current_phase}) - continuing"
    )
    return build_continue_response(
        prompt, current_iteration, max_iter, "full-review", current_phase, phase_iterations
    )


def _handle_early_completion(
    state: dict, prompt: str, current_phase: int, phase_iterations: int, min_iter: int
) -> dict:
    """Handle early phase completion attempt."""
    phase_iter_key = f"PHASE_{current_phase}_ITERATIONS"
    phase_iterations += 1
    state[phase_iter_key] = str(phase_iterations)
    current_iteration = int(state.get("CURRENT_ITERATION", "1")) + 1
    state["CURRENT_ITERATION"] = str(current_iteration)
    save_state(state)
    log_stderr(
        f"Tim Loop: Early phase {current_phase} completion attempt at "
        f"iteration {phase_iterations} (min {min_iter}) - challenging"
    )
    return build_early_phase_completion_challenge(
        prompt, current_phase, phase_iterations, min_iter
    )


def _handle_phase_transition(state: dict, current_phase: int, max_iter: int) -> dict:
    """Handle transition to next phase."""
    next_phase = current_phase + 1
    state["CURRENT_PHASE"] = str(next_phase)
    state[f"PHASE_{next_phase}_ITERATIONS"] = "0"
    current_iteration = int(state.get("CURRENT_ITERATION", "1")) + 1
    state["CURRENT_ITERATION"] = str(current_iteration)
    save_state(state)
    next_phase_prompt = get_phase_prompt(next_phase, state)
    return build_phase_transition_response(
        next_phase_prompt, current_phase, next_phase, current_iteration, max_iter
    )


def handle_full_review_phase(
    state: dict, prompt: str, assistant_text: str
) -> dict | None:
    """Handle phase transitions for full-review mode. Returns response or None."""
    current_phase = int(state.get("CURRENT_PHASE", "1"))
    phase_iter_key = f"PHASE_{current_phase}_ITERATIONS"
    phase_iterations = int(state.get(phase_iter_key, "0"))
    min_iter_key = f"MIN_PHASE_{current_phase}_ITERATIONS"
    min_iterations = int(state.get(min_iter_key, "3"))
    max_iterations = int(state.get("MAX_ITERATIONS", "30"))

    # Check for final completion signal
    final_promise = state.get("COMPLETION_PROMISE", "FULL-REVIEW-DONE")
    if f"<promise>{final_promise}</promise>" in assistant_text:
        if current_phase < 6 or state.get("PHASE_6_COMPLETE") != "true":
            return build_phase_skip_challenge(prompt, current_phase)
        return None  # All phases complete - allow exit

    # Check for phase completion signal
    phase_signal = detect_phase_signal(assistant_text)

    if phase_signal is None:
        return _handle_no_signal(
            state, prompt, current_phase, phase_iterations, max_iterations
        )

    detected_phase, _ = phase_signal

    # Check if signal matches current phase
    if detected_phase != current_phase:
        return _handle_wrong_phase_signal(
            state, prompt, current_phase, detected_phase, phase_iterations, max_iterations
        )

    # Correct phase signal - check minimum iterations
    if phase_iterations < min_iterations:
        return _handle_early_completion(
            state, prompt, current_phase, phase_iterations, min_iterations
        )

    # Phase complete - mark and transition
    state[f"PHASE_{current_phase}_COMPLETE"] = "true"
    log_stderr(f"Tim Loop: Phase {current_phase} complete")

    if current_phase < 6:
        return _handle_phase_transition(state, current_phase, max_iterations)

    # Phase 6 complete - instruct to output final signal
    save_state(state)
    return build_final_completion_instruction(prompt)
