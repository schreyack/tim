#!/usr/bin/env python3
"""
Tim Loop Response Builders - Constructs JSON responses for the stop hook.

This module contains functions that build the various response types
returned by the tim-loop hook to control conversation flow.
"""

import re


PHASE_NAMES = {
    1: "Tech Review",
    2: "Devil's Advocate",
    3: "Security Review",
    4: "AI-Ready Review",
    5: "Goal Alignment",
    6: "PM Review",
    7: "User Advocate",
}


def _build_compact_context(prompt: str, current_phase: int = 0) -> str:
    """Extract a compact ~200-token summary from the full prompt.

    Preserves: review mode, plan file path, completion signal, and key rules.
    Used on non-first iterations to avoid re-injecting the full prompt.
    When current_phase > 1, includes phase correction notice.
    """
    # Extract review mode
    mode_match = re.search(r"## Mode:\s*(.+)", prompt)
    mode = mode_match.group(1).strip() if mode_match else "Unknown"

    # Extract plan file path
    plan_match = re.search(r"Plan File:\s*(\S+)", prompt)
    plan_file = plan_match.group(1).strip() if plan_match else "Unknown"

    # Extract completion signal(s)
    promise_matches = re.findall(r"<promise>([^<]+)</promise>", prompt)
    signals = ", ".join(f"`<promise>{s}</promise>`" for s in promise_matches) if promise_matches else "N/A"

    phase_notice = ""
    if current_phase > 1:
        phase_name = PHASE_NAMES.get(current_phase, f"Phase {current_phase}")
        phase_notice = (
            f"**PHASE CORRECTION:** You are on Phase {current_phase} "
            f"({phase_name}), NOT Phase 1. The original prompt below is "
            f"Phase 1 — ignore its phase-specific instructions.\n\n"
        )

    return (
        f"## Compact Context (full prompt was injected on first iteration)\n\n"
        f"{phase_notice}"
        f"- **Mode:** {mode}\n"
        f"- **Plan File:** {plan_file}\n"
        f"- **Completion Signal(s):** {signals}\n\n"
        f"### Key Rules (unchanged)\n"
        f"- Do a COMPLETE review as if this is your only chance\n"
        f"- NEVER reduce scope — improve through precision, not reduction\n"
        f"- Raise concerns as questions, not deletions\n"
        f"- Re-read the ENTIRE plan from the top each pass\n"
        f"- Delegate subplan AND codebase verification to Explore subagents — only read a subplan when editing it\n"
    )


def _prompt_or_compact(
    prompt: str, is_first_in_phase: bool = False, current_phase: int = 0
) -> str:
    """Return full prompt on first iteration of a phase, compact summary after."""
    if is_first_in_phase:
        return f"---\n\n{prompt}"
    return f"---\n\n{_build_compact_context(prompt, current_phase)}"


def _full_review_guidance(
    current_phase: int, phase_iterations: int, iteration: int, max_iter: int
) -> str:
    """Build guidance for full-review phase continuation."""
    phase_name = PHASE_NAMES.get(current_phase, f"Phase {current_phase}")

    if phase_iterations <= 1:
        codebase_instruction = (
            "Read ONLY the main plan file. "
            "Delegate subplan verification AND codebase verification to Explore subagents. "
            "Only read a specific subplan when you need to EDIT it."
        )
    else:
        codebase_instruction = (
            "Re-read the main plan file from the top. "
            "Use Explore subagents for subplan and codebase verification "
            "— do NOT read source files or subplans directly unless editing."
        )

    return (
        f"PHASE {current_phase} ({phase_name}) - REVIEW PASS (iteration {phase_iterations})\n"
        f"(Global iteration {iteration} of {max_iter})\n\n"
        f"DO A COMPLETE {phase_name} review NOW - as if this is your only chance.\n"
        f"Do NOT pace yourself or save issues for later passes.\n\n"
        f"1. {codebase_instruction}\n"
        f"2. Evaluate EVERY section thoroughly for this phase's concerns\n"
        f"3. Fix everything you find. Do not leave known issues for a future pass\n\n"
        f"When Phase {current_phase} is genuinely complete, output the phase completion signal."
    )


def _standalone_review_guidance(iteration: int) -> str:
    """Build guidance for standalone tech-review or ai-ready continuation."""
    if iteration <= 2:
        codebase_instruction = (
            "Read ONLY the main plan file. "
            "Delegate subplan verification AND codebase verification to Explore subagents. "
            "Only read a specific subplan when you need to EDIT it."
        )
    else:
        codebase_instruction = (
            "Re-read the main plan file from the top. "
            "Use Explore subagents for subplan and codebase verification "
            "— do NOT read source files or subplans directly unless editing."
        )

    return (
        f"REVIEW PASS (iteration {iteration})\n\n"
        f"DO A COMPLETE REVIEW NOW - as if this is your only chance to review "
        f"this plan. Do NOT pace yourself or save issues for later passes.\n\n"
        f"The loop re-runs you because even thorough reviews miss things on "
        f"each pass - NOT to give you multiple passes to divide the work across. "
        f"Every pass should be a full, exhaustive review.\n\n"
        f"Your task:\n"
        f"1. {codebase_instruction}\n"
        f"2. Evaluate EVERY section thoroughly - technical accuracy, edge cases, "
        f"feasibility, testability, completeness\n"
        f"3. Fix everything you find. Do not leave known issues for a future pass\n\n"
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
        is_first = phase_iterations <= 1
    elif review_mode in ("tech-review", "ai-ready"):
        guidance = _standalone_review_guidance(iteration)
        is_first = iteration <= 1
    else:
        guidance = "The task is not yet complete. Continue working on it."
        is_first = iteration <= 1

    return {
        "decision": "block",
        "reason": (
            f"Tim Loop: Iteration {iteration} of {max_iter}\n\n"
            f"{guidance}\n\n"
            f"{_prompt_or_compact(prompt, is_first, current_phase)}"
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
    prompt: str, iteration: int, max_iter: int, min_iter: int,
    is_first_in_phase: bool = False,
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
            f"{_prompt_or_compact(prompt, is_first_in_phase)}"
        ),
    }


def build_short_output_continue_response(
    prompt: str, iteration: int, max_iter: int,
    is_first_in_phase: bool = False,
) -> dict:
    """Build a block response when output was too brief to be a real completion."""
    return {
        "decision": "block",
        "reason": (
            f"Tim Loop: Iteration {iteration} of {max_iter} (response too brief - continuing)\n\n"
            f"{_prompt_or_compact(prompt, is_first_in_phase)}"
        ),
    }


def build_fresh_eyes_review_challenge(
    prompt: str, iteration: int, max_iter: int, judge_reason: str,
    is_first_in_phase: bool = False,
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
            f"{_prompt_or_compact(prompt, is_first_in_phase)}"
        ),
    }
