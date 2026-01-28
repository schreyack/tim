#!/usr/bin/env python3
"""
TIM Design Standards: Excuse Pattern Definitions

This module aggregates all excuse and mitigation patterns for the detector.
Patterns are split across modules for maintainability.
"""

from patterns_core import ExcusePattern, CORE_EXCUSE_PATTERNS, MITIGATION_PATTERNS
from patterns_extended import EXTENDED_EXCUSE_PATTERNS

# Combined excuse patterns (all 77 patterns)
EXCUSE_PATTERNS = CORE_EXCUSE_PATTERNS + EXTENDED_EXCUSE_PATTERNS

# Re-export for backward compatibility
__all__ = ['ExcusePattern', 'EXCUSE_PATTERNS', 'MITIGATION_PATTERNS']
