#!/usr/bin/env python3
"""
TIM Design Standards: Excuse Pattern Definitions

This module aggregates all excuse and mitigation patterns for the detector.
Patterns are split across modules for maintainability.
"""

from patterns_core import ExcusePattern, CORE_EXCUSE_PATTERNS, MITIGATION_PATTERNS
from patterns_extended import EXTENDED_EXCUSE_PATTERNS
from patterns_posthook import POSTHOOK_AND_REDEFINE_PATTERNS
from patterns_shortcut import SHORTCUT_EXCUSE_PATTERNS
from patterns_failure_dismissal import FAILURE_DISMISSAL_PATTERNS
from patterns_test_manipulation import TEST_MANIPULATION_PATTERNS
from patterns_unilateral_decision import UNILATERAL_DECISION_PATTERNS

# Combined excuse patterns (all patterns)
EXCUSE_PATTERNS = (
    CORE_EXCUSE_PATTERNS
    + EXTENDED_EXCUSE_PATTERNS
    + POSTHOOK_AND_REDEFINE_PATTERNS
    + SHORTCUT_EXCUSE_PATTERNS
    + FAILURE_DISMISSAL_PATTERNS
    + TEST_MANIPULATION_PATTERNS
    + UNILATERAL_DECISION_PATTERNS
)

# Re-export for backward compatibility
__all__ = ['ExcusePattern', 'EXCUSE_PATTERNS', 'MITIGATION_PATTERNS']
