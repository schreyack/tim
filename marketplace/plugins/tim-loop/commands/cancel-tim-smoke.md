---
description: "Cancel active smoke test and clean up state"
allowed-tools: ["Bash(rm -f .tim-smoke-state.json)"]
hide-from-slash-command-tool: "true"
---

# Cancel Smoke Test

To cancel an active smoke test and clean up:

## Step 1: Remove state file

Run this Bash command to remove the smoke test state file:

```bash
rm -f .tim-smoke-state.json 2>/dev/null && echo "Smoke test state removed" || echo "No active smoke test found"
```

Report what was cleaned up:

- "Cancelled smoke test: removed state file"
- Or "No active smoke test found" if nothing was cleaned up
