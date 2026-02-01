#!/usr/bin/env python3
"""
Tim Loop Response Builders - Constructs JSON responses for the stop hook.

This module contains functions that build the various response types
returned by the tim-loop hook to control conversation flow.
"""


def build_continue_response(
    prompt: str, iteration: int, max_iter: int, review_mode: str = ""
) -> dict:
    """Build a block response that re-injects the prompt."""
    if review_mode in ("tech-review", "ai-ready"):
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
