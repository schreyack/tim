#!/bin/bash
# Tim Loop Session Management
# Handles session detection, validation, and cleanup decisions
# Sourced by tim-loop-setup.sh

# Check if an existing session should be cleaned up
should_cleanup_existing_session() {
    local old_state="$1"
    local current_project="$2"

    # Source the state file to get metadata
    local old_project=""
    local old_plan_file=""
    local created_at=""

    if [[ -f "$old_state" ]]; then
        # shellcheck disable=SC1090
        source "$old_state"
        old_project="${PROJECT_PATH:-}"
        old_plan_file="${PLAN_FILE:-}"
        created_at="${CREATED_AT:-}"
    fi

    # Case 1: Old session's plan file no longer exists
    if [[ -n "$old_plan_file" ]] && [[ ! -f "$old_plan_file" ]]; then
        echo "  Reason: Plan file no longer exists" >&2
        return 0
    fi

    # Case 2: Old session's plan file shows VERIFIED: YES (session completed successfully)
    # This catches cases where the stop hook's cleanup failed but the session actually finished
    if [[ -n "$old_plan_file" ]] && [[ -f "$old_plan_file" ]]; then
        if grep -q "<!-- VERIFIED: YES -->" "$old_plan_file"; then
            echo "  Reason: Previous session completed (plan shows VERIFIED: YES)" >&2
            return 0
        fi
    fi

    # Case 3: Different project
    if [[ -n "$old_project" ]] && [[ "$old_project" != "$current_project" ]]; then
        echo "  Reason: Different project (was: $old_project)" >&2
        return 0
    fi

    # Case 4: No recent heartbeat (session interrupted by /clear or terminal close)
    # If no tool has been used in 5+ minutes, session is likely dead
    # This threshold balances detecting stale sessions vs. not killing sessions
    # where Claude is doing extended thinking or waiting for user input
    local heartbeat_file="$HOME/.claude/.tim-loop-heartbeat"
    local heartbeat_threshold_seconds="${TIM_LOOP_HEARTBEAT_THRESHOLD_SECONDS:-300}"  # 5 minutes default
    if [[ -f "$heartbeat_file" ]]; then
        local heartbeat_epoch now_epoch age_seconds
        heartbeat_epoch=$(cat "$heartbeat_file" 2>/dev/null || echo "0")
        now_epoch=$(date "+%s")
        age_seconds=$((now_epoch - heartbeat_epoch))

        if [[ "$age_seconds" -gt "$heartbeat_threshold_seconds" ]]; then
            local age_minutes=$((age_seconds / 60))
            echo "  Reason: No activity for $age_minutes minutes (interrupted session)" >&2
            return 0
        fi
    else
        # No heartbeat file means either:
        # 1. Session predates heartbeat support (legacy)
        # 2. Heartbeat was just deleted by setup.sh to detect /clear race condition
        #
        # In case 2, a truly active parallel session would have ALREADY recreated
        # the heartbeat via its PreToolUse hook (which fires on every tool use).
        # So if there's no heartbeat, the session is almost certainly dead.
        #
        # Be aggressive: clean up if state file is >30 seconds old (not 5 minutes).
        # This handles the /clear case while still protecting genuinely concurrent sessions.
        if [[ -f "$old_state" ]]; then
            local now_epoch file_mtime_epoch age_seconds
            now_epoch=$(date "+%s")
            # Get state file modification time
            if stat -f "%m" "$old_state" &>/dev/null; then
                file_mtime_epoch=$(stat -f "%m" "$old_state")
            elif stat -c "%Y" "$old_state" &>/dev/null; then
                file_mtime_epoch=$(stat -c "%Y" "$old_state")
            else
                file_mtime_epoch=0
            fi
            age_seconds=$((now_epoch - file_mtime_epoch))

            # No heartbeat + state file older than 30 seconds = dead session
            # (Active sessions update heartbeat constantly via PreToolUse)
            if [[ "$age_seconds" -gt 30 ]]; then
                local age_display
                if [[ "$age_seconds" -gt 60 ]]; then
                    age_display="$((age_seconds / 60)) minutes"
                else
                    age_display="${age_seconds} seconds"
                fi
                echo "  Reason: No heartbeat and state file is ${age_display} old (stale session)" >&2
                return 0
            fi
        fi
    fi

    # Case 5: Session is stale (> 4 hours old)
    if [[ -n "$created_at" ]]; then
        local created_epoch now_epoch age_hours
        # Handle both macOS and Linux date commands
        if date -j -f "%Y-%m-%dT%H:%M:%S" "${created_at%Z}" "+%s" &>/dev/null; then
            created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${created_at%Z}" "+%s")
        elif date -d "${created_at}" "+%s" &>/dev/null; then
            created_epoch=$(date -d "${created_at}" "+%s")
        else
            created_epoch=0
        fi
        now_epoch=$(date "+%s")
        age_hours=$(( (now_epoch - created_epoch) / 3600 ))

        if [[ "$age_hours" -gt 4 ]]; then
            echo "  Reason: Session is $age_hours hours old (stale)" >&2
            return 0
        fi
    fi

    # Should NOT cleanup - might be a legitimate parallel session
    return 1
}

# Detect and handle existing active session
handle_existing_session() {
    local force_flag="$1"
    local current_project="$2"

    if [[ ! -f ~/.claude/.tim-loop-active ]]; then
        return 0  # No existing session
    fi

    local old_state
    old_state=$(cat ~/.claude/.tim-loop-active 2>/dev/null)

    if [[ -z "$old_state" ]] || [[ ! -f "$old_state" ]]; then
        # Stale pointer, just clean it up
        rm -f ~/.claude/.tim-loop-active
        return 0
    fi

    echo "Warning: Active tim-loop session detected" >&2

    if [[ "$force_flag" == true ]]; then
        echo "  --force specified, cleaning up existing session" >&2
        cleanup_session "$old_state"
        return 0
    fi

    if should_cleanup_existing_session "$old_state" "$current_project"; then
        cleanup_session "$old_state"
        return 0
    fi

    # Session is recent and in same project - block unless --force
    echo "" >&2
    echo "An active tim-loop session exists in this project." >&2
    echo "Use --force to override, or complete the existing session first." >&2
    echo "" >&2
    exit 1
}
