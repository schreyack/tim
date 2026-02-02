#!/usr/bin/env python3
"""Unit tests for phase signal detection in full-review mode."""

import sys
from pathlib import Path

# Add scripts directory to path
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
from tim_loop_full_review import detect_phase_signal, PHASE_SIGNALS


def test_detect_all_six_signals():
    """detect_phase_signal recognizes all 6 phase signals."""
    for phase, signal in PHASE_SIGNALS.items():
        text = f"<promise>{signal}</promise>"
        result = detect_phase_signal(text)
        assert result == (phase, signal), f"Expected ({phase}, {signal}), got {result}"


def test_detect_signal_returns_none_for_no_signal():
    """Returns None when no signal present."""
    assert detect_phase_signal("no signal here") is None


def test_detect_signal_ignores_malformed():
    """Ignores signals without proper tags."""
    assert detect_phase_signal("PHASE-1-TECH-DONE") is None
    assert detect_phase_signal("<prompt>PHASE-1-TECH-DONE</prompt>") is None


def test_detect_signal_in_longer_text():
    """Detects signal embedded in longer text."""
    text = """
    I have completed the tech review. All files verified.
    <promise>PHASE-1-TECH-DONE</promise>
    Now moving to the next phase.
    """
    result = detect_phase_signal(text)
    assert result == (1, "PHASE-1-TECH-DONE")


def test_phase_signals_dict_has_six_entries():
    """PHASE_SIGNALS dict contains exactly 6 entries."""
    assert len(PHASE_SIGNALS) == 6


def test_phase_signals_are_sequential():
    """PHASE_SIGNALS has keys 1 through 6."""
    expected_keys = {1, 2, 3, 4, 5, 6}
    assert set(PHASE_SIGNALS.keys()) == expected_keys


def test_signal_values_are_unique():
    """All phase signals are unique."""
    values = list(PHASE_SIGNALS.values())
    assert len(values) == len(set(values))


def test_signal_format():
    """All signals follow expected naming convention."""
    for phase, signal in PHASE_SIGNALS.items():
        assert signal.startswith(f"PHASE-{phase}-"), f"Signal {signal} doesn't match phase {phase}"
        assert signal.endswith("-DONE"), f"Signal {signal} doesn't end with -DONE"


if __name__ == "__main__":
    tests = [
        test_detect_all_six_signals,
        test_detect_signal_returns_none_for_no_signal,
        test_detect_signal_ignores_malformed,
        test_detect_signal_in_longer_text,
        test_phase_signals_dict_has_six_entries,
        test_phase_signals_are_sequential,
        test_signal_values_are_unique,
        test_signal_format,
    ]

    passed = 0
    failed = 0
    for test in tests:
        try:
            test()
            print(f"PASS: {test.__name__}")
            passed += 1
        except AssertionError as e:
            print(f"FAIL: {test.__name__} - {e}")
            failed += 1
        except Exception as e:
            print(f"ERROR: {test.__name__} - {e}")
            failed += 1

    print(f"\nResults: {passed} passed, {failed} failed")
    sys.exit(0 if failed == 0 else 1)
