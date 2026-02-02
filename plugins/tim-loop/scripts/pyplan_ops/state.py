"""State persistence for resumable execution.

Manages saving and loading execution state to allow resuming interrupted plans.
"""

import json
from datetime import datetime
from pathlib import Path

from pyplan_ops.models import ExecutionState, FailedAttempt

STATE_FILE = ".pyplan-state.json"


def _state_file_path(plan_path: Path) -> Path:
    """Get the state file path for a plan."""
    return plan_path.parent / STATE_FILE


def _serialize_state(state: ExecutionState) -> dict[str, str | int | list[str] | dict[str, list[dict[str, str]]]]:
    """Serialize ExecutionState to JSON-compatible dict."""
    failed_attempts: dict[str, list[dict[str, str]]] = {}
    for task_id, attempts in state.failed_attempts.items():
        failed_attempts[task_id] = [
            {
                "timestamp": a.timestamp.isoformat(),
                "error": a.error,
                "output": a.output,
            }
            for a in attempts
        ]

    return {
        "plan_path": str(state.plan_path),
        "started_at": state.started_at.isoformat(),
        "current_phase": state.current_phase,
        "current_task": state.current_task,
        "completed_tasks": state.completed_tasks,
        "failed_attempts": failed_attempts,
    }


def _deserialize_state(data: dict[str, object]) -> ExecutionState:
    """Deserialize JSON dict to ExecutionState."""
    failed_attempts: dict[str, list[FailedAttempt]] = {}
    raw_attempts = data.get("failed_attempts", {})
    if isinstance(raw_attempts, dict):
        for task_id, attempts in raw_attempts.items():
            if isinstance(attempts, list):
                failed_attempts[str(task_id)] = [
                    FailedAttempt(
                        timestamp=datetime.fromisoformat(str(a.get("timestamp", ""))),
                        error=str(a.get("error", "")),
                        output=str(a.get("output", "")),
                    )
                    for a in attempts
                    if isinstance(a, dict)
                ]

    plan_path = str(data.get("plan_path", ""))
    started_at = str(data.get("started_at", ""))
    current_phase = data.get("current_phase", 1)
    current_task = data.get("current_task", "")
    completed_tasks = data.get("completed_tasks", [])

    return ExecutionState(
        plan_path=Path(plan_path),
        started_at=datetime.fromisoformat(started_at),
        current_phase=int(current_phase) if isinstance(current_phase, (int, str)) else 1,
        current_task=str(current_task),
        completed_tasks=list(completed_tasks) if isinstance(completed_tasks, list) else [],
        failed_attempts=failed_attempts,
    )


class StateManager:
    """Manages execution state persistence."""

    def save(self, state: ExecutionState) -> None:
        """Save execution state to disk."""
        state_path = _state_file_path(state.plan_path)
        data = _serialize_state(state)
        state_path.write_text(json.dumps(data, indent=2))

    def load(self, plan_path: Path) -> ExecutionState | None:
        """Load execution state from disk if it exists."""
        state_path = _state_file_path(plan_path)

        if not state_path.exists():
            return None

        try:
            data = json.loads(state_path.read_text())
            state = _deserialize_state(data)

            # Verify the state matches this plan
            if Path(data["plan_path"]).resolve() != plan_path.resolve():
                return None

            return state
        except (json.JSONDecodeError, KeyError):
            return None

    def clear(self, plan_path: Path) -> None:
        """Remove state file for a plan."""
        state_path = _state_file_path(plan_path)
        if state_path.exists():
            state_path.unlink()

    def create_initial(self, plan_path: Path) -> ExecutionState:
        """Create initial execution state for a plan."""
        return ExecutionState(
            plan_path=plan_path,
            started_at=datetime.now(),
            current_phase=1,
            current_task="",
            completed_tasks=[],
            failed_attempts={},
        )
