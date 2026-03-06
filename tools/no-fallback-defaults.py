#!/usr/bin/env python3
"""
TIM No Fallback Defaults Enforcement

Detects ALL fallback defaults on ALL data reads — not just settings objects.
Silent defaults mask bugs; if a value is missing, code should fail loudly.

Always-on: no opt-in config file required. Runs on every file.
Optional .tim-no-fallback.yaml for exempt_files only.

Usage:
    python no-fallback-defaults.py <files...> --language python|typescript
"""

import argparse
import sys
from pathlib import Path

# Allow importing sibling modules when run as a script
sys.path.insert(0, str(Path(__file__).resolve().parent))

from sot_common import find_project_root, is_exempt, should_skip_path

import fallback_python
import fallback_typescript


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
    """Load exempt_files from .tim-no-fallback.yaml if it exists."""
    if project_root is None:
        return []
    config_path = project_root / ".tim-no-fallback.yaml"
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
            violations.extend(fallback_python.check_file(filepath))
        else:
            violations.extend(fallback_typescript.check_file(filepath))
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(
        description="No fallback defaults — fail loudly on missing values"
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

    print("Fallback default violations found:", file=sys.stderr)
    for violation in violations:
        print(f"  {violation}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
