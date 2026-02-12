# prompt-manager-core.sh - Core utility functions for prompt manager
#
# This module is sourced by tim-loop-prompt-manager.sh. Do not execute directly.
# All global variables (PROMPT_DIR, MARKER_MAX_AGE_SECONDS, etc.) are inherited.

# Clean up temp files on interrupt
cleanup_temp_files() {
    local temp_pattern="${PROMPT_DIR}/.tim-loop-prompt-*.tmp.*"
    rm -f $temp_pattern 2>/dev/null || true
}

# Get session ID from multiple sources
# Priority: TIM_LOOP_SESSION_ID > tim-loop-active file > CLAUDE_CODE_SESSION
get_session_id() {
    local session_id="${TIM_LOOP_SESSION_ID:-}"

    # Try to read from active marker file if no env var
    if [[ -z "$session_id" && -f "$PROMPT_DIR/.tim-loop-active" ]]; then
        if verify_active_marker_security 2>/dev/null; then
            local active_state
            active_state=$(cat "$PROMPT_DIR/.tim-loop-active" 2>/dev/null || true)
            if [[ -f "$active_state" ]]; then
                # Extract session ID from state file path
                session_id=$(basename "$active_state" | sed 's/\.tim-loop-state-//')
            fi
        fi
    fi

    # Fall back to CLAUDE_CODE_SESSION
    if [[ -z "$session_id" ]]; then
        session_id="${CLAUDE_CODE_SESSION:-}"
    fi

    # NO fallback-$$ pattern for security - return empty if none found
    echo "$session_id"
}

# Get canonical path
get_canonical_path() {
    local path="$1"
    if command -v realpath &>/dev/null; then
        realpath "$path" 2>/dev/null || echo "$path"
    else
        readlink -f "$path" 2>/dev/null || echo "$path"
    fi
}

# Get prompt file path for current session
get_prompt_file() {
    local session_id
    session_id=$(get_session_id)

    # Sanitize session ID before using in path
    local sanitized_id
    sanitized_id=$(sanitize_session_id "$session_id" 2>/dev/null) || {
        echo "ERROR: Invalid session ID" >&2
        return 1
    }

    echo "${PROMPT_DIR}/.tim-loop-prompt-${sanitized_id}"
}

# Create prompt JSON with all metadata
create_prompt_json() {
    local prompt="$1"
    local session_id="$2"
    local project_path="$3"

    # Validate prompt is non-empty
    if [[ -z "$prompt" || "$prompt" =~ ^[[:space:]]*$ ]]; then
        echo "ERROR: Prompt is empty or whitespace-only" >&2
        return 1
    fi

    # Validate prompt size
    local prompt_size=${#prompt}
    if [[ "$prompt_size" -gt "$PROMPT_MAX_SIZE_BYTES" ]]; then
        echo "ERROR: Prompt too large: ${prompt_size} bytes (max: ${PROMPT_MAX_SIZE_BYTES})" >&2
        return 1
    fi

    # Validate UTF-8
    if ! validate_utf8 "$prompt"; then
        return 1
    fi

    # Get canonical project path
    local canonical_path
    canonical_path=$(get_canonical_path "$project_path")

    # Generate timestamps
    local created_at created_epoch
    created_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    created_epoch=$(date +%s)

    # Compute hash of ALL security-relevant fields
    local version=1
    local prompt_hash
    prompt_hash=$(compute_content_hash "$version" "$created_epoch" "$session_id" "$canonical_path" "$prompt")

    # Build JSON using jq for proper escaping
    jq -n \
        --argjson version "$version" \
        --arg created_at "$created_at" \
        --argjson created_epoch "$created_epoch" \
        --arg claude_session "$session_id" \
        --arg project_path "$canonical_path" \
        --arg prompt_hash "$prompt_hash" \
        --arg prompt "$prompt" \
        '{
            version: $version,
            created_at: $created_at,
            created_epoch: $created_epoch,
            claude_session: $claude_session,
            project_path: $project_path,
            prompt_hash: $prompt_hash,
            prompt: $prompt
        }'
}

# Create reinjection marker with content-based timestamp
create_reinjection_marker() {
    local marker_file="$1"
    local now
    now=$(date +%s)
    printf '%s' "$now" > "$marker_file"
    chmod 0600 "$marker_file"
}

# Check if marker is fresh using content timestamp (not mtime)
is_marker_fresh() {
    local marker_file="$1"
    local max_age_seconds="${2:-$MARKER_MAX_AGE_SECONDS}"

    # Verify not symlink
    if [[ -L "$marker_file" ]]; then
        echo "WARNING: Marker file is symlink, ignoring" >&2
        return 1  # Not fresh = allow reinjection
    fi

    if [[ ! -f "$marker_file" ]]; then
        return 1  # No marker = allow reinjection
    fi

    local marker_epoch
    marker_epoch=$(cat "$marker_file" 2>/dev/null) || return 1

    # Validate epoch is numeric
    if [[ ! "$marker_epoch" =~ ^[0-9]+$ ]]; then
        echo "WARNING: Marker file contains invalid data, ignoring" >&2
        return 1  # Invalid = allow reinjection
    fi

    local now age
    now=$(date +%s)
    age=$((now - marker_epoch))

    if [[ "$age" -lt 0 ]]; then
        echo "WARNING: Marker timestamp is in the future" >&2
        return 1  # Future = allow reinjection
    fi

    if [[ "$age" -lt "$max_age_seconds" ]]; then
        return 0  # Fresh = skip reinjection
    fi

    return 1  # Stale = allow reinjection
}

# Write to log file with security
write_log() {
    local log_file="$1"
    local message="$2"

    # Verify log file is not a symlink
    if [[ -L "$log_file" ]]; then
        echo "WARNING: Log file is symlink, refusing to write" >&2
        return 1
    fi

    # Create with secure permissions if doesn't exist
    if [[ ! -f "$log_file" ]]; then
        touch "$log_file"
        chmod 0600 "$log_file"
    fi

    # Check log file size and rotate if needed (1MB limit)
    local log_size
    log_size=$(stat -f '%z' "$log_file" 2>/dev/null || stat -c '%s' "$log_file" 2>/dev/null || echo "0")
    if [[ "$log_size" -gt 1048576 ]]; then
        mv "$log_file" "${log_file}.old"
        touch "$log_file"
        chmod 0600 "$log_file"
    fi

    echo "$message" >> "$log_file"
}
