# prompt-manager-commands.sh - Command implementations for prompt manager
#
# This module is sourced by tim-loop-prompt-manager.sh. Do not execute directly.
# All global variables and functions from security/core modules are inherited.

# Save prompt for current session
cmd_save() {
    local prompt="$1"

    # Get and validate session ID
    local session_id
    session_id=$(get_session_id)
    if [[ -z "$session_id" ]]; then
        echo "ERROR: No valid session ID available" >&2
        return 1
    fi

    local sanitized_id
    sanitized_id=$(sanitize_session_id "$session_id") || return 1

    # Verify directory security
    if ! verify_directory_security "$PROMPT_DIR"; then
        return 1
    fi

    # Get project path
    local project_path="${PWD:-$(pwd)}"

    # Create prompt JSON
    local json
    json=$(create_prompt_json "$prompt" "$sanitized_id" "$project_path") || return 1

    # Get prompt file path
    local prompt_file="${PROMPT_DIR}/.tim-loop-prompt-${sanitized_id}"

    # Write atomically with mktemp
    local temp_file
    temp_file=$(mktemp "${prompt_file}.tmp.XXXXXX") || {
        echo "ERROR: Failed to create temp file" >&2
        return 1
    }

    printf '%s' "$json" > "$temp_file"
    chmod 0600 "$temp_file"
    mv -f "$temp_file" "$prompt_file"

    # Verify the move succeeded and file is not a symlink
    if [[ -L "$prompt_file" ]]; then
        rm -f "$prompt_file"
        echo "ERROR: Prompt file became a symlink after write" >&2
        return 1
    fi

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
    prompt_file=$(get_prompt_file) || return 1

    if [[ ! -f "$prompt_file" ]]; then
        return 1
    fi

    # Read JSON and extract prompt
    local content
    content=$(cat "$prompt_file")

    # Check if it's valid JSON
    if ! echo "$content" | jq empty 2>/dev/null; then
        echo "ERROR: Invalid JSON in prompt file" >&2
        return 1
    fi

    # Extract prompt field
    echo "$content" | jq -r '.prompt // empty'
}

# Clear prompt for current session
cmd_clear() {
    local prompt_file
    prompt_file=$(get_prompt_file 2>/dev/null) || return 0

    if [[ ! -f "$prompt_file" ]]; then
        return 0
    fi

    # Get current session ID for verification
    local current_session
    current_session=$(get_session_id)

    if [[ -n "$current_session" ]]; then
        # Verify session ID matches before clearing
        local sanitized_current
        sanitized_current=$(sanitize_session_id "$current_session" 2>/dev/null) || true

        if [[ -f "$prompt_file" ]]; then
            local stored_session
            stored_session=$(cat "$prompt_file" 2>/dev/null | jq -r '.claude_session // empty' 2>/dev/null || true)

            if [[ -n "$stored_session" && "$stored_session" != "$sanitized_current" ]]; then
                echo "WARNING: Session mismatch, refusing to clear: stored=$stored_session current=$sanitized_current" >&2
                return 1
            fi
        fi
    fi

    rm -f "$prompt_file"
    echo "Cleared prompt: $prompt_file" >&2

    # Also clear reinjection marker
    local sanitized_id
    sanitized_id=$(sanitize_session_id "$(get_session_id)" 2>/dev/null) || true
    if [[ -n "$sanitized_id" ]]; then
        local marker_file="${PROMPT_DIR}/.tim-loop-reinjected-${sanitized_id}"
        rm -f "$marker_file" 2>/dev/null || true
    fi
}

# Clean up stale prompts and markers
cmd_cleanup() {
    if [[ ! -d "$PROMPT_DIR" ]]; then
        return 0
    fi

    local count=0

    # Clean stale prompt files (older than STALE_MINUTES)
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((count++)) || true
    done < <(find "$PROMPT_DIR" -maxdepth 1 -name ".tim-loop-prompt-*" -type f -mmin +${STALE_MINUTES} -print0 2>/dev/null)

    # Clean stale reinjection markers (older than 1 hour)
    while IFS= read -r -d '' file; do
        rm -f "$file"
        ((count++)) || true
    done < <(find "$PROMPT_DIR" -maxdepth 1 -name ".tim-loop-reinjected-*" -type f -mmin +60 -print0 2>/dev/null)

    if [[ $count -gt 0 ]]; then
        echo "Cleaned up $count stale file(s)" >&2
    fi
}

# Install git-guard wrapper to intercept destructive git commands (Layer 2)
install_git_guard() {
    local guard_dir="$HOME/.claude/bin"
    local guard_path="$guard_dir/git"
    local guard_source="${SCRIPT_DIR}/git-guard"

    # Source template must exist
    [ -f "$guard_source" ] || return 1

    # Create bin directory
    mkdir -p "$guard_dir"

    # Detect real git path (skip our wrapper)
    local real_git
    real_git=$(which -a git 2>/dev/null | grep -v "$guard_dir" | head -1)
    [ -z "$real_git" ] && return 1

    # Validate path contains only safe characters (prevents sed injection)
    [[ "$real_git" =~ ^[/a-zA-Z0-9._-]+$ ]] || return 1

    # Unlock if previously locked
    # Safe: SessionStart hooks run as shell commands, not agent Bash tool calls,
    # so PreToolUse hooks (which block chflags nouchg) don't fire here
    [ -f "$guard_path" ] && chflags nouchg "$guard_path" 2>/dev/null || true

    # Clean up orphaned temp files from prior failed installs
    rm -f "$guard_dir/git."?????? 2>/dev/null || true

    # Install atomically: temp file + mv (same filesystem = atomic)
    local tmp
    tmp=$(mktemp "$guard_dir/git.XXXXXX")
    sed "s|%%REAL_GIT%%|${real_git}|g" "$guard_source" > "$tmp"
    chmod +x "$tmp"
    mv "$tmp" "$guard_path"

    # Verify wrapper works (pass-through to real git)
    if ! "$guard_path" --version >/dev/null 2>&1; then
        rm -f "$guard_path"
        return 1
    fi

    # Lock wrapper to prevent agent tampering
    chflags uchg "$guard_path"

    # Warn if wrapper is not first in PATH
    local first_git
    first_git=$(which git 2>/dev/null)
    if [ "$first_git" != "$guard_path" ]; then
        echo "WARNING: git-guard not first in PATH. Add \$HOME/.claude/bin to front of PATH." >&2
    fi
}

# SessionStart hook mode - outputs JSON for Claude Code
cmd_hook() {
    install_git_guard 2>/dev/null || true
    local log_file="${PROMPT_DIR}/.tim-loop-reinject.log"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Helper to log and return empty JSON
    skip_reinject() {
        local reason="$1"
        write_log "$log_file" "[$timestamp] SKIP: $reason" 2>/dev/null || true
        echo '{}'
        return 0
    }

    # First, clean up stale files
    cmd_cleanup 2>/dev/null || true

    # Check if we have a valid session ID
    local session_id
    session_id=$(get_session_id)

    if [[ -z "$session_id" ]]; then
        skip_reinject "no valid session ID"
        return 0
    fi

    # Sanitize session ID
    local sanitized_id
    sanitized_id=$(sanitize_session_id "$session_id" 2>/dev/null) || {
        skip_reinject "invalid session ID"
        return 0
    }

    # Check reinjection marker first
    local marker_file="${PROMPT_DIR}/.tim-loop-reinjected-${sanitized_id}"
    if is_marker_fresh "$marker_file"; then
        skip_reinject "already reinjected (marker fresh)"
        return 0
    fi

    # Get prompt file path
    local prompt_file="${PROMPT_DIR}/.tim-loop-prompt-${sanitized_id}"

    # Check if file exists
    if [[ ! -e "$prompt_file" ]]; then
        skip_reinject "no prompt file for session $sanitized_id"
        return 0
    fi

    # Validate file security FIRST
    if ! validate_file_security "$prompt_file" 2>/dev/null; then
        skip_reinject "file security check failed"
        return 0
    fi

    # Validate file size BEFORE reading
    if ! validate_file_size "$prompt_file" 2>/dev/null; then
        skip_reinject "file too large"
        return 0
    fi

    # Check for NUL bytes BEFORE reading
    if ! validate_file_no_nul "$prompt_file" 2>/dev/null; then
        skip_reinject "file contains NUL bytes"
        return 0
    fi

    # Read file content ONCE (TOCTOU protection)
    local file_content
    file_content=$(cat "$prompt_file")

    # Check if it's valid JSON (backwards compatibility check)
    if ! echo "$file_content" | jq empty 2>/dev/null; then
        skip_reinject "legacy format (non-JSON)"
        return 0
    fi

    # Validate JSON schema
    if ! validate_json_schema "$file_content" 2>/dev/null; then
        skip_reinject "invalid JSON schema"
        return 0
    fi

    # Extract all fields from validated content
    local version created_at created_epoch claude_session project_path prompt_hash prompt
    version=$(echo "$file_content" | jq -r '.version')
    created_at=$(echo "$file_content" | jq -r '.created_at')
    created_epoch=$(echo "$file_content" | jq -r '.created_epoch')
    claude_session=$(echo "$file_content" | jq -r '.claude_session')
    project_path=$(echo "$file_content" | jq -r '.project_path')
    prompt_hash=$(echo "$file_content" | jq -r '.prompt_hash')
    prompt=$(echo "$file_content" | jq -r '.prompt')

    # Validate UTF-8
    if ! validate_utf8 "$prompt" 2>/dev/null; then
        skip_reinject "invalid UTF-8 in prompt"
        return 0
    fi

    # Validate prompt integrity (hash verification)
    if ! validate_prompt_integrity "$prompt_hash" "$version" "$created_epoch" "$claude_session" "$project_path" "$prompt" 2>/dev/null; then
        skip_reinject "integrity check failed"
        return 0
    fi

    # Validate metadata (freshness, session, project)
    local current_project="${PWD:-$(pwd)}"
    local metadata_error
    if ! metadata_error=$(validate_prompt_metadata "$created_at" "$created_epoch" "$claude_session" "$project_path" "$sanitized_id" "$current_project" 2>&1); then
        skip_reinject "metadata validation failed: $metadata_error"
        return 0
    fi

    # All validation passed - create reinjection marker
    create_reinjection_marker "$marker_file"

    # Log successful reinjection with hash for audit
    local prompt_len=${#prompt}
    write_log "$log_file" "[$timestamp] REINJECT: session=$sanitized_id len=$prompt_len hash=$prompt_hash" 2>/dev/null || true

    # Check if this is a full-review session with phase > 1
    # If so, prepend a phase correction notice to prevent the agent from
    # re-executing Phase 1 instructions after compaction
    local phase_notice=""
    local state_file="${PROMPT_DIR}/.tim-loop-state-${sanitized_id}"
    if [[ -f "$state_file" ]]; then
        local review_mode current_phase
        review_mode=$(grep '^REVIEW_MODE=' "$state_file" 2>/dev/null | head -1 | cut -d'"' -f2)
        current_phase=$(grep '^CURRENT_PHASE=' "$state_file" 2>/dev/null | head -1 | cut -d'"' -f2)
        if [[ "$review_mode" == "full-review" && -n "$current_phase" && "$current_phase" -gt 1 ]] 2>/dev/null; then
            phase_notice="**PHASE CORRECTION:** You are on Phase ${current_phase}, NOT Phase 1. The prompt below contains the original Phase 1 instructions — ignore phase-specific instructions and work on Phase ${current_phase} instead.\n\n"
            write_log "$log_file" "[$timestamp] PHASE_CORRECTION: phase=$current_phase" 2>/dev/null || true
        fi
    fi

    # Notify user
    echo "[tim-loop] Original task prompt reinjected (${prompt_len} chars, session ${sanitized_id})" >&2

    # Build and validate output JSON
    local output_json
    output_json=$(jq -n --arg prompt "$prompt" --arg phase_notice "$phase_notice" '{
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": ($phase_notice + "=== ORIGINAL TASK (reinjected after context compaction) ===\n\nThe following is the original task prompt. Context was compacted but this task remains active. Continue working on this task:\n\n" + $prompt + "\n\n=== END ORIGINAL TASK ===")
        }
    }')

    # Verify output is valid JSON before returning
    if ! echo "$output_json" | jq empty 2>/dev/null; then
        echo "ERROR: Generated invalid JSON output" >&2
        echo "{}"
        return 1
    fi

    echo "$output_json"
}

# Show usage
cmd_help() {
    cat << 'EOF'
tim-loop-prompt-manager.sh - Manage tim-loop prompts with security validation

USAGE:
    tim-loop-prompt-manager.sh <command> [arguments]

COMMANDS:
    save <prompt>       Save prompt text for current session
    save-file <file>    Save prompt from a file
    get                 Get saved prompt for current session
    clear               Clear saved prompt for current session
    cleanup             Remove stale prompts (>24h old) and markers (>1h old)
    hook                SessionStart hook mode (outputs JSON)
    help                Show this help message

ENVIRONMENT VARIABLES:
    TIM_LOOP_SESSION_ID      Session ID (preferred)
    CLAUDE_CODE_SESSION      Fallback session ID
    TIM_PROMPT_DIR           Directory for prompt files (default: ~/.claude)
    TIM_PROMPT_STALE_MINUTES Minutes before prompts are considered stale (default: 1440)
    TIM_PROMPT_MAX_AGE_HOURS Maximum prompt age for reinjection (default: 4)
    TIM_PROMPT_MAX_SIZE_BYTES Maximum prompt content size (default: 102400)
    TIM_MAX_PROMPT_FILE_SIZE  Maximum prompt file size (default: 204800)

SECURITY FEATURES:
    - SHA-256 hash verification (covers version, epoch, session, path, prompt)
    - Session ID sanitization (prevents directory traversal)
    - Symlink attack prevention
    - TOCTOU attack prevention (read-once pattern)
    - Clock skew and future timestamp detection
    - File size limits (prevents memory exhaustion)
    - NUL byte detection (prevents silent truncation)
    - UTF-8 validation
    - Restrictive file permissions (0600)
    - Atomic writes with mktemp
    - Reinjection markers with content-based timestamps

SESSIONSTART HOOK SETUP:
    Add to .claude/settings.local.json:

    {
      "hooks": {
        "SessionStart": [
          {
            "matcher": "",
            "hooks": [
              {
                "type": "command",
                "command": "./plugins/tim-loop/scripts/tim-loop-prompt-manager.sh hook"
              }
            ]
          }
        ]
      }
    }

HOW IT WORKS:
    1. At tim-loop start, save the original prompt:
       ./plugins/tim-loop/scripts/tim-loop-prompt-manager.sh save "implement the plan..."

    2. When context compaction occurs, SessionStart hook runs:
       - Validates file security (not symlink, correct permissions, ownership)
       - Validates file size and NUL bytes
       - Validates JSON schema and version
       - Validates hash integrity (prompt not tampered)
       - Validates metadata (freshness, session match, project match)
       - Validates clock consistency (no time manipulation)
       - Creates reinjection marker to prevent duplicates
       - Returns JSON with additionalContext to reinject prompt

    3. At tim-loop completion, clear the prompt:
       ./plugins/tim-loop/scripts/tim-loop-prompt-manager.sh clear

STORAGE FORMAT:
    Prompts are stored as JSON with full metadata:
    {
      "version": 1,
      "created_at": "2025-01-29T10:00:00Z",
      "created_epoch": 1706522400,
      "claude_session": "abc123",
      "project_path": "/path/to/project",
      "prompt_hash": "sha256:abc123def456...",
      "prompt": "the actual prompt text..."
    }

    The hash covers ALL security-relevant fields to prevent tampering.

EOF
}
