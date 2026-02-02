"""Terminal output and progress display.

Provides rich terminal output with graceful fallback to plain text.
"""

from collections.abc import Iterator
from contextlib import contextmanager

from pyplan_ops.models import Phase, Plan, TaskResult, VerifyResult

# Try to import rich, fall back to plain text
try:
    from rich.console import Console
    from rich.progress import Progress, SpinnerColumn, TextColumn
    from rich.tree import Tree

    RICH_AVAILABLE = True
except ImportError:
    RICH_AVAILABLE = False


class Display:
    """Handles terminal output with optional rich formatting."""

    def __init__(self, use_rich: bool = True) -> None:
        self.use_rich = use_rich and RICH_AVAILABLE
        if self.use_rich:
            self.console = Console()

    def print(self, message: str, style: str = "") -> None:
        """Print a message with optional styling."""
        if self.use_rich:
            self.console.print(message, style=style)
        else:
            print(message)

    def print_plan_structure(self, plan: Plan) -> None:
        """Display the parsed plan structure."""
        if self.use_rich:
            self._print_plan_rich(plan)
        else:
            self._print_plan_plain(plan)

    def _print_plan_rich(self, plan: Plan) -> None:
        """Print plan structure using rich Tree."""
        tree = Tree(f"[bold]{plan.title}[/bold]")

        for phase in plan.phases:
            phase_node = tree.add(f"[blue]Phase {phase.id}: {phase.name}[/blue]")
            for task in phase.tasks:
                task_node = phase_node.add(f"[green]Task {task.id}: {task.name}[/green]")
                for criterion in task.verify_criteria:
                    task_node.add(f"[dim][ ] {criterion}[/dim]")

        self.console.print(tree)

    def _print_plan_plain(self, plan: Plan) -> None:
        """Print plan structure as plain text."""
        print(f"\n{plan.title}")
        print("=" * len(plan.title))

        for phase in plan.phases:
            print(f"\n  Phase {phase.id}: {phase.name}")
            for task in phase.tasks:
                print(f"    Task {task.id}: {task.name}")
                for criterion in task.verify_criteria:
                    print(f"      [ ] {criterion}")

    @contextmanager
    def phase_progress(self, phase: Phase) -> Iterator[None]:
        """Context manager for phase progress display."""
        self.print(f"\n{'>'} Phase {phase.id}: {phase.name} ({len(phase.tasks)} tasks)", "bold blue")
        yield
        self.print(f"  Phase {phase.id} complete", "green")

    @contextmanager
    def task_progress(self, task_id: str, task_name: str) -> Iterator["TaskProgressContext"]:
        """Context manager for task progress display."""
        ctx = TaskProgressContext(self, task_id, task_name)
        self.print(f"  ├─ Task {task_id}: {task_name}", "")
        yield ctx

    def show_task_result(self, result: TaskResult) -> None:
        """Display result of task execution."""
        status = "[check]" if result.success else "[X]"
        duration = f"({result.duration_seconds:.1f}s)"
        style = "green" if result.success else "red"
        self.print(f"  │  ├─ Implementing... {status} {duration}", style)

    def show_verify_result(self, result: VerifyResult) -> None:
        """Display result of task verification."""
        status = "[check]" if result.passed else "[X]"
        attempts = f"(attempt {result.attempts})" if result.attempts > 1 else ""
        style = "green" if result.passed else "red"
        self.print(f"  │  └─ Verifying... {status} {attempts}", style)

    def show_error(self, message: str) -> None:
        """Display an error message."""
        self.print(f"Error: {message}", "bold red")

    def show_success(self, message: str) -> None:
        """Display a success message."""
        self.print(f"Success: {message}", "bold green")

    @contextmanager
    def spinner(self, message: str) -> Iterator[None]:
        """Show a spinner during long operations."""
        if self.use_rich:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                console=self.console,
                transient=True,
            ) as progress:
                progress.add_task(description=message)
                yield
        else:
            print(f"{message}...", end="", flush=True)
            yield
            print(" done")


class TaskProgressContext:
    """Context for tracking task progress."""

    def __init__(self, display: Display, task_id: str, task_name: str) -> None:
        self.display = display
        self.task_id = task_id
        self.task_name = task_name

    def implementing(self) -> None:
        """Show that implementation is in progress."""
        if not self.display.use_rich:
            print("  │  ├─ Implementing...", end="", flush=True)

    def verifying(self) -> None:
        """Show that verification is in progress."""
        if not self.display.use_rich:
            print("  │  └─ Verifying...", end="", flush=True)
