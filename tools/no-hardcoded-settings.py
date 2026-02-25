#!/usr/bin/env python3
"""
TIM Settings SOT Enforcement

Detects hardcoded defaults and fallback values that bypass the settings
source of truth (database/config). Enforces that all configuration reads
go through the settings layer with no fallback escape hatches.

Opt-in: Only enforces if .tim-settings-sot.yaml exists in project root.
No inline suppression — exempt_files in the config is the only exclusion.

Two-tier enforcement:
  --tier block  (default) Tier 1 rules only, exits 1 on violations.
  --tier warn   Tier 1 + Tier 2 rules, prints warnings to stderr, exits 0.

Usage:
    python no-hardcoded-settings.py <files...> --language python|typescript [--tier block|warn]
"""

import argparse
import sys
from pathlib import Path

# Allow importing sibling modules when run as a script
sys.path.insert(0, str(Path(__file__).resolve().parent))

from sot_common import (
    BlockedPattern,
    check_blocked_patterns,
    find_project_root,
    is_exempt,
    load_config,
    parse_blocked_patterns,
    should_skip_path,
)
from sot_python import check_python_file
from sot_typescript import check_typescript_file


def collect_violations(
    paths: list[str],
    language: str,
    tier: str,
    project_root: Path,
    exempt_patterns: list[str],
    blocked_patterns: list[BlockedPattern],
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
            violations.extend(check_python_file(filepath, tier=tier))
        else:
            violations.extend(check_typescript_file(filepath, tier=tier))
        violations.extend(
            check_blocked_patterns(filepath, project_root, blocked_patterns)
        )
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
    parser.add_argument(
        "--tier",
        choices=["block", "warn"],
        default="block",
        help="Enforcement tier: block (Tier 1, hard fail) or warn (Tier 1+2, advisory)",
    )
    args = parser.parse_args()

    project_root = find_project_root(Path(args.paths[0]).resolve())
    if project_root is None:
        return 0

    config = load_config(project_root)
    if config is None:
        return 0

    exempt_patterns: list[str] = config.get("exempt_files", []) or []
    blocked = parse_blocked_patterns(config)

    violations = collect_violations(
        args.paths, args.language, args.tier, project_root, exempt_patterns, blocked,
    )

    if not violations:
        return 0

    if args.tier == "warn":
        print("Settings SOT warnings (advisory):", file=sys.stderr)
        for violation in violations:
            print(f"  {violation}", file=sys.stderr)
        return 0

    print("Settings SOT violations found:", file=sys.stderr)
    for violation in violations:
        print(f"  {violation}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
