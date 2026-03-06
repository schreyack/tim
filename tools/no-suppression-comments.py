#!/usr/bin/env python3
"""
TIM No Suppression Comments Enforcement

Detects inline suppression comments that silence linters, type checkers,
and formatters. Suppressing warnings hides real issues.

No inline exemption mechanism. File-level only via .tim-no-suppression.yaml.

Usage:
    python no-suppression-comments.py <files...> --language python|typescript
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sot_common import find_project_root, is_exempt, should_skip_path

PYTHON_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"#\s*noqa"), "noqa suppression comment"),
    (re.compile(r"#\s*type:\s*ignore"), "mypy type: ignore suppression"),
    (re.compile(r"#\s*pylint:\s*disable"), "pylint inline disable"),
    (re.compile(r"#\s*fmt:\s*(off|on|skip)"), "formatter suppression"),
    (re.compile(r"#\s*isort:\s*skip"), "isort skip suppression"),
]

TYPESCRIPT_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"//\s*eslint-disable"), "eslint-disable suppression"),
    (re.compile(r"/\*\s*eslint-disable"), "eslint-disable block suppression"),
    (re.compile(r"//\s*@ts-ignore"), "@ts-ignore suppression"),
    (re.compile(r"//\s*@ts-expect-error"), "@ts-expect-error suppression"),
    (re.compile(r"//\s*@ts-nocheck"), "@ts-nocheck suppression"),
    (re.compile(r"//\s*prettier-ignore"), "prettier-ignore suppression"),
    (re.compile(r"//\s*biome-ignore"), "biome-ignore suppression"),
]


def _parse_exempt_files_simple(text: str) -> list[str]:
    """Parse exempt_files list from simple YAML without PyYAML."""
    patterns: list[str] = []
    in_exempt = False
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped == "exempt_files:":
            in_exempt = True
            continue
        if in_exempt and stripped.startswith("- "):
            patterns.append(stripped[2:].strip().strip("\"'"))
        elif not line.startswith(" "):
            in_exempt = False
    return patterns


def _load_exempt_patterns(project_root: Path | None) -> list[str]:
    """Load exempt_files from .tim-no-suppression.yaml if it exists."""
    if project_root is None:
        return []
    config_path = project_root / ".tim-no-suppression.yaml"
    if not config_path.exists():
        return []

    try:
        import yaml

        data = yaml.safe_load(config_path.read_text()) or {}
        return data.get("exempt_files", []) or []
    except ImportError:
        pass

    return _parse_exempt_files_simple(config_path.read_text())


def check_file(
    filepath: Path,
    language: str,
) -> list[str]:
    """Check a single file for suppression comments."""
    try:
        lines = filepath.read_text().splitlines()
    except (OSError, UnicodeDecodeError):
        return []

    patterns = PYTHON_PATTERNS if language == "python" else TYPESCRIPT_PATTERNS
    violations: list[str] = []
    for lineno, line in enumerate(lines, 1):
        for regex, message in patterns:
            if regex.search(line):
                violations.append(f"{filepath}:{lineno}: {message}")
                break
    return violations


def collect_violations(
    paths: list[str],
    language: str,
    project_root: Path | None,
    exempt_patterns: list[str],
) -> list[str]:
    """Check all given file paths and return violations."""
    violations: list[str] = []
    for path_str in paths:
        filepath = Path(path_str)
        if not filepath.exists() or not filepath.is_file():
            continue
        if should_skip_path(filepath):
            continue
        if project_root and is_exempt(filepath, project_root, exempt_patterns):
            continue
        violations.extend(check_file(filepath, language))
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(
        description="No suppression comments — fix issues instead of silencing them"
    )
    parser.add_argument("paths", nargs="+", help="Files to check")
    parser.add_argument(
        "--language",
        choices=["python", "typescript"],
        required=True,
        help="Language to check",
    )
    args = parser.parse_args()

    project_root = find_project_root(Path(args.paths[0]).resolve())
    exempt_patterns = _load_exempt_patterns(project_root)

    violations = collect_violations(
        args.paths, args.language, project_root, exempt_patterns,
    )

    if not violations:
        return 0

    print("Suppression comment violations found:", file=sys.stderr)
    for violation in violations:
        print(f"  {violation}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
