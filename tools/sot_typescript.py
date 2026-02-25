"""TypeScript regex-based checks for settings SOT enforcement."""

import re
from pathlib import Path

# Tier 1 patterns: zero false positives, hard block
TIER1_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (
        re.compile(r"^(export\s+)?(const|let|var)\s+_?(DEFAULT|FALLBACK|BACKUP)_"),
        "DEFAULT/FALLBACK/BACKUP constant — use settings SOT",
    ),
    (
        re.compile(r"""process\.env\.\w+\s*(\|\||\?\?)\s*["']"""),
        "process.env with hardcoded default — use settings SOT",
    ),
]

# Tier 2 patterns: broader rules, CI advisory only
TIER2_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (
        re.compile(r"""\?\?\s*["'\d\[(true|false)]"""),
        "Nullish coalescing (??) with hardcoded fallback — use settings SOT",
    ),
    (
        re.compile(r"""\|\|\s*["'\d(true|false)]"""),
        "Logical OR (||) with hardcoded fallback — use settings SOT",
    ),
    (
        re.compile(r"""\.get\(.+,\s*["'\d]"""),
        ".get() with hardcoded fallback — use settings SOT",
    ),
]


def check_typescript_file(filepath: Path, tier: str = "block") -> list[str]:
    """Run regex-based checks on a TypeScript file."""
    violations: list[str] = []
    try:
        lines = filepath.read_text().splitlines()
    except (OSError, UnicodeDecodeError):
        return []

    patterns = list(TIER1_PATTERNS)
    if tier == "warn":
        patterns.extend(TIER2_PATTERNS)

    for lineno, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("*"):
            continue
        for pattern, msg in patterns:
            if pattern.search(line):
                violations.append(f"{filepath}:{lineno}: {msg}")
                break
    return violations
