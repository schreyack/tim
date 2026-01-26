#!/usr/bin/env python3
"""
Tests for the TIM excuse detector hook - Core patterns (1-38).

Tests cover:
- Core pattern detection (patterns 1-38)
- Mitigation detection (false positive prevention)
- Bypass regression prevention
- Scope reduction patterns (29-38)

See test_excuse_patterns_extended.py for extended pattern tests (39-76).
"""

import importlib.util
import pytest

# Load module with hyphenated filename
_spec = importlib.util.spec_from_file_location(
    "excuse_detector",
    __file__.rsplit("/", 1)[0] + "/excuse-detector.py"
)
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)

# Import from the detector module
find_excuses = _module.find_excuses
has_mitigation_nearby = _module.has_mitigation_nearby

# Import patterns from the patterns module
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from excuse_patterns import ExcusePattern, EXCUSE_PATTERNS, MITIGATION_PATTERNS


class TestNewPatternDetection:
    """Tests for new patterns 17-28."""

    def test_find_excuses_when_originated_in_legacy_detects_deflection(self) -> None:
        text = "This issue originated in legacy work before I started."
        excuses = find_excuses(text)
        assert len(excuses) == 1
        assert "originated" in excuses[0][1].lower()

    def test_find_excuses_when_stems_from_prior_detects_deflection(self) -> None:
        text = "The problem stems from prior development decisions."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_predates_changes_detects_deflection(self) -> None:
        text = "This violation predates my changes to the file."
        excuses = find_excuses(text)
        assert len(excuses) == 1
        assert "predates" in excuses[0][1].lower()

    def test_find_excuses_when_existed_before_detects_deflection(self) -> None:
        text = "The bug existed before my modifications were made."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_isnt_in_scope_detects_deflection(self) -> None:
        text = "This issue isn't in scope for the current task."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_follow_up_task_detects_deflection(self) -> None:
        text = "We should address this in a follow-up task."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_future_work_detects_deflection(self) -> None:
        text = "This can be done as future work."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_technical_debt_detects_deflection(self) -> None:
        text = "This is just technical debt from years ago."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_its_technical_debt_detects_deflection(self) -> None:
        text = "It's technical debt that someone else should handle."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_barely_touched_detects_deflection(self) -> None:
        text = "I barely touched that part of the code."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_hardly_changed_detects_deflection(self) -> None:
        text = "I hardly changed anything in that file."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_shouldnt_fix_detects_deflection(self) -> None:
        text = "We shouldn't fix this as part of the current PR."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_another_teams_responsibility_detects_deflection(
        self,
    ) -> None:
        text = "This is another team's responsibility to fix."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_someone_elses_responsibility_detects_deflection(
        self,
    ) -> None:
        text = "This is someone else's responsibility."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_someone_elses_issue_detects_deflection(self) -> None:
        text = "This is someone else's issue to deal with."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_cleanup_would_be_separate_detects_deflection(
        self,
    ) -> None:
        text = "The cleanup would be a separate effort from this task."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_refactoring_should_be_separate_detects_deflection(
        self,
    ) -> None:
        text = "Refactoring should be separate from feature work."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_leave_as_is_detects_deflection(self) -> None:
        text = "Let's just leave it as-is for now."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_leaving_alone_detects_deflection(self) -> None:
        text = "I'm leaving this alone since it works."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_outside_my_area_detects_deflection(self) -> None:
        text = "This is outside my area of expertise."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_not_our_domain_detects_deflection(self) -> None:
        text = "The issue is not our domain to handle."
        excuses = find_excuses(text)
        assert len(excuses) == 1


class TestMitigationDetection:
    """Tests for mitigation pattern detection (false positive prevention)."""

    def test_has_mitigation_when_ill_fix_returns_true(self) -> None:
        text = "There was a pre-existing bug but I'll fix it now."
        match_end = text.index("bug") + 3
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_i_fixed_returns_true(self) -> None:
        text = "The legacy code had issues so I fixed them all."
        match_end = text.index("issues") + 6
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_im_fixing_returns_true(self) -> None:
        text = "This was already broken but I'm fixing it right now."
        match_end = text.index("broken") + 6
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_fixing_anyway_returns_true(self) -> None:
        text = "Not my fault but fixing it anyway."
        match_end = text.index("fault") + 5
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_went_ahead_and_fixed_returns_true(self) -> None:
        text = "The issue predates my work but I went ahead and fixed it."
        match_end = text.index("work") + 4
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_addressed_it_returns_true(self) -> None:
        text = "It was an inherited problem. I addressed it completely."
        match_end = text.index("problem") + 7
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_no_mitigation_returns_false(self) -> None:
        text = "This was already broken and not my problem to fix."
        match_end = text.index("broken") + 6
        assert has_mitigation_nearby(text, match_end) is False

    def test_find_excuses_when_followed_by_mitigation_skips_flagging(self) -> None:
        text = "There was a pre-existing bug but I'll fix it now."
        excuses = find_excuses(text)
        assert len(excuses) == 0

    def test_find_excuses_when_fixed_after_excuse_skips_flagging(self) -> None:
        text = "The legacy code had issues so I fixed them all."
        excuses = find_excuses(text)
        assert len(excuses) == 0

    def test_find_excuses_when_no_mitigation_flags_excuse(self) -> None:
        text = "This was already broken and that's why it fails."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_mitigation_too_far_flags_excuse(self) -> None:
        # Mitigation is more than 150 chars away
        text = (
            "There was a pre-existing bug. "
            + "x" * 150
            + " but I'll fix it."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 1


class TestBypassPrevention:
    """Regression tests to ensure bypass attempts still get caught."""

    def test_find_excuses_when_was_already_broken_detects_original(self) -> None:
        text = "The file was already broken before I touched it."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_not_part_of_my_changes_detects_original(self) -> None:
        text = "This wasn't part of my changes to the codebase."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_pre_existing_issue_detects_original(self) -> None:
        text = "This is a pre-existing issue from the original code."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_not_my_fault_detects_original(self) -> None:
        text = "This isn't my fault, the test was broken."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_didnt_cause_detects_original(self) -> None:
        text = "I didn't cause this violation."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_out_of_scope_detects_original(self) -> None:
        text = "Fixing this is out of scope for the task."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_wont_refactor_detects_original(self) -> None:
        text = "I won't refactor since it's not in the plan."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_only_added_few_lines_detects_original(self) -> None:
        text = "I only added a few lines, the problem was already there."
        excuses = find_excuses(text)
        assert len(excuses) >= 1


class TestScopeReductionPatterns:
    """Tests for scope reduction and constraint-based deflection (patterns 29-38)."""

    def test_find_excuses_when_simplify_tests_detects_deflection(self) -> None:
        text = "Let me simplify the tests to focus on what can be done."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_restructure_to_be_practical_detects_deflection(
        self,
    ) -> None:
        text = "Let me restructure the tests to be more practical."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_since_plan_says_detects_deflection(self) -> None:
        text = 'Since the plan says "DO NOT modify component files", I need to take a different approach.'
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_cant_be_skipped_detects_deflection(self) -> None:
        text = "The photo requirements can't be skipped."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_cannot_be_bypassed_detects_deflection(self) -> None:
        text = "This validation cannot be bypassed."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_work_within_constraints_detects_deflection(self) -> None:
        text = "I need to work within the existing workflow constraints."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_whats_actually_testable_detects_deflection(self) -> None:
        text = "Let me focus on what's actually testable."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_focus_on_what_can_be_tested_detects_deflection(
        self,
    ) -> None:
        text = "I'll focus on what can actually be tested without completing the full workflow."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_needs_different_approach_detects_deflection(
        self,
    ) -> None:
        text = "This requires a different approach since the prerequisites are complex."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_best_approach_is_restructure_detects_deflection(
        self,
    ) -> None:
        text = "The best approach is to re-structure tests to test components in their natural phases."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_accepting_prerequisites_detects_deflection(self) -> None:
        text = "Accepting that some phases require prerequisites."
        excuses = find_excuses(text)
        assert len(excuses) >= 1

    def test_find_excuses_when_false_dichotomy_detects_deflection(self) -> None:
        text = "This means I need to either upload photos (complex) or change the test approach."
        excuses = find_excuses(text)
        assert len(excuses) >= 1


class TestPatternCount:
    """Verify pattern counts match expectations."""

    def test_excuse_patterns_count_equals_76(self) -> None:
        assert len(EXCUSE_PATTERNS) == 76

    def test_mitigation_patterns_count_equals_15(self) -> None:
        assert len(MITIGATION_PATTERNS) == 15


class TestCaseInsensitivity:
    """Verify patterns work regardless of case."""

    def test_find_excuses_when_uppercase_detects_deflection(self) -> None:
        text = "THIS IS ANOTHER TEAM'S RESPONSIBILITY."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_find_excuses_when_mixed_case_detects_deflection(self) -> None:
        text = "The issue PREDATES My Changes."
        excuses = find_excuses(text)
        assert len(excuses) == 1

    def test_has_mitigation_when_uppercase_returns_true(self) -> None:
        text = "Pre-existing issue BUT I'LL FIX IT."
        match_end = text.index("issue") + 5
        assert has_mitigation_nearby(text, match_end) is True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
