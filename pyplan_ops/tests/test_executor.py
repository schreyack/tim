"""Tests for Claude CLI executor."""


import pytest

from pyplan_ops.executor import ClaudeExecutor


class TestClaudeExecutor:
    def test_build_command_basic(self) -> None:
        executor = ClaudeExecutor()
        cmd = executor._build_command("test prompt", [], "text")

        assert cmd[0] == "claude"
        assert "-p" in cmd
        assert "test prompt" in cmd

    def test_build_command_with_tools(self) -> None:
        executor = ClaudeExecutor()
        cmd = executor._build_command("prompt", ["Read", "Write"], "json")

        assert "--allowed-tools" in cmd
        tools_idx = cmd.index("--allowed-tools")
        assert cmd[tools_idx + 1] == "Read,Write"

    def test_build_command_with_json_format(self) -> None:
        executor = ClaudeExecutor()
        cmd = executor._build_command("prompt", [], "json")

        assert "--output-format" in cmd
        assert "json" in cmd

    def test_build_command_with_model(self) -> None:
        executor = ClaudeExecutor(default_model="claude-3-opus")
        cmd = executor._build_command("prompt", [], "text")

        assert "--model" in cmd
        assert "claude-3-opus" in cmd

    def test_parse_json_output_valid(self) -> None:
        executor = ClaudeExecutor()
        result = executor.parse_json_output('{"key": "value"}')

        assert result == {"key": "value"}

    def test_parse_json_output_invalid(self) -> None:
        executor = ClaudeExecutor()
        result = executor.parse_json_output("not json")

        assert result is None

    @pytest.mark.asyncio
    async def test_execute_handles_missing_cli(self) -> None:
        executor = ClaudeExecutor(claude_path="/nonexistent/claude")
        result = await executor.execute("test prompt")

        assert not result.success
        assert result.error is not None
        assert "not found" in result.error.lower()
