#!/usr/bin/env python3
"""
Tim Loop Phase Response Builders - Full-review phase-specific responses.

This module contains response builders used exclusively by the 7-phase
full-review process: phase transitions, phase challenges, phase corrections,
and the final hard stop.
"""

from tim_loop_responses import PHASE_NAMES, _block_response, _prompt_or_compact


def build_phase_transition_response(
    next_phase_prompt: str,
    completed_phase: int,
    next_phase: int,
    iteration: int,
    max_iter: int,
) -> dict:
    """Build response when transitioning between phases."""
    return _block_response(
        (
            f"Tim Loop: Phase {completed_phase} COMPLETE | "
            f"Transitioning to Phase {next_phase} "
            f"(iteration {iteration} of {max_iter})"
        ),
        (
            f"Phase {completed_phase} ({PHASE_NAMES[completed_phase]}) is complete.\n\n"
            f"Transitioning to Phase {next_phase}: {PHASE_NAMES[next_phase]}\n\n"
            f"---\n\n{next_phase_prompt}"
        ),
    )


def build_early_phase_completion_challenge(
    prompt: str, phase: int, current_iter: int, min_iter: int,
    is_first_in_phase: bool = False, pressure: int = 0,
) -> dict:
    """Challenge when AI tries to complete a phase too early."""
    phase_name = PHASE_NAMES.get(phase, f"Phase {phase}")
    return _block_response(
        f"Tim Loop: Phase {phase} ({phase_name}) - review not thorough enough",
        (
            f"You've done {current_iter} pass(es) but plans consistently have "
            f"{phase_name} issues that aren't caught until pass {min_iter}+.\n\n"
            f"This is not about reaching a pass count. Do a COMPLETE {phase_name} "
            f"review right now as if it's your only chance:\n\n"
            f"1. Re-read the ENTIRE plan from the top\n"
            f"2. Evaluate EVERY section for {phase_name} concerns\n"
            f"3. Fix everything you find - do not save issues for later\n\n"
            f"{_prompt_or_compact(prompt, is_first_in_phase, pressure=pressure)}"
        ),
    )


def build_phase_skip_challenge(
    prompt: str, current_phase: int,
    is_first_in_phase: bool = False, pressure: int = 0,
) -> dict:
    """Challenge when AI tries to skip directly to final completion."""
    return _block_response(
        f"Tim Loop: Cannot complete full review - still on Phase {current_phase}",
        (
            f"Full review requires completing all 7 phases in order:\n"
            f"1. Tech Review (`<promise>PHASE-1-TECH-DONE</promise>`)\n"
            f"2. Devil's Advocate (`<promise>PHASE-2-DEVILS-ADVOCATE-DONE</promise>`)\n"
            f"3. Security Review (`<promise>PHASE-3-SECURITY-DONE</promise>`)\n"
            f"4. AI-Ready Review (`<promise>PHASE-4-AI-READY-DONE</promise>`)\n"
            f"5. Goal Alignment (`<promise>PHASE-5-GOAL-ALIGN-DONE</promise>`)\n"
            f"6. PM Review (`<promise>PHASE-6-PM-DONE</promise>`)\n"
            f"7. User Advocate (`<promise>PHASE-7-USER-ADVOCATE-DONE</promise>`)\n\n"
            f"You are on Phase {current_phase}. Complete it first.\n\n"
            f"{_prompt_or_compact(prompt, is_first_in_phase, pressure=pressure)}"
        ),
    )


def build_final_completion_instruction(
    prompt: str,
    is_first_in_phase: bool = False, pressure: int = 0,
) -> dict:
    """Instruct AI to output final completion signal after all phases done."""
    return _block_response(
        "Tim Loop: All 7 phases complete!",
        (
            "Phase 1 (Tech Review): DONE\n"
            "Phase 2 (Devil's Advocate): DONE\n"
            "Phase 3 (Security Review): DONE\n"
            "Phase 4 (AI-Ready Review): DONE\n"
            "Phase 5 (Goal Alignment): DONE\n"
            "Phase 6 (PM Review): DONE\n"
            "Phase 7 (User Advocate): DONE\n\n"
            "You may now output the final completion signal: "
            "`<promise>FULL-REVIEW-DONE</promise>`\n\n"
            f"{_prompt_or_compact(prompt, is_first_in_phase, pressure=pressure)}"
        ),
    )


def build_fresh_eyes_phase_challenge(
    prompt: str, phase: int, current_iter: int, judge_reason: str,
    is_first_in_phase: bool = False, pressure: int = 0,
) -> dict:
    """Build response when LLM judge finds a phase review superficial (full-review mode)."""
    phase_name = PHASE_NAMES.get(phase, f"Phase {phase}")
    reason_excerpt = judge_reason[:300].rstrip()
    return _block_response(
        f"Tim Loop: Phase {phase} ({phase_name}) - review quality check FAILED (pass {current_iter})",
        (
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
            f"{_prompt_or_compact(prompt, is_first_in_phase, pressure=pressure)}"
        ),
    )


def build_phase_correction_response(
    phase_prompt: str,
    detected_phase: int,
    current_phase: int,
    iteration: int,
    max_iter: int,
) -> dict:
    """Build response correcting the agent to the right phase after a stale signal."""
    detected_name = PHASE_NAMES.get(detected_phase, f"Phase {detected_phase}")
    current_name = PHASE_NAMES.get(current_phase, f"Phase {current_phase}")
    return _block_response(
        f"Tim Loop: PHASE CORRECTION (iteration {iteration} of {max_iter})",
        (
            f"You output a Phase {detected_phase} ({detected_name}) signal, but you "
            f"are on Phase {current_phase} ({current_name}). The Phase {detected_phase} "
            f"signal is stale — that phase was already completed.\n\n"
            f"Here are your Phase {current_phase} instructions:\n\n"
            f"---\n\n{phase_prompt}"
        ),
    )


def build_full_review_complete_hard_stop(plan_file: str) -> dict:
    """Build HARD STOP response when full-review completes - blocks implementation."""
    return _block_response(
        "Tim Loop: FULL REVIEW COMPLETE - HARD STOP",
        (
            "═══════════════════════════════════════════════════════════════════\n"
            "                    FULL REVIEW COMPLETE - HARD STOP\n"
            "═══════════════════════════════════════════════════════════════════\n\n"
            "The full review process has completed successfully.\n\n"
            f"Plan file: {plan_file}\n\n"
            "IMPLEMENTATION CANNOT PROCEED WITHOUT HUMAN APPROVAL\n\n"
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
    )
