#!/usr/bin/env python3
"""
Tim Loop State Management - Handles state files and cleanup operations.

This module contains functions for loading, saving, and cleaning up
tim-loop session state.
"""

import json
import os
import sys
from datetime import datetime
from pathlib import Path

# Configuration
TIM_LOOP_ACTIVE_MARKER = Path.home() / ".claude" / ".tim-loop-active"
CLEANUP_LOG = Path.home() / ".claude" / ".tim-loop-cleanup.log"


def log_message(message: str) -> None:
    """Log a message to the cleanup log file."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        with open(CLEANUP_LOG, "a") as f:
            f.write(f"{timestamp} - {message}\n")
    except Exception:
        pass


def log_stderr(message: str) -> None:
    """Log a message to stderr (visible in Claude Code logs)."""
    print(message, file=sys.stderr)


def cleanup_state_files(state_file: str, prompt_file: str) -> None:
    """Remove tim-loop state files."""
    files_to_remove = [
        state_file,
        prompt_file,
        str(TIM_LOOP_ACTIVE_MARKER),
        str(Path.home() / ".claude" / ".tim-loop-iteration-count"),
        str(Path.home() / ".claude" / ".tim-loop-auto-approve"),
        str(Path.home() / ".claude" / ".tim-loop-heartbeat"),
    ]
    for file_path in files_to_remove:
        if file_path and os.path.isfile(file_path):
            try:
                os.remove(file_path)
                log_message(f"Removed: {file_path}")
            except Exception as e:
                log_message(f"FAILED to remove {file_path}: {e}")


def cleanup_hooks_from_settings() -> None:
    """Remove tim-loop hooks from settings.local.json."""
    try:
        settings_file = Path.home() / ".claude" / "settings.local.json"
        if not settings_file.exists():
            return
        with open(settings_file, "r") as f:
            settings = json.load(f)
        if "hooks" not in settings:
            return
        for hook_type in ["stop", "PreToolUse", "SessionStart"]:
            if hook_type in settings["hooks"]:
                settings["hooks"][hook_type] = [
                    h
                    for h in settings["hooks"][hook_type]
                    if "tim-loop" not in h.get("command", "")
                ]
                if not settings["hooks"][hook_type]:
                    del settings["hooks"][hook_type]
        if not settings["hooks"]:
            del settings["hooks"]
        with open(settings_file, "w") as f:
            json.dump(settings, f, indent=2)
        log_message("Hooks cleaned from settings.local.json")
    except Exception as e:
        log_message(f"Hook cleanup error: {e}")


def cleanup_tim_loop(message: str, state_file: str, prompt_file: str) -> None:
    """Clean up all tim-loop state and hooks."""
    log_stderr(message)
    log_message(f"Cleanup started: {message}")
    cleanup_state_files(state_file, prompt_file)
    cleanup_hooks_from_settings()
    log_message("Cleanup completed")


def load_state() -> dict | None:
    """Load tim-loop state from the active marker and state file."""
    if not TIM_LOOP_ACTIVE_MARKER.exists():
        return None
    try:
        state_file = TIM_LOOP_ACTIVE_MARKER.read_text().strip()
        if not state_file or not os.path.isfile(state_file):
            return None
        state = {"_state_file": state_file}
        with open(state_file, "r") as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    key, _, value = line.partition("=")
                    state[key] = value.strip().strip('"').strip("'")
        return state
    except Exception:
        return None


def save_state(state: dict) -> None:
    """Save tim-loop state back to the state file."""
    state_file = state.get("_state_file")
    if not state_file:
        return
    try:
        with open(state_file, "w") as f:
            for key, value in state.items():
                if not key.startswith("_"):
                    f.write(f'{key}="{value}"\n')
    except Exception as e:
        log_message(f"Failed to save state: {e}")
