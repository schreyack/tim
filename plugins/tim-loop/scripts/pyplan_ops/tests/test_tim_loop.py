"""Tests for tim-loop integration."""

from pathlib import Path
from unittest.mock import patch

from pyplan_ops.tim_loop import (
    _build_tim_loop_command,
    _get_default_iterations,
    print_tim_loop_command,
)


class TestBuildTimLoopCommand:
    def test_builds_implement_command(self) -> None:
        cmd = _build_tim_loop_command(Path("/test/plan.md"), "implement", 50)
        assert cmd == "/tim-loop:tim-loop --implement /test/plan.md --max-iterations 50"

    def test_builds_full_review_command(self) -> None:
        cmd = _build_tim_loop_command(Path("/test/plan.md"), "full-review", 15)
        assert cmd == "/tim-loop:tim-loop --full-review /test/plan.md --max-iterations 15"

    def test_builds_ai_ready_command(self) -> None:
        cmd = _build_tim_loop_command(Path("/test/plan.md"), "ai-ready", 5)
        assert cmd == "/tim-loop:tim-loop --ai-ready /test/plan.md --max-iterations 5"

    def test_builds_command_without_iterations(self) -> None:
        cmd = _build_tim_loop_command(Path("/test/plan.md"), "verify", None)
        assert cmd == "/tim-loop:tim-loop --verify /test/plan.md"


class TestGetDefaultIterations:
    def test_implement_default(self) -> None:
        assert _get_default_iterations("implement") == 50

    def test_full_review_default(self) -> None:
        assert _get_default_iterations("full-review") == 15

    def test_ai_ready_default(self) -> None:
        assert _get_default_iterations("ai-ready") == 5

    def test_pm_review_default(self) -> None:
        assert _get_default_iterations("pm-review") == 10

    def test_verify_default(self) -> None:
        assert _get_default_iterations("verify") == 10


class TestPrintTimLoopCommand:
    def test_prints_command_with_defaults(self) -> None:
        with patch("builtins.print") as mock_print:
            result = print_tim_loop_command(Path("/test/plan.md"), "implement")

            assert "--implement" in result
            assert "--max-iterations 50" in result
            assert mock_print.call_count == 2

    def test_prints_command_with_custom_iterations(self) -> None:
        with patch("builtins.print"):
            result = print_tim_loop_command(Path("/test/plan.md"), "full-review", 20)

            assert "--full-review" in result
            assert "--max-iterations 20" in result
