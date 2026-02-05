#!/usr/bin/env python3
"""Tests for fast_pattern_detector.py - regex-only PostToolUse checks."""

import unittest
from unittest.mock import patch

from fast_pattern_detector import run_fast_checks


class TestFastPatternDetector(unittest.TestCase):
    """Test fast pattern detection for mode violations."""

    @patch("fast_pattern_detector.get_review_mode")
    def test_catches_phase_3_implement_in_full_review(self, mock_mode: unittest.mock.MagicMock) -> None:
        """Should catch 'Phase 3: Implement' announcement during full-review mode."""
        mock_mode.return_value = "full-review"
        text = """I've read the plan. This is a comprehensive plan for replacing custom JWT.

Current Phase Assessment:
- The plan exists and is detailed with clear implementation tasks
- The plan has REVIEWED: YES but does NOT have VERIFIED: NO or VERIFIED: YES
- This means I'm in Phase 3: Implement

Let me understand the current state of the codebase before starting implementation.
"""
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Should block when announcing implementation in review mode")
        self.assertEqual(result.get("decision"), "block")
        self.assertTrue("Mode Violation" in result.get("message", ""))

    @patch("fast_pattern_detector.get_review_mode")
    def test_allows_review_discussion_in_full_review(self, mock_mode: unittest.mock.MagicMock) -> None:
        """Should allow normal review discussion without implementation announcements."""
        mock_mode.return_value = "full-review"
        text = """I've read the plan. Let me analyze the technical aspects.

The plan proposes replacing JWT with Clerk. Key concerns:
1. Migration strategy for existing tokens
2. Session management differences
3. Error handling changes needed

I'll continue reviewing the security implications.
"""
        result = run_fast_checks(text)
        self.assertIsNone(result, "Should not block normal review discussion")

    @patch("fast_pattern_detector.get_review_mode")
    def test_allows_implementation_when_not_in_review_mode(self, mock_mode: unittest.mock.MagicMock) -> None:
        """Should allow implementation announcements when not in review mode."""
        mock_mode.return_value = ""  # No review mode
        text = "I'm in Phase 3: Implement. Let me start writing the code."
        result = run_fast_checks(text)
        # Mode violation check only runs in review modes
        # But task drift might still catch this - that's ok
        # The key is it shouldn't be blocked as a MODE violation
        if result:
            self.assertNotIn("Mode Violation", result.get("message", ""))

    @patch("fast_pattern_detector.get_review_mode")
    def test_catches_begin_implementation_in_tech_review(self, mock_mode: unittest.mock.MagicMock) -> None:
        """Should catch 'begin implementation' during tech-review mode."""
        mock_mode.return_value = "tech-review"
        text = "The plan looks good. I'll now start implementing the changes."
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Should block implementation start in tech-review")

    @patch("fast_pattern_detector.get_review_mode")
    def test_catches_proceed_to_implementation(self, mock_mode: unittest.mock.MagicMock) -> None:
        """Should catch 'proceed to implementation' during review mode."""
        mock_mode.return_value = "full-review"
        text = "Review complete. Let me proceed to implementation of the auth changes."
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Should block proceeding to implementation")


    @patch("fast_pattern_detector.get_review_mode")
    def test_allows_plan_fixes_in_full_review(self, mock_mode: unittest.mock.MagicMock) -> None:
        """Should allow 'let me fix this' when fixing plan issues in full-review mode.

        In full-review mode, agents are instructed to make improvements to the plan.
        Phrases like 'let me fix this' referring to plan corrections should NOT trigger
        task drift detection.
        """
        mock_mode.return_value = "full-review"
        text = """I see an issue! Line 313 says Revises: cleanup_invalid_detection_rules
but line 321 says down_revision = "seed_target_ranges_sidechain".
These are inconsistent. The docstring should match the actual down_revision.
Let me fix this:"""
        result = run_fast_checks(text)
        self.assertIsNone(result, "Should allow plan fixes in full-review mode")

    @patch("fast_pattern_detector.get_review_mode")
    def test_still_blocks_implementation_in_full_review(self, mock_mode: unittest.mock.MagicMock) -> None:
        """Should still block actual implementation attempts in full-review mode.

        Even though task drift is skipped, mode violation should catch implementation intent.
        """
        mock_mode.return_value = "full-review"
        text = "I'll now start implementing the authentication changes in the codebase."
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Should block implementation in full-review")
        self.assertEqual(result.get("decision"), "block")

    @patch("fast_pattern_detector.get_review_mode")
    def test_task_drift_still_works_outside_full_review(self, mock_mode: unittest.mock.MagicMock) -> None:
        """Task drift detection should still work when not in full-review mode."""
        mock_mode.return_value = ""  # No review mode
        text = "Let me fix the issues I found during my review."
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Should catch task drift outside review modes")


if __name__ == "__main__":
    unittest.main()
