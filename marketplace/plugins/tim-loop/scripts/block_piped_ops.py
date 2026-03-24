#!/usr/bin/env python3
"""
Block Piped Ops Commands - PreToolUse hook for Bash commands.

Blocks AI agents from piping ops.sh commands to other programs.
Piping buffers real-time streaming output and causes sessions to hang.
ops.sh commands (direct or via project alias) must run without output pipes.
"""

import json
import os
import re
import sys

# Regex to strip single-quoted and double-quoted strings before pipe detection
QUOTED_RE = re.compile(r"'[^']*'|\"[^\"]*\"")

# Command-position separator: start of string, or after ; && || |
SEG = r"(?:^|;\s*|&&\s*|\|\|\s*|\|\s*)"

# Commands that commonly use --env but are NOT ops.sh aliases
NON_OPS_COMMANDS = frozenset({
    "env", "export", "set", "echo", "cat", "grep",
    "python", "python3", "node", "npm", "npx", "pip", "uv",
    "docker", "kubectl", "helm", "terraform",
    "git", "ssh", "scp", "rsync", "curl", "wget",
    "make", "cargo", "go", "ruby", "java",
    "bash", "sh", "zsh", "aws", "gcloud", "az",
})

DENY_REASON = (
    "BLOCKED: Piping ops.sh output to another command causes output buffering "
    "that hangs the session. Run the ops.sh command without pipes.\n\n"
    "Instead of:  {cmd_name} --env <env> <cmd> | ...\n"
    "Use:         {cmd_name} --env <env> <cmd>\n\n"
    "If you need to filter output, run the command first (with run_in_background "
    "if long-running), then search the output separately."
)


def _extract_project_name(config_path: str) -> str | None:
    """Parse project.name from an ops-config.yaml file."""
    try:
        with open(config_path, encoding="utf-8") as f:
            in_project = False
            for line in f:
                if re.match(r"^project\s*:", line):
                    in_project = True
                    continue
                if not in_project:
                    continue
                if line and not line[0].isspace():
                    break
                m = re.match(
                    r'\s+name:\s*["\']?([a-z][a-z0-9_-]*)["\']?',
                    line,
                )
                if m:
                    return m.group(1)
    except OSError:
        pass
    return None


def find_ops_alias() -> str | None:
    """Walk up from CWD to find ops-config.yaml and extract project.name."""
    path = os.getcwd()
    for _ in range(20):
        config = os.path.join(path, "ops-config.yaml")
        if os.path.isfile(config):
            return _extract_project_name(config)
        parent = os.path.dirname(path)
        if parent == path:
            break
        path = parent
    return None


def strip_quotes(cmd: str) -> str:
    """Remove quoted strings to avoid matching | inside quotes."""
    return QUOTED_RE.sub("", cmd)


def has_pipe_in_simple_command(remainder: str) -> bool:
    """Check for a pipe within the current simple command (before && || ;)."""
    stripped = strip_quotes(remainder)
    # Find the boundary of the current simple command
    boundary = re.search(r"(&&|\|\||;)", stripped)
    if boundary:
        stripped = stripped[: boundary.start()]
    # Safety: replace any remaining || (shouldn't exist after boundary cut)
    cleaned = re.sub(r"\|\|", "  ", stripped)
    return "|" in cleaned


def find_ops_invocation(command: str, alias_name: str | None) -> int | None:
    """Find the end position of an ops.sh invocation. Returns None if not found."""
    names: list[str] = [r"(?:\S+/)?ops\.sh"]
    if alias_name:
        names.append(re.escape(alias_name))

    for name_pattern in names:
        pattern = re.compile(SEG + r"\s*(" + name_pattern + r")\b")
        match = pattern.search(command)
        if match:
            after = command[match.start() :]
            if re.search(r"--env\s+\S+", after):
                return match.end()

    # Fallback: --env heuristic for unknown aliases
    env_pattern = re.compile(SEG + r"\s*([a-z][a-z0-9_-]*)\s+--env\s+\S+")
    match = env_pattern.search(command)
    if match:
        candidate = match.group(match.lastindex)
        if candidate not in NON_OPS_COMMANDS:
            return match.end()

    return None


def main() -> None:
    try:
        hook_input = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    command = hook_input.get("tool_input", {}).get("command", "")
    if not command or "|" not in command:
        sys.exit(0)

    alias_name = find_ops_alias()
    ops_end = find_ops_invocation(command, alias_name)

    if ops_end is not None and has_pipe_in_simple_command(command[ops_end:]):
        cmd_name = alias_name or "ops.sh"
        json.dump(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": DENY_REASON.format(
                        cmd_name=cmd_name,
                    ),
                }
            },
            sys.stdout,
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
