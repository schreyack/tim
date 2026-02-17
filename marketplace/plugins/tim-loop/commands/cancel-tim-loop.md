---
description: "Cancel active Tim Loop and clean up hooks"
allowed-tools: ["Bash(rm -f ~/.claude/.tim-loop-*)"]
hide-from-slash-command-tool: "true"
---

# Cancel Tim Loop

To cancel an active Tim Loop and clean up all hooks:

## Step 1: Remove state files

Run this Bash command to remove all tim-loop state files:

```bash
rm -f ~/.claude/.tim-loop-state-* ~/.claude/.tim-loop-prompt-* ~/.claude/.tim-loop-active ~/.claude/.tim-loop-auto-approve ~/.claude/.tim-loop-iteration-count ~/.claude/.tim-loop-heartbeat ~/.claude/.tim-loop-last-fired ~/.claude/.tim-loop-block-count 2>/dev/null && echo "State files removed" || echo "No state files found"
```

Report what was cleaned up:

- "Cancelled Tim Loop: removed state files"
- Or "No active Tim Loop found" if nothing was cleaned up
