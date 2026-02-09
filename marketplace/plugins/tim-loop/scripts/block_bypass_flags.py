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
