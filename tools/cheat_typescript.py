"""
Regex-based cheat detection for TypeScript files.

Detects patterns that AI agents use to bypass type safety:
- Double cast (as unknown as Type / as any as Type)
- Empty catch blocks (catch (e) {})

Auto-exempts test files.
"""

import re
import sys
from pathlib import Path

DOUBLE_CAST_RE = re.compile(r"as\s+(unknown|any)\s+as\s+\w")
EMPTY_CATCH_RE = re.compile(r"catch\s*(\([^)]*\))?\s*\{\s*\}")

TEST_PATTERNS = (
    ".test.ts", ".test.tsx", ".spec.ts", ".spec.tsx",
)
TEST_DIRS = ("__tests__", "tests")


def _is_test_file(filepath: Path) -> bool:
    """Check if a file is a test file by name or directory."""
    name = filepath.name
    if any(name.endswith(pat) for pat in TEST_PATTERNS):
        return True
    return any(d in filepath.parts for d in TEST_DIRS)


def check_file(filepath: Path) -> list[str]:
    """Check a TypeScript file for cheat patterns."""
    if _is_test_file(filepath):
        return []

    try:
        content = filepath.read_text()
    except (OSError, UnicodeDecodeError):
        return []

    violations: list[str] = []

    for match in DOUBLE_CAST_RE.finditer(content):
        lineno = content[:match.start()].count("\n") + 1
        violations.append(
            f"{filepath}:{lineno}: Double cast (as {match.group(1)} as) "
            "bypasses type safety"
        )

    for match in EMPTY_CATCH_RE.finditer(content):
        lineno = content[:match.start()].count("\n") + 1
        violations.append(
            f"{filepath}:{lineno}: Empty catch block swallows errors"
        )

    return violations


if __name__ == "__main__":
    all_violations: list[str] = []
    for arg in sys.argv[1:]:
        all_violations.extend(check_file(Path(arg)))
    for v in all_violations:
        print(v, file=sys.stderr)
    sys.exit(1 if all_violations else 0)
