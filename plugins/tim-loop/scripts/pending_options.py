#!/usr/bin/env python3
"""
Pending Options State Management.

Writes state when stop hooks block with options, allowing the UserPromptSubmit
hook (option_expander.py) to expand "1", "2", "3" to full responses.
"""

import json
from pathlib import Path

PENDING_OPTIONS_FILE = Path.home() / ".claude" / ".tim-loop-pending-options"


def write_pending_options(category: str, excerpt: str) -> None:
    """Write pending options state for the option expander."""
    state = {
        "category": category,
        "excerpt": excerpt,
    }
    try:
        PENDING_OPTIONS_FILE.write_text(json.dumps(state))
    except Exception:
        pass


def get_options_text() -> str:
    """Get the standard options text to append to block responses."""
    return (
        "\n---\n\n"
        "**Quick response options** (just type the number):\n\n"
        "1. **Continue** - This was a false positive\n"
        "2. **Instructions** - Add guidance for Claude\n"
        "3. **Add pattern** - Note for YAML (manual add)\n"
    )


def clear_pending_options() -> None:
    """Clear the pending options state."""
    try:
        PENDING_OPTIONS_FILE.unlink(missing_ok=True)
    except Exception:
        pass
