#!/bin/bash
# Tim Loop Hook - Implements iteration for Tim Loop workflow
# This hook is registered as a "stop" hook and intercepts conversation exit

set -euo pipefail

# Configuration
TIM_LOOP_ACTIVE_MARKER="$HOME/.claude/.tim-loop-active"

if [[ ! -f "$TIM_LOOP_ACTIVE_MARKER" ]]; then
    exit 0
fi

TIM_LOOP_STATE_FILE=$(cat "$TIM_LOOP_ACTIVE_MARKER")

if [[ ! -f "$TIM_LOOP_STATE_FILE" ]]; then
    exit 0
fi

source "$TIM_LOOP_STATE_FILE"

if [[ -z "${TIM_LOOP_PROMPT_FILE:-}" ]]; then
    exit 0
fi

# Helper function to clean up all tim-loop state and hooks
cleanup_tim_loop() {
    local message="${1:-Tim Loop: Session ended}"
    echo "$message" >&2
    rm -f "$TIM_LOOP_STATE_FILE" "$TIM_LOOP_PROMPT_FILE" "$TIM_LOOP_ACTIVE_MARKER"
    rm -f "$HOME/.claude/.tim-loop-iteration-count" "$HOME/.claude/.tim-loop-auto-approve"
    python3 -c "
import json, os
try:
    with open(os.path.expanduser('~/.claude/settings.local.json'), 'r') as f:
        settings = json.load(f)
    if 'hooks' in settings:
        for ht in ['stop', 'PreToolUse', 'PreCompact']:
            if ht in settings['hooks']:
                settings['hooks'][ht] = [h for h in settings['hooks'][ht] if 'tim-loop' not in h.get('command', '')]
                if not settings['hooks'][ht]: del settings['hooks'][ht]
        if not settings['hooks']: del settings['hooks']
    with open(os.path.expanduser('~/.claude/settings.local.json'), 'w') as f:
        json.dump(settings, f, indent=2)
except: pass
" 2>/dev/null || true
}

# Check for completion promise
LAST_OUTPUT="${1:-}"
if [[ -z "$LAST_OUTPUT" ]] && [[ -p /dev/stdin ]]; then
    LAST_OUTPUT=$(cat)
fi

# Detect user termination (empty or minimal output = /clear or Ctrl+C)
# If output is less than 50 chars and doesn't contain substantive content, user terminated
OUTPUT_LENGTH=${#LAST_OUTPUT}
if [[ $OUTPUT_LENGTH -lt 50 ]]; then
    # Check if it's truly empty or just whitespace/minimal
    TRIMMED_OUTPUT=$(echo "$LAST_OUTPUT" | tr -d '[:space:]')
    if [[ ${#TRIMMED_OUTPUT} -lt 20 ]]; then
        cleanup_tim_loop "Tim Loop: Session terminated by user, cleaning up state"
        exit 0
    fi
fi

if echo "$LAST_OUTPUT" | grep -Fq "<promise>${COMPLETION_PROMISE}</promise>"; then
    # Check plan verification status
    PLAN_FILE=""
    if [[ -f "$TIM_LOOP_PROMPT_FILE" ]]; then
        PLAN_FILE=$(grep "Plan File:" "$TIM_LOOP_PROMPT_FILE" | sed 's/.*Plan File: //' | head -1)
        if [[ -z "$PLAN_FILE" ]]; then
            PLAN_FILE=$(grep "Check the plan file at:" "$TIM_LOOP_PROMPT_FILE" | sed 's/.*Check the plan file at: //' | head -1)
        fi
    fi

    if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
        # Check for verification failure
        if grep -q "<!-- VERIFIED: FAILED -->" "$PLAN_FILE"; then
            cleanup_tim_loop "Tim Loop: BLOCKED - Verification failed, remediation required"
            exit 1
        fi

        # Check for successful verification
        if ! grep -q "<!-- VERIFIED: YES -->" "$PLAN_FILE"; then
            echo "Tim Loop: BLOCKED - Plan not verified as 100% complete" >&2
            CURRENT_ITERATION=$((CURRENT_ITERATION + 1))
            cat > "$TIM_LOOP_STATE_FILE" << EOF
CURRENT_ITERATION=$CURRENT_ITERATION
MAX_ITERATIONS=$MAX_ITERATIONS
COMPLETION_PROMISE="$COMPLETION_PROMISE"
TIM_LOOP_PROMPT_FILE="$TIM_LOOP_PROMPT_FILE"
PROJECT_PATH="${PROJECT_PATH:-}"
PLAN_FILE="${PLAN_FILE:-}"
CREATED_AT="${CREATED_AT:-}"
SESSION_ID="${SESSION_ID:-}"
EOF
            echo "Tim Loop: Iteration $CURRENT_ITERATION of $MAX_ITERATIONS (verification required)" >&2
            if [[ -f "$TIM_LOOP_PROMPT_FILE" ]]; then
                cat "$TIM_LOOP_PROMPT_FILE"
            fi
            exit 0
        fi
    fi

    # Task complete
    cleanup_tim_loop "Tim Loop: Task complete"
    exit 0
fi

# Increment iteration
CURRENT_ITERATION=$((CURRENT_ITERATION + 1))

# Check max iterations
if [[ $CURRENT_ITERATION -ge $MAX_ITERATIONS ]]; then
    cleanup_tim_loop "Tim Loop: Max iterations ($MAX_ITERATIONS) reached"
    exit 0
fi

# Update state (preserving metadata)
cat > "$TIM_LOOP_STATE_FILE" << EOF
CURRENT_ITERATION=$CURRENT_ITERATION
MAX_ITERATIONS=$MAX_ITERATIONS
COMPLETION_PROMISE="$COMPLETION_PROMISE"
TIM_LOOP_PROMPT_FILE="$TIM_LOOP_PROMPT_FILE"
PROJECT_PATH="${PROJECT_PATH:-}"
PLAN_FILE="${PLAN_FILE:-}"
CREATED_AT="${CREATED_AT:-}"
SESSION_ID="${SESSION_ID:-}"
EOF

# Re-inject prompt
echo "Tim Loop: Iteration $CURRENT_ITERATION of $MAX_ITERATIONS" >&2
if [[ -f "$TIM_LOOP_PROMPT_FILE" ]]; then
    cat "$TIM_LOOP_PROMPT_FILE"
fi
