#!/bin/bash
# Tim Loop Permission Hook
# Auto-approves all tool uses when tim-loop --auto-approve is active

set -euo pipefail

TIM_LOOP_AUTO_APPROVE_MARKER="$HOME/.claude/.tim-loop-auto-approve"

# If auto-approve marker exists, approve the tool use
if [[ -f "$TIM_LOOP_AUTO_APPROVE_MARKER" ]]; then
    echo '{"decision": "approve"}'
    exit 0
fi

# Otherwise, don't interfere
exit 0
