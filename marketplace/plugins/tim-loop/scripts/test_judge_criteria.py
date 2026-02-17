#!/usr/bin/env python3
"""Tests for judge_criteria.py — LLM classification, regex fallback, and criteria routing."""

import json
import unittest
from unittest.mock import MagicMock, patch

from judge_criteria import (
    JUDGE_CRITERIA_BASE,
    JUDGE_CRITERIA_COMMIT,
    JUDGE_CRITERIA_IMPLEMENT,
    JUDGE_CRITERIA_OPS,
    JUDGE_CRITERIA_REVIEW,
    VALID_TASK_TYPES,
    _detect_task_type_regex,
    classify_task_type,
    detect_task_type,
    get_judge_criteria,
)

DEFAULT_CONFIG = {
    "server": "http://localhost:11434",
    "model": "llama3.1:8b",
    "timeout": 30,
}


def _mock_llm_response(content: str) -> MagicMock:
    """Build a mock urllib response returning the given content."""
    body = json.dumps({
        "choices": [{"message": {"content": content}}],
    }).encode("utf-8")
    mock_resp = MagicMock()
    mock_resp.read.return_value = body
    mock_resp.__enter__ = lambda s: s
    mock_resp.__exit__ = MagicMock(return_value=False)
    return mock_resp


# ──────────────────────────────────────────────
# classify_task_type — LLM classification
# ──────────────────────────────────────────────


class TestClassifyTaskType(unittest.TestCase):
    """Test LLM-based task type classification."""

    @patch("judge_criteria.urllib.request.urlopen")
    def test_classifies_commit_via_llm(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("commit")
        result = classify_task_type("commit these changes and push", DEFAULT_CONFIG)
        self.assertEqual(result, "commit")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_classifies_implement_via_llm(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("implement")
        result = classify_task_type("add a login button to the dashboard", DEFAULT_CONFIG)
        self.assertEqual(result, "implement")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_classifies_ops_via_llm(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("ops")
        result = classify_task_type("deploy to dev environment", DEFAULT_CONFIG)
        self.assertEqual(result, "ops")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_classifies_review_via_llm(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("review")
        result = classify_task_type("review the auth module for security issues", DEFAULT_CONFIG)
        self.assertEqual(result, "review")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_classifies_explain_via_llm(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("explain")
        result = classify_task_type("explain how the middleware works", DEFAULT_CONFIG)
        self.assertEqual(result, "explain")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_classifies_summary_via_llm(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("summary")
        result = classify_task_type("summarize what changes were made today", DEFAULT_CONFIG)
        self.assertEqual(result, "summary")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_handles_trailing_period(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("implement.")
        result = classify_task_type("fix the broken tests", DEFAULT_CONFIG)
        self.assertEqual(result, "implement")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_handles_extra_whitespace(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("  ops  \n")
        result = classify_task_type("restart the service", DEFAULT_CONFIG)
        self.assertEqual(result, "ops")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_handles_multiword_response_takes_first(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("implement - the user wants to build")
        result = classify_task_type("add error handling", DEFAULT_CONFIG)
        self.assertEqual(result, "implement")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_invalid_llm_response_falls_back_to_regex(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("I think this is a coding task")
        result = classify_task_type("commit the changes", DEFAULT_CONFIG)
        self.assertEqual(result, "commit")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_invalid_response_no_regex_match_returns_general(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("banana")
        result = classify_task_type("do the thing", DEFAULT_CONFIG)
        self.assertEqual(result, "general")

    def test_short_input_returns_general(self) -> None:
        self.assertEqual(classify_task_type("hi", DEFAULT_CONFIG), "general")

    def test_empty_input_returns_general(self) -> None:
        self.assertEqual(classify_task_type("", DEFAULT_CONFIG), "general")

    def test_none_input_returns_general(self) -> None:
        self.assertEqual(classify_task_type(None, DEFAULT_CONFIG), "general")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_llm_timeout_falls_back_to_regex(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.side_effect = TimeoutError("timed out")
        result = classify_task_type("review my code please", DEFAULT_CONFIG)
        self.assertEqual(result, "review")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_llm_connection_error_falls_back_to_regex(self, mock_urlopen: MagicMock) -> None:
        import urllib.error
        mock_urlopen.side_effect = urllib.error.URLError("connection refused")
        result = classify_task_type("deploy to prod", DEFAULT_CONFIG)
        self.assertEqual(result, "ops")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_strips_ollama_prefix_from_model(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("implement")
        config = {**DEFAULT_CONFIG, "model": "ollama/llama3.1:8b"}
        classify_task_type("fix the bug", config)
        req = mock_urlopen.call_args[0][0]
        payload = json.loads(req.data.decode("utf-8"))
        self.assertEqual(payload["model"], "llama3.1:8b")

    @patch("judge_criteria.urllib.request.urlopen")
    def test_uses_v1_chat_completions_endpoint(self, mock_urlopen: MagicMock) -> None:
        mock_urlopen.return_value = _mock_llm_response("general")
        classify_task_type("hello world test", DEFAULT_CONFIG)
        req = mock_urlopen.call_args[0][0]
        self.assertTrue(req.full_url.endswith("/v1/chat/completions"))


# ──────────────────────────────────────────────
# Regex fallback (legacy detect_task_type)
# ──────────────────────────────────────────────


class TestRegexFallback(unittest.TestCase):
    """Test the regex-based detection used as fallback."""

    def test_commit(self) -> None:
        self.assertEqual(_detect_task_type_regex("git commit -m 'test'"), "commit")

    def test_summary(self) -> None:
        self.assertEqual(_detect_task_type_regex("summarize what was done"), "summary")

    def test_review(self) -> None:
        self.assertEqual(_detect_task_type_regex("review this code"), "review")

    def test_explain(self) -> None:
        self.assertEqual(_detect_task_type_regex("explain how this works"), "explain")

    def test_ops_deploy(self) -> None:
        self.assertEqual(_detect_task_type_regex("deploy to dev"), "ops")

    def test_ops_restart(self) -> None:
        self.assertEqual(_detect_task_type_regex("restart the service"), "ops")

    def test_general_fallthrough(self) -> None:
        self.assertEqual(_detect_task_type_regex("hello"), "general")

    def test_legacy_alias(self) -> None:
        self.assertEqual(detect_task_type("commit changes"), "commit")


# ──────────────────────────────────────────────
# get_judge_criteria routing
# ──────────────────────────────────────────────


class TestGetJudgeCriteria(unittest.TestCase):
    """Test that task types map to the correct criteria."""

    def test_commit_criteria(self) -> None:
        self.assertIs(get_judge_criteria("commit"), JUDGE_CRITERIA_COMMIT)

    def test_summary_criteria(self) -> None:
        self.assertIs(get_judge_criteria("summary"), JUDGE_CRITERIA_COMMIT)

    def test_review_criteria(self) -> None:
        self.assertIs(get_judge_criteria("review"), JUDGE_CRITERIA_REVIEW)

    def test_explain_criteria(self) -> None:
        self.assertIs(get_judge_criteria("explain"), JUDGE_CRITERIA_REVIEW)

    def test_implement_criteria(self) -> None:
        self.assertIs(get_judge_criteria("implement"), JUDGE_CRITERIA_IMPLEMENT)

    def test_ops_criteria(self) -> None:
        self.assertIs(get_judge_criteria("ops"), JUDGE_CRITERIA_OPS)

    def test_general_criteria(self) -> None:
        self.assertIs(get_judge_criteria("general"), JUDGE_CRITERIA_BASE)

    def test_unknown_falls_back_to_base(self) -> None:
        self.assertIs(get_judge_criteria("unknown"), JUDGE_CRITERIA_BASE)

    def test_all_valid_types_have_criteria(self) -> None:
        for task_type in VALID_TASK_TYPES:
            criteria = get_judge_criteria(task_type)
            self.assertIsInstance(criteria, str)
            self.assertTrue(len(criteria) > 50)

    def test_expected_types_present(self) -> None:
        expected = {"commit", "summary", "review", "explain", "implement", "ops", "general"}
        self.assertEqual(VALID_TASK_TYPES, expected)


if __name__ == "__main__":
    unittest.main()
