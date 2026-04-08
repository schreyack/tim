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


class TestDriftContextGating(unittest.TestCase):
    """Pattern 4 ('let me fix X') should only fire when drift context is present."""

    @patch("fast_pattern_detector.load_state")
    def test_bare_let_me_fix_does_not_fire(self, mock_state: unittest.mock.MagicMock) -> None:
        """'Let me fix those' with no discovery context is not drift.

        In a long fix-the-lint-errors run the assistant will naturally say
        'Let me fix those' many times. Without an 'I found/noticed/while I'm
        here' signal there is no reason to call that drift.
        """
        mock_state.return_value = _mock_state(review_mode="")
        text = "Now rewriting the parser. Let me fix those SIM401 violations."
        result = run_fast_checks(text)
        self.assertIsNone(result, "Bare 'let me fix those' must not trigger task drift")

    @patch("fast_pattern_detector.load_state")
    def test_let_me_fix_with_discovery_still_fires(self, mock_state: unittest.mock.MagicMock) -> None:
        """'Let me fix the bugs I noticed' has discovery context and is drift."""
        mock_state.return_value = _mock_state(review_mode="")
        text = "I'll fix the bugs I noticed while reviewing the parser."
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "Drift with 'I noticed' context must still fire")

    @patch("fast_pattern_detector.load_state")
    def test_let_me_fix_while_im_here_fires(self, mock_state: unittest.mock.MagicMock) -> None:
        """'While I'm here' is a classic drift marker."""
        mock_state.return_value = _mock_state(review_mode="")
        text = "Let me fix this typo while I'm here."
        result = run_fast_checks(text)
        self.assertIsNotNone(result, "'while I'm here' must fire drift")


class TestRecentHumanTurnScanning(unittest.TestCase):
    """Action intent from earlier human turns should survive clarifying questions."""

    @staticmethod
    def _make_transcript(turns: list[tuple[str, str]]) -> list[dict]:
        """Build a transcript from (role, text) tuples."""
        return [{"message": {"role": role, "content": text}} for role, text in turns]

    @patch("fast_pattern_detector.load_state")
    def test_action_intent_survives_clarifying_question(
        self, mock_state: unittest.mock.MagicMock
    ) -> None:
        """User's 'commit and push' 2 turns ago still counts as action intent."""
        mock_state.return_value = _mock_state(review_mode="")
        transcript = self._make_transcript(
            [
                ("user", "commit and push"),
                ("assistant", "Running pre-commit..."),
                ("user", "why is it failing?"),
                ("assistant", "Lint errors. Let me fix the issues I found in the parser."),
            ]
        )
        result = run_fast_checks(
            "Lint errors. Let me fix the issues I found in the parser.",
            transcript=transcript,
        )
        self.assertIsNone(
            result,
            "Drift should be skipped when earlier human turn had action intent",
        )

    @patch("fast_pattern_detector.load_state")
    def test_drift_fires_when_no_recent_action_intent(
        self, mock_state: unittest.mock.MagicMock
    ) -> None:
        """Drift still fires when no recent human turn requested action."""
        mock_state.return_value = _mock_state(review_mode="")
        transcript = self._make_transcript(
            [
                ("user", "review this code"),
                ("assistant", "Reviewing..."),
                ("user", "anything weird?"),
                ("assistant", "Let me fix the bugs I found in the auth module."),
            ]
        )
        result = run_fast_checks(
            "Let me fix the bugs I found in the auth module.",
            transcript=transcript,
        )
        self.assertIsNotNone(
            result,
            "Review-only sessions should still catch fix-drift",
        )


class TestActiveTaskAwareness(unittest.TestCase):
    """Drifts whose verb matches an active TaskCreate subject should be skipped."""

    @staticmethod
    def _task_create(tool_use_id: str, subject: str, description: str = "") -> dict:
        return {
            "message": {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "id": tool_use_id,
                        "name": "TaskCreate",
                        "input": {
                            "subject": subject,
                            "description": description,
                            "activeForm": subject,
                        },
                    }
                ],
            }
        }

    @staticmethod
    def _task_create_result(tool_use_id: str, task_num: int, subject: str) -> dict:
        return {
            "message": {
                "role": "user",
                "content": [
                    {
                        "type": "tool_result",
                        "tool_use_id": tool_use_id,
                        "content": f"Task #{task_num} created successfully: {subject}",
                    }
                ],
            }
        }

    @staticmethod
    def _task_update(task_id: str, status: str) -> dict:
        return {
            "message": {
                "role": "assistant",
                "content": [
                    {
                        "type": "tool_use",
                        "id": f"toolu_update_{task_id}_{status}",
                        "name": "TaskUpdate",
                        "input": {"taskId": task_id, "status": status},
                    }
                ],
            }
        }

    @staticmethod
    def _user_turn(text: str) -> dict:
        return {"message": {"role": "user", "content": text}}

    @staticmethod
    def _assistant_turn(text: str) -> dict:
        return {"message": {"role": "assistant", "content": text}}

    @patch("fast_pattern_detector.load_state")
    def test_active_fix_task_covers_fix_drift(
        self, mock_state: unittest.mock.MagicMock
    ) -> None:
        """An active 'Fix mypy violations' task means 'let me fix the bugs I found' is on-task."""
        mock_state.return_value = _mock_state(review_mode="")
        transcript = [
            self._user_turn("take a look at this module"),
            self._task_create("tc_1", "Fix mypy strict violations", "Zero-warning type check"),
            self._task_create_result("tc_1", 1, "Fix mypy strict violations"),
            self._task_update("1", "in_progress"),
            self._assistant_turn("Let me fix the issues I found in the auth module."),
        ]
        result = run_fast_checks(
            "Let me fix the issues I found in the auth module.",
            transcript=transcript,
        )
        self.assertIsNone(
            result,
            "Active 'Fix ...' task should cover fix-drift as planned work",
        )

    @patch("fast_pattern_detector.load_state")
    def test_completed_task_does_not_cover_drift(
        self, mock_state: unittest.mock.MagicMock
    ) -> None:
        """A completed 'Fix X' task does NOT cover new fix-drift."""
        mock_state.return_value = _mock_state(review_mode="")
        transcript = [
            self._user_turn("take a look at this module"),
            self._task_create("tc_1", "Fix mypy strict violations", ""),
            self._task_create_result("tc_1", 1, "Fix mypy strict violations"),
            self._task_update("1", "completed"),
            self._assistant_turn("Let me fix the bugs I found in the auth module."),
        ]
        result = run_fast_checks(
            "Let me fix the bugs I found in the auth module.",
            transcript=transcript,
        )
        self.assertIsNotNone(
            result,
            "Completed task should not cover new fix-drift",
        )

    @patch("fast_pattern_detector.load_state")
    def test_unrelated_task_does_not_cover_drift(
        self, mock_state: unittest.mock.MagicMock
    ) -> None:
        """An active 'Review X' task does NOT cover 'let me fix' drift."""
        mock_state.return_value = _mock_state(review_mode="")
        transcript = [
            self._user_turn("look at this module"),
            self._task_create("tc_1", "Review API endpoints", "Security review"),
            self._task_create_result("tc_1", 1, "Review API endpoints"),
            self._task_update("1", "in_progress"),
            self._assistant_turn("Let me fix the bugs I found while reviewing."),
        ]
        result = run_fast_checks(
            "Let me fix the bugs I found while reviewing.",
            transcript=transcript,
        )
        self.assertIsNotNone(
            result,
            "Review task should not cover fix-drift",
        )

    @patch("fast_pattern_detector.load_state")
    def test_pending_task_create_result_still_covers_drift(
        self, mock_state: unittest.mock.MagicMock
    ) -> None:
        """A TaskCreate without its result yet should still be treated as active."""
        mock_state.return_value = _mock_state(review_mode="")
        transcript = [
            self._user_turn("look at this"),
            self._task_create("tc_1", "Fix all lint violations", ""),
            # No result entry — task creation is "in flight"
            self._assistant_turn("Let me fix the issues I found in the parser."),
        ]
        result = run_fast_checks(
            "Let me fix the issues I found in the parser.",
            transcript=transcript,
        )
        self.assertIsNone(
            result,
            "Pending (unresolved) TaskCreate should still count as active",
        )


if __name__ == "__main__":
    unittest.main()
