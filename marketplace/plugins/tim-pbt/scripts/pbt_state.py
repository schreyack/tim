"""PBT state file management.

State lives at bugs/.pbt-state.json in the project directory.
Machine-written, machine-read — the markdown report is the human view.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

STATE_FILENAME = ".pbt-state.json"
STATE_DIR = "bugs"
STATE_VERSION = 1

PROPERTY_TYPES = [
    "RT", "ID", "OI", "CA", "CC", "CF",  # Classic 1–6
    "FV", "BO", "TC", "NP", "SV", "CO", "SM",  # Bug-Pattern 7–13
]
# Legacy: accept integer codes (1–13) from older state files
_LEGACY_INT_CODES = set(range(1, 14))
_INT_TO_CODE = dict(zip(range(1, 14), PROPERTY_TYPES))


def log_stderr(msg: str) -> None:
    """Log to stderr (visible in hook output)."""
    print(msg, file=sys.stderr)


# ---------------------------------------------------------------------------
# PID ownership — adapted from tim-loop's tim_loop_state.py
# ---------------------------------------------------------------------------

def _get_parent_pid(pid: int) -> int | None:
    """Get the parent PID of a process (macOS/Linux)."""
    try:
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
    log_stderr(
        f"Tim PBT: PID walk failed (start={os.getppid()}, targets={target_pids})"
    )
    return None


def _pid_is_running(pid: int) -> bool:
    """Check if a process is still running."""
    try:
        os.kill(pid, 0)
        return True
    except (OSError, ProcessLookupError):
        return False


# ---------------------------------------------------------------------------
# State file I/O
# ---------------------------------------------------------------------------

def _state_path(project_dir: str) -> Path:
    """Return the path to the state file."""
    return Path(project_dir) / STATE_DIR / STATE_FILENAME


def _empty_state(project_dir: str) -> dict:
    """Return a fresh empty state."""
    return {
        "version": STATE_VERSION,
        "session_pid": os.getppid(),
        "started": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "last_updated": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "iteration": 1,
        "phase": "discovery",
        "language": "",
        "target": ".",
        "source_files": 0,
        "modules": {},
        "bugs": [],
        "total_properties_tested": 0,
        "total_bugs_found": 0,
        "compaction_count": 0,
        "response_lengths": [],
        "blockers": [],
        "blocker_resolution_phase": False,
        "project_dir": project_dir,
    }


def load_state(project_dir: str) -> dict | None:
    """Load state file, validate schema, check PID ownership.

    Returns None if:
    - No state file exists (PBT not active)
    - State file belongs to a different session (PID mismatch)
    - State file is corrupt
    """
    path = _state_path(project_dir)
    if not path.exists():
        return None

    try:
        with open(path) as f:
            state = json.load(f)
    except (json.JSONDecodeError, OSError) as e:
        log_stderr(f"Tim PBT: Corrupt state file: {e}")
        return None

    if state.get("version") != STATE_VERSION:
        log_stderr(
            f"Tim PBT: State version mismatch "
            f"(got {state.get('version')}, expected {STATE_VERSION})"
        )
        return None

    # PID ownership check
    session_pid = state.get("session_pid")
    if session_pid:
        if _pid_is_running(session_pid):
            found = _walk_parent_chain_for_pid({session_pid})
            if found is None:
                log_stderr(
                    f"Tim PBT: State belongs to different session "
                    f"(pid {session_pid})"
                )
                return None
        # If PID is dead, this is a stale session — still usable for resume

    state["project_dir"] = project_dir
    return state


def save_state(state: dict) -> None:
    """Atomic write: temp file + rename."""
    project_dir = state.get("project_dir", ".")
    path = _state_path(project_dir)
    path.parent.mkdir(parents=True, exist_ok=True)

    state["last_updated"] = time.strftime("%Y-%m-%dT%H:%M:%S")

    # Write to temp file then rename for atomicity
    fd, tmp_path = tempfile.mkstemp(
        dir=str(path.parent), suffix=".tmp", prefix=".pbt-state-"
    )
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(state, f, indent=2)
            f.write("\n")
        os.replace(tmp_path, str(path))
    except Exception:
        # Clean up temp file on failure
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def cleanup_state(project_dir: str) -> None:
    """Remove the state file."""
    path = _state_path(project_dir)
    try:
        path.unlink(missing_ok=True)
        log_stderr("Tim PBT: State file cleaned up")
    except OSError as e:
        log_stderr(f"Tim PBT: Failed to clean up state: {e}")


# ---------------------------------------------------------------------------
# Coverage analysis
# ---------------------------------------------------------------------------

def _normalize_evaluated(evaluated: list) -> set[str]:
    """Normalize evaluated list to string codes, handling legacy int format."""
    result: set[str] = set()
    for item in evaluated:
        if isinstance(item, int) and item in _LEGACY_INT_CODES:
            result.add(_INT_TO_CODE[item])
        elif isinstance(item, str) and item in PROPERTY_TYPES:
            result.add(item)
    return result


def is_coverage_complete(state: dict) -> bool:
    """Returns True only when ALL modules have complete: true AND all 13 property types evaluated."""
    modules = state.get("modules", {})
    if not modules:
        return False
    required = set(PROPERTY_TYPES)
    for m in modules.values():
        if not m.get("complete", False):
            return False
        if _normalize_evaluated(m.get("evaluated", [])) != required:
            return False
    return True


def get_remaining_work(state: dict) -> list[tuple[str, list[str]]]:
    """Returns list of (module_name, missing_property_types) for incomplete modules.

    Also catches modules marked complete but with missing property types.
    """
    remaining = []
    for name, mod in state.get("modules", {}).items():
        evaluated = _normalize_evaluated(mod.get("evaluated", []))
        missing = [t for t in PROPERTY_TYPES if t not in evaluated]
        if missing:
            remaining.append((name, missing))
        elif not mod.get("complete", False):
            remaining.append((name, []))
    return remaining


def has_pending_blockers(state: dict) -> bool:
    """Returns True if any blocker has status pending or accepted."""
    for b in state.get("blockers", []):
        if b.get("status") in ("pending", "accepted"):
            return True
    return False


def all_blockers_resolved_or_declined(state: dict) -> bool:
    """Returns True when every blocker is declined or rescanned."""
    blockers = state.get("blockers", [])
    if not blockers:
        return True
    return all(
        b.get("status") in ("declined", "rescanned") for b in blockers
    )


def get_progress_summary(state: dict) -> str:
    """One-line progress summary for log output."""
    modules = state.get("modules", {})
    if not modules:
        return "No modules tracked"
    complete = sum(1 for m in modules.values() if m.get("complete", False))
    total = len(modules)
    props = state.get("total_properties_tested", 0)
    bugs = state.get("total_bugs_found", 0)
    return (
        f"{complete}/{total} modules complete, "
        f"{props} properties tested, {bugs} bugs found"
    )
