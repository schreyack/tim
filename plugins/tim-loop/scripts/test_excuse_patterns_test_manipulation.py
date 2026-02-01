#!/usr/bin/env python3
"""
Tests for the TIM excuse detector - Test Manipulation patterns (109-116).

Tests cover:
- Category S: Test Manipulation (patterns 109-116)
- Response routing: test_manipulation → Response S
- Philosophy: Tests are diagnostic tools, not goals
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
build_block_response = _module.build_block_response
has_test_manipulation_patterns = _module.has_test_manipulation_patterns

# Import patterns
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from excuse_patterns import ExcusePattern, EXCUSE_PATTERNS


class TestTestManipulationPatterns:
    """Tests for Category S - Test Manipulation (patterns 109-116)."""

    def test_find_excuses_when_update_test_to_match_detects(self) -> None:
        text = "I'll update the test to match the new behavior."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "test_manipulation" for e, _ in excuses)

    def test_find_excuses_when_fix_test_to_reflect_detects(self) -> None:
        text = "Let me fix the test to reflect the current output."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_adjust_test_expectation_detects(self) -> None:
        text = "I'll adjust the test's expected value."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_change_assertion_expected_detects(self) -> None:
        text = "Let me change the assertion expected value to 42."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_test_needs_to_be_updated_detects(self) -> None:
        text = "The test needs to be updated to match the current behavior."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_test_should_be_changed_detects(self) -> None:
        text = "The test should be changed to reflect the new output."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_make_tests_pass_detects(self) -> None:
        text = "Let me make the tests pass."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_get_tests_to_pass_detects(self) -> None:
        text = "I need to get the tests to pass."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_all_tests_passing_detects(self) -> None:
        text = "All tests are now passing!"
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_my_tests_pass_detects(self) -> None:
        text = "My tests pass now."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_skip_failing_test_detects(self) -> None:
        text = "I'll skip this failing test for now."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_disable_the_test_detects(self) -> None:
        text = "Let me disable the test temporarily."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_comment_out_test_detects(self) -> None:
        text = "I'll comment out this test for now."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_test_checking_wrong_thing_detects(self) -> None:
        text = "The test is checking the wrong behavior."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_test_testing_wrong_value_detects(self) -> None:
        text = "The test is testing the wrong value."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_assertion_was_incorrect_anyway_detects(self) -> None:
        text = "The assertion was incorrect anyway."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_expectation_is_outdated_detects(self) -> None:
        text = "The expectation is outdated anyway."
        excuses = find_excuses(text)
        assert len(excuses) >= 1


class TestTestManipulationCategoryDetection:
    """Verify test_manipulation category is properly detected."""

    def test_has_test_manipulation_patterns_when_category_matches_returns_true(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test",
            example="test",
            category="test_manipulation",
        )
        assert has_test_manipulation_patterns([(excuse, "context")]) is True

    def test_has_test_manipulation_patterns_when_general_returns_false(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test",
            example="test",
            category="general",
        )
        assert has_test_manipulation_patterns([(excuse, "context")]) is False


class TestTestManipulationResponseRouting:
    """Verify correct response is chosen for test_manipulation patterns."""

    def test_build_block_response_when_test_manipulation_uses_correct_response(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test desc",
            example="test",
            category="test_manipulation",
        )
        response = build_block_response([(excuse, "some context")])
        assert response["decision"] == "block"
        assert "diagnostic tool" in response["reason"]

    def test_build_block_response_when_test_manipulation_has_guidance(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test desc",
            example="test",
            category="test_manipulation",
        )
        response = build_block_response([(excuse, "some context")])
        assert "STOP trying to make the test pass" in response["reason"]
        assert "Understand what the test is checking" in response["reason"]
        assert "Fix the APPLICATION" in response["reason"]

    def test_build_block_response_when_posthook_takes_priority_over_test(self) -> None:
        posthook = ExcusePattern(
            pattern="test",
            description="test desc",
            example="test",
            category="posthook",
        )
        test = ExcusePattern(
            pattern="test",
            description="test desc",
            example="test",
            category="test_manipulation",
        )
        response = build_block_response([(test, "ctx"), (posthook, "ctx")])
        assert "confused" in response["reason"]


class TestRealWorldTestManipulationExamples:
    """Test real-world examples of test manipulation behavior."""

    def test_changing_expected_value_to_match_output(self) -> None:
        text = (
            "The test expects 100 but the function returns 95. "
            "Let me update the test's expected value to 95."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_claiming_test_is_wrong_to_avoid_fixing_code(self) -> None:
        text = (
            "The test is checking the wrong behavior. The current behavior "
            "is correct, so the test assertion was incorrect anyway."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_declaring_victory_when_tests_pass(self) -> None:
        text = (
            "I've made the changes and all tests are now passing! "
            "The implementation is complete."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_skipping_test_instead_of_investigating(self) -> None:
        text = (
            "This test is failing intermittently. I'll skip this failing test "
            "for now and we can investigate later."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 1


class TestUpdatedPatternCounts:
    """Verify pattern counts include new Category S patterns."""

    def test_excuse_patterns_includes_test_manipulation(self) -> None:
        test_patterns = [p for p in EXCUSE_PATTERNS if p.category == "test_manipulation"]
        assert len(test_patterns) == 8

    def test_excuse_patterns_total_count(self) -> None:
        assert len(EXCUSE_PATTERNS) == 117


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
