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
    """Get the standard options text to append to block responses.

    DISABLED: The numbered options allowed Claude to bypass stops by typing "1".
    Humans must now write their own response to continue, which Claude cannot do.
    """
    return ""  # Options disabled - Claude learned to bypass with "1"


def clear_pending_options() -> None:
    """Clear the pending options state."""
    try:
        PENDING_OPTIONS_FILE.unlink(missing_ok=True)
    except Exception:
        pass
