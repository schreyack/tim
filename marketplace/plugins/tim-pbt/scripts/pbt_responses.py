"""Response builders for the PBT stop hook.

Five response types:
- continue: Claude stopped without completion signal
- verification_failure: Claude claims done but coverage is incomplete
- force_stop: context exhausted, save and exit gracefully
- blocker_resolution: blockers identified, ask user about each
- continue_to_completion: all blockers handled, finish up
"""

from __future__ import annotations

from pbt_context_pressure import (
    PRESSURE_CRITICAL,
    PRESSURE_WARNING,
    get_context_pressure,
)
from pbt_state import get_progress_summary, get_remaining_work, log_stderr


def _format_remaining_work(remaining: list[tuple[str, list[int]]]) -> str:
    """Format remaining modules and property types as a compact string."""
    parts = []
    for module, missing_types in remaining:
        if missing_types:
            types_str = ",".join(str(t) for t in missing_types)
            parts.append(f"{module} (types {types_str})")
        else:
            parts.append(f"{module} (mark complete)")
    return "; ".join(parts)


def _format_remaining_minimal(remaining: list[tuple[str, list[int]]]) -> str:
    """Ultra-compact remaining work for critical pressure."""
    count = len(remaining)
    total_types = sum(len(types) for _, types in remaining)
    return f"{count} modules, {total_types} property types remaining"


def build_continue_response(state: dict, iteration: int) -> dict:
    """Block exit and re-inject remaining work context.

    Adapts verbosity based on context pressure.
    """
    pressure = get_context_pressure(state)
    remaining = get_remaining_work(state)
    progress = get_progress_summary(state)

    log_stderr(f"Tim PBT: Blocking exit — {progress}")

    if pressure >= PRESSURE_CRITICAL:
        # Minimal context (~30 tokens)
        work = _format_remaining_minimal(remaining)
        reason = f"Continue PBT. {work}."
    elif pressure >= PRESSURE_WARNING:
        # Compact context (~200 tokens)
        work = _format_remaining_work(remaining)
        reason = (
            f"PBT scan incomplete. Progress: {progress}. "
            f"Remaining: {work}. "
            f"Continue with Phase 2 for uncovered modules. "
            f"Update bugs/.pbt-state.json as you go."
        )
    else:
        # Full re-injection (first iterations)
        work = _format_remaining_work(remaining)
        reason = (
            f"PBT scan is NOT complete. Do not stop.\n\n"
            f"**Progress:** {progress}\n\n"
            f"**Remaining modules:** {work}\n\n"
            f"Go back to Phase 2 with the uncovered modules/types. "
            f"For each module: mine properties → generate tests → "
            f"execute → triage → update report → update "
            f"bugs/.pbt-state.json → next module.\n\n"
            f"When ALL modules show complete=true, output "
            f"`<pbt-complete>DONE</pbt-complete>` to finish."
        )

    state["iteration"] = iteration + 1
    return {"decision": "block", "reason": reason}


def build_verification_failure(state: dict, reason: str) -> dict:
    """Block exit when Claude claims done but coverage is incomplete."""
    remaining = get_remaining_work(state)
    work = _format_remaining_work(remaining)
    progress = get_progress_summary(state)

    log_stderr(f"Tim PBT: Verification failed — {reason}")

    return {
        "decision": "block",
        "reason": (
            f"You output the completion signal but coverage is incomplete. "
            f"{reason}\n\n"
            f"**Progress:** {progress}\n\n"
            f"**Remaining:** {work}\n\n"
            f"Continue scanning. When truly complete, output "
            f"`<pbt-complete>DONE</pbt-complete>` again."
        ),
    }


def _format_blocker(blocker: dict) -> str:
    """Format a single blocker for the resolution prompt."""
    modules = ", ".join(blocker.get("modules_unlocked", []))
    return (
        f"- **{blocker['id']}** ({blocker.get('category', 'unknown')}): "
        f"{blocker.get('description', '')}. "
        f"Setup: {blocker.get('setup_action', 'unknown')}. "
        f"Unlocks: {modules or 'unknown'}"
    )


def build_blocker_resolution_response(
    state: dict, pending_blockers: list[dict],
) -> dict:
    """Block exit and instruct Claude to ask user about each blocker."""
    progress = get_progress_summary(state)
    blocker_lines = "\n".join(_format_blocker(b) for b in pending_blockers)

    log_stderr(
        f"Tim PBT: Blocker resolution — {len(pending_blockers)} pending"
    )

    return {
        "decision": "block",
        "reason": (
            f"PBT found resolvable blockers that may unlock additional "
            f"bugs. Do NOT emit the completion signal yet.\n\n"
            f"**Progress:** {progress}\n\n"
            f"**Pending blockers:**\n{blocker_lines}\n\n"
            f"Ask the user about each pending blocker in a single "
            f"message. For each one, explain what it is, what setup is "
            f"needed, and which modules it unlocks. Let the user accept "
            f"or decline each.\n\n"
            f"For accepted blockers: perform the setup, re-scan the "
            f"unlocked modules, update `bugs/.pbt-state.json` (set "
            f"blocker status to `resolved` then `rescanned`). If setup "
            f"fails after 2 attempts, mark as `declined` with a failure "
            f"note.\n\n"
            f"For declined blockers: set status to `declined` in state.\n\n"
            f"When all blockers are resolved or declined, update the "
            f"report and emit `<pbt-complete>DONE</pbt-complete>`."
        ),
    }


def build_continue_to_completion(state: dict) -> dict:
    """All blockers handled — instruct Claude to finish up."""
    progress = get_progress_summary(state)

    log_stderr("Tim PBT: All blockers handled — continuing to completion")

    return {
        "decision": "block",
        "reason": (
            f"All blockers have been resolved or declined. "
            f"**Progress:** {progress}\n\n"
            f"Update `bugs/PBT-REPORT.md` with final results "
            f"(including any new bugs from re-scanned modules). "
            f"Then emit `<pbt-complete>DONE</pbt-complete>` to finish."
        ),
    }


def build_force_stop(state: dict) -> dict:
    """Allow exit at context exhaustion. State is already saved."""
    progress = get_progress_summary(state)
    remaining = get_remaining_work(state)
    work = _format_remaining_minimal(remaining)

    log_stderr(f"Tim PBT: Force stop — context exhausted. {progress}")

    return {
        "decision": "allow",
        "reason": (
            f"Context exhausted. Progress saved to bugs/.pbt-state.json. "
            f"{progress}. {work}. "
            f"Re-run /tim-pbt to resume from where you left off."
        ),
    }
