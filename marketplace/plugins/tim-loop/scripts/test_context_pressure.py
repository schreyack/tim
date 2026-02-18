#!/usr/bin/env python3
"""Tests for context pressure detection module.

Covers:
- Pressure levels from compaction count
- Compaction counter increment
- Response length tracking
- Response degradation detection
- Soft completion pattern matching
- Minimal context builder
- Verification response bloat reduction
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from tim_loop_context_pressure import (
    PRESSURE_CRITICAL,
    PRESSURE_FORCE_STOP,
    PRESSURE_NORMAL,
    PRESSURE_WARNING,
    check_soft_completion,
    detect_response_degradation,
    get_context_pressure,
    increment_compaction_count,
    track_response_length,
)
from tim_loop_responses import (
    _build_compact_context,
    _build_minimal_context,
    _prompt_or_compact,
    build_soft_completion_nudge,
    build_verification_response,
)


# --- Pressure level tests ---

def test_pressure_normal_at_zero_compactions():
    state = {"COMPACTION_COUNT": "0"}
    assert get_context_pressure(state) == PRESSURE_NORMAL


def test_pressure_normal_when_key_missing():
    assert get_context_pressure({}) == PRESSURE_NORMAL


def test_pressure_warning_at_one_compaction():
    state = {"COMPACTION_COUNT": "1"}
    assert get_context_pressure(state) == PRESSURE_WARNING


def test_pressure_critical_at_two_compactions():
    state = {"COMPACTION_COUNT": "2"}
    assert get_context_pressure(state) == PRESSURE_CRITICAL


def test_pressure_force_stop_at_default_max():
    state = {"COMPACTION_COUNT": "3"}
    assert get_context_pressure(state) == PRESSURE_FORCE_STOP


def test_pressure_force_stop_custom_max():
    state = {"COMPACTION_COUNT": "5", "MAX_COMPACTIONS": "5"}
    assert get_context_pressure(state) == PRESSURE_FORCE_STOP


def test_pressure_critical_below_custom_max():
    state = {"COMPACTION_COUNT": "4", "MAX_COMPACTIONS": "5"}
    assert get_context_pressure(state) == PRESSURE_CRITICAL


# --- Compaction counter tests ---

def test_increment_from_zero():
    state = {}
    result = increment_compaction_count(state)
    assert result == 1
    assert state["COMPACTION_COUNT"] == "1"


def test_increment_from_existing():
    state = {"COMPACTION_COUNT": "2"}
    result = increment_compaction_count(state)
    assert result == 3
    assert state["COMPACTION_COUNT"] == "3"


# --- Response length tracking tests ---

def test_track_response_length_first():
    state = {}
    track_response_length(state, "hello world")
    assert state["RESPONSE_LENGTHS"] == "11"


def test_track_response_length_accumulates():
    state = {}
    track_response_length(state, "a" * 100)
    track_response_length(state, "b" * 200)
    track_response_length(state, "c" * 300)
    lengths = state["RESPONSE_LENGTHS"].split(",")
    assert lengths == ["100", "200", "300"]


def test_track_response_length_caps_at_five():
    state = {}
    for i in range(7):
        track_response_length(state, "x" * ((i + 1) * 100))
    lengths = state["RESPONSE_LENGTHS"].split(",")
    assert len(lengths) == 5
    # Should keep last 5: 300, 400, 500, 600, 700
    assert lengths == ["300", "400", "500", "600", "700"]


def test_track_response_length_strips_whitespace():
    state = {}
    track_response_length(state, "  hello  ")
    assert state["RESPONSE_LENGTHS"] == "5"


# --- Response degradation tests ---

def test_degradation_not_enough_data():
    state = {"RESPONSE_LENGTHS": "100,200"}
    assert detect_response_degradation(state) is False


def test_degradation_detected():
    # Average of 1000,1000 = 1000, latest 400 is < 500 (50%)
    state = {"RESPONSE_LENGTHS": "1000,1000,400"}
    assert detect_response_degradation(state) is True


def test_degradation_not_detected():
    # Average of 1000,1000 = 1000, latest 600 is > 500 (50%)
    state = {"RESPONSE_LENGTHS": "1000,1000,600"}
    assert detect_response_degradation(state) is False


def test_degradation_at_boundary():
    # Average of 1000,1000 = 1000, latest 500 is exactly 50% — not degraded
    state = {"RESPONSE_LENGTHS": "1000,1000,500"}
    assert detect_response_degradation(state) is False


def test_degradation_empty_state():
    assert detect_response_degradation({}) is False


def test_degradation_invalid_data():
    state = {"RESPONSE_LENGTHS": "abc,def,ghi"}
    assert detect_response_degradation(state) is False


# --- Soft completion tests ---

def test_soft_completion_implementation_complete():
    text = "I've finished all the work. The implementation is complete."
    assert check_soft_completion(text, "") is True


def test_soft_completion_all_objectives_met():
    text = "After thorough testing, all objectives have been met."
    assert check_soft_completion(text, "") is True


def test_soft_completion_tasks_completed():
    text = "All tasks have been completed successfully."
    assert check_soft_completion(text, "") is True


def test_soft_completion_work_is_complete():
    text = "The work is complete and ready for review."
    assert check_soft_completion(text, "") is True


def test_soft_completion_everything_implemented():
    text = "Everything has been implemented as specified."
    assert check_soft_completion(text, "") is True


def test_soft_completion_all_changes_made():
    text = "All changes have been made to the codebase."
    assert check_soft_completion(text, "") is True


def test_soft_completion_returns_false_for_full_review():
    text = "The implementation is complete."
    assert check_soft_completion(text, "full-review") is False


def test_soft_completion_not_in_middle_of_text():
    # Pattern only checks last 500 chars
    long_prefix = "x" * 600
    text = long_prefix + "The implementation is complete." + "y" * 200
    # "implementation is complete" is within last 500 chars
    assert check_soft_completion(text, "") is True


def test_soft_completion_no_match():
    text = "I'm still working on the task. Need to fix a few more things."
    assert check_soft_completion(text, "") is False


def test_soft_completion_case_insensitive():
    text = "The IMPLEMENTATION IS COMPLETE now."
    assert check_soft_completion(text, "") is True


# --- Compact context tests (Key Rules removed) ---

def test_compact_context_no_key_rules():
    prompt = "## Mode: implement\nPlan File: /tmp/plan.md\n<promise>COMPLETE</promise>"
    result = _build_compact_context(prompt)
    assert "Key Rules" not in result
    assert "NEVER reduce scope" not in result
    assert "Mode:" in result
    assert "Plan File:" in result
    assert "Completion Signal" in result


# --- Minimal context tests ---

def test_minimal_context_short():
    prompt = "## Mode: implement\nPlan File: /tmp/plan.md\n<promise>COMPLETE</promise>"
    result = _build_minimal_context(prompt)
    assert "/tmp/plan.md" in result
    assert "COMPLETE" in result
    assert len(result) < 200


def test_minimal_context_missing_plan():
    result = _build_minimal_context("some random prompt")
    assert "Unknown" in result


# --- Prompt-or-compact pressure behavior ---

def test_prompt_or_compact_normal_first():
    prompt = "full prompt content"
    result = _prompt_or_compact(prompt, is_first_in_phase=True, pressure=0)
    assert "full prompt content" in result


def test_prompt_or_compact_warning_skips_full():
    prompt = "## Mode: implement\nPlan File: /tmp/plan.md\n<promise>COMPLETE</promise>"
    result = _prompt_or_compact(prompt, is_first_in_phase=True, pressure=1)
    # WARNING skips full prompt even on first-in-phase
    assert "Compact Context" in result


def test_prompt_or_compact_critical_uses_minimal():
    prompt = "## Mode: implement\nPlan File: /tmp/plan.md\n<promise>COMPLETE</promise>"
    result = _prompt_or_compact(prompt, is_first_in_phase=True, pressure=2)
    assert "Plan:" in result
    assert "Compact Context" not in result


# --- Verification response bloat reduction ---

def test_verification_response_no_full_prompt():
    prompt = "## Mode: implement\nPlan File: /tmp/plan.md\n<promise>COMPLETE</promise>\n" + "x" * 5000
    result = build_verification_response(prompt, 5, 30)
    reason = result["reason"]
    # Should NOT contain the full 5000-char prompt
    assert len(reason) < 1000
    assert "verification required" in reason


def test_verification_response_under_pressure():
    prompt = "## Mode: implement\nPlan File: /tmp/plan.md\n<promise>COMPLETE</promise>\n" + "x" * 5000
    result = build_verification_response(prompt, 5, 30, pressure=2)
    reason = result["reason"]
    assert "Plan:" in reason
    assert len(reason) < 500


# --- Soft completion nudge tests ---

def test_nudge_implementation_mode():
    result = build_soft_completion_nudge(5, 30)
    assert "promise" in result["reason"].lower() or "COMPLETE" in result["reason"]
    assert result["decision"] == "block"


def test_nudge_review_mode():
    result = build_soft_completion_nudge(5, 30, "tech-review")
    assert "completion signal" in result["reason"]
    assert "continue reviewing" in result["reason"]
