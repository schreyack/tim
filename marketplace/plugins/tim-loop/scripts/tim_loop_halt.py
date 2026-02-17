#!/usr/bin/env python3
"""
TIM Loop System Halt - Central mechanism for forcing Claude to stop.

All hooks must use system_halt() instead of building their own responses.

The Problem:
- {"decision": "block", ...} for Stop hooks means "don't stop, keep working"
- Claude receives the message and continues anyway

The Solution:
- Use {"continue": false, "stopReason": "..."}
- Per Claude Code docs: "If false, Claude stops processing entirely"
- "Takes precedence over any event-specific decision fields"
"""

import json
import sys
from pathlib import Path


def get_plugin_version() -> str:
    """Get the plugin version from plugin.json."""
    plugin_json = Path(__file__).parent.parent / ".claude-plugin" / "plugin.json"
    try:
        with open(plugin_json, "r", encoding="utf-8") as f:
            return json.load(f).get("version", "unknown")
    except Exception:
        return "unknown"


def _build_header(category: str, is_escalation: bool, escalation_count: int) -> str:
    """Build the header section of the halt message."""
    if is_escalation:
        return (
            f"🛑🛑🛑 FULL SYSTEM HALT - {escalation_count} CONSECUTIVE VIOLATIONS 🛑🛑🛑\n\n"
            f"CATEGORY: {category}\n\n"
            f"This hook has fired {escalation_count} times. You ignored it every time.\n\n"
        )
    version = get_plugin_version()
    return f"🛑 FULL SYSTEM HALT 🛑\n\nCATEGORY: {category} (v{version})\n\n"


def _build_recovery_section(recovery_instructions: str) -> str:
    """Build the recovery instructions section."""
    if recovery_instructions:
        return f"RECOVERY PATH:\n{recovery_instructions}\n\n"
    return "RECOVERY PATH:\nThe human must intervene. This session cannot continue.\n\n"


def system_halt(
    category: str,
    details: str,
    *,
    recovery_instructions: str = "",
    is_escalation: bool = False,
    escalation_count: int = 0,
) -> None:
    """
    Issue a FULL SYSTEM HALT that Claude cannot ignore.

    Uses {"continue": false} which forces Claude to stop processing entirely.
    This function NEVER returns - it always exits the process.
    """
    header = _build_header(category, is_escalation, escalation_count)
    recovery = _build_recovery_section(recovery_instructions)

    stop_reason = (
        f"{header}"
        f"DETAILS:\n{details}\n\n"
        f"{recovery}"
        f"---\n"
        f"The human placed this hook here for a reason. This session is now stopped."
    )

    # Persist halt so it survives turn boundaries
    from tim_loop_state import load_state, save_state

    state = load_state()
    if state:
        state["HALTED"] = "true"
        save_state(state)

    # THE KEY: "continue": false forces full stop per Claude Code docs
    print(json.dumps({"continue": False, "stopReason": stop_reason}))
    sys.exit(0)


def system_warning(
    category: str,
    details: str,
    *,
    recovery_instructions: str = "",
) -> None:
    """
    Issue a warning that Claude sees but can continue from.

    Unlike system_halt(), this does NOT stop Claude. It provides feedback
    about violations and tells Claude to fix them before moving on.
    Used for fixable issues like code quality violations where stopping
    is counterproductive — Claude should just fix the problem.
    """
    version = get_plugin_version()
    header = f"⚠️ CODE QUALITY WARNING (v{version})\n\n"
    recovery = ""
    if recovery_instructions:
        recovery = f"ACTION REQUIRED:\n{recovery_instructions}\n\n"

    message = (
        f"{header}"
        f"DETAILS:\n{details}\n\n"
        f"{recovery}"
        f"Fix these issues now before continuing with your current task."
    )

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": message,
        }
    }))
    sys.exit(0)


def build_halt_details_from_patterns(
    patterns: list[tuple],
    intro: str = "The following patterns were detected:",
) -> str:
    """Build details string from a list of detected patterns."""
    if not patterns:
        return intro + "\n(No specific patterns provided)"

    lines = []
    for pattern, context in patterns:
        desc = getattr(pattern, "description", str(pattern))
        lines.append(f"  - Pattern: {desc}\n    Context: \"{context}\"")
    return f"{intro}\n\n" + "\n".join(lines)


def build_halt_details_from_violations(
    violations: list,
    intro: str = "The following violations were detected:",
) -> str:
    """Build details string from a list of code quality violations."""
    if not violations:
        return intro + "\n(No specific violations provided)"
    return f"{intro}\n\n" + "\n".join(f"  - {v.message}" for v in violations)
