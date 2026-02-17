#!/usr/bin/env python3
"""Tests for full review phase tracking after context compaction.

Covers:
- Layer 1: Fast-forward in _check_final_signal
- Layer 2: Phase correction via build_phase_correction_response
- Layer 3: Phase-aware compact context (_build_compact_context)
- Regression: normal full review without compaction
"""

import sys
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))

from tim_loop_full_review import (
    PHASE_SIGNALS,
    _all_phase_signals_present,
    _check_final_signal,
    _handle_wrong_phase_signal,
)
from tim_loop_phase_responses import build_phase_correction_response
from tim_loop_responses import _build_compact_context


def _build_all_phase_signals_text() -> str:
    """Build text containing all 7 phase signals + final signal."""
    lines = []
    for signal in PHASE_SIGNALS.values():
        lines.append(f"<promise>{signal}</promise>")
    lines.append("<promise>FULL-REVIEW-DONE</promise>")
    return "\n".join(lines)


def _base_full_review_state(current_phase: int = 1) -> dict:
    """Build a minimal full-review state dict."""
    state = {
        "CURRENT_PHASE": str(current_phase),
        "COMPLETION_PROMISE": "FULL-REVIEW-DONE",
        "PLAN_FILE": "/tmp/test-plan.md",
        "CURRENT_ITERATION": "10",
        "MAX_ITERATIONS": "30",
        "REVIEW_MODE": "full-review",
    }
    for p in range(1, 8):
        state[f"PHASE_{p}_COMPLETE"] = "false"
        state[f"PHASE_{p}_ITERATIONS"] = "0"
    return state


class TestAllPhaseSignalsPresent:
    def test_all_signals_present_when_returns_true(self) -> None:
        text = _build_all_phase_signals_text()
        assert _all_phase_signals_present(text) is True

    def test_missing_one_signal_when_returns_false(self) -> None:
        text = _build_all_phase_signals_text()
        # Remove phase 4 signal
        text = text.replace("<promise>PHASE-4-AI-READY-DONE</promise>", "")
        assert _all_phase_signals_present(text) is False

    def test_empty_text_when_returns_false(self) -> None:
        assert _all_phase_signals_present("") is False

    def test_signals_without_promise_tags_when_returns_false(self) -> None:
        text = "\n".join(PHASE_SIGNALS.values())
        assert _all_phase_signals_present(text) is False


class TestCheckFinalSignalFastForward:
    """Layer 1: Fast-forward when all phase signals present but state behind."""

    @patch("tim_loop_full_review.save_state")
    def test_fast_forward_all_signals_present_then_hard_stop(
        self, mock_save: object
    ) -> None:
        state = _base_full_review_state(current_phase=1)
        text = _build_all_phase_signals_text()
        result = _check_final_signal(state, "prompt", text, phase=1)
        assert result is not None
        assert result.get("hard_stop") is True
        # State should be updated
        assert state["CURRENT_PHASE"] == "7"
        for p in range(1, 8):
            assert state[f"PHASE_{p}_COMPLETE"] == "true"

    @patch("tim_loop_full_review.save_state")
    def test_fast_forward_mid_phase_then_hard_stop(
        self, mock_save: object
    ) -> None:
        state = _base_full_review_state(current_phase=4)
        # Phases 1-3 already done
        for p in range(1, 4):
            state[f"PHASE_{p}_COMPLETE"] = "true"
        text = _build_all_phase_signals_text()
        result = _check_final_signal(state, "prompt", text, phase=4)
        assert result is not None
        assert result.get("hard_stop") is True
        assert state["CURRENT_PHASE"] == "7"

    def test_missing_signals_then_skip_challenge(self) -> None:
        state = _base_full_review_state(current_phase=1)
        # Only final signal, no phase signals
        text = "<promise>FULL-REVIEW-DONE</promise>"
        result = _check_final_signal(state, "prompt", text, phase=1)
        assert result is not None
        assert result.get("hard_stop") is not True
        assert result["decision"] == "block"
        assert "Cannot complete full review" in result["reason"]

    def test_no_final_signal_then_returns_none(self) -> None:
        state = _base_full_review_state(current_phase=1)
        result = _check_final_signal(state, "prompt", "just some text", phase=1)
        assert result is None

    def test_all_phases_already_complete_then_hard_stop(self) -> None:
        """Regression: normal completion without compaction still works."""
        state = _base_full_review_state(current_phase=7)
        for p in range(1, 8):
            state[f"PHASE_{p}_COMPLETE"] = "true"
        text = "<promise>FULL-REVIEW-DONE</promise>"
        result = _check_final_signal(state, "prompt", text, phase=7)
        assert result is not None
        assert result.get("hard_stop") is True


class TestHandleWrongPhaseSignalCorrection:
    """Layer 2: Stale signal triggers phase correction response."""

    @patch("tim_loop_full_review.save_state")
    def test_stale_signal_then_phase_correction(self, mock_save: object) -> None:
        state = _base_full_review_state(current_phase=5)
        state["PLAN_FILE"] = "/tmp/plan.md"
        result = _handle_wrong_phase_signal(
            state, "prompt", current_phase=5, detected_phase=1,
            phase_iterations=2, max_iter=30
        )
        assert result["decision"] == "block"
        assert "PHASE CORRECTION" in result["reason"]
        assert "Phase 5" in result["reason"]
        assert "Phase 1 (Tech Review) signal" in result["reason"]

    @patch("tim_loop_full_review.save_state")
    def test_forward_skip_then_continue_response(self, mock_save: object) -> None:
        """Forward skip (detected > current) keeps generic continue, not correction."""
        state = _base_full_review_state(current_phase=2)
        result = _handle_wrong_phase_signal(
            state, "prompt", current_phase=2, detected_phase=5,
            phase_iterations=1, max_iter=30
        )
        assert result["decision"] == "block"
        # Should NOT use the dedicated phase correction response format
        assert "Tim Loop: PHASE CORRECTION" not in result["reason"]
        assert "stale" not in result["reason"]


class TestBuildPhaseCorrection:
    def test_correction_response_content(self) -> None:
        result = build_phase_correction_response(
            phase_prompt="Do security review...",
            detected_phase=1, current_phase=3,
            iteration=8, max_iter=30
        )
        assert result["decision"] == "block"
        assert "Phase 1 (Tech Review)" in result["reason"]
        assert "Phase 3 (Security Review)" in result["reason"]
        assert "stale" in result["reason"]
        assert "Do security review..." in result["reason"]


class TestCompactContextPhaseCorrection:
    """Layer 3: Compact context includes phase correction for phase > 1."""

    def test_phase_1_then_no_correction_notice(self) -> None:
        ctx = _build_compact_context("## Mode: full-review\nPlan File: /tmp/p.md", 1)
        assert "PHASE CORRECTION" not in ctx

    def test_phase_0_then_no_correction_notice(self) -> None:
        ctx = _build_compact_context("## Mode: full-review\nPlan File: /tmp/p.md", 0)
        assert "PHASE CORRECTION" not in ctx

    def test_phase_4_then_includes_correction_notice(self) -> None:
        ctx = _build_compact_context("## Mode: full-review\nPlan File: /tmp/p.md", 4)
        assert "PHASE CORRECTION" in ctx
        assert "Phase 4" in ctx
        assert "NOT Phase 1" in ctx

    def test_default_phase_then_no_correction(self) -> None:
        ctx = _build_compact_context("## Mode: tech-review\nPlan File: /tmp/p.md")
        assert "PHASE CORRECTION" not in ctx
