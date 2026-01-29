#!/usr/bin/env bash
# tim-loop-prompt-manager.sh - Manage tim-loop prompts for PreCompact reinjection
#
# This script handles saving, retrieving, and cleaning up tim-loop prompts
# to preserve prompt fidelity across context compaction.
#
# Usage:
#   tim-loop-prompt-manager.sh save <prompt-text>   # Save prompt for current session
#   tim-loop-prompt-manager.sh save-file <file>     # Save prompt from file
#   tim-loop-prompt-manager.sh get                  # Get prompt for current session
#   tim-loop-prompt-manager.sh clear                # Clear prompt for current session
#   tim-loop-prompt-manager.sh cleanup              # Remove stale prompts (>24h)
#   tim-loop-prompt-manager.sh hook                 # PreCompact hook mode (outputs JSON)

set -euo pipefail

# Configuration - match tim-loop-setup.sh paths
PROMPT_DIR="${TIM_PROMPT_DIR:-$HOME/.claude}"
STALE_MINUTES="${TIM_PROMPT_STALE_MINUTES:-1440}"  # 24 hours default

# Get session ID from multiple sources
# Priority: TIM_LOOP_SESSION_ID > tim-loop-active file > CLAUDE_CODE_SESSION
get_session_id() {
    local session_id="${TIM_LOOP_SESSION_ID:-}"

    # Try to read from active marker file if no env var
    if [[ -z "$session_id" && -f "$PROMPT_DIR/.tim-loop-active" ]]; then
        local active_state
        active_state=$(cat "$PROMPT_DIR/.tim-loop-active" 2>/dev/null || true)
        if [[ -f "$active_state" ]]; then
            # Extract session ID from state file path
            session_id=$(basename "$active_state" | sed 's/\.tim-loop-state-//')
        fi
    fi

    # Fall back to CLAUDE_CODE_SESSION
    if [[ -z "$session_id" ]]; then
        session_id="${CLAUDE_CODE_SESSION:-}"
    fi

    # Last resort fallback
    if [[ -z "$session_id" ]]; then
        session_id="fallback-$$"
    fi
    echo "$session_id"
}

# Get prompt file path for current session (matches tim-loop-setup.sh format)
get_prompt_file() {
    local session_id
    session_id=$(get_session_id)
    # Note: No .md extension - matches tim-loop-setup.sh
    echo "${PROMPT_DIR}/.tim-loop-prompt-${session_id}"
}

# Ensure prompt directory exists
ensure_dir() {
    mkdir -p "$PROMPT_DIR"
}

# Save prompt for current session
cmd_save() {
    local prompt="$1"
    ensure_dir

    local prompt_file
    prompt_file=$(get_prompt_file)

    # Save raw prompt (matches tim-loop-setup.sh format)
    printf '%s' "$prompt" > "$prompt_file"

    echo "Prompt saved to: $prompt_file" >&2
}

# Save prompt from file
cmd_save_file() {
    local source_file="$1"
    if [[ ! -f "$source_file" ]]; then
        echo "Error: File not found: $source_file" >&2
        exit 1
    fi

    local prompt
    prompt=$(cat "$source_file")
    cmd_save "$prompt"
}

# Get prompt for current session
cmd_get() {
    local prompt_file
    prompt_file=$(get_prompt_file)

    if [[ ! -f "$prompt_file" ]]; then
        return 1
    fi

    # Read the file directly (tim-loop-setup.sh saves raw prompt, no frontmatter)
    cat "$prompt_file"
}

# Clear prompt for current session
cmd_clear() {
    local prompt_file
    prompt_file=$(get_prompt_file)

    if [[ -f "$prompt_file" ]]; then
        rm -f "$prompt_file"
        echo "Cleared prompt: $prompt_file" >&2
    fi
}

# Clean up stale prompts (older than STALE_MINUTES)
cmd_cleanup() {
    if [[ ! -d "$PROMPT_DIR" ]]; then
        return 0
    fi

    local count=0
    # Match files without .md extension (tim-loop-setup.sh format)
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((count++)) || true
    done < <(find "$PROMPT_DIR" -maxdepth 1 -name ".tim-loop-prompt-*" -type f -mmin +${STALE_MINUTES} -print0 2>/dev/null)

    if [[ $count -gt 0 ]]; then
        echo "Cleaned up $count stale prompt file(s)" >&2
    fi
}

# PreCompact hook mode - outputs JSON for Claude Code
cmd_hook() {
    # Debug logging (writes to stderr, captured to log file)
    local log_file="${PROMPT_DIR}/.tim-loop-reinject.log"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # First, clean up stale files
    cmd_cleanup 2>/dev/null || true

    # Check if we have a session ID
    local session_id
    session_id=$(get_session_id)

    if [[ "$session_id" == fallback-* ]]; then
        # No valid session ID, can't safely reinject
        echo "[$timestamp] SKIP: fallback session ID (no valid session)" >> "$log_file"
        echo '{}'
        return 0
    fi

    # Try to get the prompt
    local prompt
    prompt=$(cmd_get 2>/dev/null) || true

    if [[ -z "$prompt" ]]; then
        # No prompt saved for this session
        echo "[$timestamp] SKIP: no prompt for session $session_id" >> "$log_file"
        echo '{}'
        return 0
    fi

    # Log successful reinjection
    local prompt_len=${#prompt}
    echo "[$timestamp] REINJECT: session=$session_id prompt_length=$prompt_len" >> "$log_file"

    # Notify user that reinject occurred
    echo "[tim-loop] Original task prompt reinjected (${prompt_len} chars, session ${session_id})" >&2

    # Output JSON with additionalContext for SessionStart post-compaction reinjection
    # Using jq for proper JSON escaping
    if command -v jq &>/dev/null; then
        jq -n --arg prompt "$prompt" '{
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": ("=== ORIGINAL TASK (reinjected after context compaction) ===\n\nThe following is the original task prompt. Context was compacted but this task remains active. Continue working on this task:\n\n" + $prompt + "\n\n=== END ORIGINAL TASK ===")
            }
        }'
    else
        # Fallback without jq - basic escaping
        local escaped_prompt
        escaped_prompt=$(echo "$prompt" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n')
        echo "{\"hookSpecificOutput\": {\"hookEventName\": \"SessionStart\", \"additionalContext\": \"=== ORIGINAL TASK (reinjected after context compaction) ===\\n\\nThe following is the original task prompt. Context was compacted but this task remains active. Continue working on this task:\\n\\n${escaped_prompt}\\n\\n=== END ORIGINAL TASK ===\"}}"
    fi
}

# Show usage
cmd_help() {
    cat << 'EOF'
tim-loop-prompt-manager.sh - Manage tim-loop prompts for PreCompact reinjection

USAGE:
    tim-loop-prompt-manager.sh <command> [arguments]

COMMANDS:
    save <prompt>       Save prompt text for current session
    save-file <file>    Save prompt from a file
    get                 Get saved prompt for current session
    clear               Clear saved prompt for current session
    cleanup             Remove stale prompts (>24h old)
    hook                PreCompact hook mode (outputs JSON)
    help                Show this help message

ENVIRONMENT VARIABLES:
    TIM_LOOP_SESSION_ID     Session ID (preferred)
    CLAUDE_CODE_SESSION     Fallback session ID
    TIM_PROMPT_DIR          Directory for prompt files (default: .tim-execution-requests)
    TIM_PROMPT_STALE_MINUTES  Minutes before prompts are considered stale (default: 1440)

PRECOMPACT HOOK SETUP:
    Add to .claude/settings.local.json:

    {
      "hooks": {
        "PreCompact": [
          {
            "matcher": "",
            "hooks": [
              {
                "type": "command",
                "command": "./tools/tim-loop-prompt-manager.sh hook"
              }
            ]
          }
        ]
      }
    }

HOW IT WORKS:
    1. At tim-loop start, save the original prompt:
       ./tools/tim-loop-prompt-manager.sh save "implement the plan..."

    2. When context compaction occurs, PreCompact hook runs:
       - Cleans up stale prompts (>24h old)
       - Finds prompt for current session
       - Returns JSON with systemMessage to reinject prompt

    3. At tim-loop completion, clear the prompt:
       ./tools/tim-loop-prompt-manager.sh clear

SESSION ISOLATION:
    Each session has its own prompt file based on session ID.
    Multiple concurrent sessions won't interfere with each other.

CLEANUP:
    - Stale files (>24h) are automatically cleaned on each hook invocation
    - Call 'clear' when tim-loop completes
    - Call 'cleanup' manually to remove old files

EOF
}

# Main dispatch
case "${1:-help}" in
    save)
        if [[ -z "${2:-}" ]]; then
            echo "Error: Prompt text required" >&2
            echo "Usage: $0 save <prompt-text>" >&2
            exit 1
        fi
        cmd_save "$2"
        ;;
    save-file)
        if [[ -z "${2:-}" ]]; then
            echo "Error: File path required" >&2
            echo "Usage: $0 save-file <file>" >&2
            exit 1
        fi
        cmd_save_file "$2"
        ;;
    get)
        cmd_get
        ;;
    clear)
        cmd_clear
        ;;
    cleanup)
        cmd_cleanup
        ;;
    hook)
        cmd_hook
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Run '$0 help' for usage." >&2
        exit 1
        ;;
esac
