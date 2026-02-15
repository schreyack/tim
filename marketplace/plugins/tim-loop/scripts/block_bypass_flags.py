#!/usr/bin/env python3
"""
Block Bypass Flags - PreToolUse hook for Bash commands.

Blocks AI agents from using flags that bypass enforcement:
  --no-verify    Skips pre-commit hooks
  chflags nouchg Removes user immutable flag (unlocks protected files)
  chflags noschg Removes system immutable flag (unlocks protected files)
"""

import json
import re
import sys

BYPASS_PATTERNS = [
    (re.compile(r"--no-verify"), "BLOCKED: --no-verify skips pre-commit hooks. Enforcement files require human approval."),
    (re.compile(r"chflags\s+(?:\S+\s+)?no[us]chg"), "BLOCKED: Removing file locks requires human approval."),
    (re.compile(r"git\s+stash(?!\s+(list|show)\b)"), "BLOCKED: git stash risks data loss if pop fails. Commit to a temp branch instead."),
    (re.compile(r"git\s+reset\b.*--hard"), "BLOCKED: git reset --hard destroys uncommitted changes. Commit to a branch first."),
    (re.compile(r"git\s+clean\b.*(--force|-[a-zA-Z]*f)"), "BLOCKED: git clean -f deletes untracked files irreversibly."),
    (re.compile(r"git\s+checkout\s+(--\s+)?\.(\s|$)"), "BLOCKED: Blanket working tree discard. Target specific files instead."),
    (re.compile(r"git\s+restore\b.*\s\.(\s|$)"), "BLOCKED: Blanket restore. Target specific files instead."),
    (re.compile(r"git\s+push\b.*(--force(?!-with-lease)|-f\b)"), "BLOCKED: Force push can destroy remote history. Requires human approval."),
    (re.compile(r"git\s+branch\b.*\s-D\b"), "BLOCKED: Force-deletes branch with potentially unmerged work. Use -d instead."),
    (re.compile(r"git\s+checkout\b.*(--force|-f\b)"), "BLOCKED: Force checkout discards local modifications. Commit to a branch first."),
]


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    command = hook_input.get("tool_input", {}).get("command", "")
    if not command:
        sys.exit(0)

    for pattern, reason in BYPASS_PATTERNS:
        if pattern.search(command):
            json.dump({
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                }
            }, sys.stdout)
            sys.exit(0)


if __name__ == "__main__":
    main()
