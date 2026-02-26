"""TypeScript regex-based checks for universal fallback default detection."""

import re
from pathlib import Path

NOQA_TAG = "// noqa: no-fallback"

# Literal patterns for reuse
_STR_LIT = r"""["'`]"""
_NUM_LIT = r"\d"
_BOOL_LIT = r"(true|false)"
_ARR_LIT = r"\["
_OBJ_LIT = r"\{"

_LITERAL = rf"({_STR_LIT}|{_NUM_LIT}|{_BOOL_LIT}|{_ARR_LIT}|{_OBJ_LIT})"

PATTERNS: list[tuple[re.Pattern[str], str]] = [
    # Pattern 1: ?? <literal>
    (
        re.compile(rf"\?\?\s*{_LITERAL}"),
        "Nullish coalescing (??) with literal fallback — fail loudly instead",
    ),
    # Pattern 2: || <literal>
    (
        re.compile(rf"\|\|\s*{_LITERAL}"),
        "Logical OR (||) with literal fallback — fail loudly instead",
    ),
    # Pattern 3: .get(key, default)
    (
        re.compile(rf"""\.get\(.+,\s*{_LITERAL}"""),
        ".get() with fallback default — fail loudly instead",
    ),
    # Pattern 4: { x = <literal> } destructuring defaults
    (
        re.compile(
            rf"""\{{\s*[^}}]*\w+\s*=\s*{_LITERAL}"""
        ),
        "Destructuring with literal default — fail loudly instead",
    ),
    # Pattern 5: _.get(obj, path, default) — lodash
    (
        re.compile(rf"""_\.get\(.+,.+,\s*{_LITERAL}"""),
        "_.get() with fallback default — fail loudly instead",
    ),
]


def check_file(filepath: Path) -> list[str]:
    """Run regex-based fallback default checks on a TypeScript file."""
    violations: list[str] = []
    try:
        lines = filepath.read_text().splitlines()
    except (OSError, UnicodeDecodeError):
        return []

    for lineno, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("//") or stripped.startswith("*"):
            continue
        if NOQA_TAG in line:
            continue
        for pattern, msg in PATTERNS:
            if pattern.search(line):
                violations.append(f"{filepath}:{lineno}: {msg}")
                break
    return violations
