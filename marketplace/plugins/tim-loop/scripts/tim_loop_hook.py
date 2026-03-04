#!/usr/bin/env python3
"""
Tim Loop Hook - Implements iteration for Tim Loop workflow.

This hook is registered as a "Stop" hook in hooks.json and intercepts conversation exit.
It checks if Claude output the completion promise and if the plan is verified.
If not, it blocks completion and re-injects the prompt to continue the loop.

Key fix: This hook now properly handles Claude Code's JSON input format
(receiving transcript_path) and outputs JSON responses (decision: block/allow).
"""

import json
import os
import sys

from tim_loop_context_pressure import (
    PRESSURE_CRITICAL,
    PRESSURE_FORCE_STOP,
    PRESSURE_WARNING,
    check_soft_completion,
    detect_response_degradation,
    get_context_pressure,
    track_response_length,
)
from tim_loop_full_review import handle_full_review_phase
from tim_loop_responses import (
    build_continue_response,
    build_decision_audit_reminder,
    build_early_completion_challenge,
    build_fresh_eyes_review_challenge,
    build_short_output_continue_response,
    build_soft_completion_nudge,
    build_verification_response,
)
from tim_loop_state import (
    cleanup_tim_loop,
    load_state,
    log_stderr,
    save_state,
)
from tim_loop_verification import (
    check_plan_verification,
    get_plan_file,
    handle_force_stop,
    handle_max_iterations,
    write_verification_failure,
)
from transcript_utils import extract_assistant_text, is_agent_coordination_turn, read_transcript


def _check_review_quality_llm(
    state: dict, prompt: str, assistant_text: str,
    current_iteration: int, max_iterations: int
) -> dict | None:
    """Run LLM judge on review quality. Returns challenge response or None if passed."""
    from review_quality_judge import judge_review_quality

    verdict = judge_review_quality(assistant_text)
    if "error" in verdict:
        error_type = verdict["error"]
        detail = verdict["detail"]
        log_stderr(f"Tim Loop: Review quality judge {error_type} - {detail}")
        current_iteration += 1
        state["CURRENT_ITERATION"] = str(current_iteration)
        save_state(state)
        return build_fresh_eyes_review_challenge(
            prompt, current_iteration, max_iterations,
            f"Judge {error_type}: {detail}"
        )
    if not verdict["passed"]:
        log_stderr("Tim Loop: Review quality check FAILED - challenging")
        current_iteration += 1
        state["CURRENT_ITERATION"] = str(current_iteration)
        save_state(state)
        return build_fresh_eyes_review_challenge(
            prompt, current_iteration, max_iterations, verdict["reason"]
        )
    log_stderr("Tim Loop: Review quality check PASSED")
    return None


def _challenge_review_completion(
    state: dict, prompt: str, assistant_text: str
) -> dict | None:
    """Challenge early completion in review modes. Returns response or None to proceed."""
    current_iteration = int(state.get("CURRENT_ITERATION", "1"))
    max_iterations = int(state.get("MAX_ITERATIONS", "30"))
    min_review_iterations = int(state.get("MIN_REVIEW_ITERATIONS", "5"))
    llm_loop = state.get("LLM_LOOP") == "true"

    if llm_loop:
        result = _check_review_quality_llm(
            state, prompt, assistant_text, current_iteration, max_iterations
        )
        if result is not None:
            return result
        return None  # Judge passed
    if current_iteration < min_review_iterations:
        log_stderr(
            f"Tim Loop: Early completion attempt at iteration {current_iteration} "
            f"(minimum {min_review_iterations}) - challenging"
        )
        current_iteration += 1
        state["CURRENT_ITERATION"] = str(current_iteration)
        save_state(state)
        return build_early_completion_challenge(
            prompt, current_iteration, max_iterations, min_review_iterations
        )
    return None


def handle_completion_promise(
    state: dict, prompt: str, assistant_text: str, pressure: int = 0,
) -> dict | None:
    """Handle case when completion promise is found. Returns response or None."""
    state_file = state.get("_state_file", "")
    prompt_file = state.get("TIM_LOOP_PROMPT_FILE", "")
    current_iteration = int(state.get("CURRENT_ITERATION", "1"))
    max_iterations = int(state.get("MAX_ITERATIONS", "30"))
    review_mode = state.get("REVIEW_MODE", "")

    if review_mode in ("tech-review", "ai-ready"):
        challenge = _challenge_review_completion(state, prompt, assistant_text)
        if challenge is not None:
            return challenge

    # Decision audit enforcement for review/plan modes
    plan_only = state.get("PLAN_ONLY") == "true"
    if review_mode in ("tech-review", "ai-ready", "pm-review") or plan_only:
        if "DECISION AUDIT:" not in assistant_text:
            log_stderr("Tim Loop: BLOCKED - Missing DECISION AUDIT marker")
            current_iteration += 1
            state["CURRENT_ITERATION"] = str(current_iteration)
            save_state(state)
            return build_decision_audit_reminder(
                prompt, current_iteration, max_iterations, review_mode, pressure,
            )

    plan_file = get_plan_file(state, prompt)
    verification = check_plan_verification(plan_file)

    if verification == "FAILED":
        cleanup_tim_loop(
            "Tim Loop: BLOCKED - Verification failed", state_file, prompt_file
        )
        return {}

    if verification == "NOT_VERIFIED":
        log_stderr("Tim Loop: BLOCKED - Plan not verified as 100% complete")
        current_iteration += 1
        state["CURRENT_ITERATION"] = str(current_iteration)
        save_state(state)
        return build_verification_response(
            prompt, current_iteration, max_iterations, pressure,
        )

    cleanup_tim_loop("Tim Loop: Task complete", state_file, prompt_file)
    return {}


def handle_continue_loop(
    state: dict, prompt: str, pressure: int = 0,
) -> dict:
    """Handle case when completion promise is NOT found - continue loop."""
    # Reset short output counter since we got a normal response
    state["SHORT_OUTPUT_COUNT"] = "0"
    current_iteration = int(state.get("CURRENT_ITERATION", "1")) + 1
    max_iterations = int(state.get("MAX_ITERATIONS", "30"))
    review_mode = state.get("REVIEW_MODE", "")

    if current_iteration >= max_iterations:
        return handle_max_iterations(state, max_iterations)

    state["CURRENT_ITERATION"] = str(current_iteration)
    save_state(state)
    log_stderr(f"Tim Loop: Iteration {current_iteration} of {max_iterations}")
    return build_continue_response(
        prompt, current_iteration, max_iterations, review_mode, pressure=pressure,
    )


def handle_short_output(state: dict, prompt: str, assistant_text: str) -> dict | None:
    """Handle short or empty output. Returns response dict or None to allow exit."""
    state_file = state.get("_state_file", "")
    prompt_file = state.get("TIM_LOOP_PROMPT_FILE", "")
    plan_file = state.get("PLAN_FILE", "")
    verification_status = check_plan_verification(plan_file)

    if verification_status is None:
        cleanup_tim_loop("Tim Loop: Session ended (plan verified)", state_file, prompt_file)
        return None

    # Not verified - check if this looks like user interrupt (no output at all)
    if not assistant_text:
        cleanup_tim_loop(
            f"Tim Loop: Session interrupted. Plan not verified ({verification_status}).\n"
            f"Run: /tim-loop --verify {plan_file}",
            state_file,
            prompt_file,
        )
        return None

    # Short output but some content - continue loop with counter
    current_iteration = int(state.get("CURRENT_ITERATION", "1")) + 1
    max_iterations = int(state.get("MAX_ITERATIONS", "30"))
    short_output_count = int(state.get("SHORT_OUTPUT_COUNT", "0")) + 1

    if short_output_count >= 3:
        # Too many short outputs - something is wrong
        if verification_status != "PLAN_FILE_MISSING":
            write_verification_failure(
                plan_file,
                f"Session stuck (repeated brief responses). Status: {verification_status}",
            )
        cleanup_tim_loop(
            f"Tim Loop: Session appears stuck (repeated brief responses). "
            f"Plan not verified ({verification_status}).\n"
            f"Run: /tim-loop --verify {plan_file}",
            state_file,
            prompt_file,
        )
        return None

    state["CURRENT_ITERATION"] = str(current_iteration)
    state["SHORT_OUTPUT_COUNT"] = str(short_output_count)
    save_state(state)
    return build_short_output_continue_response(prompt, current_iteration, max_iterations)


def load_prompt_from_state(state: dict) -> str | None:
    """Load prompt file content. Returns None if unavailable."""
    prompt_file_path = state.get("TIM_LOOP_PROMPT_FILE", "")
    if not prompt_file_path or not os.path.isfile(prompt_file_path):
        return None
    try:
        with open(prompt_file_path, "r") as f:
            return f.read()
    except Exception:
        return ""


def read_hook_input() -> dict:
    """Read and parse hook input from stdin."""
    try:
        return json.load(sys.stdin)
    except json.JSONDecodeError:
        return {}


def process_assistant_output(state: dict, prompt: str, assistant_text: str) -> dict:
    """Process assistant output and determine response."""
    review_mode = state.get("REVIEW_MODE", "")

    # Context pressure detection
    track_response_length(state, assistant_text)
    pressure = get_context_pressure(state)

    if pressure >= PRESSURE_FORCE_STOP:
        log_stderr("Tim Loop: FORCE STOP — context pressure at maximum")
        return handle_force_stop(state)

    # Escalate WARNING to CRITICAL if response degradation detected
    if pressure == PRESSURE_WARNING and detect_response_degradation(state):
        log_stderr("Tim Loop: Response degradation detected — escalating to CRITICAL")
        pressure = PRESSURE_CRITICAL

    # Full-review mode has its own phase-based handling
    if review_mode == "full-review":
        response = handle_full_review_phase(state, prompt, assistant_text, pressure)
        if response is not None:
            return response
        # response is None means all phases complete, fall through to normal completion

    completion_promise = state.get("COMPLETION_PROMISE", "COMPLETE")
    promise_tag = f"<promise>{completion_promise}</promise>"

    if promise_tag in assistant_text:
        return handle_completion_promise(state, prompt, assistant_text, pressure) or {}

    # Check for soft completion before full re-injection
    if check_soft_completion(assistant_text, review_mode):
        current_iteration = int(state.get("CURRENT_ITERATION", "1"))
        max_iterations = int(state.get("MAX_ITERATIONS", "30"))
        log_stderr("Tim Loop: Soft completion detected — sending nudge instead of full re-injection")
        current_iteration += 1
        state["CURRENT_ITERATION"] = str(current_iteration)
        save_state(state)
        return build_soft_completion_nudge(current_iteration, max_iterations, review_mode)

    return handle_continue_loop(state, prompt, pressure)


def main() -> None:
    """Main hook entry point."""
    state = load_state()
    if not state:
        log_stderr("Tim Loop: Stop hook could not load session state - allowing exit")
        print("{}")
        sys.exit(0)

    prompt = load_prompt_from_state(state)
    if prompt is None:
        log_stderr(f"Tim Loop: Prompt file missing (session {state.get('SESSION_ID', '?')})")
        print("{}")
        sys.exit(0)

    hook_input = read_hook_input()
    if hook_input.get("stop_hook_active"):
        print("{}")
        sys.exit(0)

    transcript_path = hook_input.get("transcript_path", "")
    transcript = read_transcript(transcript_path) if transcript_path else []
    assistant_text = extract_assistant_text(transcript)

    if is_agent_coordination_turn(transcript):
        log_stderr("Tim Loop: Agent coordination turn — skipping iteration")
        print(json.dumps({"decision": "block", "reason": "Continue processing."}))
        sys.exit(0)

    if not assistant_text or len(assistant_text.strip()) < 20:
        response = handle_short_output(state, prompt, assistant_text)
        print(json.dumps(response) if response else "{}")
        sys.exit(0)

    response = process_assistant_output(state, prompt, assistant_text)
    print(json.dumps(response))
    sys.exit(0)


if __name__ == "__main__":
    main()
