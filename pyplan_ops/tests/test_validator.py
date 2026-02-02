"""Tests for plan validator."""

from pathlib import Path

import pytest

from pyplan_ops.validator import validate_plan_structure


@pytest.fixture
def valid_plan_content() -> str:
    return (Path(__file__).parent / "fixtures" / "valid_plan.md").read_text()


@pytest.fixture
def rough_plan_content() -> str:
    return (Path(__file__).parent / "fixtures" / "rough_plan.md").read_text()


@pytest.fixture
def invalid_plan_content() -> str:
    return (Path(__file__).parent / "fixtures" / "invalid_plan.md").read_text()


class TestValidatePlanStructure:
    def test_valid_plan_passes(self, valid_plan_content: str) -> None:
        result = validate_plan_structure(valid_plan_content)
        assert result.is_valid
        assert result.severity == "ok"
        assert len(result.issues) == 0

    def test_empty_plan_is_unfixable(self, invalid_plan_content: str) -> None:
        result = validate_plan_structure(invalid_plan_content)
        assert not result.is_valid
        assert result.severity == "unfixable"

    def test_rough_plan_is_fixable(self, rough_plan_content: str) -> None:
        result = validate_plan_structure(rough_plan_content)
        assert not result.is_valid
        assert result.severity == "fixable"

    def test_detects_missing_status(self) -> None:
        content = "# Plan\n\n## Phase 1: Test\n\n### Task 1.1: Do thing\n\n**Verify**:\n- [ ] Done"
        result = validate_plan_structure(content)
        issues = [i.message for i in result.issues]
        assert any("Status" in msg for msg in issues)

    def test_detects_missing_phases(self) -> None:
        content = "# Plan\n\n## Status\n\n| Field | Value |\n| Stage | draft |"
        result = validate_plan_structure(content)
        issues = [i.message for i in result.issues]
        assert any("phase" in msg.lower() for msg in issues)

    def test_detects_missing_verify_blocks(self) -> None:
        content = """# Plan

## Status

| Field | Value |
| Stage | draft |

## Phase 1: Test

### Task 1.1: Do something

Just do it, no verification.
"""
        result = validate_plan_structure(content)
        issues = [i.message for i in result.issues]
        assert any("Verify" in msg for msg in issues)
