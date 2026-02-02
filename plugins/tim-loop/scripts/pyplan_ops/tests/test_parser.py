"""Tests for plan parser."""

from pathlib import Path

import pytest

from pyplan_ops.parser import (
    parse_permissions,
    parse_phase_meta,
    parse_phases,
    parse_plan,
    parse_status_table,
    parse_title,
    parse_verify_criteria,
)


@pytest.fixture
def valid_plan_path() -> Path:
    return Path(__file__).parent / "fixtures" / "valid_plan.md"


@pytest.fixture
def valid_plan_content(valid_plan_path: Path) -> str:
    return valid_plan_path.read_text()


class TestParseTitle:
    def test_extracts_h1_title(self) -> None:
        content = "# My Plan Title\n\nSome content"
        assert parse_title(content) == "My Plan Title"

    def test_returns_untitled_when_no_h1(self) -> None:
        content = "No title here\n## Just a section"
        assert parse_title(content) == "Untitled Plan"


class TestParseStatusTable:
    def test_extracts_status_fields(self) -> None:
        content = """
## Status

| Field | Value |
|-------|-------|
| Stage | draft |
| Created | 2025-02-01 |
| Author | Claude |
"""
        status = parse_status_table(content)
        assert status.stage == "draft"
        assert status.created == "2025-02-01"
        assert status.author == "Claude"

    def test_handles_missing_fields(self) -> None:
        content = "| Stage | active |"
        status = parse_status_table(content)
        assert status.stage == "active"
        assert status.author == ""


class TestParsePermissions:
    def test_extracts_preset(self) -> None:
        content = """
<!-- PLAN_PERMISSIONS
preset: python-dev
-->
"""
        permissions = parse_permissions(content)
        assert permissions.preset == "python-dev"

    def test_handles_no_permissions_block(self) -> None:
        content = "No permissions here"
        permissions = parse_permissions(content)
        assert permissions.preset == ""


class TestParsePhaseMeta:
    def test_extracts_dependencies(self) -> None:
        content = """
## Phase 2: Second Phase

<!-- PHASE_META
depends: Phase 1
-->
"""
        depends, tools = parse_phase_meta(content, 0, None)
        assert depends == [1]

    def test_handles_none_dependencies(self) -> None:
        content = """
<!-- PHASE_META
depends: none
-->
"""
        depends, tools = parse_phase_meta(content, 0, None)
        assert depends == []


class TestParseVerifyCriteria:
    def test_extracts_checkbox_items(self) -> None:
        content = """
**Verify**:
- [ ] First criterion
- [ ] Second criterion
- [x] Already checked
"""
        criteria = parse_verify_criteria(content)
        assert len(criteria) == 3
        assert "First criterion" in criteria
        assert "Second criterion" in criteria


class TestParsePhases:
    def test_extracts_phases_from_content(self, valid_plan_content: str) -> None:
        phases = parse_phases(valid_plan_content)
        assert len(phases) == 2
        assert phases[0].id == 1
        assert phases[0].name == "Create File"
        assert phases[1].id == 2
        assert phases[1].name == "Modify File"

    def test_extracts_tasks_within_phases(self, valid_plan_content: str) -> None:
        phases = parse_phases(valid_plan_content)
        assert len(phases[0].tasks) == 1
        assert phases[0].tasks[0].id == "1.1"
        assert phases[0].tasks[0].name == "Create test file"


class TestParsePlan:
    def test_parses_complete_plan(self, valid_plan_path: Path) -> None:
        plan = parse_plan(valid_plan_path)

        assert plan.title == "Test Plan: Create a File"
        assert plan.status.stage == "draft"
        assert plan.permissions.preset == "python-dev"
        assert len(plan.phases) == 2

    def test_extracts_verification_criteria(self, valid_plan_path: Path) -> None:
        plan = parse_plan(valid_plan_path)

        task = plan.phases[0].tasks[0]
        assert len(task.verify_criteria) == 2
        assert "File `test_output.txt` exists" in task.verify_criteria
