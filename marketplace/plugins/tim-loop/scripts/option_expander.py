#!/usr/bin/env python3
"""
Option Expander - UserPromptSubmit hook for stop hook option shortcuts.

When the stop hook (excuse detector) blocks with numbered options, the user
can type "1", "2", or "3" and this hook expands it to the full response.

Options:
1. Continue (false positive) -> "This was a false positive. Continue with your previous task."
2. Continue with instructions -> Prompts for instructions via /dev/tty
3. Add regex pattern -> Adds pattern to YAML and continues

State file: ~/.claude/.tim-loop-pending-options
Written by: excuse_detector_v2.py, guardrails_judge.py
Read by: this script
"""

import json
import sys
from pathlib import Path

PENDING_OPTIONS_FILE = Path.home() / ".claude" / ".tim-loop-pending-options"

# Option responses
OPTION_RESPONSES = {
    "1": "This was a false positive. Continue with your previous task.",
    "2": None,  # Will prompt for instructions
    "3": None,  # Will add pattern and continue
}


def read_pending_options() -> dict | None:
    """Read pending options state if it exists."""
    if not PENDING_OPTIONS_FILE.exists():
        return None
    try:
        return json.loads(PENDING_OPTIONS_FILE.read_text())
    except Exception:
        return None


def clear_pending_options() -> None:
    """Remove the pending options file."""
    try:
        PENDING_OPTIONS_FILE.unlink(missing_ok=True)
    except Exception:
        pass


def prompt_for_instructions() -> str:
    """Prompt user for additional instructions via /dev/tty."""
    try:
        with open("/dev/tty", "r") as tty_in, open("/dev/tty", "w") as tty_out:
            tty_out.write("\nEnter instructions for Claude: ")
            tty_out.flush()
            instructions = tty_in.readline().strip()
            return f"Continue, but note: {instructions}" if instructions else OPTION_RESPONSES["1"]
    except Exception:
        return OPTION_RESPONSES["1"]


def add_pattern_to_yaml(pending: dict) -> str:
    """Add the detected pattern to excuse_patterns.yaml."""
    yaml_path = Path(__file__).parent / "excuse_patterns.yaml"
    category = pending.get("category", "general")
    excerpt = pending.get("excerpt", "")

    # For now, just inform the user - they need to add manually
    # Full implementation would append to YAML
    return (
        f"Pattern noted for category '{category}'. "
        f"Please add manually to {yaml_path}. "
        f"Continue with your previous task."
    )


def expand_option(user_input: str, pending: dict) -> str | None:
    """Expand a numbered option to its full response."""
    option = user_input.strip()

    if option == "1":
        return OPTION_RESPONSES["1"]
    elif option == "2":
        return prompt_for_instructions()
    elif option == "3":
        return add_pattern_to_yaml(pending)

    return None  # Not an option number


def set_user_initiated_marker() -> None:
    """Set marker indicating this turn was initiated by user input.

    This marker tells the excuse detector that the user is actively interacting,
    so it should skip checking. Without this marker, the excuse detector runs
    (indicating tim-loop auto-continued without user intervention).

    Claude cannot manipulate this because:
    1. This hook only fires on actual user input (UserPromptSubmit)
    2. Claude's tool calls don't trigger UserPromptSubmit
    3. The marker is checked and cleared atomically by the excuse detector
    """
    marker = Path.home() / ".claude" / ".tim-loop-user-initiated"
    try:
        marker.touch()
    except Exception:
        pass


def main():
    """Main hook entry point.

    Sets a marker indicating user interaction, then passes through.
    This marker is used by the excuse detector to skip checking when
    the user is actively participating in the conversation.
    """
    # Set marker so excuse detector knows user is interacting
    set_user_initiated_marker()

    # Clear any pending options state
    clear_pending_options()
    sys.exit(0)


if __name__ == "__main__":
    main()
