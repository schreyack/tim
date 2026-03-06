#!/usr/bin/env python3
"""
TIM AI Cheat Detection

Detects patterns that AI agents use to bypass type safety, error handling,
and other enforcement mechanisms.

Python (AST-based): empty except, broad exception, log-and-swallow,
    typing.cast(), defaultdict()
TypeScript (regex-based): double cast, empty catch

Usage:
    python detect-ai-cheats.py <files...> --language python|typescript
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sot_common import find_project_root, is_exempt, should_skip_path

import cheat_python
import cheat_typescript


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
    """Load exempt_files from .tim-ai-cheat.yaml if it exists."""
    if project_root is None:
        return []
    config_path = project_root / ".tim-ai-cheat.yaml"
    if not config_path.exists():
        return []

    try:
        import yaml

        data = yaml.safe_load(config_path.read_text()) or {}
        return data.get("exempt_files", []) or []
    except ImportError:
        pass

    return _parse_exempt_files_simple(config_path.read_text())


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

        if language == "python":
            violations.extend(cheat_python.check_file(filepath))
        else:
            violations.extend(cheat_typescript.check_file(filepath))
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Detect AI cheat patterns that bypass enforcement"
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

    print("AI cheat pattern violations found:", file=sys.stderr)
    for violation in violations:
        print(f"  {violation}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
