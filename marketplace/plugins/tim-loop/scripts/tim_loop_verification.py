#!/usr/bin/env python3
"""
Tim Loop Verification - Plan verification and force-stop handling.

This module contains functions for checking plan verification status,
writing failure markers, and handling context exhaustion shutdowns.
"""

import os
import re
from datetime import datetime

from tim_loop_state import cleanup_tim_loop, log_message, log_stderr


def get_plan_file(state: dict, prompt: str) -> str:
    """Get plan file path from state or prompt."""
    plan_file = state.get("PLAN_FILE", "")
    if not plan_file and prompt:
        match = re.search(r"Plan File:\s*(\S+)", prompt)
        if match:
            plan_file = match.group(1)
    return plan_file


def check_plan_verification(plan_file: str) -> str | None:
    """Check plan verification status. Returns error message or None if verified."""
    if not plan_file:
        return None  # No plan specified - verification not applicable (e.g., review mode)
    if not os.path.isfile(plan_file):
        return "PLAN_FILE_MISSING"  # Plan was specified but doesn't exist - FAILURE
    try:
        with open(plan_file, "r") as f:
            content = f.read()
        if "<!-- VERIFIED: FAILED -->" in content:
            return "FAILED"
        if "<!-- VERIFIED: YES -->" not in content:
            return "NOT_VERIFIED"
        return None  # Verified
    except Exception:
        return None


def write_verification_failure(plan_file: str, reason: str) -> None:
    """Write verification failure marker to plan file."""
    if not plan_file or not os.path.isfile(plan_file):
        return
    try:
        with open(plan_file, "r") as f:
            content = f.read()

        # Don't double-write failure markers
        if "<!-- VERIFIED: FAILED -->" in content:
            return

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        failure_block = (
            f"\n\n<!-- VERIFIED: FAILED -->\n"
            f"<!-- FAILURE_REASON: {reason} -->\n"
            f"<!-- FAILURE_TIME: {timestamp} -->\n"
        )

        with open(plan_file, "a") as f:
            f.write(failure_block)

        log_message(f"Wrote verification failure to {plan_file}: {reason}")
    except Exception as e:
        log_message(f"Failed to write verification failure: {e}")


def handle_force_stop(state: dict) -> dict:
    """Graceful shutdown when context is exhausted (FORCE_STOP pressure).

    Checks plan verification first — if verified, clean exit. Otherwise
    writes a failure marker with remediation instructions.
    """
    state_file = state.get("_state_file", "")
    prompt_file = state.get("TIM_LOOP_PROMPT_FILE", "")
    plan_file = get_plan_file(state, "")
    verification = check_plan_verification(plan_file)
    iteration = state.get("CURRENT_ITERATION", "?")

    if verification is None:
        # Plan is verified — clean exit despite context exhaustion
        cleanup_tim_loop(
            f"Tim Loop: Context exhausted at iteration {iteration} but plan is verified — clean exit",
            state_file, prompt_file,
        )
        return {}

    # Not verified — write failure and exit with remediation
    if plan_file and verification != "PLAN_FILE_MISSING":
        write_verification_failure(
            plan_file,
            f"Context exhausted (force-stop) at iteration {iteration}. "
            f"Status: {verification}",
        )
    cleanup_tim_loop(
        f"Tim Loop: FORCE STOP — Context exhausted at iteration {iteration}.\n"
        f"Plan not verified ({verification}). Too many context compactions.\n"
        f"Run: /tim-loop --verify {plan_file}" if plan_file else
        f"Tim Loop: FORCE STOP — Context exhausted at iteration {iteration}.",
        state_file, prompt_file,
    )
    return {}


def handle_max_iterations(state: dict, max_iterations: int) -> dict:
    """Handle max iterations reached - check verification before exiting."""
    state_file = state.get("_state_file", "")
    prompt_file = state.get("TIM_LOOP_PROMPT_FILE", "")
    plan_file = state.get("PLAN_FILE", "")
    verification_status = check_plan_verification(plan_file)

    if verification_status is None:
        # Plan is verified - clean exit
        cleanup_tim_loop(
            f"Tim Loop: Completed after {max_iterations} iterations (verified)",
            state_file,
            prompt_file,
        )
        return {}

    # NOT verified - write failure and create remediation notice
    if verification_status == "PLAN_FILE_MISSING":
        cleanup_tim_loop(
            f"Tim Loop: FAILED - Max iterations ({max_iterations}) reached.\n"
            f"Plan file missing: {plan_file}\n"
            f"Cannot write failure marker. Recreate the plan or check the path.",
            state_file,
            prompt_file,
        )
        return {}

    write_verification_failure(
        plan_file,
        f"Max iterations ({max_iterations}) reached without verification. "
        f"Status: {verification_status}",
    )
    cleanup_tim_loop(
        f"Tim Loop: FAILED - Max iterations ({max_iterations}) reached "
        f"without verification.\n"
        f"The plan has been marked as FAILED. A remediation pass is required.\n"
        f"Run: /tim-loop --verify {plan_file}",
        state_file,
        prompt_file,
    )
    return {}
