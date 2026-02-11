#!/usr/bin/env python3
"""
Tim Loop State Management - Handles state files and cleanup operations.

This module contains functions for loading, saving, and cleaning up
tim-loop session state.
"""

import json
import os
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


def reset_detection_state() -> None:
    """Reset detection state files (called after human intervention).

    This clears the slate so previously-flagged content doesn't cause
    repeated halts after the human has intervened.
    """
    detection_files = [
        Path.home() / ".claude" / ".tim-loop-last-fired",
        Path.home() / ".claude" / ".tim-loop-block-count",
    ]
    for file_path in detection_files:
        try:
            file_path.unlink(missing_ok=True)
        except Exception:
            pass


def cleanup_state_files(state_file: str, prompt_file: str) -> None:
    """Remove tim-loop state files."""
    files_to_remove = [
        state_file,
        prompt_file,
        str(TIM_LOOP_ACTIVE_MARKER),
        str(Path.home() / ".claude" / ".tim-loop-iteration-count"),
        str(Path.home() / ".claude" / ".tim-loop-auto-approve"),
        str(Path.home() / ".claude" / ".tim-loop-heartbeat"),
        str(Path.home() / ".claude" / ".tim-loop-pending-options"),
        str(Path.home() / ".claude" / ".tim-loop-last-fired"),
        str(Path.home() / ".claude" / ".tim-loop-block-count"),
    ]
    for file_path in files_to_remove:
        if file_path and os.path.isfile(file_path):
            try:
                os.remove(file_path)
                log_message(f"Removed: {file_path}")
            except Exception as e:
                log_message(f"FAILED to remove {file_path}: {e}")


def _filter_tim_loop_hooks(hooks: dict, hook_type: str) -> None:
    """Remove tim-loop hooks from a specific hook type, deleting key if empty."""
    if hook_type not in hooks:
        return
    hooks[hook_type] = [
        h for h in hooks[hook_type] if "tim-loop" not in h.get("command", "")
    ]
    if not hooks[hook_type]:
        del hooks[hook_type]


def cleanup_hooks_from_settings() -> None:
    """Remove tim-loop hooks from settings.local.json."""
    settings_file = Path.home() / ".claude" / "settings.local.json"
    if not settings_file.exists():
        return
    try:
        with open(settings_file, "r") as f:
            settings = json.load(f)
        if "hooks" not in settings:
            return
        for hook_type in ["stop", "PreToolUse", "SessionStart", "UserPromptSubmit"]:
            _filter_tim_loop_hooks(settings["hooks"], hook_type)
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


def _get_parent_pid(pid: int) -> int | None:
    """Get the parent PID of a process (macOS/Linux)."""
    try:
        import subprocess

        result = subprocess.run(
            ["ps", "-o", "ppid=", "-p", str(pid)],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return int(result.stdout.strip())
    except Exception:
        pass
    return None


def _extract_pid_from_state_file(state_file: Path | str) -> int | None:
    """Extract CLAUDE_PID from a state file, with filename fallback."""
    import re as _re
    path = Path(state_file) if not isinstance(state_file, Path) else state_file
    try:
        if path.exists():
            for line in path.read_text().splitlines():
                if line.startswith("CLAUDE_PID="):
                    return int(line.split("=", 1)[1].strip().strip('"').strip("'"))
    except Exception:
        pass
    match = _re.search(r"\.tim-loop-state-(\d+)$", str(state_file))
    return int(match.group(1)) if match else None


def _collect_claude_pids_from_state_files() -> set[int]:
    """Collect all CLAUDE_PIDs from existing state files."""
    claude_dir = Path.home() / ".claude"
    claude_pids: set[int] = set()
    for state_file in claude_dir.glob(".tim-loop-state-*"):
        pid = _extract_pid_from_state_file(state_file)
        if pid is not None:
            claude_pids.add(pid)
    return claude_pids


def _walk_parent_chain_for_pid(target_pids: set[int]) -> int | None:
    """Walk up parent process chain looking for a PID in the target set."""
    pid = os.getppid()
    visited: set[int] = set()
    while pid and pid > 1 and pid not in visited:
        if pid in target_pids:
            return pid
        visited.add(pid)
        parent = _get_parent_pid(pid)
        if parent is None:
            break
        pid = parent
    log_stderr(f"Tim Loop: PID walk failed (start={os.getppid()}, targets={target_pids})")
    return None


def _find_claude_pid() -> int | None:
    """Walk up parent chain to find Claude process matching a state file."""
    claude_pids = _collect_claude_pids_from_state_files()
    if not claude_pids:
        return None
    return _walk_parent_chain_for_pid(claude_pids)


def _parse_state_file(state_file_path: Path | str) -> dict | None:
    """Parse a state file into a dictionary."""
    try:
        state_file_str = str(state_file_path)
        if not os.path.isfile(state_file_str):
            return None
        state = {"_state_file": state_file_str}
        with open(state_file_str, "r") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    key, _, value = line.partition("=")
                    state[key] = value.strip().strip('"').strip("'")
        return state
    except Exception:
        return None


def load_state() -> dict | None:
    """Load tim-loop state for the current Claude process.

    Uses PID-based lookup to find the correct state file when multiple
    tim-loop sessions are running in different projects. Falls back to
    the .tim-loop-active marker for backwards compatibility.
    """
    claude_dir = Path.home() / ".claude"

    # Try PID-based lookup first
    claude_pid = _find_claude_pid()
    if claude_pid:
        for state_file in claude_dir.glob(".tim-loop-state-*"):
            state = _parse_state_file(state_file)
            if state and state.get("CLAUDE_PID") == str(claude_pid):
                return state
        log_stderr(f"Tim Loop: PID {claude_pid} found but no matching state file")

    # Fall back to .tim-loop-active marker (backwards compatibility)
    if not TIM_LOOP_ACTIVE_MARKER.exists():
        log_stderr("Tim Loop: No active marker found - state lookup failed")
        return None
    try:
        state_file = TIM_LOOP_ACTIVE_MARKER.read_text().strip()
        return _parse_state_file(state_file)
    except Exception as e:
        log_stderr(f"Tim Loop: Active marker read failed: {e}")
        return None


def get_review_mode() -> str:
    """Get the current review mode from tim-loop state."""
    state = load_state()
    if state:
        return state.get("REVIEW_MODE", "")
    return ""


def is_implement_mode() -> bool:
    """Check if tim-loop is in implement mode (--implement flag)."""
    state = load_state()
    if state:
        return state.get("IMPLEMENT_MODE", "false") == "true"
    return False


def check_and_clear_user_initiated_marker() -> bool:
    """Check if user initiated this turn, and clear the marker.

    Returns True if the marker existed (user is interacting).
    When user intervenes, we reset detection state so previously-flagged
    content doesn't cause repeated halts.
    """
    marker = Path.home() / ".claude" / ".tim-loop-user-initiated"
    try:
        if marker.exists():
            marker.unlink()
            reset_detection_state()
            return True
    except Exception:
        pass
    return False


def is_excuse_detector_enabled() -> bool:
    """Check if excuse detector is enabled via environment variable.

    Default: enabled (True). Set TIM_EXCUSE_DETECTOR_ENABLED=false to disable.
    """
    return os.environ.get("TIM_EXCUSE_DETECTOR_ENABLED", "true").lower() != "false"


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


# Staleness detection thresholds
HEARTBEAT_THRESHOLD_SECONDS = 300  # 5 minutes
STATE_FILE_THRESHOLD_SECONDS = 30  # 30 seconds if no heartbeat


def _is_process_running(pid: int) -> bool:
    """Check if a process with the given PID is still running."""
    try:
        os.kill(pid, 0)  # Signal 0 doesn't kill, just checks existence
        return True
    except ProcessLookupError:
        return False  # Process doesn't exist
    except PermissionError:
        return True  # Process exists but we can't signal it
    except Exception:
        return True  # Assume running on any other error


def _cleanup_stale_session() -> None:
    """Clean up orphaned tim-loop session files."""
    heartbeat_path = Path.home() / ".claude" / ".tim-loop-heartbeat"
    try:
        state_file_path = (
            TIM_LOOP_ACTIVE_MARKER.read_text().strip()
            if TIM_LOOP_ACTIVE_MARKER.exists()
            else None
        )
        TIM_LOOP_ACTIVE_MARKER.unlink(missing_ok=True)
        heartbeat_path.unlink(missing_ok=True)
        if state_file_path:
            Path(state_file_path).unlink(missing_ok=True)
        # Also clean up related files
        for pattern in [".tim-loop-iteration-count", ".tim-loop-auto-approve"]:
            (Path.home() / ".claude" / pattern).unlink(missing_ok=True)
        log_message("Cleaned up stale session files")
    except Exception as e:
        log_message(f"Stale session cleanup error: {e}")


def _is_heartbeat_fresh() -> bool | None:
    """Check if heartbeat file exists and is fresh. Returns None if no heartbeat."""
    heartbeat_path = Path.home() / ".claude" / ".tim-loop-heartbeat"
    if not heartbeat_path.exists():
        return None
    heartbeat_epoch = int(heartbeat_path.read_text().strip())
    age_seconds = int(datetime.now().timestamp()) - heartbeat_epoch
    return age_seconds <= HEARTBEAT_THRESHOLD_SECONDS


def _is_state_file_fresh(state_file_path: str) -> bool:
    """Check if state file exists and was recently modified."""
    if not state_file_path or not Path(state_file_path).exists():
        return False
    state_mtime = Path(state_file_path).stat().st_mtime
    age_seconds = datetime.now().timestamp() - state_mtime
    return age_seconds <= STATE_FILE_THRESHOLD_SECONDS


def _check_session_staleness(state_file_path: str) -> bool:
    """Check if session is stale (dead process + stale files). Returns True if active."""
    # Extract Claude PID - if process is running, session is active
    claude_pid = _extract_pid_from_state_file(state_file_path)
    if claude_pid and _is_process_running(claude_pid):
        return True

    # Process dead or unknown - check file freshness
    heartbeat_fresh = _is_heartbeat_fresh()
    if heartbeat_fresh is True:
        return True
    if heartbeat_fresh is False:
        _cleanup_stale_session()
        return False

    # No heartbeat - fall back to state file age
    if _is_state_file_fresh(state_file_path):
        return True

    _cleanup_stale_session()
    return False


def is_tim_loop_active() -> bool:
    """Check if we're inside an active tim-loop session FOR THIS PROCESS.

    Uses PID-chain walking to verify the current process is actually part
    of the tim-loop session, not just that some tim-loop exists somewhere.
    This ensures proper session isolation when multiple Claude instances run.

    Includes staleness detection to avoid false positives from orphaned
    marker files. Only cleans up if the owning process is confirmed dead.
    """
    if not TIM_LOOP_ACTIVE_MARKER.exists():
        return False

    try:
        state_file_path = TIM_LOOP_ACTIVE_MARKER.read_text().strip()

        # First check if the session is stale (dead process)
        if not _check_session_staleness(state_file_path):
            return False

        # Session is alive - now verify THIS process belongs to it
        # by walking up the parent chain to find the CLAUDE_PID
        state_claude_pid = _extract_pid_from_state_file(state_file_path)
        if not state_claude_pid:
            # No PID in state file - fall back to assuming active (legacy)
            return True

        # Walk up parent chain to see if we're a child of the tim-loop session
        found_pid = _walk_parent_chain_for_pid({state_claude_pid})
        return found_pid is not None
    except Exception:
        # On any error, assume NOT active to avoid blocking unrelated sessions
        return False
