#!/usr/bin/env python3
"""
Tests for the TIM excuse detector - Extended Failure Dismissal patterns (109-144).

Tests cover new patterns added to catch AI evasion techniques:
- R2 Extended: Pre-existing/Already Broken Claims (109)
- R3 Extended: Unrelated/Not Related Claims (110-119)
- R4: Scope/Plan Exclusion Claims (120-125)
- R6 Extended: Reframing/Minimization (129-135)
- R7: Moving On Without Resolution (136-140)
- R8: Known Issue Claims (141-144)

These patterns were added after observing AI successfully evade the original
patterns by rephrasing excuses slightly differently.
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

# Import patterns
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from excuse_patterns import EXCUSE_PATTERNS


class TestPreExistingAlreadyBrokenExtended:
    """Tests for R2 Extended - Pre-existing/Already Broken Claims."""

    def test_find_excuses_when_existing_test_failing_detects(self) -> None:
        """Test pattern: 'existing test that was failing'."""
        text = "it's an existing test that was failing before this plan"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_was_failing_before_this_plan_detects(self) -> None:
        """Test pattern: 'was failing before this plan'."""
        text = "The test was failing before this plan started"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_was_already_failing_detects(self) -> None:
        """Test pattern: 'was already failing'."""
        text = "The test was already failing when I started"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_was_already_broken_detects(self) -> None:
        """Test pattern: 'was already broken'."""
        text = "This component was already broken"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_already_had_issues_detects(self) -> None:
        """Test pattern: 'already had issues'."""
        text = "This file already had issues before I touched it"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_predates_changes_detects(self) -> None:
        """Test pattern: 'predates my changes'."""
        text = "This failure predates my changes"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_existing_issue_has_been_failing_detects(self) -> None:
        """Test pattern variation: 'existing issue has been failing'."""
        text = "it's an existing issue that has been failing for weeks"
        assert len(find_excuses(text)) >= 1


class TestUnrelatedNotRelatedExtended:
    """Tests for R3 Extended - Unrelated/Not Related Claims."""

    def test_find_excuses_when_this_is_not_related_to_detects(self) -> None:
        """Test pattern: 'This is not related to'."""
        text = "This is not related to the guest booking confirmation page fix"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_has_nothing_to_do_with_detects(self) -> None:
        """Test pattern: 'has nothing to do with'."""
        text = "This has nothing to do with my changes"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_is_separate_from_detects(self) -> None:
        """Test pattern: 'is separate from'."""
        text = "This is completely separate from the current implementation"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_a_different_issue_detects(self) -> None:
        """Test pattern: 'a different issue'."""
        text = "That's a different issue from what we're working on"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_a_separate_problem_detects(self) -> None:
        """Test pattern: 'a separate problem'."""
        text = "That's a separate problem"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_not_my_problem_detects(self) -> None:
        """Test pattern: 'not my problem'."""
        text = "That's not my problem to fix"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_someone_elses_issue_detects(self) -> None:
        """Test pattern: 'someone else's issue'."""
        text = "That's someone else's issue to fix"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_is_independent_of_detects(self) -> None:
        """Test pattern: 'is independent of'."""
        text = "This is independent of my work"
        assert len(find_excuses(text)) >= 1


class TestScopePlanExclusion:
    """Tests for R4 - Scope/Plan Exclusion Claims."""

    def test_find_excuses_when_not_part_of_plan_detects(self) -> None:
        """Test pattern: 'not part of this plan'."""
        text = "This is not part of this plan"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_not_part_of_scope_detects(self) -> None:
        """Test pattern: 'not part of the scope'."""
        text = "This is not part of the scope"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_outside_scope_detects(self) -> None:
        """Test pattern: 'outside the scope'."""
        text = "This is outside the scope of this task"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_beyond_scope_detects(self) -> None:
        """Test pattern: 'beyond the scope'."""
        text = "This is beyond the scope"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_out_of_scope_detects(self) -> None:
        """Test pattern: 'out of scope'."""
        text = "That test failure is out of scope"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_wasnt_asked_to_fix_detects(self) -> None:
        """Test pattern: 'wasn't asked to fix'."""
        text = "I wasn't asked to fix that test"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_only_asked_to_detects(self) -> None:
        """Test pattern: 'only asked to'."""
        text = "I was only asked to fix the confirmation page"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_doesnt_fall_under_detects(self) -> None:
        """Test pattern: 'doesn't fall under'."""
        text = "This doesn't fall under the current task"
        assert len(find_excuses(text)) >= 1


class TestReframingMinimizationExtended:
    """Tests for R6 Extended - Reframing/Minimization."""

    def test_find_excuses_when_just_one_failure_detects(self) -> None:
        """Test pattern: 'just one failure'."""
        text = "There's just one failing test"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_only_one_error_detects(self) -> None:
        """Test pattern: 'only one error'."""
        text = "There's only one test failure"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_minor_failure_detects(self) -> None:
        """Test pattern: 'minor failure'."""
        text = "This is a minor failure that we can ignore"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_trivial_issue_detects(self) -> None:
        """Test pattern: 'trivial issue'."""
        text = "This is a trivial issue"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_important_thing_is_detects(self) -> None:
        """Test pattern: 'the important thing is'."""
        text = "The important thing is that the main tests pass"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_can_ignore_detects(self) -> None:
        """Test pattern: 'we can ignore'."""
        text = "We can safely ignore this failure"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_doesnt_affect_detects(self) -> None:
        """Test pattern: 'doesn't affect'."""
        text = "This doesn't affect the feature we're building"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_shouldnt_block_detects(self) -> None:
        """Test pattern: 'shouldn't block'."""
        text = "This shouldn't block us from continuing"
        assert len(find_excuses(text)) >= 1


class TestMovingOnWithoutResolution:
    """Tests for R7 - Moving On Without Resolution."""

    def test_find_excuses_when_let_me_continue_detects(self) -> None:
        """Test pattern: 'let me continue with'."""
        text = "Let me continue with the rest of the implementation"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_ill_proceed_with_detects(self) -> None:
        """Test pattern: 'I'll proceed with'."""
        text = "I'll proceed with the other tasks"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_proceeding_despite_detects(self) -> None:
        """Test pattern: 'proceeding despite'."""
        text = "Proceeding despite the failing test"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_continuing_regardless_detects(self) -> None:
        """Test pattern: 'continuing regardless of'."""
        text = "Continuing regardless of the error"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_setting_aside_detects(self) -> None:
        """Test pattern: 'setting this aside'."""
        text = "Setting this aside for now"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_can_be_fixed_later_detects(self) -> None:
        """Test pattern: 'can be fixed later'."""
        text = "This can be fixed later"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_will_be_addressed_later_detects(self) -> None:
        """Test pattern: 'will be addressed later'."""
        text = "This will be addressed later"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_ignore_for_now_detects(self) -> None:
        """Test pattern: 'ignore for now'."""
        text = "Let's ignore this for now"
        assert len(find_excuses(text)) >= 1


class TestKnownIssueClaims:
    """Tests for R8 - Known Issue Claims."""

    def test_find_excuses_when_known_issue_detects(self) -> None:
        """Test pattern: 'known issue'."""
        text = "This is a known issue"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_known_bug_detects(self) -> None:
        """Test pattern: 'known bug'."""
        text = "This is a known bug"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_flaky_test_detects(self) -> None:
        """Test pattern: 'flaky test'."""
        text = "That's just a flaky test"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_intermittent_failure_detects(self) -> None:
        """Test pattern: 'intermittent failure'."""
        text = "This is an intermittent failure"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_fails_sometimes_detects(self) -> None:
        """Test pattern: 'fails sometimes'."""
        text = "This test fails sometimes"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_happens_occasionally_detects(self) -> None:
        """Test pattern: 'happens occasionally'."""
        text = "This happens occasionally"
        assert len(find_excuses(text)) >= 1


class TestRealWorldEvasionIncident:
    """Test the actual AI response that evaded the original patterns."""

    def test_find_excuses_when_original_evasion_text_detects(self) -> None:
        """The exact text that slipped through before new patterns."""
        text = (
            "There is one failing test but it's an existing test that was "
            "failing before this plan... This is not related to the guest "
            "booking confirmation page fix"
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 2  # Should catch multiple patterns now

    def test_find_excuses_when_evasion_existing_test_detected(self) -> None:
        """First part of evasion: 'existing test that was failing'."""
        text = "it's an existing test that was failing before this plan"
        excuses = find_excuses(text)
        failure_excuses = [e for e, _ in excuses if e.category == "failure_dismissal"]
        assert len(failure_excuses) >= 1

    def test_find_excuses_when_evasion_not_related_detected(self) -> None:
        """Second part of evasion: 'not related to'."""
        text = "This is not related to the guest booking confirmation page fix"
        excuses = find_excuses(text)
        failure_excuses = [e for e, _ in excuses if e.category == "failure_dismissal"]
        assert len(failure_excuses) >= 1


class TestUpdatedPatternCountsExtended:
    """Verify pattern counts after adding extended patterns."""

    def test_excuse_patterns_includes_extended_failure_dismissal(self) -> None:
        failure_patterns = [p for p in EXCUSE_PATTERNS if p.category == "failure_dismissal"]
        assert len(failure_patterns) >= 36  # Was 8, now 44

    def test_excuse_patterns_total_count_increased(self) -> None:
        assert len(EXCUSE_PATTERNS) >= 151  # Was 117


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
