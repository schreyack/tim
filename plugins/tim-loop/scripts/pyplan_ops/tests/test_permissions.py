"""Tests for permission management."""

from pathlib import Path
from unittest.mock import patch

import pytest

from pyplan_ops.models import Phase, Plan, PlanPermissions, PlanStatus, Task
from pyplan_ops.permissions import PERMISSION_PRESETS, PermissionManager


@pytest.fixture
def permission_manager() -> PermissionManager:
    return PermissionManager()


@pytest.fixture
def sample_plan() -> Plan:
    return Plan(
        path=Path("test.md"),
        title="Test Plan",
        status=PlanStatus(),
        permissions=PlanPermissions(preset="python-dev"),
        phases=[
            Phase(
                id=1,
                name="Phase 1",
                tasks=[Task(id="1.1", name="Task", content="", verify_criteria=[])],
                additional_tools=["WebFetch"],
            )
        ],
    )


class TestPermissionPresets:
    def test_read_only_preset_exists(self) -> None:
        assert "read-only" in PERMISSION_PRESETS
        assert "Read" in PERMISSION_PRESETS["read-only"]

    def test_python_dev_preset_has_write_tools(self) -> None:
        preset = PERMISSION_PRESETS["python-dev"]
        assert "Write" in preset
        assert "Edit" in preset
        assert "Bash" in preset

    def test_full_dev_has_web_tools(self) -> None:
        preset = PERMISSION_PRESETS["full-dev"]
        assert "WebFetch" in preset
        assert "WebSearch" in preset


class TestPermissionManager:
    def test_load_from_plan_resolves_preset(
        self, permission_manager: PermissionManager, sample_plan: Plan
    ) -> None:
        permissions = permission_manager.load_from_plan(sample_plan)

        assert "Read" in permissions.global_tools
        assert "Write" in permissions.global_tools
        assert "Bash" in permissions.global_tools

    def test_load_from_plan_with_unknown_preset(self, permission_manager: PermissionManager) -> None:
        plan = Plan(
            path=Path("test.md"),
            title="Test",
            permissions=PlanPermissions(preset="unknown-preset"),
            phases=[],
        )
        permissions = permission_manager.load_from_plan(plan)
        assert permissions.global_tools == []

    def test_tools_for_phase_includes_global_tools(
        self, permission_manager: PermissionManager, sample_plan: Plan
    ) -> None:
        permissions = permission_manager.load_from_plan(sample_plan)
        tools = permission_manager.tools_for_phase(permissions, 1)

        assert "Read" in tools
        assert "Write" in tools

    def test_tools_for_phase_includes_phase_specific_tools(
        self, permission_manager: PermissionManager
    ) -> None:
        permissions = PlanPermissions(
            global_tools=["Read"],
            phase_tools={1: ["WebFetch"], 2: ["WebSearch"]},
        )
        tools = permission_manager.tools_for_phase(permissions, 1)

        assert "Read" in tools
        assert "WebFetch" in tools
        assert "WebSearch" not in tools

    def test_get_preset_tools_returns_correct_list(self, permission_manager: PermissionManager) -> None:
        tools = permission_manager.get_preset_tools("read-only")
        assert tools == PERMISSION_PRESETS["read-only"]

    def test_get_preset_tools_returns_empty_for_unknown(
        self, permission_manager: PermissionManager
    ) -> None:
        tools = permission_manager.get_preset_tools("nonexistent")
        assert tools == []

    def test_prompt_approval_returns_true_on_yes(self, permission_manager: PermissionManager) -> None:
        permissions = PlanPermissions(preset="python-dev", global_tools=["Read"])
        with patch("builtins.input", return_value="y"):
            result = permission_manager.prompt_approval(permissions)
        assert result is True
        assert permissions.approved is True

    def test_prompt_approval_returns_false_on_no(self, permission_manager: PermissionManager) -> None:
        permissions = PlanPermissions(preset="python-dev", global_tools=["Read"])
        with patch("builtins.input", return_value="n"):
            result = permission_manager.prompt_approval(permissions)
        assert result is False
