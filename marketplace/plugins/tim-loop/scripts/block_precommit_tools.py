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

# Tools whose pre-commit hooks auto-fix files (--write / --fix)
AUTOFIX_TOOLS = {"prettier", "ruff", "black", "isort", "autopep8", "biome", "stylelint", "eslint"}

DENY_AUTOFIX = (
    "Direct invocation of `{tool}` is blocked. Write correct code and let "
    "pre-commit enforce at commit time. Use `pre-commit run --all-files` to validate.\n\n"
    "Recovery when `{tool}` fails during a commit (hooks auto-fix with --write):\n"
    "  1. Run `git diff --name-only` to find ALL files the hook modified\n"
    "  2. `git add` every file from that list (not just the one you think failed)\n"
    "  3. Re-commit with the same message"
)

DENY_CHECKONLY = (
    "Direct invocation of `{tool}` is blocked. Write correct code and let "
    "pre-commit enforce at commit time. Use `pre-commit run --all-files` to validate.\n\n"
    "Recovery when `{tool}` fails during a commit (check-only — no auto-fix):\n"
    "  1. Read the pre-commit error output to see the specific errors\n"
    "  2. Fix the errors in your source code\n"
    "  3. `git add` the fixed files and re-commit"
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
        template = DENY_AUTOFIX if tool in AUTOFIX_TOOLS else DENY_CHECKONLY
        json.dump({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": template.format(tool=tool),
            }
        }, sys.stdout)
    sys.exit(0)


if __name__ == "__main__":
    main()
