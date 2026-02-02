"""Main orchestrator for plan execution.

Coordinates parsing, permission approval, task execution, and verification.
"""

import time
from datetime import datetime
from pathlib import Path
from typing import Literal

from pyplan_ops.display import Display
from pyplan_ops.executor import ClaudeExecutor
from pyplan_ops.models import (
    ExecutionState,
    Phase,
    PhaseResult,
    Plan,
    PlanResult,
    Task,
    TaskResult,
)
from pyplan_ops.normalizer import normalize_and_save
from pyplan_ops.parser import parse_plan
from pyplan_ops.permissions import PermissionManager
from pyplan_ops.state import StateManager
from pyplan_ops.validator import validate_plan_structure
from pyplan_ops.verifier import VerifyResult, verify_task

IMPLEMENT_TASK_PROMPT = '''Implement the following task:

Task {task_id}: {task_name}

{task_content}

Complete all the work described above. When finished, the following criteria will be verified:
{verify_criteria}
'''


def _build_implement_prompt(task: Task) -> str:
    """Build the implementation prompt for a task."""
    criteria = "\n".join(f"- {c}" for c in task.verify_criteria)
    return IMPLEMENT_TASK_PROMPT.format(
        task_id=task.id,
        task_name=task.name,
        task_content=task.content,
        verify_criteria=criteria,
    )


class PlanOrchestrator:
    """Orchestrates plan execution with verification loops."""

    def __init__(
        self,
        executor: ClaudeExecutor | None = None,
        display: Display | None = None,
        state_manager: StateManager | None = None,
        permission_manager: PermissionManager | None = None,
    ) -> None:
        self.executor = executor or ClaudeExecutor()
        self.display = display or Display()
        self.state_manager = state_manager or StateManager()
        self.permission_manager = permission_manager or PermissionManager()

    async def _normalize_if_needed(self, plan_path: Path) -> None:
        """Normalize plan if structure is invalid."""
        content = plan_path.read_text()
        validation = validate_plan_structure(content)

        if not validation.is_valid and validation.severity == "fixable":
            self.display.print("Plan needs normalization...", "yellow")
            await normalize_and_save(plan_path, executor=self.executor)

    async def _execute_task(self, task: Task, tools: list[str]) -> TaskResult:
        """Execute a single task."""
        start_time = time.monotonic()
        prompt = _build_implement_prompt(task)

        result = await self.executor.execute(
            prompt=prompt,
            allowed_tools=tools,
            output_format="text",
        )

        duration = time.monotonic() - start_time

        return TaskResult(
            task_id=task.id,
            success=result.success,
            output=result.output,
            duration_seconds=duration,
            error=result.error,
        )

    async def _execute_and_verify_task(
        self, task: Task, tools: list[str], mode: Literal["by-task", "by-phase"]
    ) -> tuple[TaskResult, VerifyResult | None]:
        """Execute a task and optionally verify it."""
        task_result = await self._execute_task(task, tools)
        self.display.show_task_result(task_result)

        verify_result = None
        if task_result.success and mode == "by-task":
            verify_result = await verify_task(task, self.executor)
            self.display.show_verify_result(verify_result)

        return task_result, verify_result

    async def _execute_phase(
        self, phase: Phase, tools: list[str], state: ExecutionState, mode: Literal["by-task", "by-phase"]
    ) -> PhaseResult:
        """Execute all tasks in a phase."""
        task_results: list[TaskResult] = []
        verify_results: list[VerifyResult] = []
        phase_start = time.monotonic()

        with self.display.phase_progress(phase):
            for task in phase.tasks:
                if task.id in state.completed_tasks:
                    continue

                state.current_task = task.id
                self.state_manager.save(state)

                with self.display.task_progress(task.id, task.name):
                    task_result, verify_result = await self._execute_and_verify_task(task, tools, mode)
                    task_results.append(task_result)
                    if verify_result:
                        verify_results.append(verify_result)

                    if not task_result.success or (verify_result and not verify_result.passed):
                        return PhaseResult(
                            phase_id=phase.id, success=False, task_results=task_results,
                            verify_results=verify_results, duration_seconds=time.monotonic() - phase_start,
                        )

                state.completed_tasks.append(task.id)
                self.state_manager.save(state)

        return PhaseResult(
            phase_id=phase.id, success=True, task_results=task_results,
            verify_results=verify_results, duration_seconds=time.monotonic() - phase_start,
        )

    def _get_or_create_state(self, plan: Plan, resume: bool) -> ExecutionState:
        """Get existing state if resuming, or create new state."""
        if resume:
            existing = self.state_manager.load(plan.path)
            if existing:
                self.display.print(f"Resuming from task {existing.current_task}", "yellow")
                return existing

        return ExecutionState(
            plan_path=plan.path, started_at=datetime.now(), current_phase=1,
            current_task="", completed_tasks=[], failed_attempts={},
        )

    async def _execute_all_phases(
        self, plan: Plan, state: ExecutionState, mode: Literal["by-task", "by-phase"]
    ) -> tuple[list[PhaseResult], bool]:
        """Execute all phases and return results with success flag."""
        permissions = self.permission_manager.load_from_plan(plan)
        phase_results: list[PhaseResult] = []

        for phase in plan.phases:
            if phase.id < state.current_phase:
                continue
            state.current_phase = phase.id
            tools = self.permission_manager.tools_for_phase(permissions, phase.id)
            phase_result = await self._execute_phase(phase, tools, state, mode)
            phase_results.append(phase_result)
            if not phase_result.success:
                return phase_results, False

        self.state_manager.clear(plan.path)
        return phase_results, True

    async def execute_plan(
        self, plan_path: Path, mode: Literal["by-task", "by-phase"] = "by-task", resume: bool = False
    ) -> PlanResult:
        """Execute a complete plan with verification."""
        start_time = time.monotonic()

        await self._normalize_if_needed(plan_path)
        plan = parse_plan(plan_path)

        permissions = self.permission_manager.load_from_plan(plan)
        if not permissions.approved and not self.permission_manager.prompt_approval(permissions):
            return PlanResult(plan_path=plan_path, success=False, duration_seconds=time.monotonic() - start_time)

        state = self._get_or_create_state(plan, resume)
        phase_results, success = await self._execute_all_phases(plan, state, mode)

        return PlanResult(
            plan_path=plan_path, success=success, phase_results=phase_results,
            duration_seconds=time.monotonic() - start_time, final_verification_passed=success,
        )
