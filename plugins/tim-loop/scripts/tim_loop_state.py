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
        for hook_type in ["stop", "PreToolUse", "SessionStart"]:
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


# Staleness detection thresholds
HEARTBEAT_THRESHOLD_SECONDS = 300  # 5 minutes
STATE_FILE_THRESHOLD_SECONDS = 30  # 30 seconds if no heartbeat


def _extract_session_pid(state_file_path: str) -> int | None:
    """Extract the session PID from a state file path like .tim-loop-state-12345."""
    import re

    match = re.search(r"\.tim-loop-state-(\d+)$", state_file_path)
    if match:
        return int(match.group(1))
    return None


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
    # Extract session PID - if process is running, session is active
    session_pid = _extract_session_pid(state_file_path) if state_file_path else None
    if session_pid and _is_process_running(session_pid):
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
    """Check if we're inside an active tim-loop session.

    Includes staleness detection to avoid false positives from orphaned
    marker files. Only cleans up if the owning process is confirmed dead.
    """
    if not TIM_LOOP_ACTIVE_MARKER.exists():
        return False

    try:
        state_file_path = TIM_LOOP_ACTIVE_MARKER.read_text().strip()
        return _check_session_staleness(state_file_path)
    except Exception:
        # On any error, assume active to avoid accidentally cleaning up live session
        return True
