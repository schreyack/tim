#!/usr/bin/env python3
"""
Tests for the TIM excuse detector - Shortcut Reasoning patterns (93-100).

Tests cover Category Q: Easy Path / Shortcut Reasoning
  - Simplest/easiest/quickest fix patterns
  - Path of least resistance
  - Quick disable patterns
  - Temporary fix patterns
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
has_shortcut_patterns = _module.has_shortcut_patterns
build_shortcut_block_response = _module.build_shortcut_block_response

# Import patterns
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from excuse_patterns import EXCUSE_PATTERNS
from patterns_shortcut import SHORTCUT_EXCUSE_PATTERNS


class TestShortcutPatterns:
    """Tests for Category Q - Shortcut Reasoning (patterns 93-100)."""

    def test_find_excuses_when_simplest_fix_detects_shortcut(self) -> None:
        text = "The simplest fix is to disable FastAPI's automatic trailing slash redirects."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)

    def test_find_excuses_when_easiest_solution_detects_shortcut(self) -> None:
        text = "The easiest solution is to remove the validation entirely."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)

    def test_find_excuses_when_quickest_fix_detects_shortcut(self) -> None:
        text = "The quickest fix would be to hardcode the value."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)

    def test_find_excuses_when_fastest_approach_detects_shortcut(self) -> None:
        text = "The fastest approach is to skip the validation step."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)

    def test_find_excuses_when_path_of_least_resistance_detects_shortcut(self) -> None:
        text = "The path of least resistance is to just disable it."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)

    def test_find_excuses_when_just_disable_detects_shortcut(self) -> None:
        text = "I'll just disable the automatic redirects."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)

    def test_find_excuses_when_simply_remove_detects_shortcut(self) -> None:
        text = "We can simply remove the feature for now."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)

    def test_find_excuses_when_simple_answer_detects_shortcut(self) -> None:
        text = "The simple answer is to just delete the problematic code."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)

    def test_find_excuses_when_for_now_quick_fix_detects_shortcut(self) -> None:
        text = "For now, I'll just disable the feature."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)

    def test_find_excuses_when_as_quick_fix_detects_shortcut(self) -> None:
        text = "As a quick fix, let's simply turn off validation."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)


class TestShortcutPatternHelpers:
    """Tests for shortcut pattern helper functions."""

    def test_has_shortcut_patterns_returns_true_for_shortcut(self) -> None:
        text = "The simplest fix is to disable it."
        excuses = find_excuses(text)
        assert has_shortcut_patterns(excuses) is True

    def test_has_shortcut_patterns_returns_false_for_general(self) -> None:
        text = "This was already broken before my changes."
        excuses = find_excuses(text)
        assert has_shortcut_patterns(excuses) is False


class TestShortcutBlockResponse:
    """Tests for the shortcut-specific block response."""

    def test_build_shortcut_block_response_is_gentle(self) -> None:
        text = "The simplest fix is to disable it."
        excuses = find_excuses(text)
        response = build_shortcut_block_response(excuses)

        assert response["decision"] == "block"
        reason = response["reason"]

        # Should be encouraging, not accusatory
        assert "not necessarily wrong" in reason
        assert "BEST solution" in reason or "best" in reason.lower()

        # Should ask for alternatives analysis
        assert "alternative" in reason.lower()
        assert "trade-off" in reason.lower()

    def test_build_shortcut_block_response_asks_for_reasoning(self) -> None:
        text = "The easiest solution is to remove it."
        excuses = find_excuses(text)
        response = build_shortcut_block_response(excuses)

        reason = response["reason"]
        # Should ask to show reasoning
        assert "reasoning" in reason.lower() or "explain" in reason.lower()


class TestShortcutWithMitigation:
    """Tests that mitigation patterns work with shortcut patterns."""

    def test_shortcut_with_mitigation_not_flagged(self) -> None:
        # If the speaker explains why it's the best choice, not flagged
        text = "The simplest fix is to disable it. But let me try a better approach first."
        excuses = find_excuses(text)
        # Should not flag because mitigation follows
        assert len(excuses) == 0

    def test_shortcut_with_analysis_not_flagged(self) -> None:
        # If the speaker analyzes alternatives, not flagged
        text = "The simplest fix is to disable it. However, I'll find a more robust solution."
        excuses = find_excuses(text)
        assert len(excuses) == 0


class TestRealWorldExamples:
    """Tests based on real-world examples from the user."""

    def test_nextjs_fastapi_redirect_example(self) -> None:
        """The original example that prompted this feature."""
        text = (
            "Now there's a redirect loop. The issue is conflicting trailing slash "
            "handling between Next.js and FastAPI. The simplest fix is to disable "
            "FastAPI's automatic trailing slash redirects."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)

    def test_database_connection_quick_fix(self) -> None:
        text = (
            "The database connection is timing out. The quickest fix would be to "
            "increase the timeout to 60 seconds."
        )
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)

    def test_auth_just_disable(self) -> None:
        text = "To avoid the CORS errors, I'll just disable CORS checking entirely."
        excuses = find_excuses(text)
        assert len(excuses) >= 1
        assert any(e.category == "shortcut" for e, _ in excuses)
