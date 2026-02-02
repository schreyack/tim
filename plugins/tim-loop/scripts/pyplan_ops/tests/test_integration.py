"""Integration tests for pyplan-ops."""

import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest

from pyplan_ops.display import Display
from pyplan_ops.executor import ClaudeExecutor
from pyplan_ops.models import ExecutionResult, PlanPermissions
from pyplan_ops.orchestrator import PlanOrchestrator
from pyplan_ops.parser import parse_plan
from pyplan_ops.permissions import PermissionManager
from pyplan_ops.state import StateManager


@pytest.fixture
def valid_plan_path() -> Path:
    return Path(__file__).parent / "fixtures" / "valid_plan.md"


@pytest.fixture
def mock_executor() -> MagicMock:
    executor = MagicMock(spec=ClaudeExecutor)
    # Return PASS for all criteria that might be checked
    executor.execute = AsyncMock(
        return_value=ExecutionResult(
            success=True,
            output="""CRITERION: File exists
STATUS: PASS
EVIDENCE: File found

CRITERION: File contains
STATUS: PASS
EVIDENCE: Content verified

CRITERION: test_output.txt
STATUS: PASS
EVIDENCE: File exists

CRITERION: Hello, World
STATUS: PASS
EVIDENCE: Content found

CRITERION: Goodbye, World
STATUS: PASS
EVIDENCE: Content found

OVERALL: PASS""",
            error=None,
            duration_seconds=1.0,
            exit_code=0,
        )
    )
    return executor


@pytest.fixture
def mock_display() -> MagicMock:
    display = MagicMock(spec=Display)
    display.phase_progress = MagicMock(return_value=MagicMock(__enter__=MagicMock(), __exit__=MagicMock()))
    display.task_progress = MagicMock(return_value=MagicMock(__enter__=MagicMock(), __exit__=MagicMock()))
    return display


@pytest.fixture
def mock_permission_manager() -> MagicMock:
    pm = MagicMock(spec=PermissionManager)
    pm.load_from_plan = MagicMock(
        return_value=PlanPermissions(preset="python-dev", global_tools=["Read", "Write"], approved=True)
    )
    pm.tools_for_phase = MagicMock(return_value=["Read", "Write", "Bash"])
    return pm


class TestPlanParsing:
    def test_parses_valid_plan_completely(self, valid_plan_path: Path) -> None:
        plan = parse_plan(valid_plan_path)

        assert plan.title == "Test Plan: Create a File"
        assert len(plan.phases) == 2
        assert plan.phases[0].tasks[0].name == "Create test file"
        assert len(plan.phases[0].tasks[0].verify_criteria) == 2


class TestOrchestratorWithMocks:
    @pytest.mark.asyncio
    async def test_executes_plan_phases_in_order(
        self,
        valid_plan_path: Path,
        mock_executor: MagicMock,
        mock_display: MagicMock,
        mock_permission_manager: MagicMock,
    ) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            # Copy plan to temp dir for state management
            temp_plan = Path(temp_dir) / "plan.md"
            temp_plan.write_text(valid_plan_path.read_text())

            orchestrator = PlanOrchestrator(
                executor=mock_executor,
                display=mock_display,
                state_manager=StateManager(),
                permission_manager=mock_permission_manager,
            )

            result = await orchestrator.execute_plan(temp_plan)

            assert result.success
            assert len(result.phase_results) == 2

    @pytest.mark.asyncio
    async def test_stops_on_task_failure(
        self,
        valid_plan_path: Path,
        mock_display: MagicMock,
        mock_permission_manager: MagicMock,
    ) -> None:
        failing_executor = MagicMock(spec=ClaudeExecutor)
        failing_executor.execute = AsyncMock(
            return_value=ExecutionResult(
                success=False,
                output="",
                error="Task failed",
                duration_seconds=1.0,
                exit_code=1,
            )
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_plan = Path(temp_dir) / "plan.md"
            temp_plan.write_text(valid_plan_path.read_text())

            orchestrator = PlanOrchestrator(
                executor=failing_executor,
                display=mock_display,
                state_manager=StateManager(),
                permission_manager=mock_permission_manager,
            )

            result = await orchestrator.execute_plan(temp_plan)

            assert not result.success
            assert len(result.phase_results) == 1  # Stopped after first phase failure


class TestStateResume:
    @pytest.mark.asyncio
    async def test_resumes_from_saved_state(
        self,
        valid_plan_path: Path,
        mock_executor: MagicMock,
        mock_display: MagicMock,
        mock_permission_manager: MagicMock,
    ) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_plan = Path(temp_dir) / "plan.md"
            temp_plan.write_text(valid_plan_path.read_text())

            state_manager = StateManager()
            orchestrator = PlanOrchestrator(
                executor=mock_executor,
                display=mock_display,
                state_manager=state_manager,
                permission_manager=mock_permission_manager,
            )

            # Create initial state with task 1.1 completed
            initial_state = state_manager.create_initial(temp_plan)
            initial_state.completed_tasks = ["1.1"]
            initial_state.current_phase = 2
            state_manager.save(initial_state)

            result = await orchestrator.execute_plan(temp_plan, resume=True)

            assert result.success
            # Verify it resumed (display.print was called with resuming message)
            calls = [str(c) for c in mock_display.print.call_args_list]
            assert any("Resuming" in c for c in calls)
