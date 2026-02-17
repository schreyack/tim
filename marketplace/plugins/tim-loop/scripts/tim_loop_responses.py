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


def _full_review_guidance(
    current_phase: int, phase_iterations: int, iteration: int, max_iter: int
) -> str:
    """Build guidance for full-review phase continuation."""
    phase_name = PHASE_NAMES.get(current_phase, f"Phase {current_phase}")
    return (
        f"PHASE {current_phase} ({phase_name}) - REVIEW PASS (iteration {phase_iterations})\n"
        f"(Global iteration {iteration} of {max_iter})\n\n"
        f"DO A COMPLETE {phase_name} review NOW - as if this is your only chance.\n"
        f"Do NOT pace yourself or save issues for later passes.\n\n"
        f"1. Re-read the ENTIRE plan from the top\n"
        f"2. Evaluate EVERY section thoroughly for this phase's concerns\n"
        f"3. Fix everything you find. Do not leave known issues for a future pass\n"
        f"4. Verify file references, API calls, and assumptions against the actual codebase\n\n"
        f"When Phase {current_phase} is genuinely complete, output the phase completion signal."
    )


def _standalone_review_guidance(iteration: int) -> str:
    """Build guidance for standalone tech-review or ai-ready continuation."""
    return (
        f"REVIEW PASS (iteration {iteration})\n\n"
        f"DO A COMPLETE REVIEW NOW - as if this is your only chance to review "
        f"this plan. Do NOT pace yourself or save issues for later passes.\n\n"
        f"The loop re-runs you because even thorough reviews miss things on "
        f"each pass - NOT to give you multiple passes to divide the work across. "
        f"Every pass should be a full, exhaustive review.\n\n"
        f"Your task:\n"
        f"1. Re-read the ENTIRE plan from the top\n"
        f"2. Evaluate EVERY section thoroughly - technical accuracy, edge cases, "
        f"feasibility, testability, completeness\n"
        f"3. Fix everything you find. Do not leave known issues for a future pass\n"
        f"4. Verify file references, API calls, and assumptions against the actual codebase\n\n"
        f"If you find nothing to improve after an exhaustive re-read, output the "
        f"completion promise. But 'I already reviewed this' is not the same as "
        f"'I re-read every section and found nothing new.'"
    )


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
        guidance = _full_review_guidance(current_phase, phase_iterations, iteration, max_iter)
    elif review_mode in ("tech-review", "ai-ready"):
        guidance = _standalone_review_guidance(iteration)
    else:
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
            f"Your review was not thorough enough. Plans consistently have issues "
            f"that aren't caught until pass {min_iter}+. You're on pass {iteration}.\n\n"
            f"This is not about reaching a pass count - it's about doing a genuinely "
            f"exhaustive review. Go back and re-read EVERY section of the plan from "
            f"the top. Check every file reference against the codebase. Verify every "
            f"API assumption. Tighten every vague criterion.\n\n"
            f"If after that exhaustive re-read you truly find nothing, output the "
            f"completion promise again.\n\n"
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
            f"Tim Loop: Phase {phase} ({phase_name}) - review not thorough enough\n\n"
            f"You've done {current_iter} pass(es) but plans consistently have "
            f"{phase_name} issues that aren't caught until pass {min_iter}+.\n\n"
            f"This is not about reaching a pass count. Do a COMPLETE {phase_name} "
            f"review right now as if it's your only chance:\n\n"
            f"1. Re-read the ENTIRE plan from the top\n"
            f"2. Evaluate EVERY section for {phase_name} concerns\n"
            f"3. Fix everything you find - do not save issues for later\n\n"
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


def build_fresh_eyes_review_challenge(
    prompt: str, iteration: int, max_iter: int, judge_reason: str
) -> dict:
    """Build response when LLM judge finds a review superficial (standalone review modes)."""
    # Truncate judge reason to keep prompt reasonable
    reason_excerpt = judge_reason[:300].rstrip()
    return {
        "decision": "block",
        "reason": (
            f"Tim Loop: Iteration {iteration} of {max_iter} "
            f"(review quality check FAILED)\n\n"
            f"**Judge assessment:** {reason_excerpt}\n\n"
            f"---\n\n"
            f"Clear your mind completely. You are a DIFFERENT reviewer seeing this "
            f"plan for the FIRST time.\n\n"
            f"1. Read the plan from line one\n"
            f"2. Verify specific claims against the actual codebase\n"
            f"3. Fix any issues you find\n"
            f"4. If nothing is found, explain exactly what you examined and why "
            f"it's sound\n\n"
            f"Do not reference your previous review. This is a clean-slate "
            f"evaluation.\n\n"
            f"---\n\n{prompt}"
        ),
    }


def build_fresh_eyes_phase_challenge(
    prompt: str, phase: int, current_iter: int, judge_reason: str
) -> dict:
    """Build response when LLM judge finds a phase review superficial (full-review mode)."""
    phase_name = PHASE_NAMES.get(phase, f"Phase {phase}")
    reason_excerpt = judge_reason[:300].rstrip()
    return {
        "decision": "block",
        "reason": (
            f"Tim Loop: Phase {phase} ({phase_name}) - "
            f"review quality check FAILED (pass {current_iter})\n\n"
            f"**Judge assessment:** {reason_excerpt}\n\n"
            f"---\n\n"
            f"Clear your mind completely. You are a DIFFERENT {phase_name} reviewer "
            f"seeing this plan for the FIRST time.\n\n"
            f"1. Read the plan from line one\n"
            f"2. Evaluate EVERY section for {phase_name} concerns\n"
            f"3. Verify claims against the actual codebase\n"
            f"4. Fix any issues you find\n"
            f"5. If nothing is found, explain exactly what you examined and why "
            f"it's sound\n\n"
            f"Do not reference your previous review. This is a clean-slate "
            f"evaluation.\n\n"
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
