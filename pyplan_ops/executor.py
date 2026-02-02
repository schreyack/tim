"""Claude CLI subprocess execution.

Manages execution of Claude via the CLI with proper argument handling.
"""

import asyncio
import json
import time
from dataclasses import dataclass, field

from pyplan_ops.models import ExecutionResult


@dataclass
class ClaudeExecutor:
    """Executes Claude via the CLI subprocess."""

    timeout_seconds: float = 300.0
    claude_path: str = "claude"
    default_model: str | None = None
    extra_args: list[str] = field(default_factory=list)

    def _build_command(
        self,
        prompt: str,
        allowed_tools: list[str],
        output_format: str,
    ) -> list[str]:
        """Build the claude CLI command."""
        cmd = [self.claude_path, "-p", prompt]

        if allowed_tools:
            cmd.extend(["--allowed-tools", ",".join(allowed_tools)])

        if output_format == "json":
            cmd.extend(["--output-format", "json"])

        if self.default_model:
            cmd.extend(["--model", self.default_model])

        cmd.extend(self.extra_args)

        return cmd

    async def _run_subprocess(self, cmd: list[str]) -> tuple[bytes, bytes, int]:
        """Run subprocess and return stdout, stderr, returncode."""
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            process.communicate(),
            timeout=self.timeout_seconds,
        )
        return stdout, stderr, process.returncode or 0

    def _build_result(
        self, stdout: bytes, stderr: bytes, returncode: int, duration: float
    ) -> ExecutionResult:
        """Build ExecutionResult from subprocess output."""
        stdout_str = stdout.decode("utf-8", errors="replace")
        stderr_str = stderr.decode("utf-8", errors="replace")

        if returncode != 0:
            return ExecutionResult(
                success=False,
                output=stdout_str,
                error=stderr_str or f"Process exited with code {returncode}",
                duration_seconds=duration,
                exit_code=returncode,
            )
        return ExecutionResult(
            success=True,
            output=stdout_str,
            error=None,
            duration_seconds=duration,
            exit_code=0,
        )

    async def execute(
        self,
        prompt: str,
        allowed_tools: list[str] | None = None,
        output_format: str = "json",
    ) -> ExecutionResult:
        """Execute a prompt via Claude CLI."""
        cmd = self._build_command(prompt, allowed_tools or [], output_format)
        start_time = time.monotonic()

        try:
            stdout, stderr, returncode = await self._run_subprocess(cmd)
            duration = time.monotonic() - start_time
            return self._build_result(stdout, stderr, returncode, duration)
        except TimeoutError:
            return ExecutionResult(
                success=False,
                output="",
                error=f"Execution timed out after {self.timeout_seconds}s",
                duration_seconds=time.monotonic() - start_time,
                exit_code=-1,
            )
        except FileNotFoundError:
            return ExecutionResult(
                success=False,
                output="",
                error=f"Claude CLI not found at: {self.claude_path}",
                duration_seconds=0.0,
                exit_code=-1,
            )

    def parse_json_output(self, output: str) -> dict[str, object] | list[object] | None:
        """Parse JSON output from Claude CLI."""
        try:
            result = json.loads(output)
            if isinstance(result, dict):
                return dict(result)
            if isinstance(result, list):
                return list(result)
            return None
        except json.JSONDecodeError:
            return None
