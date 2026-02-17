#!/usr/bin/env python3
"""Tests for guardrails_judge.py — verdict parsing, categories, and full flow."""

import json
import unittest
from unittest.mock import MagicMock, patch

from guardrails_judge import (
    _extract_category_from_reason,
    _parse_llm_verdict,
    check_with_guardrails,
)

DEFAULT_CONFIG = {
    "server": "http://localhost:11434",
    "model": "llama3.1:8b",
    "timeout": 30,
}


# ──────────────────────────────────────────────
# _parse_llm_verdict
# ──────────────────────────────────────────────


class TestParseLlmVerdict(unittest.TestCase):
    """Test verdict parsing from LLM responses."""

    def test_pass_verdict(self) -> None:
        result = _parse_llm_verdict("PASS - the response is appropriate")
        self.assertTrue(result["passed"])

    def test_fail_verdict(self) -> None:
        result = _parse_llm_verdict("FAIL - unilateral decision detected")
        self.assertFalse(result["passed"])

    def test_fail_with_markdown_bold(self) -> None:
        result = _parse_llm_verdict("**FAIL** - shortcut reasoning")
        self.assertFalse(result["passed"])

    def test_fail_with_underscores(self) -> None:
        result = _parse_llm_verdict("__FAIL__ - the response skips the issue")
        self.assertFalse(result["passed"])

    def test_ambiguous_first_line_defaults_pass(self) -> None:
        result = _parse_llm_verdict("The response seems okay overall.")
        self.assertTrue(result["passed"])

    def test_fail_and_pass_on_same_line_passes(self) -> None:
        result = _parse_llm_verdict("PASS/FAIL - unclear verdict")
        self.assertTrue(result["passed"])

    def test_inconclusive_no_response(self) -> None:
        result = _parse_llm_verdict("There is no response provided to evaluate.")
        self.assertTrue(result["passed"])

    def test_inconclusive_cannot_evaluate(self) -> None:
        result = _parse_llm_verdict("FAIL - cannot evaluate without more context")
        self.assertTrue(result["passed"])

    def test_inconclusive_likely_asking(self) -> None:
        result = _parse_llm_verdict("FAIL - the user is likely asking for a review")
        self.assertTrue(result["passed"])

    def test_inconclusive_assuming_user(self) -> None:
        result = _parse_llm_verdict("FAIL - assuming the user wanted implementation")
        self.assertTrue(result["passed"])

    def test_inconclusive_probably_wanted(self) -> None:
        result = _parse_llm_verdict("FAIL - the user probably wanted something else")
        self.assertTrue(result["passed"])

    def test_real_fail_not_caught_by_inconclusive(self) -> None:
        result = _parse_llm_verdict(
            "FAIL - the assistant dismisses test failures as pre-existing"
        )
        self.assertFalse(result["passed"])

    def test_multiline_only_checks_first_line(self) -> None:
        result = _parse_llm_verdict("PASS\nThe rest of this says FAIL but doesn't matter")
        self.assertTrue(result["passed"])


# ──────────────────────────────────────────────
# _extract_category_from_reason
# ──────────────────────────────────────────────


class TestExtractCategory(unittest.TestCase):
    """Test category extraction from failure reasons."""

    def test_unilateral_decision(self) -> None:
        self.assertEqual(
            _extract_category_from_reason("Made a unilateral decision about the UI"),
            "unilateral_decision",
        )

    def test_failure_dismissal(self) -> None:
        self.assertEqual(
            _extract_category_from_reason("Test failure was dismissed as pre-existing"),
            "failure_dismissal",
        )

    def test_shortcut(self) -> None:
        self.assertEqual(
            _extract_category_from_reason("Chose the easy shortcut instead of best solution"),
            "shortcut",
        )

    def test_posthook(self) -> None:
        self.assertEqual(
            _extract_category_from_reason("Tried to bypass the hook"),
            "posthook",
        )

    def test_general_fallback(self) -> None:
        self.assertEqual(
            _extract_category_from_reason("Something went wrong"),
            "general",
        )


# ──────────────────────────────────────────────
# check_with_guardrails (integration)
# ──────────────────────────────────────────────


class TestCheckWithGuardrails(unittest.TestCase):
    """Test the full check_with_guardrails flow."""

    @patch("guardrails_judge.is_llm_judge_enabled", return_value=False)
    def test_returns_none_when_disabled(self, _mock: MagicMock) -> None:
        result = check_with_guardrails("some text", "some request")
        self.assertIsNone(result)

    @patch("guardrails_judge.is_llm_judge_enabled", return_value=True)
    def test_returns_none_for_short_text(self, _mock: MagicMock) -> None:
        result = check_with_guardrails("short", "request")
        self.assertIsNone(result)

    @patch("guardrails_judge.is_llm_judge_enabled", return_value=True)
    @patch("guardrails_judge.get_llm_config", return_value=DEFAULT_CONFIG)
    @patch("guardrails_judge.classify_task_type", return_value="implement")
    @patch("guardrails_judge._call_ollama_direct")
    def test_pass_returns_none(
        self, mock_call: MagicMock, _cls: MagicMock, _cfg: MagicMock, _en: MagicMock
    ) -> None:
        mock_call.return_value = {"passed": True, "reason": "PASS"}
        result = check_with_guardrails("a" * 100, "fix the login bug")
        self.assertIsNone(result)

    @patch("guardrails_judge.is_llm_judge_enabled", return_value=True)
    @patch("guardrails_judge.get_llm_config", return_value=DEFAULT_CONFIG)
    @patch("guardrails_judge.classify_task_type", return_value="review")
    @patch("guardrails_judge._call_ollama_direct")
    @patch("guardrails_judge.log_llm_catch")
    def test_fail_returns_block_response(
        self, mock_log: MagicMock, mock_call: MagicMock, _cls: MagicMock,
        _cfg: MagicMock, _en: MagicMock
    ) -> None:
        mock_call.return_value = {
            "passed": False,
            "reason": "FAIL - unilateral decision to implement",
        }
        result = check_with_guardrails("a" * 100, "review the auth module")
        self.assertIsNotNone(result)
        self.assertFalse(result["continue"])
        assert "LLM JUDGE" in result["stopReason"]
        mock_log.assert_called_once()

    @patch("guardrails_judge.is_llm_judge_enabled", return_value=True)
    @patch("guardrails_judge.get_llm_config", return_value=DEFAULT_CONFIG)
    @patch("guardrails_judge.classify_task_type", return_value="general")
    @patch("guardrails_judge._call_ollama_direct", return_value=None)
    def test_llm_unavailable_returns_none(
        self, _call: MagicMock, _cls: MagicMock, _cfg: MagicMock, _en: MagicMock
    ) -> None:
        result = check_with_guardrails("a" * 100, "do something")
        self.assertIsNone(result)

    @patch("guardrails_judge.is_llm_judge_enabled", return_value=True)
    @patch("guardrails_judge.get_llm_config", return_value=DEFAULT_CONFIG)
    @patch("guardrails_judge.classify_task_type")
    @patch("guardrails_judge._call_ollama_direct")
    def test_uses_llm_classification_not_regex(
        self, mock_call: MagicMock, mock_classify: MagicMock,
        _cfg: MagicMock, _en: MagicMock
    ) -> None:
        """Verify classify_task_type is called (not the old detect_task_type)."""
        mock_classify.return_value = "ops"
        mock_call.return_value = {"passed": True, "reason": "PASS"}
        check_with_guardrails("a" * 100, "deploy to dev")
        mock_classify.assert_called_once_with("deploy to dev", DEFAULT_CONFIG)

    @patch("guardrails_judge.is_llm_judge_enabled", return_value=True)
    @patch("guardrails_judge.get_llm_config", return_value=DEFAULT_CONFIG)
    @patch("guardrails_judge._call_ollama_direct")
    def test_no_user_request_skips_classification(
        self, mock_call: MagicMock, _cfg: MagicMock, _en: MagicMock
    ) -> None:
        """Empty user_request should skip classification and use 'general'."""
        mock_call.return_value = {"passed": True, "reason": "PASS"}
        check_with_guardrails("a" * 100, "")
        call_args = mock_call.call_args
        self.assertEqual(call_args[0][2], "general")

    @patch("guardrails_judge.is_llm_judge_enabled", return_value=True)
    @patch("guardrails_judge.get_llm_config", return_value=DEFAULT_CONFIG)
    @patch("guardrails_judge.classify_task_type", return_value="implement")
    @patch("guardrails_judge._call_ollama_direct")
    def test_truncates_long_transcript(
        self, mock_call: MagicMock, _cls: MagicMock, _cfg: MagicMock, _en: MagicMock
    ) -> None:
        mock_call.return_value = {"passed": True, "reason": "PASS"}
        check_with_guardrails("x" * 10000, "fix it")
        actual_text = mock_call.call_args[0][0]
        self.assertLessEqual(len(actual_text), 4000)


if __name__ == "__main__":
    unittest.main()
