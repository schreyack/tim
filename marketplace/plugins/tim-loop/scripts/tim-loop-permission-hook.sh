#!/bin/bash
# Tim Loop Permission Hook
# Auto-approves all tool uses when tim-loop --auto-approve is active
# Also maintains heartbeat for stale session detection

set -euo pipefail

TIM_LOOP_AUTO_APPROVE_MARKER="$HOME/.claude/.tim-loop-auto-approve"
TIM_LOOP_ACTIVE_MARKER="$HOME/.claude/.tim-loop-active"
TIM_LOOP_HEARTBEAT_FILE="$HOME/.claude/.tim-loop-heartbeat"

# Update heartbeat if there's an active tim-loop session
# This enables detection of sessions interrupted by /clear or terminal close
if [[ -f "$TIM_LOOP_ACTIVE_MARKER" ]]; then
    date "+%s" > "$TIM_LOOP_HEARTBEAT_FILE" 2>/dev/null || true
fi

# If auto-approve marker exists, approve the tool use
if [[ -f "$TIM_LOOP_AUTO_APPROVE_MARKER" ]]; then
    echo '{"decision": "approve"}'
    exit 0
fi

# Otherwise, don't interfere
exit 0
