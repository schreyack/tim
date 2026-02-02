#!/usr/bin/env python3
"""
YAML-based Excuse Pattern Loader

Loads excuse patterns from YAML for easy updating. When the Guardrails LLM
catches something the local regex missed, add a new pattern to the YAML file.

Over time, the local regex catches more, reducing LLM API calls.
"""

import re
import sys
from dataclasses import dataclass
from pathlib import Path

# PyYAML is optional - fall back to Python patterns if not available
try:
    import yaml
    YAML_AVAILABLE = True
except ImportError:
    YAML_AVAILABLE = False


@dataclass
class ExcusePattern:
    """A single excuse detection pattern."""
    pattern: str
    category: str
    description: str
    example: str
    compiled: re.Pattern
    added_from_llm: bool = False
    added_date: str | None = None


@dataclass
class PatternConfig:
    """Complete pattern configuration loaded from YAML."""
    version: str
    patterns: list[ExcusePattern]
    mitigation_patterns: list[re.Pattern]


def _load_fallback_patterns() -> PatternConfig:
    """Load patterns from Python modules when YAML is unavailable."""
    from patterns_core import CORE_EXCUSE_PATTERNS, MITIGATION_PATTERNS as MIT_PATTERNS
    from patterns_extended import EXTENDED_EXCUSE_PATTERNS
    from patterns_posthook import POSTHOOK_AND_REDEFINE_PATTERNS
    from patterns_shortcut import SHORTCUT_EXCUSE_PATTERNS
    from patterns_failure_dismissal import FAILURE_DISMISSAL_PATTERNS
    from patterns_test_manipulation import TEST_MANIPULATION_PATTERNS
    from patterns_unilateral_decision import UNILATERAL_DECISION_PATTERNS

    all_patterns = (
        CORE_EXCUSE_PATTERNS + EXTENDED_EXCUSE_PATTERNS +
        POSTHOOK_AND_REDEFINE_PATTERNS + SHORTCUT_EXCUSE_PATTERNS +
        FAILURE_DISMISSAL_PATTERNS + TEST_MANIPULATION_PATTERNS +
        UNILATERAL_DECISION_PATTERNS
    )

    patterns = [
        ExcusePattern(
            pattern=p.pattern,
            category=p.category,
            description=p.description,
            example=p.example,
            compiled=re.compile(p.pattern, re.IGNORECASE | re.MULTILINE),
        )
        for p in all_patterns
    ]

    mitigation = [re.compile(p, re.IGNORECASE) for p in MIT_PATTERNS]
    return PatternConfig(version="python-fallback", patterns=patterns, mitigation_patterns=mitigation)


def load_patterns_from_yaml(yaml_path: Path | None = None) -> PatternConfig:
    """Load and compile patterns from YAML file."""
    if not YAML_AVAILABLE:
        print("Warning: PyYAML not available, using Python patterns", file=sys.stderr)
        return _load_fallback_patterns()

    if yaml_path is None:
        yaml_path = Path(__file__).parent / "excuse_patterns.yaml"

    if not yaml_path.exists():
        print(f"Warning: Pattern file not found: {yaml_path}", file=sys.stderr)
        return _load_fallback_patterns()

    with open(yaml_path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f)

    # Compile mitigation patterns
    mitigation_patterns = []
    for pattern_str in data.get("mitigation_patterns", []):
        try:
            mitigation_patterns.append(re.compile(pattern_str, re.IGNORECASE))
        except re.error as e:
            print(f"Warning: Invalid mitigation pattern '{pattern_str}': {e}", file=sys.stderr)

    # Compile excuse patterns
    patterns = []
    for item in data.get("patterns", []):
        try:
            compiled = re.compile(item["pattern"], re.IGNORECASE | re.MULTILINE)
            patterns.append(ExcusePattern(
                pattern=item["pattern"],
                category=item["category"],
                description=item["description"],
                example=item["example"],
                compiled=compiled,
                added_from_llm=item.get("added_from_llm", False),
                added_date=item.get("added_date"),
            ))
        except re.error as e:
            print(f"Warning: Invalid pattern '{item.get('pattern', '?')}': {e}", file=sys.stderr)
        except KeyError as e:
            print(f"Warning: Pattern missing required field {e}", file=sys.stderr)

    return PatternConfig(
        version=data.get("version", "1.0"),
        patterns=patterns,
        mitigation_patterns=mitigation_patterns,
    )


def get_patterns_by_category(config: PatternConfig, category: str) -> list[ExcusePattern]:
    """Get all patterns for a specific category."""
    return [p for p in config.patterns if p.category == category]


def get_all_categories(config: PatternConfig) -> set[str]:
    """Get all unique categories in the pattern config."""
    return {p.category for p in config.patterns}


# Module-level cache
_cached_config: PatternConfig | None = None


def get_pattern_config() -> PatternConfig:
    """Get cached pattern config, loading from YAML if needed."""
    global _cached_config
    if _cached_config is None:
        _cached_config = load_patterns_from_yaml()
    return _cached_config


def reload_patterns() -> PatternConfig:
    """Force reload patterns from YAML."""
    global _cached_config
    _cached_config = load_patterns_from_yaml()
    return _cached_config


if __name__ == "__main__":
    # Test loading
    config = load_patterns_from_yaml()
    print(f"Loaded {len(config.patterns)} patterns (version {config.version})")
    print(f"Categories: {get_all_categories(config)}")
    print(f"Mitigation patterns: {len(config.mitigation_patterns)}")

    # Show counts by category
    for cat in sorted(get_all_categories(config)):
        count = len(get_patterns_by_category(config, cat))
        print(f"  {cat}: {count} patterns")
