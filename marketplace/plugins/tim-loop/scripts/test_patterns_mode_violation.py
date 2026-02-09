#!/usr/bin/env python3
"""Tests for mode violation pattern detection."""

import pytest

from patterns_mode_violation import (
    REVIEW_MODES,
    build_mode_violation_response,
    find_mode_violations,
)


class TestFindModeViolations:
    """Tests for find_mode_violations function."""

    def test_no_violation_when_not_in_review_mode(self) -> None:
        """No violations detected when not in a review mode."""
        text = "I'll now start implementing the feature."
        violations = find_mode_violations(text, "")
        assert violations == []

    def test_no_violation_when_in_implementation_mode(self) -> None:
        """No violations when mode allows implementation."""
        text = "Phase 3: Implement - I'll create the files now."
        violations = find_mode_violations(text, "implement")
        assert violations == []

    def test_detects_phase_3_implement_in_ai_ready_mode(self) -> None:
        """Catches 'Phase 3: Implement' during ai-ready review."""
        text = "The plan is comprehensive. Phase 3: Implement - I'll start now."
        violations = find_mode_violations(text, "ai-ready")
        assert len(violations) == 1
        assert "Phase 3: Implement" in violations[0].matched_text

    def test_detects_start_implementation_in_tech_review(self) -> None:
        """Catches 'start implementing' during tech review."""
        text = "I'll now start implementing the authentication module."
        violations = find_mode_violations(text, "tech-review")
        assert len(violations) == 1

    def test_detects_begin_implementation_in_full_review(self) -> None:
        """Catches 'begin implementation' during full review."""
        text = "Let me begin implementation of the database layer."
        violations = find_mode_violations(text, "full-review")
        assert len(violations) == 1

    def test_detects_proceed_with_implementation_in_pm_review(self) -> None:
        """Catches 'proceed with implementation' during PM review."""
        text = "Now I'll proceed with the implementation."
        violations = find_mode_violations(text, "pm-review")
        assert len(violations) == 1

    def test_detects_code_modification_intent_in_verify_mode(self) -> None:
        """Catches code modification intent during verify mode."""
        text = "I'll create the missing function in the module."
        violations = find_mode_violations(text, "verify")
        assert len(violations) == 1

    def test_detects_plan_promotion_attempt(self) -> None:
        """Catches attempt to move plan between folders."""
        text = "I'll move the plan from drafts to active now."
        violations = find_mode_violations(text, "tech-review")
        assert len(violations) == 1

    def test_no_false_positive_for_review_language(self) -> None:
        """Normal review language should not trigger violations."""
        text = """
        I've reviewed the plan and found several issues:
        1. The API endpoint is missing error handling
        2. The test coverage could be improved
        Let me add these suggestions to the plan.
        """
        violations = find_mode_violations(text, "ai-ready")
        assert violations == []

    def test_all_review_modes_are_covered(self) -> None:
        """Verify all documented review modes are in REVIEW_MODES set."""
        expected_modes = {"tech-review", "ai-ready", "full-review", "pm-review", "verify"}
        assert REVIEW_MODES == expected_modes


class TestBuildModeViolationResponse:
    """Tests for build_mode_violation_response function."""

    def test_returns_empty_when_no_violations(self) -> None:
        """Returns empty dict when no violations."""
        response = build_mode_violation_response([])
        assert response == {}

    def test_returns_block_decision(self) -> None:
        """Response has block decision."""
        violations = find_mode_violations(
            "Phase 3: Implement", "ai-ready"
        )
        response = build_mode_violation_response(violations)
        assert response["decision"] == "block"

    def test_response_includes_mode_in_message(self) -> None:
        """Response message includes the current mode."""
        violations = find_mode_violations(
            "I'll start implementing now", "tech-review"
        )
        response = build_mode_violation_response(violations)
        assert "tech-review" in response["message"]

    def test_response_includes_matched_text(self) -> None:
        """Response message includes what was matched."""
        violations = find_mode_violations(
            "Phase 3: Implement the feature", "ai-ready"
        )
        response = build_mode_violation_response(violations)
        assert "Phase 3: Implement" in response["message"]


class TestRealWorldExamples:
    """Tests based on real-world examples of mode confusion."""

    def test_real_world_example_phase_3_implement(self) -> None:
        """Test the exact example from a real-world bug report."""
        text = """
        The plan is comprehensive and already in active status. I'll now start implementation.

        Phase 3: Implement

        The plan is already approved and in plans/active/. I'll implement it phase by phase.

        Implementation Step 1: Create stem_expectations.py (Foundation - Phase 1)
        """
        violations = find_mode_violations(text, "ai-ready")
        assert len(violations) >= 1
        # Should catch "Phase 3: Implement" or "start implementation"

    def test_no_violation_when_discussing_implementation_abstractly(self) -> None:
        """Discussing implementation in abstract (during review) is OK."""
        text = """
        Looking at this plan, the implementation approach seems sound.
        The implementation steps are well-ordered.
        However, I have concerns about the implementation timeline.
        """
        violations = find_mode_violations(text, "tech-review")
        # These are discussing implementation, not attempting it
        assert violations == []
