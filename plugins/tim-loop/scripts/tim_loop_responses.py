#!/usr/bin/env python3
"""
Tim Loop Response Builders - Constructs JSON responses for the stop hook.

This module contains functions that build the various response types
returned by the tim-loop hook to control conversation flow.
"""


PHASE_NAMES = {
    1: "Tech Review",
    2: "Devil's Advocate",
    3: "Security Review",
    4: "AI-Ready Review",
    5: "Goal Alignment",
    6: "PM Review",
    7: "User Advocate",
}


def build_continue_response(
    prompt: str,
    iteration: int,
    max_iter: int,
    review_mode: str = "",
    current_phase: int = 0,
    phase_iterations: int = 0,
) -> dict:
    """Build a block response that re-injects the prompt."""
    if review_mode == "full-review" and current_phase > 0:
        # For full-review: show phase context
        phase_name = PHASE_NAMES.get(current_phase, f"Phase {current_phase}")
        guidance = (
            f"PHASE {current_phase} ({phase_name}) - ITERATION {phase_iterations}\n"
            f"(Global iteration {iteration} of {max_iter})\n\n"
            f"Continue your {phase_name} review. Take a fresh pass:\n"
            f"1. Re-read the plan AS IT CURRENTLY EXISTS\n"
            f"2. Evaluate with FRESH EYES - pretend you haven't seen it before\n"
            f"3. Look for issues the previous iteration(s) missed\n"
            f"4. Make improvements if you find any\n\n"
            f"When Phase {current_phase} is complete, output the phase completion signal."
        )
    elif review_mode in ("tech-review", "ai-ready"):
        # For reviews: emphasize fresh pass, finding NEW issues
        guidance = (
            f"ITERATION {iteration} OF {max_iter} - TAKE A FRESH PASS\n\n"
            f"Previous iterations may have improved the plan, but likely missed issues. "
            f"Do NOT assume prior reviews were thorough.\n\n"
            f"Your task for this iteration:\n"
            f"1. Re-read the plan AS IT CURRENTLY EXISTS (it may have changed)\n"
            f"2. Evaluate with FRESH EYES - pretend you haven't seen it before\n"
            f"3. Look for issues the previous iteration(s) missed\n"
            f"4. Make improvements if you find any\n\n"
            f"Output the completion promise ONLY when you genuinely cannot find "
            f"any more ways to improve the plan - not because it was already reviewed."
        )
    else:
        # For implementation: continue working
        guidance = "The task is not yet complete. Continue working on it."

    return {
        "decision": "block",
        "reason": (
            f"Tim Loop: Iteration {iteration} of {max_iter}\n\n"
            f"{guidance}\n\n"
            f"---\n\n{prompt}"
        ),
    }


def build_verification_response(prompt: str, iteration: int, max_iter: int) -> dict:
    """Build a block response when verification is required."""
    return {
        "decision": "block",
        "reason": (
            f"Tim Loop: Iteration {iteration} of {max_iter} (verification required)\n\n"
            f"You output the completion promise but the plan is not verified.\n"
            f"Add <!-- VERIFIED: YES --> after verifying all objectives.\n\n"
            f"---\n\n{prompt}"
        ),
    }


def build_early_completion_challenge(
    prompt: str, iteration: int, max_iter: int, min_iter: int
) -> dict:
    """Build a response challenging early completion in review mode."""
    return {
        "decision": "block",
        "reason": (
            f"Tim Loop: Iteration {iteration} of {max_iter}\n\n"
            f"The human has found that it usually takes ~{min_iter} iterations to discover "
            f"all the ways to improve a plan. You're only on iteration {iteration}.\n\n"
            f"Are you sure you can't find anything else to improve? "
            f"Take another fresh look at the plan - read it from the beginning, "
            f"check each section with fresh eyes. Previous iterations often miss things.\n\n"
            f"If you genuinely cannot find any more improvements after a thorough re-read, "
            f"you may output the completion promise again.\n\n"
            f"---\n\n{prompt}"
        ),
    }


def build_short_output_continue_response(
    prompt: str, iteration: int, max_iter: int
) -> dict:
    """Build a block response when output was too brief to be a real completion."""
    return {
        "decision": "block",
        "reason": (
            f"Tim Loop: Iteration {iteration} of {max_iter} (response too brief - continuing)\n\n"
            f"---\n\n{prompt}"
        ),
    }


def build_phase_transition_response(
    next_phase_prompt: str,
    completed_phase: int,
    next_phase: int,
    iteration: int,
    max_iter: int,
) -> dict:
    """Build response when transitioning between phases."""
    return {
        "decision": "block",
        "reason": (
            f"Tim Loop: Phase {completed_phase} ({PHASE_NAMES[completed_phase]}) COMPLETE\n\n"
            f"Transitioning to Phase {next_phase}: {PHASE_NAMES[next_phase]}\n\n"
            f"(Global iteration {iteration} of {max_iter})\n\n"
            f"---\n\n{next_phase_prompt}"
        ),
    }


def build_early_phase_completion_challenge(
    prompt: str, phase: int, current_iter: int, min_iter: int
) -> dict:
    """Challenge when AI tries to complete a phase too early."""
    phase_name = PHASE_NAMES.get(phase, f"Phase {phase}")
    return {
        "decision": "block",
        "reason": (
            f"Tim Loop: Early Phase {phase} completion attempt\n\n"
            f"You've completed {current_iter} iteration(s) of {phase_name}, "
            f"but the minimum is {min_iter}.\n\n"
            f"Experience shows that {phase_name} typically finds new issues "
            f"on subsequent passes. Take another fresh look:\n\n"
            f"1. Re-read the plan from the beginning with fresh eyes\n"
            f"2. Focus on aspects you might have missed in previous passes\n"
            f"3. If you genuinely find no more improvements, output the "
            f"completion signal again\n\n"
            f"---\n\n{prompt}"
        ),
    }


def build_phase_skip_challenge(prompt: str, current_phase: int) -> dict:
    """Challenge when AI tries to skip directly to final completion."""
    return {
        "decision": "block",
        "reason": (
            f"Tim Loop: Cannot complete full review - still on Phase {current_phase}\n\n"
            f"Full review requires completing all 7 phases in order:\n"
            f"1. Tech Review (`<promise>PHASE-1-TECH-DONE</promise>`)\n"
            f"2. Devil's Advocate (`<promise>PHASE-2-DEVILS-ADVOCATE-DONE</promise>`)\n"
            f"3. Security Review (`<promise>PHASE-3-SECURITY-DONE</promise>`)\n"
            f"4. AI-Ready Review (`<promise>PHASE-4-AI-READY-DONE</promise>`)\n"
            f"5. Goal Alignment (`<promise>PHASE-5-GOAL-ALIGN-DONE</promise>`)\n"
            f"6. PM Review (`<promise>PHASE-6-PM-DONE</promise>`)\n"
            f"7. User Advocate (`<promise>PHASE-7-USER-ADVOCATE-DONE</promise>`)\n\n"
            f"You are on Phase {current_phase}. Complete it first.\n\n"
            f"---\n\n{prompt}"
        ),
    }


def build_final_completion_instruction(prompt: str) -> dict:
    """Instruct AI to output final completion signal after all phases done."""
    return {
        "decision": "block",
        "reason": (
            "Tim Loop: All 7 phases complete!\n\n"
            "Phase 1 (Tech Review): DONE\n"
            "Phase 2 (Devil's Advocate): DONE\n"
            "Phase 3 (Security Review): DONE\n"
            "Phase 4 (AI-Ready Review): DONE\n"
            "Phase 5 (Goal Alignment): DONE\n"
            "Phase 6 (PM Review): DONE\n"
            "Phase 7 (User Advocate): DONE\n\n"
            "You may now output the final completion signal: "
            "`<promise>FULL-REVIEW-DONE</promise>`\n\n"
            f"---\n\n{prompt}"
        ),
    }


def build_full_review_complete_hard_stop(plan_file: str) -> dict:
    """Build HARD STOP response when full-review completes - blocks implementation."""
    return {
        "decision": "block",
        "reason": (
            "═══════════════════════════════════════════════════════════════════\n"
            "                    🛑 FULL REVIEW COMPLETE - HARD STOP 🛑\n"
            "═══════════════════════════════════════════════════════════════════\n\n"
            "The full review process has completed successfully.\n\n"
            f"Plan file: {plan_file}\n\n"
            "╔═══════════════════════════════════════════════════════════════════╗\n"
            "║  ⚠️  IMPLEMENTATION CANNOT PROCEED WITHOUT HUMAN APPROVAL  ⚠️     ║\n"
            "╚═══════════════════════════════════════════════════════════════════╝\n\n"
            "DO NOT:\n"
            "- Start implementing the plan\n"
            "- Make any code changes\n"
            "- Create, edit, or modify any files\n"
            "- Run any commands that change the codebase\n\n"
            "THE SESSION IS NOW BLOCKED.\n\n"
            "To proceed, the HUMAN must:\n"
            "1. Review the plan file\n"
            "2. Explicitly approve implementation by running:\n"
            f"   /tim-loop --implement {plan_file}\n\n"
            "Any attempt to continue work in this session without human approval\n"
            "is a violation of the review process.\n\n"
            "═══════════════════════════════════════════════════════════════════\n"
        ),
    }
