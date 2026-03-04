"""CLI entrypoint for sync-pre-commit."""

from __future__ import annotations

import sys
from typing import Any

from sync_pre_commit.projects import (
    check_projects,
    list_projects,
    load_projects,
    sync_all,
    sync_one,
)


def parse_args(argv: list[str]) -> dict[str, Any]:
    """Parse command-line arguments."""
    args: dict[str, Any] = {
        "command": "sync_all",
        "project": None,
        "commit": True,
        "push": False,
    }
    positionals: list[str] = []

    for arg in argv[1:]:
        if arg in ("--list", "-l"):
            args["command"] = "list"
        elif arg in ("--check", "-c"):
            args["command"] = "check"
        elif arg in ("--help", "-h"):
            args["command"] = "help"
        elif arg == "--commit":
            args["commit"] = True
        elif arg == "--no-commit":
            args["commit"] = False
        elif arg == "--push":
            args["push"] = True
        elif arg == "--no-push":
            args["push"] = False
        else:
            positionals.append(arg)

    if positionals:
        args["command"] = "sync_one"
        args["project"] = positionals[0]

    return args


def print_help() -> None:
    print("Usage: sync-pre-commit [OPTIONS] [PROJECT]")
    print()
    print("Options:")
    print("  --list, -l     List projects + detected template types")
    print("  --check, -c    Check which projects need updates")
    print("  --no-commit    Skip auto-commit (default: commit locally)")
    print("  --push         Commit and push (default: commit only)")
    print("  --help, -h     Show this help")
    print()
    print("If PROJECT is specified, only that project is synced.")
    print("If no arguments, all projects are synced.")
    print()
    print("Auto-commits with --no-verify because .pre-commit-config.yaml")
    print("is a locked enforcement file.")


def main() -> None:
    args = parse_args(sys.argv)
    projects = load_projects()

    if args["command"] == "list":
        list_projects(projects)
    elif args["command"] == "check":
        count = check_projects(projects)
        sys.exit(1 if count > 0 else 0)
    elif args["command"] == "help":
        print_help()
    elif args["command"] == "sync_one":
        ok = sync_one(
            args["project"], projects,
            commit=args["commit"], push=args["push"],
        )
        sys.exit(0 if ok else 1)
    else:
        ok = sync_all(
            projects, commit=args["commit"], push=args["push"],
        )
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
