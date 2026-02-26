---
description: "Clean up generated PBT test files"
allowed-tools: ["Bash(find:*)", "Bash(rm:*)"]
hide-from-slash-command-tool: "true"
---

# Cancel PBT

Clean up any generated property-based test files:

```bash
find . -name "pbt_test_*" -not -path "./.venv/*" -not -path "./node_modules/*" -delete 2>/dev/null && echo "PBT test files removed" || echo "No PBT test files found"
```

Report what was cleaned up.
