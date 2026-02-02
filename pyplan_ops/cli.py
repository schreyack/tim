"""CLI definition for pyplan-ops.

Provides command-line interface using Click.
"""

import asyncio
from pathlib import Path
from typing import Literal

import click

from pyplan_ops.display import Display
from pyplan_ops.executor import ClaudeExecutor
from pyplan_ops.normalizer import normalize_and_save
from pyplan_ops.orchestrator import PlanOrchestrator
from pyplan_ops.parser import parse_plan
from pyplan_ops.resolver import resolve_plan_path
from pyplan_ops.tim_loop import TimLoopMode, print_tim_loop_command, run_tim_loop_interactive
from pyplan_ops.validator import validate_plan_structure


def _resolve_plan(plan_arg: str, display: Display) -> Path:
    """Resolve plan argument to path, handling errors."""
    try:
        return resolve_plan_path(plan_arg)
    except FileNotFoundError as e:
        display.show_error(str(e))
        raise SystemExit(1) from None


@click.group()
@click.version_option(version="0.2.0")
def main() -> None:
    """pyplan-ops: Python-based plan orchestrator for Claude Code."""
    pass


@main.command()
@click.argument("plan_arg")
@click.option(
    "--mode",
    type=click.Choice(["by-task", "by-phase"]),
    default="by-task",
    help="Verification granularity",
)
@click.option("--resume", is_flag=True, help="Resume from saved state")
@click.option("--dry-run", is_flag=True, help="Show what would run without executing")
def execute(plan_arg: str, mode: str, resume: bool, dry_run: bool) -> None:
    """Execute a plan file. PLAN_ARG can be a path or plan name."""
    display = Display()
    plan_path = _resolve_plan(plan_arg, display)

    if dry_run:
        plan = parse_plan(plan_path)
        display.print_plan_structure(plan)
        display.print("\n[Dry run - no execution performed]", "yellow")
        return

    orchestrator = PlanOrchestrator(display=display)
    mode_literal: Literal["by-task", "by-phase"] = "by-task" if mode == "by-task" else "by-phase"

    result = asyncio.run(orchestrator.execute_plan(plan_path, mode=mode_literal, resume=resume))

    if result.success:
        display.show_success(f"Plan completed in {result.duration_seconds:.1f}s")
    else:
        display.show_error("Plan execution failed")
        raise SystemExit(1)


@main.command()
@click.argument("plan_arg")
def verify(plan_arg: str) -> None:
    """Verify a plan without implementing. PLAN_ARG can be a path or plan name."""
    display = Display()
    _resolve_plan(plan_arg, display)  # Validate plan exists
    display.print("Verification-only mode not yet implemented", "yellow")


@main.command()
@click.argument("plan_arg")
@click.option("--output", "-o", type=click.Path(path_type=Path), help="Output file path")
@click.option("--auto-approve", is_flag=True, help="Skip approval prompt")
def normalize(plan_arg: str, output: Path | None, auto_approve: bool) -> None:
    """Normalize a plan file structure. PLAN_ARG can be a path or plan name."""
    display = Display()
    plan_path = _resolve_plan(plan_arg, display)

    try:
        executor = ClaudeExecutor()
        result_path = asyncio.run(
            normalize_and_save(plan_path, output_path=output, executor=executor, auto_approve=auto_approve)
        )
        display.show_success(f"Normalized plan saved to: {result_path}")
    except ValueError as e:
        display.show_error(str(e))
        raise SystemExit(1) from None
    except RuntimeError as e:
        display.show_error(str(e))
        raise SystemExit(1) from None


@main.command()
@click.argument("plan_arg")
def inspect(plan_arg: str) -> None:
    """Show parsed plan structure. PLAN_ARG can be a path or plan name."""
    display = Display()
    plan_path = _resolve_plan(plan_arg, display)

    # First validate
    content = plan_path.read_text()
    validation = validate_plan_structure(content)

    if not validation.is_valid:
        display.print(f"\nValidation issues ({validation.severity}):", "yellow")
        for issue in validation.issues:
            display.print(f"  - [{issue.severity}] {issue.message}", "")
        display.print("")

    # Parse and display
    try:
        plan = parse_plan(plan_path)
        display.print_plan_structure(plan)

        # Show metadata
        display.print(f"\nStatus: {plan.status.stage}", "")
        display.print(f"Phases: {len(plan.phases)}", "")
        total_tasks = sum(len(p.tasks) for p in plan.phases)
        display.print(f"Tasks: {total_tasks}", "")

        if plan.permissions.preset:
            display.print(f"Permission preset: {plan.permissions.preset}", "")

    except Exception as e:
        display.show_error(f"Failed to parse plan: {e}")
        raise SystemExit(1) from None


def _run_tim_loop(plan_arg: str, mode: TimLoopMode, max_iterations: int | None, print_only: bool) -> None:
    """Common logic for running tim-loop commands."""
    display = Display()
    plan_path = _resolve_plan(plan_arg, display)

    if print_only:
        print_tim_loop_command(plan_path, mode, max_iterations)
        return

    display.print(f"\nRunning tim-loop --{mode} on {plan_path.name}...\n", "bold")
    result = run_tim_loop_interactive(plan_path, mode, max_iterations)

    if result.success:
        display.show_success(f"Tim-loop completed in {result.duration_seconds:.1f}s")
    else:
        display.show_error(f"Tim-loop failed: {result.error}")
        raise SystemExit(1)


@main.command()
@click.argument("plan_arg")
@click.option("--max-iterations", "-n", type=int, help="Max iterations (default: 50)")
@click.option("--print-only", is_flag=True, help="Print command without executing")
def implement(plan_arg: str, max_iterations: int | None, print_only: bool) -> None:
    """Run tim-loop --implement on a plan. PLAN_ARG can be a path or plan name."""
    _run_tim_loop(plan_arg, "implement", max_iterations, print_only)


@main.command()
@click.argument("plan_arg")
@click.option("--max-iterations", "-n", type=int, help="Max iterations (default: 15)")
@click.option("--print-only", is_flag=True, help="Print command without executing")
def review(plan_arg: str, max_iterations: int | None, print_only: bool) -> None:
    """Run tim-loop --full-review on a plan. PLAN_ARG can be a path or plan name."""
    _run_tim_loop(plan_arg, "full-review", max_iterations, print_only)


@main.command("ai-ready")
@click.argument("plan_arg")
@click.option("--max-iterations", "-n", type=int, help="Max iterations (default: 5)")
@click.option("--print-only", is_flag=True, help="Print command without executing")
def ai_ready(plan_arg: str, max_iterations: int | None, print_only: bool) -> None:
    """Run tim-loop --ai-ready on a plan. PLAN_ARG can be a path or plan name."""
    _run_tim_loop(plan_arg, "ai-ready", max_iterations, print_only)


@main.command("pm-review")
@click.argument("plan_arg")
@click.option("--max-iterations", "-n", type=int, help="Max iterations (default: 10)")
@click.option("--print-only", is_flag=True, help="Print command without executing")
def pm_review(plan_arg: str, max_iterations: int | None, print_only: bool) -> None:
    """Run tim-loop --pm-review on a plan. PLAN_ARG can be a path or plan name."""
    _run_tim_loop(plan_arg, "pm-review", max_iterations, print_only)


if __name__ == "__main__":
    main()
