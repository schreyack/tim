#!/usr/bin/env python3
"""Tests for fast_pattern_detector.py - regex-only PostToolUse checks."""

import unittest
from unittest.mock import patch

from fast_pattern_detector import run_fast_checks


def _mock_state(review_mode: str = "", implement_mode: bool = False) -> dict:
    """Build a mock tim-loop state dict."""
    return {
        "REVIEW_MODE": review_mode,
        "IMPLEMENT_MODE": "true" if implement_mode else "false",
        "_state_file": "/tmp/fake-state",
    }


class TestFastPatternDetector(unittest.TestCase):
    """Test fast pattern detection for mode violations."""

    @patch("fast_pattern_detector.load_state")
    def test_catches_phase_3_implement_in_full_review(self, mock_state: unittest.mock.MagicMock) -> None:
        """Should catch 'Phase 3: Implement' announcement during full-review mode."""
        mock_state.return_value = _mock_state(review_mode="full-review")
        text = """I've read the plan. This is a comprehensive plan for replacing custom JWT.

Current Phase Assessment:
- The plan exists and is detailed with clear implementation tasks
- The plan has REVIEWED: YES but does NOT have VERIFIED: NO or VERIFIED: YES
- This means I'm in Phase 3: Implement

Let me understand the current state of the codebase before starting implementation.
"""
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Should block when announcing implementation in review mode")

    @patch("fast_pattern_detector.load_state")
    def test_allows_review_discussion_in_full_review(self, mock_state: unittest.mock.MagicMock) -> None:
        """Should allow normal review discussion without implementation announcements."""
        mock_state.return_value = _mock_state(review_mode="full-review")
        text = """I've read the plan. Let me analyze the technical aspects.

The plan proposes replacing JWT with Clerk. Key concerns:
1. Migration strategy for existing tokens
2. Session management differences
3. Error handling changes needed

I'll continue reviewing the security implications.
"""
        result = run_fast_checks(text)
        self.assertIsNone(result, "Should not block normal review discussion")

    @patch("fast_pattern_detector.load_state")
    def test_allows_implementation_when_not_in_review_mode(self, mock_state: unittest.mock.MagicMock) -> None:
        """Should allow implementation announcements when not in review mode."""
        mock_state.return_value = _mock_state(review_mode="")
        text = "I'm in Phase 3: Implement. Let me start writing the code."
        result = run_fast_checks(text)
        # Mode violation check only runs in review modes
        # But task drift might still catch this - that's ok
        # The key is it shouldn't be blocked as a MODE violation
        if result:
            category, _ = result
            self.assertNotEqual(category, "MODE VIOLATION")

    @patch("fast_pattern_detector.load_state")
    def test_catches_begin_implementation_in_tech_review(self, mock_state: unittest.mock.MagicMock) -> None:
        """Should catch 'begin implementation' during tech-review mode."""
        mock_state.return_value = _mock_state(review_mode="tech-review")
        text = "The plan looks good. I'll now start implementing the changes."
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Should block implementation start in tech-review")

    @patch("fast_pattern_detector.load_state")
    def test_catches_proceed_to_implementation(self, mock_state: unittest.mock.MagicMock) -> None:
        """Should catch 'proceed to implementation' during review mode."""
        mock_state.return_value = _mock_state(review_mode="full-review")
        text = "Review complete. Let me proceed to implementation of the auth changes."
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Should block proceeding to implementation")

    @patch("fast_pattern_detector.load_state")
    def test_allows_plan_fixes_in_full_review(self, mock_state: unittest.mock.MagicMock) -> None:
        """Should allow 'let me fix this' when fixing plan issues in full-review mode.

        In full-review mode, agents are instructed to make improvements to the plan.
        Phrases like 'let me fix this' referring to plan corrections should NOT trigger
        task drift detection.
        """
        mock_state.return_value = _mock_state(review_mode="full-review")
        text = """I see an issue! Line 313 says Revises: cleanup_invalid_detection_rules
but line 321 says down_revision = "seed_target_ranges_sidechain".
These are inconsistent. The docstring should match the actual down_revision.
Let me fix this:"""
        result = run_fast_checks(text)
        self.assertIsNone(result, "Should allow plan fixes in full-review mode")

    @patch("fast_pattern_detector.load_state")
    def test_still_blocks_implementation_in_full_review(self, mock_state: unittest.mock.MagicMock) -> None:
        """Should still block actual implementation attempts in full-review mode.

        Even though task drift is skipped, mode violation should catch implementation intent.
        """
        mock_state.return_value = _mock_state(review_mode="full-review")
        text = "I'll now start implementing the authentication changes in the codebase."
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Should block implementation in full-review")

    @patch("fast_pattern_detector.load_state")
    def test_task_drift_still_works_outside_full_review(self, mock_state: unittest.mock.MagicMock) -> None:
        """Task drift detection should still work when not in full-review mode."""
        mock_state.return_value = _mock_state(review_mode="")
        text = "Let me fix the issues I found during my review."
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Should catch task drift outside review modes")

    @patch("fast_pattern_detector.load_state")
    def test_allows_implementation_audit_heading(self, mock_state: unittest.mock.MagicMock) -> None:
        """Should NOT catch 'Phase N: Implementation Audit' as task drift.

        This is a verification section heading, not an implementation announcement.
        False positive was causing system halts during --verify mode.
        """
        mock_state.return_value = _mock_state(review_mode="")
        text = """Starting verification audit. Let me read the plan file first.

Phase 1: Intent Review

I've read the full plan. Let me now systematically verify every deliverable.

Phase 2: Implementation Audit

Starting parallel verification of all phases.
"""
        result = run_fast_checks(text)
        # Should not trigger on "Phase 2: Implementation Audit"
        if result:
            category, details = result
            self.assertNotIn(
                "Phase 2: Implement",
                details,
                "Should not flag 'Implementation Audit' as task drift",
            )

    @patch("fast_pattern_detector.load_state")
    def test_still_catches_bare_implementation_phase(self, mock_state: unittest.mock.MagicMock) -> None:
        """Should still catch 'Phase 3: Implementation' without audit/review qualifier."""
        mock_state.return_value = _mock_state(review_mode="")
        text = "The review is done. Phase 3: Implementation begins now."
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Should catch bare 'Phase 3: Implementation'")


class TestUserActionIntentBypass(unittest.TestCase):
    """Test that task drift is skipped when the user requested a mutating action."""

    @staticmethod
    def _make_transcript(user_text: str, assistant_text: str) -> list[dict]:
        """Build a minimal transcript with one human turn and one assistant turn."""
        return [
            {"message": {"role": "user", "content": user_text}},
            {"message": {"role": "assistant", "content": assistant_text}},
        ]

    @patch("fast_pattern_detector.load_state")
    def test_skips_task_drift_when_user_said_commit(self, mock_state: unittest.mock.MagicMock) -> None:
        """'Let me fix the pre-commit failures' is not drift when user asked to commit."""
        mock_state.return_value = _mock_state(review_mode="")
        transcript = self._make_transcript(
            "commit push frst",
            "Pre-commit hooks caught issues. Let me fix them all.",
        )
        result = run_fast_checks(
            "Pre-commit hooks caught issues. Let me fix them all.",
            transcript=transcript,
        )
        self.assertIsNone(result, "Should not fire task drift when user asked to commit")

    @patch("fast_pattern_detector.load_state")
    def test_skips_task_drift_when_user_said_fix(self, mock_state: unittest.mock.MagicMock) -> None:
        """'Let me fix the issues' is not drift when user explicitly asked to fix."""
        mock_state.return_value = _mock_state(review_mode="")
        transcript = self._make_transcript(
            "fix the lint errors",
            "Let me fix the issues I found.",
        )
        result = run_fast_checks(
            "Let me fix the issues I found.",
            transcript=transcript,
        )
        self.assertIsNone(result, "Should not fire task drift when user asked to fix")

    @patch("fast_pattern_detector.load_state")
    def test_still_catches_drift_when_user_asked_to_review(self, mock_state: unittest.mock.MagicMock) -> None:
        """'Let me fix the issues' IS drift when user only asked for a review."""
        mock_state.return_value = _mock_state(review_mode="")
        transcript = self._make_transcript(
            "review this code for me",
            "Let me fix the issues I found during my review.",
        )
        result = run_fast_checks(
            "Let me fix the issues I found during my review.",
            transcript=transcript,
        )
        self.assertIsNotNone(result, "Should catch task drift when user only asked for review")

    @patch("fast_pattern_detector.load_state")
    def test_still_catches_drift_with_no_transcript(self, mock_state: unittest.mock.MagicMock) -> None:
        """Backward compat: no transcript means task drift still fires."""
        mock_state.return_value = _mock_state(review_mode="")
        result = run_fast_checks("Let me fix the issues I found.")
        self.assertIsNotNone(result, "Should catch task drift when no transcript provided")

    @patch("fast_pattern_detector.load_state")
    def test_skips_task_drift_when_user_said_deploy(self, mock_state: unittest.mock.MagicMock) -> None:
        """Action intent covers deploy/ship commands too."""
        mock_state.return_value = _mock_state(review_mode="")
        transcript = self._make_transcript(
            "deploy this to dev",
            "Let me fix the failing health check first.",
        )
        result = run_fast_checks(
            "Let me fix the failing health check first.",
            transcript=transcript,
        )
        self.assertIsNone(result, "Should not fire task drift when user asked to deploy")


if __name__ == "__main__":
    unittest.main()
