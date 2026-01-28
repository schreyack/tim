#!/usr/bin/env python3
"""
Tests for the TIM excuse detector - Post-Hook Defiance and Rule Redefining patterns (77-92).

Tests cover:
- Category O: Post-Hook Defiance (patterns 77-88)
- Category P: Rule Redefining (patterns 89-92)
- Response routing: posthook/redefine → Response B, general only → Response A
- Mitigation interaction for new patterns
- Real-world example from the original incident
"""

import importlib.util
import sys
import pytest

# Load detector module
_spec = importlib.util.spec_from_file_location(
    "excuse_detector",
    __file__.rsplit("/", 1)[0] + "/excuse-detector.py"
)
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)
find_excuses = _module.find_excuses
has_mitigation_nearby = _module.has_mitigation_nearby
build_block_response = _module.build_block_response
has_posthook_or_redefine = _module.has_posthook_or_redefine

# Import patterns
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from excuse_patterns import ExcusePattern, EXCUSE_PATTERNS, MITIGATION_PATTERNS


class TestPostHookDefiancePatterns:
    """Tests for Category O - Post-Hook Defiance (patterns 77-88)."""

    def test_find_excuses_when_despite_the_hook_detects_deflection(self) -> None:
        text = "The changes applied despite the hook blocking them."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_hook_warnings_detects_deflection(self) -> None:
        text = "I see the hook warnings but the edits went through."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_hook_errors_detects_deflection(self) -> None:
        text = "Let me check the hook errors to understand what happened."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_verify_applied_despite_detects_deflection(self) -> None:
        text = "Let me verify my edits applied despite the blocking error."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_scope_strictly_limited_detects_deflection(self) -> None:
        text = "My scope is strictly limited to the requested change."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_only_making_minimal_detects_deflection(self) -> None:
        text = "I'm only making minimal changes to the file."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_just_doing_small_detects_deflection(self) -> None:
        text = "I'm just doing small modifications here."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_specific_line_counts_detects_deflection(self) -> None:
        text = "These files were 1319 and 1302 lines before my edit."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_was_500_lines_detects_deflection(self) -> None:
        text = "The file was 500 lines already."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_not_adding_any_code_detects_deflection(self) -> None:
        text = "I'm not adding any new code, just removing a reference."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_not_adding_lines_detects_deflection(self) -> None:
        text = "I'm not adding lines to this file."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_blocking_my_edits_however_detects_deflection(self) -> None:
        text = "The hook is blocking my edits. However, I believe the changes are correct."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_edits_applied_despite_detects_deflection(self) -> None:
        text = "My edits actually applied despite the hook error."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_changes_applied_regardless_detects_deflection(self) -> None:
        text = "The changes applied regardless of the warning."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_hook_is_false_positive_detects_deflection(self) -> None:
        text = "This hook is a false positive for my case."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_gate_is_incorrect_detects_deflection(self) -> None:
        text = "The gate is incorrect about this violation."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_disable_the_hook_detects_deflection(self) -> None:
        text = "We should disable the hook for this task."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_turn_off_the_validator_detects_deflection(self) -> None:
        text = "Can we turn off the validator temporarily?"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_could_you_disable_hook_detects_deflection(self) -> None:
        text = "Could you disable the hook so I can proceed?"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_would_you_remove_validator_detects_deflection(self) -> None:
        text = "Would you remove the validator for this file?"
        assert len(find_excuses(text)) >= 1


class TestRuleRedefiningPatterns:
    """Tests for Category P - Rule Redefining (patterns 89-92)."""

    def test_find_excuses_when_limit_doesnt_apply_detects_deflection(self) -> None:
        text = "The limit doesn't apply to generated code."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_rule_should_not_apply_detects_deflection(self) -> None:
        text = "This rule shouldn't apply in test files."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_standard_does_not_apply_detects_deflection(self) -> None:
        text = "The standard does not apply to configuration files."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_exception_because_detects_deflection(self) -> None:
        text = "This is an exception because the file is auto-generated."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_special_case_for_detects_deflection(self) -> None:
        text = "This is a special case for migration files."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_contextual_rule_detects_deflection(self) -> None:
        text = "This seems like a contextual rule that doesn't fit here."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_flexible_guideline_detects_deflection(self) -> None:
        text = "This is a flexible guideline, not a hard requirement."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_overridden_by_detects_deflection(self) -> None:
        text = "This rule is overridden by the project requirements."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_superseded_because_detects_deflection(self) -> None:
        text = "The limit is superseded because of the plan scope."
        assert len(find_excuses(text)) >= 1


class TestResponseRouting:
    """Verify correct response is chosen based on pattern categories."""

    def test_has_posthook_or_redefine_when_posthook_pattern_returns_true(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test",
            example="test",
            category="posthook",
        )
        assert has_posthook_or_redefine([(excuse, "context")]) is True

    def test_has_posthook_or_redefine_when_redefine_pattern_returns_true(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test",
            example="test",
            category="redefine",
        )
        assert has_posthook_or_redefine([(excuse, "context")]) is True

    def test_has_posthook_or_redefine_when_general_pattern_returns_false(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test",
            example="test",
            category="general",
        )
        assert has_posthook_or_redefine([(excuse, "context")]) is False

    def test_has_posthook_or_redefine_when_mixed_returns_true(self) -> None:
        general = ExcusePattern(
            pattern="test",
            description="test",
            example="test",
            category="general",
        )
        posthook = ExcusePattern(
            pattern="test",
            description="test",
            example="test",
            category="posthook",
        )
        assert has_posthook_or_redefine([(general, "ctx"), (posthook, "ctx")]) is True

    def test_build_block_response_when_general_uses_response_a(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test desc",
            example="test",
            category="general",
        )
        response = build_block_response([(excuse, "some context")])
        assert response["decision"] == "block"
        assert "counting on complete, quality work" in response["reason"]
        assert "confused" not in response["reason"]

    def test_build_block_response_when_posthook_uses_response_b(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test desc",
            example="test",
            category="posthook",
        )
        response = build_block_response([(excuse, "some context")])
        assert response["decision"] == "block"
        assert "confused" in response["reason"]
        assert "PLEASE STOP AND DO THIS" in response["reason"]

    def test_build_block_response_when_redefine_uses_response_b(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test desc",
            example="test",
            category="redefine",
        )
        response = build_block_response([(excuse, "some context")])
        assert response["decision"] == "block"
        assert "confused" in response["reason"]

    def test_build_block_response_when_mixed_categories_uses_response_b(self) -> None:
        general = ExcusePattern(
            pattern="test",
            description="general desc",
            example="test",
            category="general",
        )
        posthook = ExcusePattern(
            pattern="test",
            description="posthook desc",
            example="test",
            category="posthook",
        )
        response = build_block_response([(general, "ctx"), (posthook, "ctx")])
        assert "confused" in response["reason"]


class TestMitigationInteractionWithNewPatterns:
    """Verify mitigation detection works with posthook/redefine patterns."""

    def test_find_excuses_when_hook_warning_with_mitigation_skips(self) -> None:
        text = "I see the hook warnings but I'll fix the violations now."
        assert len(find_excuses(text)) == 0

    def test_find_excuses_when_disable_hook_with_mitigation_skips(self) -> None:
        text = "We could disable the hook, but let me try to fix this instead."
        assert len(find_excuses(text)) == 0

    def test_find_excuses_when_limit_doesnt_apply_with_mitigation_skips(self) -> None:
        text = "The limit doesn't apply here, but I'll fix it anyway."
        excuses = find_excuses(text)
        assert len(excuses) == 0


class TestRealWorldIncident:
    """Test the actual AI response from the original incident that motivated this feature."""

    def test_find_excuses_when_real_world_defiance_transcript_detects(self) -> None:
        text = (
            "The PostToolUse hook is blocking my edits with a code quality warning. "
            "These files were 1319 and 1302 lines before my changes. "
            "I'm not adding any new code - just removing a cleanup reference. "
            "Let me verify my edits actually applied despite the hook warnings."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 3

    def test_find_excuses_when_real_world_defiance_has_posthook_category(self) -> None:
        text = (
            "The PostToolUse hook is blocking my edits with a code quality warning. "
            "These files were 1319 and 1302 lines before my changes."
        )
        excuses = find_excuses(text)
        posthook_excuses = [e for e, _ in excuses if e.category == "posthook"]
        assert len(posthook_excuses) >= 1

    def test_real_world_response_routes_to_posthook_message(self) -> None:
        text = (
            "These files were 1319 and 1302 lines before my changes. "
            "I'm not adding any new code."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        response = build_block_response(excuses)
        assert "confused" in response["reason"]
        assert "PLEASE STOP AND DO THIS" in response["reason"]


class TestUpdatedPatternCounts:
    """Verify updated pattern counts after adding Categories O and P."""

    def test_excuse_patterns_count_equals_93(self) -> None:
        assert len(EXCUSE_PATTERNS) == 93

    def test_mitigation_patterns_count_equals_15(self) -> None:
        assert len(MITIGATION_PATTERNS) == 15


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
