#!/usr/bin/env python3
"""
Tim Loop Full Review - Handles per-phase iteration tracking for full-review mode.

This module contains the phase transition logic and signal detection for the
7-phase full review process:
- Phase 1: Tech Review (min 5 iterations)
- Phase 2: Devil's Advocate (min 2 iterations)
- Phase 3: Security Review (min 2 iterations)
- Phase 4: AI-Ready Review (min 2 iterations)
- Phase 5: Goal Alignment (min 1 iteration)
- Phase 6: PM Review (min 1 iteration)
- Phase 7: User Advocate (min 1 iteration)
"""

from tim_loop_phase_prompts import get_phase_prompt
from tim_loop_phase_responses import (
    build_early_phase_completion_challenge,
    build_final_completion_instruction,
    build_fresh_eyes_phase_challenge,
    build_full_review_complete_hard_stop,
    build_phase_correction_response,
    build_phase_skip_challenge,
    build_phase_transition_response,
)
from tim_loop_responses import build_continue_response
from tim_loop_state import cleanup_tim_loop, log_stderr, save_state

# Phase signals for full-review mode
PHASE_SIGNALS = {
    1: "PHASE-1-TECH-DONE",
    2: "PHASE-2-DEVILS-ADVOCATE-DONE",
    3: "PHASE-3-SECURITY-DONE",
    4: "PHASE-4-AI-READY-DONE",
    5: "PHASE-5-GOAL-ALIGN-DONE",
    6: "PHASE-6-PM-DONE",
    7: "PHASE-7-USER-ADVOCATE-DONE",
}

# Minimum iterations per phase
MIN_PHASE_ITERATIONS = {
    1: 5,  # Tech Review - thorough analysis needed
    2: 2,  # Devil's Advocate
    3: 2,  # Security Review
    4: 2,  # AI-Ready
    5: 1,  # Goal Alignment
    6: 1,  # PM Review
    7: 1,  # User Advocate - final decision audit
}

FINAL_PHASE = 7


def _all_phase_signals_present(text: str) -> bool:
    """Check if ALL 7 phase completion signals exist in the assistant text."""
    return all(
        f"<promise>{signal}</promise>" in text
        for signal in PHASE_SIGNALS.values()
    )


def detect_phase_signal(assistant_text: str) -> tuple[int, str] | None:
    """Detect phase completion signal. Returns (phase_num, signal) or None."""
    for phase, signal in PHASE_SIGNALS.items():
        if f"<promise>{signal}</promise>" in assistant_text:
            return (phase, signal)
    return None


def _handle_no_signal(
    state: dict, prompt: str, current_phase: int, phase_iterations: int, max_iter: int,
    pressure: int = 0,
) -> dict:
    """Handle case when no phase signal is detected - continue current phase."""
    phase_iter_key = f"PHASE_{current_phase}_ITERATIONS"
    phase_iterations += 1
    state[phase_iter_key] = str(phase_iterations)
    current_iteration = int(state.get("CURRENT_ITERATION", "1")) + 1
    state["CURRENT_ITERATION"] = str(current_iteration)
    save_state(state)
    return build_continue_response(
        prompt, current_iteration, max_iter, "full-review", current_phase, phase_iterations,
        pressure,
    )


def _handle_wrong_phase_signal(
    state: dict, prompt: str, current_phase: int, detected_phase: int,
    phase_iterations: int, max_iter: int, pressure: int = 0,
) -> dict:
    """Handle case when wrong phase signal is detected."""
    phase_iter_key = f"PHASE_{current_phase}_ITERATIONS"
    phase_iterations += 1
    state[phase_iter_key] = str(phase_iterations)
    current_iteration = int(state.get("CURRENT_ITERATION", "1")) + 1
    state["CURRENT_ITERATION"] = str(current_iteration)
    save_state(state)
    # Stale signal (already-completed phase): inject correct phase prompt
    if detected_phase < current_phase:
        log_stderr(
            f"Tim Loop: Stale phase signal (got phase {detected_phase}, "
            f"on phase {current_phase}) - injecting correct phase prompt"
        )
        review_file = state.get("PLAN_FILE", "")
        phase_prompt = get_phase_prompt(current_phase, review_file)
        return build_phase_correction_response(
            phase_prompt, detected_phase, current_phase, current_iteration, max_iter
        )
    # Forward skip (future phase): continue with generic guidance
    log_stderr(
        f"Tim Loop: Wrong phase signal (got phase {detected_phase}, "
        f"expected {current_phase}) - continuing"
    )
    return build_continue_response(
        prompt, current_iteration, max_iter, "full-review", current_phase, phase_iterations,
        pressure,
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
    review_file = state.get("PLAN_FILE", "")
    next_phase_prompt = get_phase_prompt(next_phase, review_file)
    return build_phase_transition_response(
        next_phase_prompt, current_phase, next_phase, current_iteration, max_iter
    )


def _check_final_signal(state: dict, prompt: str, text: str, phase: int) -> dict | None:
    """Check for final completion signal. Returns response, or None to continue."""
    final_promise = state.get("COMPLETION_PROMISE", "FULL-REVIEW-DONE")
    if f"<promise>{final_promise}</promise>" not in text:
        return None  # No final signal - continue normal processing
    if phase < FINAL_PHASE or state.get(f"PHASE_{FINAL_PHASE}_COMPLETE") != "true":
        # Before rejecting, check if all 7 phase signals are in the text.
        # After context compaction, the agent may have completed all phases in
        # a single turn, so the stop hook never processed intermediate transitions.
        if _all_phase_signals_present(text):
            log_stderr(
                "Tim Loop: Fast-forwarding phase state — all 7 phase signals "
                "found in assistant text (likely post-compaction recovery)"
            )
            for p in range(1, FINAL_PHASE + 1):
                state[f"PHASE_{p}_COMPLETE"] = "true"
            state["CURRENT_PHASE"] = str(FINAL_PHASE)
            save_state(state)
        else:
            return build_phase_skip_challenge(prompt, phase)
    # All phases complete - return HARD STOP to block implementation
    plan_file = state.get("PLAN_FILE", "the plan file")
    return {"hard_stop": True, "plan_file": plan_file}


def _handle_hard_stop(state: dict, final_result: dict) -> dict:
    """Handle full review complete - clean up state, return HARD STOP response.

    Must clean up state so the hook doesn't re-fire on subsequent turns
    in the same session (e.g. the user asking unrelated questions).
    """
    log_stderr("Tim Loop: Full review complete - HARD STOP (requires human approval)")
    state_file = state.get("_state_file", "")
    prompt_file = state.get("TIM_LOOP_PROMPT_FILE", "")
    cleanup_tim_loop("Tim Loop: Full review complete — cleaning up state", state_file, prompt_file)
    plan_file = final_result.get("plan_file", "the plan file")
    return build_full_review_complete_hard_stop(plan_file)


def _handle_quality_failure(
    state: dict, prompt: str, current_phase: int,
    phase_iterations: int, judge_reason: str
) -> dict:
    """Handle LLM judge quality failure for a phase review."""
    phase_iter_key = f"PHASE_{current_phase}_ITERATIONS"
    phase_iterations += 1
    state[phase_iter_key] = str(phase_iterations)
    current_iteration = int(state.get("CURRENT_ITERATION", "1")) + 1
    state["CURRENT_ITERATION"] = str(current_iteration)
    save_state(state)
    log_stderr(f"Tim Loop: Phase {current_phase} review quality check FAILED - challenging")
    return build_fresh_eyes_phase_challenge(
        prompt, current_phase, phase_iterations, judge_reason
    )


def _check_phase_quality_llm(
    state: dict, prompt: str, assistant_text: str,
    current_phase: int, phase_iterations: int
) -> dict | None:
    """Run LLM judge on phase review quality. Returns challenge or None if passed."""
    from review_quality_judge import judge_review_quality

    verdict = judge_review_quality(assistant_text)
    if "error" in verdict:
        error_type = verdict["error"]
        detail = verdict["detail"]
        log_stderr(f"Tim Loop: Phase {current_phase} judge {error_type} - {detail}")
        return _handle_quality_failure(
            state, prompt, current_phase, phase_iterations,
            f"Judge {error_type}: {detail}"
        )
    if not verdict["passed"]:
        return _handle_quality_failure(
            state, prompt, current_phase, phase_iterations, verdict["reason"]
        )
    log_stderr(f"Tim Loop: Phase {current_phase} review quality check PASSED")
    return None


def _handle_phase_signal(
    state: dict, prompt: str, assistant_text: str, phase_signal: tuple[int, str],
    current_phase: int, phase_iterations: int, min_iterations: int, max_iterations: int,
    pressure: int = 0,
) -> dict:
    """Handle detected phase signal - validate and process."""
    detected_phase, _ = phase_signal
    if detected_phase != current_phase:
        return _handle_wrong_phase_signal(
            state, prompt, current_phase, detected_phase, phase_iterations, max_iterations,
            pressure,
        )

    llm_loop = state.get("LLM_LOOP") == "true"
    if llm_loop:
        result = _check_phase_quality_llm(
            state, prompt, assistant_text, current_phase, phase_iterations
        )
        if result is not None:
            return result
    elif phase_iterations < min_iterations:
        return _handle_early_completion(
            state, prompt, current_phase, phase_iterations, min_iterations
        )

    # Phase complete - mark and transition
    state[f"PHASE_{current_phase}_COMPLETE"] = "true"
    log_stderr(f"Tim Loop: Phase {current_phase} complete")
    if current_phase < FINAL_PHASE:
        return _handle_phase_transition(state, current_phase, max_iterations)
    save_state(state)
    return build_final_completion_instruction(prompt)


def handle_full_review_phase(
    state: dict, prompt: str, assistant_text: str, pressure: int = 0,
) -> dict | None:
    """Handle phase transitions for full-review mode. Returns response or None."""
    current_phase = int(state.get("CURRENT_PHASE", "1"))
    phase_iterations = int(state.get(f"PHASE_{current_phase}_ITERATIONS", "0"))
    min_iterations = int(state.get(f"MIN_PHASE_{current_phase}_ITERATIONS", "3"))
    max_iterations = int(state.get("MAX_ITERATIONS", "30"))

    # Check for final completion signal first
    final_result = _check_final_signal(state, prompt, assistant_text, current_phase)
    if final_result is not None:
        if final_result.get("hard_stop"):
            return _handle_hard_stop(state, final_result)
        return final_result

    # Check for phase completion signal
    phase_signal = detect_phase_signal(assistant_text)
    if phase_signal is None:
        return _handle_no_signal(
            state, prompt, current_phase, phase_iterations, max_iterations, pressure,
        )

    return _handle_phase_signal(
        state, prompt, assistant_text, phase_signal,
        current_phase, phase_iterations, min_iterations, max_iterations, pressure,
    )
