#!/usr/bin/env python3
"""
Tim Loop Hook - Implements iteration for Tim Loop workflow.

This hook is registered as a "stop" hook and intercepts conversation exit.
It checks if Claude output the completion promise and if the plan is verified.
If not, it blocks completion and re-injects the prompt to continue the loop.

Key fix: This hook now properly handles Claude Code's JSON input format
(receiving transcript_path) and outputs JSON responses (decision: block/allow).
"""

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

# Configuration
TIM_LOOP_ACTIVE_MARKER = Path.home() / ".claude" / ".tim-loop-active"
CLEANUP_LOG = Path.home() / ".claude" / ".tim-loop-cleanup.log"


def log_message(message: str) -> None:
    """Log a message to the cleanup log file."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(CLEANUP_LOG, "a") as f:
            f.write(f"{timestamp} - {message}\n")
    except Exception:
        pass


def log_stderr(message: str) -> None:
    """Log a message to stderr (visible in Claude Code logs)."""
    print(message, file=sys.stderr)


def read_transcript(transcript_path: str) -> list[dict]:
    """Read and parse the JSONL transcript file."""
    entries = []
    try:
        path = Path(transcript_path).expanduser()
        if not path.exists():
            return entries
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
    except Exception:
        pass
    return entries


def extract_assistant_text(transcript: list[dict]) -> str:
    """Extract all assistant (Claude) text from transcript."""
    texts = []
    for entry in transcript:
        role = entry.get("role") or entry.get("type")
        if role != "assistant":
            continue
        content = entry.get("content", "")
        if isinstance(content, str):
            texts.append(content)
        elif isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    texts.append(block.get("text", ""))
    return "\n".join(texts)


def cleanup_state_files(state_file: str, prompt_file: str) -> None:
    """Remove tim-loop state files."""
    files_to_remove = [
        state_file,
        prompt_file,
        str(TIM_LOOP_ACTIVE_MARKER),
        str(Path.home() / ".claude" / ".tim-loop-iteration-count"),
        str(Path.home() / ".claude" / ".tim-loop-auto-approve"),
        str(Path.home() / ".claude" / ".tim-loop-heartbeat"),
    ]
    for file_path in files_to_remove:
        if file_path and os.path.isfile(file_path):
            try:
                os.remove(file_path)
                log_message(f"Removed: {file_path}")
            except Exception as e:
                log_message(f"FAILED to remove {file_path}: {e}")


def cleanup_hooks_from_settings() -> None:
    """Remove tim-loop hooks from settings.local.json."""
    try:
        settings_file = Path.home() / ".claude" / "settings.local.json"
        if not settings_file.exists():
            return
        with open(settings_file, "r") as f:
            settings = json.load(f)
        if "hooks" not in settings:
            return
        for hook_type in ["stop", "PreToolUse", "PreCompact"]:
            if hook_type in settings["hooks"]:
                settings["hooks"][hook_type] = [
                    h
                    for h in settings["hooks"][hook_type]
                    if "tim-loop" not in h.get("command", "")
                ]
                if not settings["hooks"][hook_type]:
                    del settings["hooks"][hook_type]
        if not settings["hooks"]:
            del settings["hooks"]
        with open(settings_file, "w") as f:
            json.dump(settings, f, indent=2)
        log_message("Hooks cleaned from settings.local.json")
    except Exception as e:
        log_message(f"Hook cleanup error: {e}")


def cleanup_tim_loop(message: str, state_file: str, prompt_file: str) -> None:
    """Clean up all tim-loop state and hooks."""
    log_stderr(message)
    log_message(f"Cleanup started: {message}")
    cleanup_state_files(state_file, prompt_file)
    cleanup_hooks_from_settings()
    log_message("Cleanup completed")


def load_state() -> dict | None:
    """Load tim-loop state from the active marker and state file."""
    if not TIM_LOOP_ACTIVE_MARKER.exists():
        return None
    try:
        state_file = TIM_LOOP_ACTIVE_MARKER.read_text().strip()
        if not state_file or not os.path.isfile(state_file):
            return None
        state = {"_state_file": state_file}
        with open(state_file, "r") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    key, _, value = line.partition("=")
                    state[key] = value.strip().strip('"').strip("'")
        return state
    except Exception:
        return None


def save_state(state: dict) -> None:
    """Save tim-loop state back to the state file."""
    state_file = state.get("_state_file")
    if not state_file:
        return
    try:
        with open(state_file, "w") as f:
            for key, value in state.items():
                if not key.startswith("_"):
                    f.write(f'{key}="{value}"\n')
    except Exception as e:
        log_message(f"Failed to save state: {e}")


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
    if not plan_file or not os.path.isfile(plan_file):
        return None  # No plan to check, consider verified
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


def handle_completion_promise(state: dict, prompt: str) -> dict | None:
    """Handle case when completion promise is found. Returns response or None."""
    state_file = state.get("_state_file", "")
    prompt_file = state.get("TIM_LOOP_PROMPT_FILE", "")
    current_iteration = int(state.get("CURRENT_ITERATION", "1"))
    max_iterations = int(state.get("MAX_ITERATIONS", "30"))
    review_mode = state.get("REVIEW_MODE", "")
    min_review_iterations = int(state.get("MIN_REVIEW_ITERATIONS", "5"))

    # For review modes, challenge early completion
    if review_mode in ("tech-review", "ai-ready"):
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
        return build_verification_response(prompt, current_iteration, max_iterations)

    cleanup_tim_loop("Tim Loop: Task complete", state_file, prompt_file)
    return {}


def handle_continue_loop(state: dict, prompt: str) -> dict:
    """Handle case when completion promise is NOT found - continue loop."""
    state_file = state.get("_state_file", "")
    prompt_file = state.get("TIM_LOOP_PROMPT_FILE", "")
    current_iteration = int(state.get("CURRENT_ITERATION", "1")) + 1
    max_iterations = int(state.get("MAX_ITERATIONS", "30"))
    review_mode = state.get("REVIEW_MODE", "")

    if current_iteration >= max_iterations:
        cleanup_tim_loop(
            f"Tim Loop: Max iterations ({max_iterations}) reached",
            state_file,
            prompt_file,
        )
        return {}

    state["CURRENT_ITERATION"] = str(current_iteration)
    save_state(state)
    log_stderr(f"Tim Loop: Iteration {current_iteration} of {max_iterations}")
    return build_continue_response(prompt, current_iteration, max_iterations, review_mode)


def main() -> None:
    """Main hook entry point."""
    state = load_state()
    if not state:
        print("{}")
        sys.exit(0)

    prompt_file = state.get("TIM_LOOP_PROMPT_FILE", "")
    if not prompt_file or not os.path.isfile(prompt_file):
        print("{}")
        sys.exit(0)

    completion_promise = state.get("COMPLETION_PROMISE", "COMPLETE")
    state_file = state.get("_state_file", "")

    try:
        with open(prompt_file, "r") as f:
            prompt = f.read()
    except Exception:
        prompt = ""

    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        hook_input = {}

    if hook_input.get("stop_hook_active"):
        print("{}")
        sys.exit(0)

    transcript_path = hook_input.get("transcript_path", "")
    assistant_text = ""
    if transcript_path:
        transcript = read_transcript(transcript_path)
        assistant_text = extract_assistant_text(transcript)

    if not assistant_text or len(assistant_text.strip()) < 20:
        cleanup_tim_loop("Tim Loop: Session terminated by user", state_file, prompt_file)
        print("{}")
        sys.exit(0)

    promise_tag = f"<promise>{completion_promise}</promise>"
    if promise_tag in assistant_text:
        response = handle_completion_promise(state, prompt)
    else:
        response = handle_continue_loop(state, prompt)

    print(json.dumps(response))
    sys.exit(0)


if __name__ == "__main__":
    main()
