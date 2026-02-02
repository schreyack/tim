#!/bin/bash
# Tim Loop Cleanup Functions
# Handles cleanup of orphan files, hooks, and session artifacts
# Sourced by tim-loop-setup.sh

# Cleanup: Configurable orphan age threshold (default 24 hours)
TIM_LOOP_ORPHAN_AGE_HOURS="${TIM_LOOP_ORPHAN_AGE_HOURS:-24}"

# Cleanup function: Remove expired approval requests
cleanup_expired_approval_requests() {
    local requests_dir=".tim-execution-requests"
    [ -d "$requests_dir" ] || return 0

    python3 << PYTHON_EOF
import json, os
from datetime import datetime, timezone

requests_dir = "$requests_dir"
for f in os.listdir(requests_dir):
    if not f.endswith('.json'): continue
    filepath = os.path.join(requests_dir, f)
    try:
        with open(filepath) as fp:
            data = json.load(fp)
        expires = data.get('expires_at', '').replace('Z', '+00:00')
        if expires and datetime.now(timezone.utc) > datetime.fromisoformat(expires):
            os.remove(filepath)
    except: pass
PYTHON_EOF
}

# Cleanup function: Remove orphan hooks when no active sessions
cleanup_orphan_hooks() {
    local recent_state_files
    recent_state_files=$(find ~/.claude -maxdepth 1 -name ".tim-loop-state-*" -mmin -60 2>/dev/null | wc -l)
    [ "$recent_state_files" -gt 0 ] && return 0
    [ -f ~/.claude/settings.local.json ] || return 0

    python3 << 'PYTHON_EOF'
import json, os, sys
settings_file = os.path.expanduser("~/.claude/settings.local.json")
try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    sys.exit(0)

modified = False
if 'hooks' in settings:
    for hook_type in ['stop', 'PreToolUse', 'SessionStart']:
        if hook_type in settings['hooks']:
            original = len(settings['hooks'][hook_type])
            settings['hooks'][hook_type] = [h for h in settings['hooks'][hook_type] if 'tim-loop' not in h.get('command', '')]
            if len(settings['hooks'][hook_type]) != original:
                modified = True
            if not settings['hooks'][hook_type]:
                del settings['hooks'][hook_type]
    if not settings['hooks']:
        del settings['hooks']
        modified = True
if modified:
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)
PYTHON_EOF
}

# Cleanup function: Remove orphan state files older than threshold
cleanup_orphan_state_files() {
    local age_minutes=$((TIM_LOOP_ORPHAN_AGE_HOURS * 60))
    find ~/.claude -maxdepth 1 -name ".tim-loop-state-*" -mmin +"$age_minutes" -delete 2>/dev/null || true
    find ~/.claude -maxdepth 1 -name ".tim-loop-prompt-*" -mmin +"$age_minutes" -delete 2>/dev/null || true

    if [ -f ~/.claude/.tim-loop-active ]; then
        local active_state
        active_state=$(cat ~/.claude/.tim-loop-active 2>/dev/null)
        [ -n "$active_state" ] && [ ! -f "$active_state" ] && rm -f ~/.claude/.tim-loop-active
    fi

    if [ -f ~/.claude/.tim-loop-auto-approve ]; then
        local session_id
        session_id=$(cat ~/.claude/.tim-loop-auto-approve 2>/dev/null)
        [ -n "$session_id" ] && [ ! -f ~/.claude/.tim-loop-state-"$session_id" ] && rm -f ~/.claude/.tim-loop-auto-approve
    fi

    # Remove orphan heartbeat file if no active session
    if [ -f ~/.claude/.tim-loop-heartbeat ] && [ ! -f ~/.claude/.tim-loop-active ]; then
        rm -f ~/.claude/.tim-loop-heartbeat
    fi

    cleanup_expired_approval_requests
    cleanup_orphan_hooks
}

# Cleanup function: Remove all tim-loop artifacts
cleanup_all() {
    local force="${1:-}"
    if [ "$force" = "--force" ]; then
        rm -f ~/.claude/.tim-loop-state-* ~/.claude/.tim-loop-prompt-* ~/.claude/.tim-loop-active ~/.claude/.tim-loop-auto-approve ~/.claude/.tim-loop-heartbeat 2>/dev/null || true
        [ -d ".tim-execution-requests" ] && rm -f .tim-execution-requests/*.json 2>/dev/null || true
        cleanup_orphan_hooks
        echo "All tim-loop state files and hooks cleaned up" >&2
    else
        cleanup_orphan_state_files
        echo "Orphan tim-loop state files cleaned up" >&2
    fi
}

# Cleanup function: Remove a specific session's files
cleanup_session() {
    local state_file="$1"
    local session_id
    session_id=$(basename "$state_file" | sed 's/\.tim-loop-state-//')

    echo "Cleaning up orphaned session $session_id" >&2

    # Remove session files
    rm -f "$state_file"
    rm -f "${state_file/state/prompt}"
    rm -f ~/.claude/.tim-loop-active
    rm -f ~/.claude/.tim-loop-iteration-count
    rm -f ~/.claude/.tim-loop-heartbeat

    cleanup_orphan_hooks
}
