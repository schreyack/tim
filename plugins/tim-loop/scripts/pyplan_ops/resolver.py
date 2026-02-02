"""Plan path resolution.

Searches for plans by name across standard plan directories.
"""

import os
from pathlib import Path

PLAN_STAGES = ["drafts", "active", "completed", "abandoned"]


def get_plans_dir() -> Path:
    """Get the plans directory for the current project."""
    cwd = Path.cwd()
    check_dir = cwd
    while check_dir != check_dir.parent:
        plans_dir = check_dir / "plans"
        if plans_dir.is_dir():
            return plans_dir
        check_dir = check_dir.parent
    return cwd / "plans"


def get_claude_plans_dir() -> Path:
    """Get the Claude plans directory (~/.claude/plans/)."""
    return Path.home() / ".claude" / "plans"


def _search_directory(directory: Path, pattern: str) -> list[Path]:
    """Search a directory for matching plan files."""
    results: list[Path] = []
    if directory.is_dir():
        for file in directory.glob(f"*{pattern}*.md"):
            if file.is_file():
                results.append(file.resolve())
    return results


def _search_stage_dir(stage_dir: Path, pattern: str) -> list[Path]:
    """Search a stage directory for plans and packages."""
    results: list[Path] = []
    if not stage_dir.is_dir():
        return results

    # Standalone plan files
    results.extend(_search_directory(stage_dir, pattern))

    # Package folders (directories with MASTER.md)
    for subdir in stage_dir.iterdir():
        if subdir.is_dir() and pattern in subdir.name:
            master = subdir / "MASTER.md"
            if master.is_file():
                results.append(master.resolve())
    return results


def find_plans_by_name(pattern: str) -> list[Path]:
    """Find plan files matching a name pattern."""
    results: list[Path] = []
    base_pattern = pattern.removesuffix(".md")

    plans_dir = get_plans_dir()
    if plans_dir.is_dir():
        results.extend(_search_directory(plans_dir, base_pattern))
        for stage in PLAN_STAGES:
            results.extend(_search_stage_dir(plans_dir / stage, base_pattern))

    results.extend(_search_directory(get_claude_plans_dir(), base_pattern))
    return sorted(set(results))


def _prompt_user_selection(matches: list[Path], pattern: str) -> Path:
    """Prompt user to select from multiple matching plans."""
    print(f"\nMultiple plans found matching '{pattern}':\n")

    for i, match in enumerate(matches, 1):
        # Show relative path from home or absolute
        display_path = str(match).replace(str(Path.home()), "~")
        # Indicate if this is a package MASTER.md
        if match.name == "MASTER.md":
            pkg_dir = match.parent
            display_path = f"{str(pkg_dir).replace(str(Path.home()), '~')} [PACKAGE]"
        print(f"  [{i}] {display_path}")

    print()

    while True:
        try:
            choice = input(f"Select plan [1-{len(matches)}]: ").strip()
            idx = int(choice)
            if 1 <= idx <= len(matches):
                return matches[idx - 1]
        except (ValueError, EOFError):
            pass
        print(f"Invalid choice. Enter a number between 1 and {len(matches)}.")


def _try_resolve_as_path(arg: str) -> Path | None:
    """Try to resolve argument as a direct file path. Returns None if not found."""
    arg_path = Path(arg)
    abs_path = arg_path if arg_path.is_absolute() else Path.cwd() / arg_path

    if abs_path.is_file():
        return abs_path.resolve()
    if abs_path.is_dir():
        master = abs_path / "MASTER.md"
        if master.is_file():
            return master.resolve()
    return None


def _get_search_name(arg: str) -> str:
    """Extract search name from argument, warning if path doesn't exist."""
    if os.sep in arg or "/" in arg:
        print(f"Warning: File not found at: {arg}")
        print(f"Searching for plan by name: {Path(arg).stem}")
        return Path(arg).stem
    return arg


def _raise_not_found(arg: str) -> None:
    """Raise FileNotFoundError with helpful message."""
    plans_dir = get_plans_dir()
    raise FileNotFoundError(
        f"No plan found matching: {arg}\n"
        f"Searched in: {plans_dir}, {plans_dir}/*, {get_claude_plans_dir()}"
    )


def resolve_plan_path(arg: str, auto_select_single: bool = True) -> Path:
    """Resolve a plan argument to an absolute path."""
    # If it looks like a path, try direct resolution first
    if os.sep in arg or "/" in arg:
        resolved = _try_resolve_as_path(arg)
        if resolved:
            return resolved

    search_name = _get_search_name(arg)
    matches = find_plans_by_name(search_name)

    if not matches:
        _raise_not_found(arg)

    if len(matches) == 1 and auto_select_single:
        return matches[0]

    return _prompt_user_selection(matches, arg)
