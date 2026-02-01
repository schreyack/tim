#!/usr/bin/env python3
"""
Tests for the TIM excuse detector - Failure Dismissal patterns (101-108).

Tests cover:
- Category R: Failure Dismissal (patterns 101-108)
- Response routing: failure_dismissal → Response R
- Mitigation interaction for new patterns
- Real-world example from the test failures incident
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
has_failure_dismissal_patterns = _module.has_failure_dismissal_patterns

# Import patterns
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from excuse_patterns import ExcusePattern, EXCUSE_PATTERNS


class TestFailureDismissalPatterns:
    """Tests for Category R - Failure Dismissal (patterns 101-108)."""

    def test_find_excuses_when_exit_code_is_expected_detects(self) -> None:
        text = "The exit code 1 is expected because there are pre-existing failures."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_exit_code_is_normal_detects(self) -> None:
        text = "Exit code 2 is normal for this type of command."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_exit_code_due_to_detects(self) -> None:
        text = "The exit code 1 is due to unrelated test failures."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_failures_are_pre_existing_detects(self) -> None:
        text = "These 20 failures are all pre-existing issues."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_failures_were_pre_existing_detects(self) -> None:
        text = "The failures were pre-existing in the codebase."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_failures_existed_pre_existing_detects(self) -> None:
        text = "All failures existed pre-existing before my work."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_failures_unrelated_to_fix_detects(self) -> None:
        text = "20 failures (pre-existing issues unrelated to this fix)"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_failures_unrelated_to_changes_detects(self) -> None:
        text = "The failures are unrelated to my changes."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_failures_existed_before_changes_detects(self) -> None:
        text = "These failures existed before my changes and are unrelated."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_failures_existed_before_the_changes_detects(self) -> None:
        text = "The errors existed before the changes were made."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_not_caused_by_fix_detects(self) -> None:
        text = "These are not caused by the fix I implemented."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_not_caused_by_my_change_detects(self) -> None:
        text = "The failures are not caused by my change to the component."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_pre_existing_failures_in_other_detects(self) -> None:
        text = "There are pre-existing failures in other test files."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_pre_existing_test_failures_unrelated_detects(self) -> None:
        text = "These are pre-existing test failures in unrelated modules."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_failures_in_other_files_detects(self) -> None:
        text = "The 20 failures are all in other test files, not mine."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_failures_in_different_files_detects(self) -> None:
        text = "These failures were in different test files from my work."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_key_verification_tests_pass_detects(self) -> None:
        text = "The key verification is that all guestBooking tests pass."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_important_point_is_tests_pass_detects(self) -> None:
        text = "The important point is that the relevant tests pass."
        assert len(find_excuses(text)) >= 1


class TestFailureDismissalCategoryDetection:
    """Verify failure_dismissal category is properly detected."""

    def test_has_failure_dismissal_patterns_when_category_matches_returns_true(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test",
            example="test",
            category="failure_dismissal",
        )
        assert has_failure_dismissal_patterns([(excuse, "context")]) is True

    def test_has_failure_dismissal_patterns_when_general_returns_false(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test",
            example="test",
            category="general",
        )
        assert has_failure_dismissal_patterns([(excuse, "context")]) is False

    def test_has_failure_dismissal_patterns_when_mixed_returns_true(self) -> None:
        general = ExcusePattern(
            pattern="test",
            description="test",
            example="test",
            category="general",
        )
        failure = ExcusePattern(
            pattern="test",
            description="test",
            example="test",
            category="failure_dismissal",
        )
        assert has_failure_dismissal_patterns([(general, "ctx"), (failure, "ctx")]) is True


class TestFailureDismissalResponseRouting:
    """Verify correct response is chosen for failure_dismissal patterns."""

    def test_build_block_response_when_failure_dismissal_uses_correct_response(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test desc",
            example="test",
            category="failure_dismissal",
        )
        response = build_block_response([(excuse, "some context")])
        assert response["decision"] == "block"
        assert "not your call to make" in response["reason"]
        assert "ASK the human" in response["reason"]

    def test_build_block_response_when_failure_dismissal_has_guidance(self) -> None:
        excuse = ExcusePattern(
            pattern="test",
            description="test desc",
            example="test",
            category="failure_dismissal",
        )
        response = build_block_response([(excuse, "some context")])
        assert "Report the failures clearly" in response["reason"]
        assert "Do NOT claim they are pre-existing" in response["reason"]
        assert "Wait for their guidance" in response["reason"]

    def test_build_block_response_when_posthook_takes_priority_over_failure(self) -> None:
        posthook = ExcusePattern(
            pattern="test",
            description="test desc",
            example="test",
            category="posthook",
        )
        failure = ExcusePattern(
            pattern="test",
            description="test desc",
            example="test",
            category="failure_dismissal",
        )
        response = build_block_response([(failure, "ctx"), (posthook, "ctx")])
        assert "confused" in response["reason"]


class TestRealWorldFailureDismissalIncident:
    """Test the actual AI response from the test failures incident."""

    def test_find_excuses_when_real_world_failure_dismissal_detects(self) -> None:
        text = (
            "The 20 failures are all pre-existing test failures in: "
            "- techWorkflow/phase0-safety.spec.js (2 failures) "
            "- techWorkflow/phase1-approval.spec.js (1 failure) "
            "These are all pre-existing failures in other test files, "
            "unrelated to the guest booking confirmation fix."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_real_world_exit_code_expected_detects(self) -> None:
        text = (
            "The exit code 1 is expected because there are pre-existing test failures "
            "in other test files (timeTracking, TipSelector, visual snapshots, techWorkflow). "
            "These failures existed before my changes and are not caused by the fix."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_real_world_has_failure_dismissal_category(self) -> None:
        text = (
            "The exit code 1 is expected because there are pre-existing test failures."
        )
        excuses = find_excuses(text)
        failure_excuses = [e for e, _ in excuses if e.category == "failure_dismissal"]
        assert len(failure_excuses) >= 1

    def test_real_world_response_routes_to_failure_dismissal_message(self) -> None:
        text = (
            "These 20 failures are all pre-existing test failures in other files. "
            "The exit code 1 is expected."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        response = build_block_response(excuses)
        assert "ASK the human" in response["reason"]
        assert "not your call to make" in response["reason"]

    def test_real_world_complete_transcript_detects_multiple_patterns(self) -> None:
        text = (
            "The test run is complete. The results show: "
            "- 742 passed tests "
            "- 6 skipped "
            "- 7 did not run (due to previous failures) "
            "- 20 failures (pre-existing issues unrelated to this fix) "
            "The 20 failures are all pre-existing test failures in other test files. "
            "The exit code 1 is expected because there are pre-existing test failures. "
            "These failures existed before my changes and are unrelated to the "
            "guest booking confirmation fix. The key verification is that all "
            "guestBooking.spec.js tests pass (20 tests)."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 3


class TestUpdatedPatternCounts:
    """Verify pattern counts include new Category R patterns."""

    def test_excuse_patterns_includes_failure_dismissal(self) -> None:
        failure_patterns = [p for p in EXCUSE_PATTERNS if p.category == "failure_dismissal"]
        assert len(failure_patterns) == 8

    def test_excuse_patterns_total_count(self) -> None:
        assert len(EXCUSE_PATTERNS) == 117


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
