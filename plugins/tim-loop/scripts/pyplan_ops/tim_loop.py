"""Tim Loop integration.

Calls tim-loop via Claude CLI for plan execution and review.
"""

import asyncio
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

TimLoopMode = Literal["implement", "full-review", "ai-ready", "pm-review", "verify"]


@dataclass
class TimLoopResult:
    """Result from running tim-loop."""

    success: bool
    mode: TimLoopMode
    plan_path: Path
    duration_seconds: float
    exit_code: int
    error: str | None = None


def _build_tim_loop_command(
    plan_path: Path,
    mode: TimLoopMode,
    max_iterations: int | None = None,
) -> str:
    """Build the tim-loop skill command."""
    cmd = f"/tim-loop:tim-loop --{mode} {plan_path}"
    if max_iterations:
        cmd += f" --max-iterations {max_iterations}"
    return cmd


def _get_default_iterations(mode: TimLoopMode) -> int:
    """Get default max iterations for a mode."""
    defaults = {
        "implement": 50,
        "full-review": 15,
        "ai-ready": 5,
        "pm-review": 10,
        "verify": 10,
    }
    return defaults.get(mode, 20)


def _make_error_result(
    mode: TimLoopMode, plan_path: Path, duration: float, error: str
) -> TimLoopResult:
    """Create an error TimLoopResult."""
    return TimLoopResult(
        success=False, mode=mode, plan_path=plan_path,
        duration_seconds=duration, exit_code=-1, error=error,
    )


async def run_tim_loop_async(
    plan_path: Path,
    mode: TimLoopMode,
    max_iterations: int | None = None,
    timeout_seconds: float = 3600.0,
    claude_path: str = "claude",
) -> TimLoopResult:
    """Run tim-loop asynchronously via Claude CLI."""
    iterations = max_iterations or _get_default_iterations(mode)
    prompt = _build_tim_loop_command(plan_path, mode, iterations)
    start_time = time.monotonic()

    try:
        process = await asyncio.create_subprocess_exec(
            claude_path, "-p", prompt,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=timeout_seconds)
        duration = time.monotonic() - start_time
        exit_code = process.returncode or 0

        return TimLoopResult(
            success=exit_code == 0, mode=mode, plan_path=plan_path,
            duration_seconds=duration, exit_code=exit_code,
            error=stderr.decode() if exit_code != 0 else None,
        )
    except TimeoutError:
        return _make_error_result(
            mode, plan_path, time.monotonic() - start_time, f"Timed out after {timeout_seconds}s"
        )
    except FileNotFoundError:
        return _make_error_result(mode, plan_path, 0.0, f"Claude CLI not found: {claude_path}")


def run_tim_loop_interactive(
    plan_path: Path,
    mode: TimLoopMode,
    max_iterations: int | None = None,
    claude_path: str = "claude",
) -> TimLoopResult:
    """Run tim-loop interactively (stdout/stderr go to terminal).

    This is the preferred method as it shows real-time output.
    """
    if max_iterations is None:
        max_iterations = _get_default_iterations(mode)

    prompt = _build_tim_loop_command(plan_path, mode, max_iterations)
    start_time = time.monotonic()

    try:
        result = subprocess.run(
            [claude_path, "-p", prompt],
            stdin=sys.stdin,
            stdout=sys.stdout,
            stderr=sys.stderr,
        )

        return TimLoopResult(
            success=result.returncode == 0,
            mode=mode,
            plan_path=plan_path,
            duration_seconds=time.monotonic() - start_time,
            exit_code=result.returncode,
            error=None if result.returncode == 0 else f"Exit code: {result.returncode}",
        )

    except FileNotFoundError:
        return TimLoopResult(
            success=False,
            mode=mode,
            plan_path=plan_path,
            duration_seconds=0.0,
            exit_code=-1,
            error=f"Claude CLI not found at: {claude_path}",
        )


def print_tim_loop_command(
    plan_path: Path,
    mode: TimLoopMode,
    max_iterations: int | None = None,
) -> str:
    """Print the tim-loop command for manual execution.

    Returns the command string.
    """
    if max_iterations is None:
        max_iterations = _get_default_iterations(mode)

    cmd = _build_tim_loop_command(plan_path, mode, max_iterations)
    print("\nRun /clear first, then paste this command in Claude Code:\n")
    print(f"  {cmd}\n")
    return cmd
