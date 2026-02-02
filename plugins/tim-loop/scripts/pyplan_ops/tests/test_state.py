"""Tests for state persistence."""

import json
import tempfile
from collections.abc import Generator
from datetime import datetime
from pathlib import Path

import pytest

from pyplan_ops.models import ExecutionState, FailedAttempt
from pyplan_ops.state import StateManager


@pytest.fixture
def temp_dir() -> "Generator[Path, None, None]":
    with tempfile.TemporaryDirectory() as d:
        yield Path(d)


@pytest.fixture
def state_manager() -> StateManager:
    return StateManager()


@pytest.fixture
def sample_state(temp_dir: Path) -> ExecutionState:
    return ExecutionState(
        plan_path=temp_dir / "plan.md",
        started_at=datetime(2025, 2, 1, 12, 0, 0),
        current_phase=2,
        current_task="2.1",
        completed_tasks=["1.1", "1.2"],
        failed_attempts={
            "1.2": [
                FailedAttempt(
                    timestamp=datetime(2025, 2, 1, 11, 30, 0),
                    error="First failure",
                    output="Error output",
                )
            ]
        },
    )


class TestStateManager:
    def test_save_creates_state_file(
        self, state_manager: StateManager, sample_state: ExecutionState, temp_dir: Path
    ) -> None:
        state_manager.save(sample_state)

        state_file = temp_dir / ".pyplan-state.json"
        assert state_file.exists()

    def test_save_writes_valid_json(
        self, state_manager: StateManager, sample_state: ExecutionState, temp_dir: Path
    ) -> None:
        state_manager.save(sample_state)

        state_file = temp_dir / ".pyplan-state.json"
        data = json.loads(state_file.read_text())

        assert data["current_phase"] == 2
        assert data["current_task"] == "2.1"
        assert "1.1" in data["completed_tasks"]

    def test_load_returns_state(
        self, state_manager: StateManager, sample_state: ExecutionState, temp_dir: Path
    ) -> None:
        state_manager.save(sample_state)
        loaded = state_manager.load(temp_dir / "plan.md")

        assert loaded is not None
        assert loaded.current_phase == 2
        assert loaded.current_task == "2.1"
        assert loaded.completed_tasks == ["1.1", "1.2"]

    def test_load_returns_none_when_no_file(self, state_manager: StateManager, temp_dir: Path) -> None:
        loaded = state_manager.load(temp_dir / "nonexistent.md")
        assert loaded is None

    def test_load_returns_none_for_wrong_plan(
        self, state_manager: StateManager, sample_state: ExecutionState, temp_dir: Path
    ) -> None:
        state_manager.save(sample_state)
        loaded = state_manager.load(temp_dir / "different_plan.md")
        assert loaded is None

    def test_clear_removes_state_file(
        self, state_manager: StateManager, sample_state: ExecutionState, temp_dir: Path
    ) -> None:
        state_manager.save(sample_state)
        state_file = temp_dir / ".pyplan-state.json"
        assert state_file.exists()

        state_manager.clear(temp_dir / "plan.md")
        assert not state_file.exists()

    def test_clear_handles_missing_file(self, state_manager: StateManager, temp_dir: Path) -> None:
        # Should not raise
        state_manager.clear(temp_dir / "plan.md")

    def test_create_initial_returns_fresh_state(self, state_manager: StateManager, temp_dir: Path) -> None:
        plan_path = temp_dir / "plan.md"
        state = state_manager.create_initial(plan_path)

        assert state.plan_path == plan_path
        assert state.current_phase == 1
        assert state.current_task == ""
        assert state.completed_tasks == []

    def test_load_preserves_failed_attempts(
        self, state_manager: StateManager, sample_state: ExecutionState, temp_dir: Path
    ) -> None:
        state_manager.save(sample_state)
        loaded = state_manager.load(temp_dir / "plan.md")

        assert loaded is not None
        assert "1.2" in loaded.failed_attempts
        assert len(loaded.failed_attempts["1.2"]) == 1
        assert loaded.failed_attempts["1.2"][0].error == "First failure"
