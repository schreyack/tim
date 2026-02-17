#!/usr/bin/env python3
"""
Tim Loop Staleness Detection - Detects and cleans up orphaned sessions.

Checks whether a tim-loop session is still alive by examining process status,
heartbeat freshness, and state file age. Cleans up stale sessions automatically.
"""

import os
from datetime import datetime
from pathlib import Path

# Duplicated from tim_loop_state to avoid circular imports
TIM_LOOP_ACTIVE_MARKER = Path.home() / ".claude" / ".tim-loop-active"
_CLEANUP_LOG = Path.home() / ".claude" / ".tim-loop-cleanup.log"

# Staleness detection thresholds
HEARTBEAT_THRESHOLD_SECONDS = 300  # 5 minutes
STATE_FILE_THRESHOLD_SECONDS = 30  # 30 seconds if no heartbeat


def _log_message(message: str) -> None:
    """Log a message to the cleanup log file."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(_CLEANUP_LOG, "a") as f:
            f.write(f"{timestamp} - {message}\n")
    except Exception:
        pass


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
        for pattern in [".tim-loop-iteration-count", ".tim-loop-auto-approve"]:
            (Path.home() / ".claude" / pattern).unlink(missing_ok=True)
        _log_message("Cleaned up stale session files")
    except Exception as e:
        _log_message(f"Stale session cleanup error: {e}")


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


def check_session_staleness(state_file_path: str, claude_pid: int | None) -> bool:
    """Check if session is stale (dead process + stale files). Returns True if active.

    Args:
        state_file_path: Path to the state file.
        claude_pid: The CLAUDE_PID from the state file (or None if unknown).
    """
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
