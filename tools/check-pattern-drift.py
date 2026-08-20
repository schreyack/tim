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
import re
import sys
import tomllib
from collections.abc import Iterable
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


def load_patterns(project: Path) -> dict[str, str] | None:
    """Load registered patterns, returning {pattern_key: standard}.

    Returns None if the file is missing (distinct from empty patterns).
    Supports both dict format (standard: value) and list format
    (- name: x, scope: y).
    """
    path = project / ".tim-patterns.yaml"
    if not path.exists():
        return None
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
    """Extract bare package name from a dependency specifier.

    Extras and environment markers are stripped before the version operators:
    in `uvicorn[standard]>=0.34` the `>` is reached first, so trimming there
    would leave the extras attached and the name would match nothing.
    """
    name = raw.split("=")[0].strip().strip('"').strip("'")
    for sep in ("[", ";", ">=", "<=", "==", "!=", "~=", ">", "<"):
        if sep in name:
            name = name[:name.index(sep)]
            break
    return name.strip().lower()


def _dep_names(specs: Iterable[str]) -> set[str]:
    """Package names from requirement specifiers or a table's keys."""
    names = {_extract_dep_name(spec) for spec in specs}
    return {name for name in names if name and name != "python"}


def parse_pyproject_toml(path: Path) -> set[str]:
    """Extract dependency names from pyproject.toml.

    Reads the file as TOML rather than scanning lines, because the two layouts
    put dependencies in different shapes: PEP 621 uses an inline array under
    `[project]`, Poetry uses a table whose keys are the package names. The old
    line scanner only recognised a section header containing "dependencies",
    so a PEP 621 project reported its optional extras and none of its real
    dependencies — including the closing bracket as if it were a package.
    """
    if not path.exists():
        return set()
    with path.open("rb") as handle:
        data = tomllib.load(handle)

    packages: set[str] = set()

    project = data["project"] if "project" in data else {}
    if "dependencies" in project:
        packages |= _dep_names(project["dependencies"])
    for extra in project.get("optional-dependencies", {}).values():
        packages |= _dep_names(extra)

    # PEP 735 dependency groups, which sit at the top level.
    for group in data.get("dependency-groups", {}).values():
        packages |= _dep_names(item for item in group if isinstance(item, str))

    poetry = data.get("tool", {}).get("poetry", {})
    packages |= _dep_names(poetry.get("dependencies", {}))
    for group in poetry.get("group", {}).values():
        packages |= _dep_names(group.get("dependencies", {}))

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


_CMAKE_FIND_PACKAGE = re.compile(r"find_package\s*\(\s*([A-Za-z0-9_\-]+)", re.IGNORECASE)
_CMAKE_FETCHCONTENT = re.compile(r"FetchContent_Declare\s*\(\s*([A-Za-z0-9_\-]+)", re.IGNORECASE)
_SWIFT_PKG_URL = re.compile(r'\.package\(\s*url:\s*"([^"]+)"')
_SWIFT_PKG_NAME = re.compile(r'\.package\(\s*name:\s*"([^"]+)"')


def parse_cmake(path: Path) -> set[str]:
    """Extract dependency names from a CMakeLists.txt (find_package, FetchContent)."""
    if not path.exists():
        return set()
    text = path.read_text()
    packages = {m.group(1).lower() for m in _CMAKE_FIND_PACKAGE.finditer(text)}
    packages |= {m.group(1).lower() for m in _CMAKE_FETCHCONTENT.finditer(text)}
    return packages


def parse_swift_package(path: Path) -> set[str]:
    """Extract SwiftPM dependency names from a Package.swift."""
    if not path.exists():
        return set()
    text = path.read_text()
    packages: set[str] = set()
    for m in _SWIFT_PKG_URL.finditer(text):
        name = m.group(1).rstrip("/").rsplit("/", 1)[-1]
        if name.endswith(".git"):
            name = name[:-4]
        packages.add(name.lower())
    packages |= {m.group(1).lower() for m in _SWIFT_PKG_NAME.finditer(text)}
    return packages


def parse_swift_resolved(path: Path) -> set[str]:
    """Extract resolved package identities from a Package.resolved (v1 or v2)."""
    if not path.exists():
        return set()
    with open(path) as f:
        data = json.load(f)
    pins = data.get("pins", []) or data.get("object", {}).get("pins", [])
    packages: set[str] = set()
    for pin in pins:
        ident = pin.get("identity") or pin.get("package")
        if ident:
            packages.add(ident.lower())
    return packages


def _is_native(project: Path) -> bool:
    """Detect a native (C++/Swift) project by its build/package manifest."""
    if (project / "CMakeLists.txt").exists():
        return True
    if any(project.glob("*.xcodeproj")):
        return True
    return (
        (project / "Package.swift").exists()
        or any(project.glob("*/Package.swift"))
        or any(project.glob("*/*/Package.swift"))
    )


def detect_project_type(project: Path) -> str:
    """Detect python, node, fullstack, or native."""
    has_backend = (
        (project / "backend" / "pyproject.toml").exists()
        or (project / "backend" / "requirements.txt").exists()
    )
    has_frontend = (project / "frontend" / "package.json").exists()
    if has_backend and has_frontend:
        return "fullstack"
    if _is_native(project):
        return "native"
    if (project / "package.json").exists():
        return "node"
    return "python"


def _collect_native_deps(project: Path) -> set[str]:
    """Collect C++ (CMake) and Swift (SwiftPM) dependency names."""
    packages: set[str] = parse_cmake(project / "CMakeLists.txt")
    for cml in project.glob("*/CMakeLists.txt"):
        packages |= parse_cmake(cml)
    swift_manifests = [
        project / "Package.swift",
        *project.glob("*/Package.swift"),
        *project.glob("*/*/Package.swift"),
    ]
    for manifest in swift_manifests:
        packages |= parse_swift_package(manifest)
    resolved = [
        project / "Package.resolved",
        *project.glob("*/Package.resolved"),
        *project.glob("*/*/Package.resolved"),
    ]
    for lock in resolved:
        packages |= parse_swift_resolved(lock)
    return packages


def collect_deps(project: Path, project_type: str) -> dict[str, set[str]]:
    """Collect all deps, keyed by language."""
    result: dict[str, set[str]] = {"python": set(), "node": set(), "native": set()}
    if project_type in ("python", "fullstack"):
        for subdir in (".", "backend"):
            base = project / subdir
            result["python"] |= parse_requirements_txt(base / "requirements.txt")
            result["python"] |= parse_pyproject_toml(base / "pyproject.toml")
    if project_type in ("node", "fullstack"):
        for subdir in (".", "frontend", "client", "server"):
            result["node"] |= parse_package_json(project / subdir / "package.json")
    if project_type == "native":
        result["native"] |= _collect_native_deps(project)
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
    if patterns is None:
        return ["No .tim-patterns.yaml found"]
    if not patterns:
        return []

    deps = collect_deps(project, detect_project_type(project))
    categories = _registered_categories(patterns)
    all_deps = (
        deps.get("python", set()) | deps.get("node", set()) | deps.get("native", set())
    )

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
