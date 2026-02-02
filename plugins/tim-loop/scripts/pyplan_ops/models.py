"""Core data models for pyplan-ops.

Contains dataclasses representing plans, phases, tasks, and execution state.
"""

from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path


@dataclass
class Task:
    """A single task within a phase."""

    id: str  # e.g., "1.1"
    name: str  # e.g., "Create project structure"
    content: str  # Full markdown content
    verify_criteria: list[str] = field(default_factory=list)  # Extracted from **Verify** block


@dataclass
class Phase:
    """A phase containing multiple tasks."""

    id: int  # e.g., 1
    name: str  # e.g., "Project Scaffolding"
    tasks: list[Task] = field(default_factory=list)
    depends_on: list[int] = field(default_factory=list)  # Phase dependencies
    additional_tools: list[str] = field(default_factory=list)  # Phase-specific permissions


@dataclass
class PlanPermissions:
    """Permission configuration for a plan."""

    preset: str = ""  # Permission preset name
    global_tools: list[str] = field(default_factory=list)
    phase_tools: dict[int, list[str]] = field(default_factory=dict)
    approved: bool = False
    approved_by: str | None = None


@dataclass
class PlanStatus:
    """Status header fields from a plan."""

    stage: str = "draft"
    created: str = ""
    last_updated: str = ""
    author: str = ""
    approver: str = "-"
    plan_review: str = "required"
    review_date: str = "-"
    execution_approved: str = "no"
    execution_approved_by: str = "-"
    execution_started: str = "-"


@dataclass
class Plan:
    """A complete plan with phases and metadata."""

    path: Path
    title: str
    status: PlanStatus = field(default_factory=PlanStatus)
    permissions: PlanPermissions = field(default_factory=PlanPermissions)
    phases: list[Phase] = field(default_factory=list)


@dataclass
class FailedAttempt:
    """Record of a failed verification attempt."""

    timestamp: datetime
    error: str
    output: str


@dataclass
class ExecutionState:
    """Persistent state for resumable execution."""

    plan_path: Path
    started_at: datetime
    current_phase: int = 1
    current_task: str = ""
    completed_tasks: list[str] = field(default_factory=list)
    failed_attempts: dict[str, list[FailedAttempt]] = field(default_factory=dict)


@dataclass
class TaskResult:
    """Result of executing a single task."""

    task_id: str
    success: bool
    output: str
    duration_seconds: float
    error: str | None = None


@dataclass
class VerifyResult:
    """Result of verifying a task."""

    task_id: str
    passed: bool
    criteria_results: dict[str, bool] = field(default_factory=dict)
    evidence: str = ""
    attempts: int = 1
    error: str | None = None


@dataclass
class PhaseResult:
    """Result of executing a phase."""

    phase_id: int
    success: bool
    task_results: list[TaskResult] = field(default_factory=list)
    verify_results: list[VerifyResult] = field(default_factory=list)
    duration_seconds: float = 0.0


@dataclass
class PlanResult:
    """Result of executing a complete plan."""

    plan_path: Path
    success: bool
    phase_results: list[PhaseResult] = field(default_factory=list)
    duration_seconds: float = 0.0
    final_verification_passed: bool = False


@dataclass
class ValidationIssue:
    """A single validation issue found in a plan."""

    severity: str  # "error", "warning", "info"
    message: str
    line: int | None = None


@dataclass
class ValidationResult:
    """Result of validating plan structure."""

    is_valid: bool
    severity: str  # "ok", "fixable", "unfixable"
    issues: list[ValidationIssue] = field(default_factory=list)


@dataclass
class ExecutionResult:
    """Result from Claude CLI execution."""

    success: bool
    output: str
    error: str | None = None
    duration_seconds: float = 0.0
    exit_code: int = 0
