# setup-hooks.sh - Process and cleanup hooks for tim-loop-setup
# Sourced by tim-loop-setup.sh - no shebang or set options

# Find the Claude parent process (walk up from PPID to find 'claude')
find_claude_pid() {
    local pid=$PPID
    while [ "$pid" != "1" ] && [ -n "$pid" ]; do
        local comm
        comm=$(ps -p "$pid" -o comm= 2>/dev/null) || break
        if [[ "$comm" == "claude" ]]; then
            echo "$pid"
            return
        fi
        pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ') || break
    done
    echo "$$"  # Fallback to self if Claude not found
}

# Cleanup on error/interrupt
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        rm -f "$TIM_LOOP_STATE_FILE" "$TIM_LOOP_PROMPT_FILE" "$HOME/.claude/.tim-loop-active" "$HOME/.claude/.tim-loop-auto-approve"
        python3 -c "
import json, os
try:
    with open(os.path.expanduser('~/.claude/settings.local.json'), 'r') as f:
        settings = json.load(f)
    if 'hooks' in settings:
        for ht in ['stop', 'PreToolUse', 'SessionStart', 'UserPromptSubmit']:
            if ht in settings['hooks']:
                settings['hooks'][ht] = [h for h in settings['hooks'][ht] if 'tim-loop' not in h.get('command', '')]
                if not settings['hooks'][ht]: del settings['hooks'][ht]
        if not settings['hooks']: del settings['hooks']
    with open(os.path.expanduser('~/.claude/settings.local.json'), 'w') as f:
        json.dump(settings, f, indent=2)
except: pass
" 2>/dev/null || true
    fi
}
