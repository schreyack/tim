#!/usr/bin/env python3
"""TIM Pattern Drift Detector.

Compares .tim-patterns.yaml against actual dependencies to find:
  - Libraries in deps that map to unregistered patterns
  - Registered patterns whose libraries are missing from deps

Usage:
    python check-pattern-drift.py [project_path]
    python check-pattern-drift.py  # uses current directory

Exit codes: 0 = clean, 1 = drift detected
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[0;33m"
NC = "\033[0m"

TOOL_DIR = Path(__file__).resolve().parent
LIBRARY_MAP_PATH = TOOL_DIR / "pattern-library-map.yaml"


def load_library_map() -> dict[str, dict[str, list[str]]]:
    """Load the library-to-pattern mapping."""
    with open(LIBRARY_MAP_PATH) as f:
        return yaml.safe_load(f) or {}


# Standards that don't imply a specific installable library.
# Patterns using these won't trigger "stale" warnings.
STDLIB_STANDARDS = {
    "api-key", "python-stdlib", "local-filesystem", "asyncio",
    "raw-yaml", "kustomize", "helm", "clusterip", "longhorn",
    "self-hosted", "prometheus-grafana", "in-memory-ttl",
    "app-error-hierarchy", "tim-lib-errors", "CUSTOM",
}


def _parse_dict_patterns(raw: dict[str, object]) -> dict[str, str]:
    """Parse patterns in dict format: {key: {standard: value}}."""
    return {
        key: val.get("standard", "")
        for key, val in raw.items()
        if isinstance(val, dict)
    }


def _parse_list_patterns(raw: list[object]) -> dict[str, str]:
    """Parse patterns in list format: [{name: x, standard: y}]."""
    return {
        item["name"]: item.get("standard", "")
        for item in raw
        if isinstance(item, dict) and "name" in item
    }


def load_patterns(project: Path) -> dict[str, str]:
    """Load registered patterns, returning {pattern_key: standard}.

    Supports both dict format (standard: value) and list format
    (- name: x, scope: y).
    """
    path = project / ".tim-patterns.yaml"
    if not path.exists():
        return {}
    with open(path) as f:
        data = yaml.safe_load(f) or {}
    raw = data.get("patterns", {})
    if isinstance(raw, dict):
        return _parse_dict_patterns(raw)
    if isinstance(raw, list):
        return _parse_list_patterns(raw)
    return {}


def parse_requirements_txt(path: Path) -> set[str]:
    """Extract package names from requirements.txt."""
    if not path.exists():
        return set()
    packages: set[str] = set()
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("-"):
            continue
        # Handle name[extras]>=version, name==version, etc.
        for sep in (">=", "<=", "==", "!=", "~=", ">", "<", "[", ";"):
            if sep in line:
                line = line[:line.index(sep)]
                break
        name = line.strip().lower()
        if name:
            packages.add(name)
    return packages


def _extract_dep_name(raw: str) -> str:
    """Extract bare package name from a dependency specifier."""
    name = raw.split("=")[0].strip().strip('"').strip("'")
    for sep in (">=", "<=", "==", "!=", "~=", ">", "<", "[", ";"):
        if sep in name:
            name = name[:name.index(sep)]
            break
    return name.strip().lower()


def parse_pyproject_toml(path: Path) -> set[str]:
    """Extract dependency names from pyproject.toml."""
    if not path.exists():
        return set()
    packages: set[str] = set()
    in_deps = False
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            in_deps = "dependencies" in stripped.lower()
            continue
        if not in_deps or not stripped or stripped.startswith("#"):
            continue
        name = _extract_dep_name(stripped)
        if name and name != "python":
            packages.add(name)
    return packages


def parse_package_json(path: Path) -> set[str]:
    """Extract dependency names from package.json."""
    if not path.exists():
        return set()
    with open(path) as f:
        data = json.load(f)
    packages: set[str] = set()
    for key in ("dependencies", "devDependencies"):
        for name in data.get(key, {}):
            packages.add(name.lower())
    return packages


def detect_project_type(project: Path) -> str:
    """Detect python, node, or fullstack."""
    has_backend = (
        (project / "backend" / "pyproject.toml").exists()
        or (project / "backend" / "requirements.txt").exists()
    )
    has_frontend = (project / "frontend" / "package.json").exists()
    if has_backend and has_frontend:
        return "fullstack"
    if (project / "package.json").exists():
        return "node"
    return "python"


def collect_deps(project: Path, project_type: str) -> dict[str, set[str]]:
    """Collect all deps, keyed by language."""
    result: dict[str, set[str]] = {"python": set(), "node": set()}
    if project_type in ("python", "fullstack"):
        for subdir in (".", "backend"):
            base = project / subdir
            result["python"] |= parse_requirements_txt(base / "requirements.txt")
            result["python"] |= parse_pyproject_toml(base / "pyproject.toml")
    if project_type in ("node", "fullstack"):
        for subdir in (".", "frontend", "client", "server"):
            result["node"] |= parse_package_json(project / subdir / "package.json")
    return result


def _registered_categories(patterns: dict[str, str]) -> set[str]:
    """Collect all pattern categories covered by the registry.

    Includes both pattern keys and standard field values.
    """
    return set(patterns.keys()) | {v.lower() for v in patterns.values() if v}


def _lib_matches_registered(
    names: list[str],
    categories: set[str],
) -> bool:
    """Check if any of a library's acceptable names are registered."""
    return any(n in categories for n in names)


def _find_unregistered(
    deps: dict[str, set[str]],
    lib_map: dict[str, dict[str, list[str]]],
    categories: set[str],
) -> list[str]:
    """Find deps that map to patterns not in .tim-patterns.yaml."""
    unregistered: dict[str, list[str]] = {}
    for lang, packages in deps.items():
        lang_map = lib_map.get(lang, {})
        for pkg in packages:
            names = lang_map.get(pkg)
            if names and not _lib_matches_registered(names, categories):
                unregistered.setdefault(names[0], []).append(pkg)
    issues: list[str] = []
    for pattern, libs in sorted(unregistered.items()):
        lib_list = ", ".join(sorted(libs))
        issues.append(
            f"Unregistered: [{lib_list}] found in deps "
            f"but no '{pattern}' pattern in .tim-patterns.yaml"
        )
    return issues


def _find_stale(
    patterns: dict[str, str],
    all_deps: set[str],
    lib_map: dict[str, dict[str, list[str]]],
) -> list[str]:
    """Find registered patterns whose libraries are missing from deps."""
    reverse_map: dict[str, list[str]] = {}
    for lang_map in lib_map.values():
        for lib_name, names in lang_map.items():
            for name in names:
                reverse_map.setdefault(name, []).append(lib_name)

    issues: list[str] = []
    for pattern_key in sorted(patterns):
        standard = patterns[pattern_key]
        if standard in STDLIB_STANDARDS:
            continue
        expected_libs = reverse_map.get(pattern_key, [])
        if not expected_libs:
            continue
        if not any(lib.lower() in all_deps for lib in expected_libs):
            issues.append(
                f"Stale: '{pattern_key}' registered but none of "
                f"[{', '.join(sorted(set(expected_libs)))}] found in deps"
            )
    return issues


def check_drift(project: Path) -> list[str]:
    """Check for pattern drift. Returns list of issues."""
    lib_map = load_library_map()
    patterns = load_patterns(project)
    if not patterns:
        return ["No .tim-patterns.yaml found"]

    deps = collect_deps(project, detect_project_type(project))
    categories = _registered_categories(patterns)
    all_deps = deps.get("python", set()) | deps.get("node", set())

    issues = _find_unregistered(deps, lib_map, categories)
    issues += _find_stale(patterns, all_deps, lib_map)
    return issues


def main() -> None:
    project = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()
    project = project.resolve()

    issues = check_drift(project)

    if not issues:
        print(f"{GREEN}✓{NC} {project.name}: patterns in sync with deps")
        sys.exit(0)

    print(f"{RED}✗{NC} {project.name}: pattern drift detected")
    for issue in issues:
        print(f"  {YELLOW}→{NC} {issue}")
    sys.exit(1)


if __name__ == "__main__":
    main()
