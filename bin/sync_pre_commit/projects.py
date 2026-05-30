"""Project discovery, detection, syncing, and status checking."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from sync_pre_commit.config import (
    BLUE,
    GREEN,
    NC,
    RED,
    TEMPLATES_DIR,
    TIM_ROOT,
    YELLOW,
    load_template,
    load_yaml_file,
    merge_config,
    write_config,
)
from sync_pre_commit.fileops import (
    git_commit_and_push,
    has_autogen_header,
    is_file_locked,
    print_schg_commands,
)


def load_projects() -> list[Path]:
    """Load registered projects from .tim-projects file."""
    projects_file = TIM_ROOT / ".tim-projects"
    if not projects_file.exists():
        print(f"{YELLOW}Warning: {projects_file} not found.{NC}")
        print("Create it with one project path per line.")
        return []
    projects: list[Path] = []
    with open(projects_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                projects.append(Path(line))
    return projects


def _detect_from_symlink(project: Path) -> str | None:
    """Detect template type from existing config symlink target."""
    config = project / ".pre-commit-config.yaml"
    if not config.is_symlink():
        return None
    target = str(os.readlink(config))
    for ttype in ("fullstack", "native", "node", "python"):
        if f"templates/{ttype}" in target:
            return ttype
    return None


def _is_native(project: Path) -> bool:
    """Detect a native (C++/Swift) project.

    A native project is identified by a build/package manifest for compiled
    desktop code: a root CMakeLists.txt, an Xcode project, or a Package.swift
    at the root or up to two directory levels down (e.g. native/App/Package.swift).
    """
    if (project / "CMakeLists.txt").exists():
        return True
    if any(project.glob("*.xcodeproj")):
        return True
    return (
        (project / "Package.swift").exists()
        or any(project.glob("*/Package.swift"))
        or any(project.glob("*/*/Package.swift"))
    )


def detect_template_type(project: Path) -> str | None:
    """Auto-detect whether a project is python, node, fullstack, or native."""
    has_backend = (
        (project / "backend" / "pyproject.toml").exists()
        or (project / "backend" / "requirements.txt").exists()
    )
    has_frontend = (project / "frontend" / "package.json").exists()

    if has_backend and has_frontend:
        return "fullstack"

    # Native is checked above node/python: a native project may carry stray
    # Python tooling (or none packaged) but is keyed by its C++/Swift manifest.
    if _is_native(project):
        return "native"

    if (project / "package.json").exists():
        return "node"
    if (project / "pyproject.toml").exists() or (project / "requirements.txt").exists():
        return "python"

    return _detect_from_symlink(project)


def _template_mtimes(template_type: str) -> list[float]:
    """Get mtimes of all relevant templates for a type."""
    if template_type == "fullstack":
        paths = [
            TEMPLATES_DIR / "fullstack" / ".pre-commit-config.yaml",
            TEMPLATES_DIR / "python" / ".pre-commit-config.yaml",
            TEMPLATES_DIR / "node" / ".pre-commit-config.yaml",
        ]
    else:
        paths = [TEMPLATES_DIR / template_type / ".pre-commit-config.yaml"]
    return [p.stat().st_mtime for p in paths if p.exists()]


def _presets_newer_than(overrides_path: Path, config_mtime: float) -> bool:
    """Check if presets.py is newer than config for preset-using projects."""
    if not overrides_path.exists():
        return False
    overrides_data = load_yaml_file(overrides_path)
    if not overrides_data.get("project_type"):
        return False
    presets_path = Path(__file__).parent / "presets.py"
    return presets_path.exists() and presets_path.stat().st_mtime > config_mtime


def needs_sync(project: Path, template_type: str) -> tuple[bool, str]:
    """Check if a project's pre-commit config needs regeneration."""
    config_path = project / ".pre-commit-config.yaml"

    if not config_path.exists():
        return True, "config missing"

    if config_path.is_symlink():
        return True, "still a symlink (needs migration)"

    if not has_autogen_header(config_path):
        return True, "missing AUTO-GENERATED header"

    config_mtime = config_path.stat().st_mtime

    for tmpl_mtime in _template_mtimes(template_type):
        if tmpl_mtime > config_mtime:
            return True, "base template is newer"

    overrides_path = project / ".pre-commit-overrides.yaml"
    if overrides_path.exists() and overrides_path.stat().st_mtime > config_mtime:
        return True, "overrides file is newer"

    if _presets_newer_than(overrides_path, config_mtime):
        return True, "presets module is newer"

    return False, "up to date"


def print_header(title: str) -> None:
    print(f"{BLUE}{'━' * 60}{NC}")
    print(f"{BLUE}  {title}{NC}")
    print(f"{BLUE}{'━' * 60}{NC}")


def list_projects(projects: list[Path]) -> None:
    """List all registered projects with detected types."""
    print_header("Registered TIM Projects")
    for project in projects:
        name = project.name
        if not project.is_dir():
            print(f"  {RED}✗{NC} {name} - directory not found")
            continue
        ttype = detect_template_type(project)
        config = project / ".pre-commit-config.yaml"
        if ttype:
            status = "symlink" if config.is_symlink() else (
                "generated" if has_autogen_header(config) else "manual"
            )
            locked = " [locked]" if is_file_locked(config) else ""
            print(f"  {GREEN}✓{NC} {name} ({ttype}) - {status}{locked}")
        else:
            print(f"  {YELLOW}!{NC} {name} - unable to detect type")


def check_projects(projects: list[Path]) -> int:
    """Check which projects need updates. Returns count needing sync."""
    print_header("Checking Pre-commit Config Status")
    needs_update = 0

    for project in projects:
        name = project.name
        if not project.is_dir():
            print(f"  {RED}✗{NC} {name} - directory not found")
            continue

        ttype = detect_template_type(project)
        if not ttype:
            print(f"  {YELLOW}!{NC} {name} - unable to detect type, skipping")
            continue

        should_sync, reason = needs_sync(project, ttype)
        if should_sync:
            print(f"  {YELLOW}↻{NC} {name} ({ttype}) - {reason}")
            needs_update += 1
        else:
            print(f"  {GREEN}✓{NC} {name} ({ttype}) - {reason}")

    return needs_update


def sync_project(project: Path) -> Path | None:
    """Sync a single project. Returns output path on success."""
    name = project.name

    if not project.is_dir():
        print(f"  {RED}✗{NC} {name} - directory not found: {project}")
        return None

    ttype = detect_template_type(project)
    if not ttype:
        print(f"  {RED}✗{NC} {name} - unable to detect project type")
        print(
            "      Add package.json (node), pyproject.toml (python), "
            "or CMakeLists.txt/Package.swift (native)"
        )
        return None

    base = load_template(ttype)
    overrides = load_yaml_file(project / ".pre-commit-overrides.yaml")

    if overrides:
        _print_overrides_summary(name, overrides)

    config = merge_config(base, overrides)
    write_config(project, ttype, name, config)

    print(f"  {GREEN}✓{NC} {name} ({ttype}) - synced successfully")
    return project / ".pre-commit-config.yaml"


def _print_overrides_summary(name: str, overrides: dict[str, Any]) -> None:
    """Print a summary of applied overrides."""
    disabled = overrides.get("disable", [])
    extra = len(overrides.get("repos", []))
    hook_mods = overrides.get("hooks", {})
    enabled = overrides.get("enable", [])
    project_type = overrides.get("project_type")
    parts: list[str] = []
    if project_type:
        parts.append(f"type={project_type}")
    if disabled:
        parts.append(f"disabled {len(disabled)} hooks")
    if enabled:
        parts.append(f"enabled {len(enabled)} hooks")
    if hook_mods:
        parts.append(f"modified {len(hook_mods)} hooks")
    if extra:
        parts.append(f"added {extra} repos")
    print(f"  {BLUE}⚙{NC} {name} - applying overrides: {', '.join(parts)}")


def sync_all(
    projects: list[Path], *, commit: bool = False, push: bool = True,
) -> bool:
    """Sync all registered projects."""
    print_header("Syncing Pre-commit Configs")
    all_ok = True
    synced_projects: list[Path] = []
    synced_paths: list[Path] = []
    for project in projects:
        result = sync_project(project)
        if result is None:
            all_ok = False
        else:
            synced_paths.append(result)
            synced_projects.append(project)

    print()
    if all_ok:
        print(f"{GREEN}All projects synced successfully.{NC}")
    else:
        print(f"{YELLOW}Some projects failed to sync. See errors above.{NC}")

    if commit and synced_projects:
        print()
        print_header("Committing Changes")
        for project in synced_projects:
            if not git_commit_and_push(project, push=push):
                all_ok = False

    print_schg_commands(synced_paths)
    return all_ok


def sync_one(
    target: str,
    projects: list[Path],
    *,
    commit: bool = False,
    push: bool = True,
) -> bool:
    """Sync a specific project by name or path."""
    for project in projects:
        if project.name == target or str(project) == target:
            print_header(f"Syncing {project.name}")
            result = sync_project(project)
            if result is None:
                return False
            if commit:
                print()
                print_header("Committing Changes")
                if not git_commit_and_push(project, push=push):
                    print_schg_commands([result])
                    return False
            print_schg_commands([result])
            return True

    print(f"{RED}Error: Project '{target}' not found in registered projects.{NC}")
    print("Run 'sync-pre-commit --list' to see registered projects.")
    return False
