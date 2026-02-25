#!/usr/bin/env python3
"""
TIM Settings SOT Enforcement

Detects hardcoded defaults and fallback values that bypass the settings
source of truth (database/config). Enforces that all configuration reads
go through the settings layer with no fallback escape hatches.

Opt-in: Only enforces if .tim-settings-sot.yaml exists in project root.
No inline suppression — exempt_files in the config is the only exclusion.

Usage:
    python no-hardcoded-settings.py <files...> --language python|typescript
"""

import argparse
import sys
from pathlib import Path

# Allow importing sibling modules when run as a script
sys.path.insert(0, str(Path(__file__).resolve().parent))

from sot_common import (
    build_extra_names,
    find_project_root,
    is_exempt,
    load_config,
    should_skip_path,
)
from sot_python import check_python_file
from sot_typescript import check_typescript_file


def collect_violations(
    paths: list[str],
    language: str,
    project_root: Path,
    exempt_patterns: list[str],
    extra_names: set[str],
) -> list[str]:
    """Check all given file paths and return violations."""
    violations: list[str] = []
    for path_str in paths:
        filepath = Path(path_str)
        if not filepath.exists() or not filepath.is_file():
            continue
        if should_skip_path(filepath):
            continue
        if is_exempt(filepath, project_root, exempt_patterns):
            continue

        if language == "python":
            violations.extend(check_python_file(filepath, extra_names))
        else:
            violations.extend(check_typescript_file(filepath))
    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description="Enforce settings SOT — no hardcoded defaults")
    parser.add_argument("paths", nargs="+", help="Files to check")
    parser.add_argument(
        "--language",
        choices=["python", "typescript"],
        required=True,
        help="Language to check",
    )
    args = parser.parse_args()

    project_root = find_project_root(Path(args.paths[0]).resolve())
    if project_root is None:
        return 0

    config = load_config(project_root)
    if config is None:
        return 0

    exempt_patterns: list[str] = config.get("exempt_files", []) or []
    extra_names = build_extra_names(config)

    violations = collect_violations(
        args.paths, args.language, project_root, exempt_patterns, extra_names,
    )

    if not violations:
        return 0

    print("Settings SOT violations found:", file=sys.stderr)
    for violation in violations:
        print(f"  {violation}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
