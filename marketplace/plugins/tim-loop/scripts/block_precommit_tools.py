#!/usr/bin/env python3
"""
Block Pre-commit Tool Invocation - PreToolUse hook for Bash commands.

Blocks AI agents from directly invoking linters, formatters, and type checkers
that are managed by pre-commit hooks. Write correct code and let pre-commit
enforce at commit time.

Blocked tools: ruff, prettier, eslint, mypy, pyright, tsc, black, isort,
autopep8, flake8, pylint, biome, stylelint, bandit
"""

import json
import re
import sys

TOOLS = r"(ruff|prettier|eslint|mypy|pyright|tsc|black|isort|autopep8|flake8|pylint|biome|stylelint|bandit)"
SEG = r"(^|;\s*|&&\s*|\|\|\s*|\|\s*)"

BLOCKED_PATTERNS = [
    re.compile(SEG + r"\s*(\S+/)*" + TOOLS),
    re.compile(SEG + r"\s*(npx|bunx|pnpx)\s+" + TOOLS),
    re.compile(SEG + r"\s*(pipx\s+run|uv\s+run|poetry\s+run|pdm\s+run)\s+" + TOOLS),
    re.compile(SEG + r"\s*(\S+/)*python[0-9.]*\s+-m\s+" + TOOLS),
    re.compile(SEG + r"\s*(env|sudo|xargs|command|exec)\s+(-\S+\s+|[A-Z_]+=\S+\s+)*" + TOOLS),
]

DENY_TEMPLATE = (
    "Direct invocation of `{tool}` is blocked. Write correct code and let "
    "pre-commit enforce at commit time. Use `pre-commit run --all-files` to validate. "
    "If `{tool}` failed during a commit, the files are already fixed (hooks use --write). "
    "Just `git add` the changed files and re-commit."
)


def check_command(command: str) -> str | None:
    """Return the matched tool name if command should be blocked, else None."""
    for pattern in BLOCKED_PATTERNS:
        match = pattern.search(command)
        if match:
            return match.group(match.lastindex)
    return None


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    command = hook_input.get("tool_input", {}).get("command", "")
    if not command:
        sys.exit(0)

    tool = check_command(command)
    if tool:
        json.dump({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": DENY_TEMPLATE.format(tool=tool),
            }
        }, sys.stdout)
    sys.exit(0)


if __name__ == "__main__":
    main()
