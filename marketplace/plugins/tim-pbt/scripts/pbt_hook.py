"""PBT Stop Hook — the core enforcement mechanism.

Blocks Claude from exiting until all modules have full property-type coverage.
Reads state from bugs/.pbt-state.json (machine-written, machine-read).

Entry point: reads JSON from stdin (same format as tim-loop hooks),
extracts transcript, checks for completion signal, verifies coverage.

Logic flow:
1. Load state — no file or PID mismatch → allow exit
2. Extract assistant text from transcript
3. Short/empty output → block with "continue scanning"
4. Signal dispatch (in priority order):
   a. <pbt-blockers> → enter blocker resolution phase
   b. blocker_resolution_phase active → check blocker status
   c. <pbt-complete>DONE → verify coverage
   d. No signal → block, re-inject remaining work
5. Verify all modules complete: true
   - Incomplete → block with specific remaining work
   - Complete → allow exit, cleanup state
"""

from __future__ import annotations

import json
import os
import re
import sys

# Add scripts directory to path for sibling imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pbt_context_pressure import (
    PRESSURE_FORCE_STOP,
    detect_response_degradation,
    get_context_pressure,
    increment_compaction_count,
    track_response_length,
)
from pbt_responses import (
    build_blocker_resolution_response,
    build_continue_response,
    build_continue_to_completion,
    build_force_stop,
    build_verification_failure,
)
from pbt_state import (
    all_blockers_resolved_or_declined,
    cleanup_state,
    has_pending_blockers,
    is_coverage_complete,
    load_state,
    log_stderr,
    save_state,
)

COMPLETION_SIGNAL = re.compile(r"<pbt-complete>\s*DONE\s*</pbt-complete>")
BLOCKERS_SIGNAL = re.compile(
    r"<pbt-blockers>\s*(\[.*?\])\s*</pbt-blockers>", re.DOTALL
)
COMPACTION_MARKER = "compressed prior conversation"


def read_hook_input() -> dict:
    """Read and parse hook input from stdin."""
    try:
        return json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return {}


def read_transcript(path: str) -> list[dict]:
    """Read transcript JSONL file."""
    if not path or not os.path.exists(path):
        return []
    entries = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
    except OSError:
        pass
    return entries


def extract_assistant_text(transcript: list[dict]) -> str:
    """Extract the last assistant message text from transcript entries."""
    # Walk backwards to find the last assistant turn
    for entry in reversed(transcript):
        if entry.get("type") == "assistant":
            message = entry.get("message", {})
            content = message.get("content", [])
            if isinstance(content, str):
                return content
            if isinstance(content, list):
                parts = []
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        parts.append(block.get("text", ""))
                    elif isinstance(block, str):
                        parts.append(block)
                return "\n".join(parts)
    return ""


def detect_compaction(transcript: list[dict]) -> bool:
    """Detect if a context compaction happened in this transcript."""
    for entry in transcript:
        if entry.get("type") == "system":
            message = entry.get("message", {})
            content = message.get("content", "")
            if isinstance(content, str) and COMPACTION_MARKER in content.lower():
                return True
            if isinstance(content, list):
                for block in content:
                    text = block.get("text", "") if isinstance(block, dict) else str(block)
                    if COMPACTION_MARKER in text.lower():
                        return True
    return False


def find_project_dir() -> str:
    """Find the project directory by looking for bugs/.pbt-state.json.

    Walk up from cwd to find the state file.
    """
    cwd = os.getcwd()
    path = cwd
    while True:
        state_path = os.path.join(path, "bugs", ".pbt-state.json")
        if os.path.exists(state_path):
            return path
        parent = os.path.dirname(path)
        if parent == path:
            break
        path = parent
    return cwd


def _emit(response: dict | None) -> None:
    """Print JSON response to stdout and exit."""
    print(json.dumps(response) if response else "{}")
    sys.exit(0)


def _update_compaction(state: dict, transcript: list[dict]) -> None:
    """Track compaction events from transcript."""
    if detect_compaction(transcript):
        new_count = increment_compaction_count(state)
        log_stderr(f"Tim PBT: Compaction detected (count: {new_count})")
        save_state(state)


def _handle_force_stop(state: dict) -> dict | None:
    """Check context pressure; return force-stop response or None."""
    if get_context_pressure(state) >= PRESSURE_FORCE_STOP:
        log_stderr("Tim PBT: Context exhausted — forcing stop with state save")
        save_state(state)
        return build_force_stop(state)
    return None


def _handle_completion_signal(state: dict, project_dir: str) -> dict | None:
    """Verify coverage when completion signal is present.

    Returns a response dict (block or allow) or None if no signal found.
    """
    if is_coverage_complete(state):
        log_stderr("Tim PBT: Coverage complete — allowing exit")
        cleanup_state(project_dir)
        return None  # allow exit

    response = build_verification_failure(
        state,
        "Not all modules have complete=true in bugs/.pbt-state.json.",
    )
    save_state(state)
    return response


def _handle_blockers_signal(state: dict, blocker_ids_json: str) -> dict:
    """Process <pbt-blockers> signal — enter blocker resolution phase."""
    try:
        blocker_ids = json.loads(blocker_ids_json)
    except json.JSONDecodeError:
        blocker_ids = []

    log_stderr(
        f"Tim PBT: Blockers signal received — {len(blocker_ids)} blocker(s)"
    )
    state["blocker_resolution_phase"] = True
    save_state(state)

    pending = [
        b for b in state.get("blockers", [])
        if b.get("status") in ("pending", "accepted")
    ]
    return build_blocker_resolution_response(state, pending)


def _handle_blocker_phase(state: dict) -> dict | None:
    """Check blocker resolution progress; return response or None."""
    if not state.get("blocker_resolution_phase"):
        return None

    if all_blockers_resolved_or_declined(state):
        log_stderr("Tim PBT: All blockers resolved/declined — continuing")
        state["blocker_resolution_phase"] = False
        save_state(state)
        return build_continue_to_completion(state)

    if has_pending_blockers(state):
        pending = [
            b for b in state.get("blockers", [])
            if b.get("status") in ("pending", "accepted")
        ]
        return build_blocker_resolution_response(state, pending)

    return None


def _dispatch_signal(
    state: dict, assistant_text: str, project_dir: str,
) -> dict:
    """Route based on signal in assistant text."""
    blockers_match = BLOCKERS_SIGNAL.search(assistant_text)
    if blockers_match:
        return _handle_blockers_signal(state, blockers_match.group(1))

    blocker_response = _handle_blocker_phase(state)
    if blocker_response:
        return blocker_response

    if COMPLETION_SIGNAL.search(assistant_text):
        log_stderr("Tim PBT: Completion signal found — verifying coverage")
        return _handle_completion_signal(state, project_dir)

    return _handle_no_signal(state, assistant_text)


def _handle_no_signal(state: dict, assistant_text: str) -> dict:
    """Block exit when no completion signal — re-inject remaining work."""
    if detect_response_degradation(state):
        log_stderr("Tim PBT: Response degradation detected — incrementing pressure")
        increment_compaction_count(state)

    iteration = state.get("iteration", 1)
    response = build_continue_response(state, iteration)
    save_state(state)
    return response


def _extract_and_track(state: dict, transcript: list[dict]) -> str:
    """Extract assistant text and track response length. Returns text."""
    assistant_text = extract_assistant_text(transcript)
    if assistant_text:
        track_response_length(state, assistant_text)
        save_state(state)
    return assistant_text


def _check_short_output(state: dict, assistant_text: str) -> dict | None:
    """Block exit on short/empty output. Returns response or None."""
    if not assistant_text or len(assistant_text.strip()) < 20:
        log_stderr("Tim PBT: Short/empty output — blocking exit")
        iteration = state.get("iteration", 1)
        response = build_continue_response(state, iteration)
        save_state(state)
        return response
    return None


def main() -> None:
    """Main hook entry point — coordinator for decision helpers."""
    project_dir = find_project_dir()
    state = load_state(project_dir)
    if not state:
        _emit(None)

    hook_input = read_hook_input()
    transcript_path = hook_input.get("transcript_path", "")
    transcript = read_transcript(transcript_path) if transcript_path else []

    _update_compaction(state, transcript)

    force = _handle_force_stop(state)
    if force:
        _emit(force)

    assistant_text = _extract_and_track(state, transcript)

    short = _check_short_output(state, assistant_text)
    if short:
        _emit(short)

    _emit(_dispatch_signal(state, assistant_text, project_dir))


if __name__ == "__main__":
    main()
