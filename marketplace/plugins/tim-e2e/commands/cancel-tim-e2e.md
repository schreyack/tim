---
description: "Clean up E2E test artifacts and close browser sessions"
allowed-tools: ["Bash(npx:*)", "Bash(rm:*)", "Bash(find:*)"]
hide-from-slash-command-tool: "true"
---

# Cancel E2E

Clean up any Playwright browser sessions and temporary artifacts:

1. If a Playwright MCP browser session is active, close it using the `browser_close` MCP tool.

2. Remove any incomplete or temporary test artifacts:

```bash
echo "E2E session cleaned up"
```

Do NOT remove generated test files in `tests/e2e/` — those are the deliverable and should be kept for the user.

Report what was cleaned up.
