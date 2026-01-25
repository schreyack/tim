---
description: "Cancel active Tim Loop and clean up hooks"
allowed-tools: ["Bash(rm -f ~/.claude/.tim-loop-*)", "Bash(cat ~/.claude/settings.local.json)", "Write(~/.claude/settings.local.json)"]
hide-from-slash-command-tool: "true"
---

# Cancel Tim Loop

To cancel an active Tim Loop and clean up all hooks:

## Step 1: Remove state files

Run this Bash command to remove all tim-loop state files:

```bash
rm -f ~/.claude/.tim-loop-state-* ~/.claude/.tim-loop-prompt-* ~/.claude/.tim-loop-active ~/.claude/.tim-loop-auto-approve ~/.claude/.tim-loop-iteration-count 2>/dev/null && echo "State files removed" || echo "No state files found"
```

## Step 2: Remove hooks from settings

1. Read `~/.claude/settings.local.json` using Bash: `cat ~/.claude/settings.local.json`

2. If the file exists and contains tim-loop hooks, use the Write tool to write a new version with the tim-loop hooks removed:
   - Remove any hook objects where `command` contains "tim-loop"
   - Remove the `stop`, `PreToolUse`, or `PreCompact` arrays if they become empty
   - Remove the `hooks` object entirely if it becomes empty
   - Preserve all other settings

3. Report what was cleaned up:
   - "Cancelled Tim Loop: removed N state files and M hooks"
   - Or "No active Tim Loop found" if nothing was cleaned up
