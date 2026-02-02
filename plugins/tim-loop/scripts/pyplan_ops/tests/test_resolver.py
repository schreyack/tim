"""Tests for plan path resolution."""

import tempfile
from collections.abc import Generator
from pathlib import Path
from unittest.mock import patch

import pytest

from pyplan_ops.resolver import (
    find_plans_by_name,
    get_claude_plans_dir,
    get_plans_dir,
    resolve_plan_path,
)


@pytest.fixture
def temp_plans_dir() -> Generator[Path, None, None]:
    """Create a temporary plans directory structure."""
    with tempfile.TemporaryDirectory() as d:
        plans = Path(d) / "plans"
        plans.mkdir()
        (plans / "drafts").mkdir()
        (plans / "active").mkdir()
        (plans / "completed").mkdir()
        (plans / "abandoned").mkdir()

        # Create some test plans
        (plans / "drafts" / "2025-01-15-test-plan.md").write_text("# Test Plan")
        (plans / "active" / "2025-01-16-feature-x.md").write_text("# Feature X")
        (plans / "completed" / "2025-01-10-old-plan.md").write_text("# Old Plan")

        # Create a package
        pkg = plans / "active" / "2025-01-17-big-feature"
        pkg.mkdir()
        (pkg / "MASTER.md").write_text("# Big Feature Package")

        yield plans


class TestGetPlansDir:
    def test_returns_plans_dir_in_cwd(self, temp_plans_dir: Path) -> None:
        with patch("pyplan_ops.resolver.Path.cwd", return_value=temp_plans_dir.parent):
            result = get_plans_dir()
            assert result == temp_plans_dir

    def test_returns_default_when_not_found(self) -> None:
        with tempfile.TemporaryDirectory() as d, patch("pyplan_ops.resolver.Path.cwd", return_value=Path(d)):
            result = get_plans_dir()
            assert result == Path(d) / "plans"


class TestGetClaudePlansDir:
    def test_returns_claude_plans_path(self) -> None:
        result = get_claude_plans_dir()
        assert result == Path.home() / ".claude" / "plans"


class TestFindPlansByName:
    def test_finds_plan_by_partial_name(self, temp_plans_dir: Path) -> None:
        with (
            patch("pyplan_ops.resolver.get_plans_dir", return_value=temp_plans_dir),
            patch("pyplan_ops.resolver.get_claude_plans_dir", return_value=Path("/nonexistent")),
        ):
            results = find_plans_by_name("test")
            assert len(results) == 1
            assert "test-plan.md" in str(results[0])

    def test_finds_plans_across_stages(self, temp_plans_dir: Path) -> None:
        with (
            patch("pyplan_ops.resolver.get_plans_dir", return_value=temp_plans_dir),
            patch("pyplan_ops.resolver.get_claude_plans_dir", return_value=Path("/nonexistent")),
        ):
            results = find_plans_by_name("2025")
            assert len(results) == 4

    def test_finds_package_master_md(self, temp_plans_dir: Path) -> None:
        with (
            patch("pyplan_ops.resolver.get_plans_dir", return_value=temp_plans_dir),
            patch("pyplan_ops.resolver.get_claude_plans_dir", return_value=Path("/nonexistent")),
        ):
            results = find_plans_by_name("big-feature")
            assert len(results) == 1
            assert results[0].name == "MASTER.md"

    def test_returns_empty_when_no_match(self, temp_plans_dir: Path) -> None:
        with (
            patch("pyplan_ops.resolver.get_plans_dir", return_value=temp_plans_dir),
            patch("pyplan_ops.resolver.get_claude_plans_dir", return_value=Path("/nonexistent")),
        ):
            results = find_plans_by_name("nonexistent")
            assert len(results) == 0


class TestResolvePlanPath:
    def test_resolves_existing_file_path(self, temp_plans_dir: Path) -> None:
        plan_file = temp_plans_dir / "drafts" / "2025-01-15-test-plan.md"
        result = resolve_plan_path(str(plan_file))
        assert result == plan_file.resolve()

    def test_resolves_package_directory(self, temp_plans_dir: Path) -> None:
        pkg_dir = temp_plans_dir / "active" / "2025-01-17-big-feature"
        result = resolve_plan_path(str(pkg_dir))
        assert result.name == "MASTER.md"
        assert result.parent == pkg_dir.resolve()

    def test_resolves_by_name_search(self, temp_plans_dir: Path) -> None:
        with (
            patch("pyplan_ops.resolver.get_plans_dir", return_value=temp_plans_dir),
            patch("pyplan_ops.resolver.get_claude_plans_dir", return_value=Path("/nonexistent")),
        ):
            result = resolve_plan_path("test-plan")
            assert "test-plan.md" in str(result)

    def test_raises_when_not_found(self, temp_plans_dir: Path) -> None:
        with (
            patch("pyplan_ops.resolver.get_plans_dir", return_value=temp_plans_dir),
            patch("pyplan_ops.resolver.get_claude_plans_dir", return_value=Path("/nonexistent")),
            pytest.raises(FileNotFoundError),
        ):
            resolve_plan_path("nonexistent-plan")

    def test_prompts_on_multiple_matches(self, temp_plans_dir: Path) -> None:
        with (
            patch("pyplan_ops.resolver.get_plans_dir", return_value=temp_plans_dir),
            patch("pyplan_ops.resolver.get_claude_plans_dir", return_value=Path("/nonexistent")),
            patch("builtins.input", return_value="1"),
        ):
            result = resolve_plan_path("2025-01")
            assert result is not None
