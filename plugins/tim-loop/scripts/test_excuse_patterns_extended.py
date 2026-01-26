#!/usr/bin/env python3
"""
Tests for the TIM excuse detector - Extended patterns (39-76).

Tests cover Categories A-O:
- Time/Effort (A), Risk Aversion (B), Deferral (D), Minimization (G)
- Documentation (H), Conditional Compliance (I), Permission Seeking (J)
- Claiming No Problem (K), False Progress (L), Authority Appeals (M)
- Alternative Deflection (N)
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

# Import patterns
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from excuse_patterns import EXCUSE_PATTERNS, MITIGATION_PATTERNS


class TestTimeEffortPatterns:
    """Tests for Category A - Time/Effort deflection (patterns 39-41)."""

    def test_find_excuses_when_would_take_too_long_detects_deflection(self) -> None:
        text = "This would take too long to fix properly."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_take_much_time_detects_deflection(self) -> None:
        text = "This will take much time to implement."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_dont_have_time_detects_deflection(self) -> None:
        text = "I don't have time to refactor this module."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_requires_significant_effort_detects_deflection(self) -> None:
        text = "This requires significant effort to complete."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_considerable_work_detects_deflection(self) -> None:
        text = "This needs considerable work to fix."
        assert len(find_excuses(text)) >= 1


class TestRiskAversionPatterns:
    """Tests for Category B - Risk Aversion as Excuse (patterns 42-45)."""

    def test_find_excuses_when_could_break_things_detects_deflection(self) -> None:
        text = "This could break things in production."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_might_break_other_detects_deflection(self) -> None:
        text = "Changing this might break other functionality."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_too_risky_detects_deflection(self) -> None:
        text = "It's too risky to change without more testing."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_could_introduce_regressions_detects_deflection(self) -> None:
        text = "This could introduce regressions in the system."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_dangerous_to_modify_detects_deflection(self) -> None:
        text = "It's dangerous to modify this code."
        assert len(find_excuses(text)) >= 1


class TestDeferralPatterns:
    """Tests for Category D - Deferral to Others (patterns 46-48)."""

    def test_find_excuses_when_human_should_decide_detects_deflection(self) -> None:
        text = "A human should decide on this approach."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_team_should_discuss_detects_deflection(self) -> None:
        text = "The team should discuss this first."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_someone_with_expertise_detects_deflection(self) -> None:
        text = "Someone with more expertise should handle this."
        assert len(find_excuses(text)) >= 1


class TestMinimizationPatterns:
    """Tests for Category G - Minimization (patterns 49-52)."""

    def test_find_excuses_when_minor_issue_detects_deflection(self) -> None:
        text = "This is just a minor issue."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_small_problem_detects_deflection(self) -> None:
        text = "This is a small problem that can wait."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_impact_negligible_detects_deflection(self) -> None:
        text = "The impact is negligible for users."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_rarely_happens_detects_deflection(self) -> None:
        text = "This rarely happens in production."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_edge_case_detects_deflection(self) -> None:
        text = "This is just an edge case."
        assert len(find_excuses(text)) >= 1


class TestDocumentationDeflectionPatterns:
    """Tests for Category H - Documentation Instead of Fixing (patterns 53-56)."""

    def test_find_excuses_when_ill_document_detects_deflection(self) -> None:
        text = "I'll just document this issue for now."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_create_ticket_detects_deflection(self) -> None:
        text = "Let's create a ticket for this."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_add_to_backlog_detects_deflection(self) -> None:
        text = "Adding this to the backlog for later."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_future_task_detects_deflection(self) -> None:
        text = "This should be addressed in a future task."
        assert len(find_excuses(text)) >= 1


class TestConditionalCompliancePatterns:
    """Tests for Category I - Conditional/Reluctant Compliance (patterns 57-59)."""

    def test_find_excuses_when_if_you_insist_detects_deflection(self) -> None:
        text = "If you insist, I can make the change."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_if_you_really_want_detects_deflection(self) -> None:
        text = "If you really want me to, I'll do it."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_dont_recommend_detects_deflection(self) -> None:
        text = "I can do it but I don't recommend this approach."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_ill_proceed_but_detects_deflection(self) -> None:
        text = "I'll proceed but I have concerns about this."
        assert len(find_excuses(text)) >= 1


class TestAskingPermissionPatterns:
    """Tests for Category J - Asking Permission Not To (patterns 60-63)."""

    def test_find_excuses_when_should_i_skip_detects_deflection(self) -> None:
        text = "Should I skip this for now?"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_acceptable_to_defer_detects_deflection(self) -> None:
        text = "Would it be acceptable to defer this?"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_want_me_to_leave_detects_deflection(self) -> None:
        text = "Do you want me to leave this as-is?"
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_can_we_table_detects_deflection(self) -> None:
        text = "Can we table this for later?"
        assert len(find_excuses(text)) >= 1


class TestClaimingNoProblemPatterns:
    """Tests for Category K - Claiming It Works/No Problem (patterns 64-67)."""

    def test_find_excuses_when_works_as_intended_detects_deflection(self) -> None:
        text = "This works as intended."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_current_behavior_correct_detects_deflection(self) -> None:
        text = "The current behavior is correct."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_isnt_a_bug_detects_deflection(self) -> None:
        text = "This isn't actually a bug."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_test_expectation_wrong_detects_deflection(self) -> None:
        text = "The test's expectation is wrong."
        assert len(find_excuses(text)) >= 1


class TestFalseProgressPatterns:
    """Tests for Category L - False Progress Claims (patterns 68-70)."""

    def test_find_excuses_when_addressed_key_parts_detects_deflection(self) -> None:
        text = "I've addressed the key parts of the issue."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_essential_complete_detects_deflection(self) -> None:
        text = "The essential functionality is complete."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_most_work_done_detects_deflection(self) -> None:
        text = "Most of the work is done."
        assert len(find_excuses(text)) >= 1


class TestAuthorityAppealPatterns:
    """Tests for Category M - Authority/Precedent Appeals (patterns 71-73)."""

    def test_find_excuses_when_original_author_reason_detects_deflection(self) -> None:
        text = "The original author must have had a reason for this."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_pattern_used_elsewhere_detects_deflection(self) -> None:
        text = "This pattern is used elsewhere in the codebase."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_always_been_done_detects_deflection(self) -> None:
        text = "This is how it's always been done."
        assert len(find_excuses(text)) >= 1


class TestAlternativeDeflectionPatterns:
    """Tests for Category N - Alternative Deflection (patterns 74-76)."""

    def test_find_excuses_when_instead_of_fixing_detects_deflection(self) -> None:
        text = "Instead of fixing this, we should redesign the system."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_real_solution_avoid_detects_deflection(self) -> None:
        text = "The real solution is to avoid this pattern entirely."
        assert len(find_excuses(text)) >= 1

    def test_find_excuses_when_rather_than_fixing_detects_deflection(self) -> None:
        text = "Rather than fixing, let's refactor the whole module."
        assert len(find_excuses(text)) >= 1


class TestEnhancedMitigationPatterns:
    """Tests for enhanced mitigation patterns (7-15)."""

    def test_has_mitigation_when_let_me_try_returns_true(self) -> None:
        text = "This is a risk but let me try a different approach."
        match_end = text.index("risk") + 4
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_i_can_still_returns_true(self) -> None:
        text = "This is complex but I can still make it work."
        match_end = text.index("complex") + 7
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_nevertheless_returns_true(self) -> None:
        text = "This is an edge case. Nevertheless, I'll handle it."
        match_end = text.index("case") + 4
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_however_ill_returns_true(self) -> None:
        text = "Risky change. However, I'll find a safe way."
        match_end = text.index("change") + 6
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_workaround_returns_true(self) -> None:
        text = "Can't be bypassed. I'll find a workaround."
        match_end = text.index("bypassed") + 8
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_working_around_by_returns_true(self) -> None:
        text = "The constraint exists. Working around it by using mocks."
        match_end = text.index("exists") + 6
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_so_instead_returns_true(self) -> None:
        text = "Can't modify. So instead I'll create a wrapper."
        match_end = text.index("modify") + 6
        assert has_mitigation_nearby(text, match_end) is True

    def test_has_mitigation_when_heres_how_returns_true(self) -> None:
        text = "This is tricky. Here's how I'll handle it."
        match_end = text.index("tricky") + 6
        assert has_mitigation_nearby(text, match_end) is True

    def test_find_excuses_when_risk_with_mitigation_skips_flagging(self) -> None:
        text = "This could break things but I'll find a workaround."
        assert len(find_excuses(text)) == 0

    def test_find_excuses_when_minor_with_mitigation_skips_flagging(self) -> None:
        text = "It's a minor issue. Nevertheless, I'll fix it now."
        assert len(find_excuses(text)) == 0


class TestUpdatedPatternCounts:
    """Verify updated pattern counts."""

    def test_excuse_patterns_count_equals_76(self) -> None:
        assert len(EXCUSE_PATTERNS) == 76

    def test_mitigation_patterns_count_equals_15(self) -> None:
        assert len(MITIGATION_PATTERNS) == 15


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
