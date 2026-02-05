#!/usr/bin/env bash
# tim-loop-prompt-manager.sh - Manage tim-loop prompts with security validation
#
# This script handles saving, retrieving, and cleaning up tim-loop prompts
# to preserve prompt fidelity across context compaction, with comprehensive
# security validation to prevent reinjection of stale, tampered, or wrong prompts.
#
# SECURITY FEATURES:
# - SHA-256 hash verification (covers version, epoch, session, path, prompt)
# - Session ID sanitization (prevents directory traversal)
# - Symlink attack prevention
# - TOCTOU attack prevention (read-once pattern)
# - Clock skew and future timestamp detection
# - File size limits (prevents memory exhaustion)
# - NUL byte detection (prevents silent truncation)
# - UTF-8 validation
# - Restrictive file permissions (0600)
# - Atomic writes with mktemp
#
# Usage:
#   tim-loop-prompt-manager.sh save <prompt-text>   # Save prompt for current session
#   tim-loop-prompt-manager.sh save-file <file>     # Save prompt from file
#   tim-loop-prompt-manager.sh get                  # Get prompt for current session
#   tim-loop-prompt-manager.sh clear                # Clear prompt for current session
#   tim-loop-prompt-manager.sh cleanup              # Remove stale prompts (>24h)
#   tim-loop-prompt-manager.sh hook                 # SessionStart hook mode (outputs JSON)

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

PROMPT_DIR="${TIM_PROMPT_DIR:-$HOME/.claude}"
STALE_MINUTES="${TIM_PROMPT_STALE_MINUTES:-1440}"  # 24 hours default

# Validation parameters
PROMPT_MAX_AGE_HOURS="${TIM_PROMPT_MAX_AGE_HOURS:-4}"
PROMPT_MAX_SIZE_BYTES="${TIM_PROMPT_MAX_SIZE_BYTES:-102400}"  # 100KB for prompt content
MAX_PROMPT_FILE_SIZE="${TIM_MAX_PROMPT_FILE_SIZE:-204800}"    # 200KB for JSON file

# Clock validation
CLOCK_SKEW_TOLERANCE_SECONDS=300  # 5 minutes
FUTURE_TOLERANCE_SECONDS=300      # 5 minutes

# Marker freshness
MARKER_MAX_AGE_SECONDS=300  # 5 minutes

# ============================================================================
# TOOL AVAILABILITY VERIFICATION
# ============================================================================

# Verify required tools are available (run once at script load)
verify_required_tools() {
    local missing=()

    # jq is required for JSON handling - no unreliable fallback
    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    # SHA-256 tool is required for hash verification
    if ! command -v shasum &>/dev/null && ! command -v sha256sum &>/dev/null; then
        missing+=("shasum or sha256sum")
    fi

    # realpath or readlink -f is required for path canonicalization
    if ! command -v realpath &>/dev/null; then
        # Test if readlink -f works (GNU readlink)
        if ! readlink -f / &>/dev/null 2>&1; then
            missing+=("realpath or GNU readlink")
        fi
    fi

    # iconv is required for UTF-8 validation
    if ! command -v iconv &>/dev/null; then
        missing+=("iconv")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "FATAL: Required tools missing: ${missing[*]}" >&2
        exit 1
    fi
}

# Call at script load time
verify_required_tools

# ============================================================================
# SIGNAL TRAPPING FOR CLEANUP
# ============================================================================

# Trap signals to clean up temp files on interrupt
cleanup_temp_files() {
    local temp_pattern="${PROMPT_DIR}/.tim-loop-prompt-*.tmp.*"
    rm -f $temp_pattern 2>/dev/null || true
}
trap cleanup_temp_files EXIT SIGTERM SIGINT

# ============================================================================
# SESSION ID SANITIZATION
# ============================================================================

# Validate and sanitize session ID to prevent directory traversal
sanitize_session_id() {
    local session_id="$1"

    # Reject empty session ID
    if [[ -z "$session_id" || "$session_id" =~ ^[[:space:]]*$ ]]; then
        echo "ERROR: Empty session ID" >&2
        return 1
    fi

    # Reject if contains path traversal characters
    if [[ "$session_id" == *".."* || "$session_id" == *"/"* || "$session_id" == *"\\"* ]]; then
        echo "ERROR: Session ID contains path traversal characters: $session_id" >&2
        return 1
    fi

    # Only allow alphanumeric, dash, underscore (max 128 chars)
    if [[ ! "$session_id" =~ ^[a-zA-Z0-9_-]{1,128}$ ]]; then
        echo "ERROR: Session ID contains invalid characters: $session_id" >&2
        return 1
    fi

    echo "$session_id"
}

# ============================================================================
# DIRECTORY SECURITY
# ============================================================================

# Verify prompt directory is secure
verify_directory_security() {
    local dir="$1"

    # CRITICAL: Check for symlink BEFORE creating directory
    if [[ -L "$dir" ]]; then
        echo "ERROR: Prompt directory is a symlink: $dir" >&2
        return 1
    fi

    # Directory must exist - create if not
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            echo "ERROR: Failed to create prompt directory: $dir" >&2
            return 1
        }
        chmod 0700 "$dir"
    fi

    # Re-check for symlink AFTER potential creation (TOCTOU protection)
    if [[ -L "$dir" ]]; then
        echo "ERROR: Prompt directory became a symlink: $dir" >&2
        return 1
    fi

    # Must be owned by current user
    local dir_owner
    dir_owner=$(stat -f '%u' "$dir" 2>/dev/null || stat -c '%u' "$dir" 2>/dev/null)
    if [[ "$dir_owner" != "$(id -u)" ]]; then
        echo "ERROR: Prompt directory owned by different user: $dir" >&2
        return 1
    fi

    # Must have correct permissions (owner only)
    local dir_perms
    dir_perms=$(stat -f '%Lp' "$dir" 2>/dev/null || stat -c '%a' "$dir" 2>/dev/null)
    if [[ "$dir_perms" != "700" ]]; then
        echo "WARNING: Fixing prompt directory permissions: $dir" >&2
        chmod 0700 "$dir"
    fi

    return 0
}

# Verify .tim-loop-active marker file is secure before trusting it
verify_active_marker_security() {
    local marker_file="$PROMPT_DIR/.tim-loop-active"

    # If file doesn't exist, that's fine
    if [[ ! -e "$marker_file" ]]; then
        return 0
    fi

    # Must not be a symlink
    if [[ -L "$marker_file" ]]; then
        echo "WARNING: .tim-loop-active is a symlink, ignoring" >&2
        return 1
    fi

    # Must have correct permissions
    local perms
    perms=$(stat -f '%Lp' "$marker_file" 2>/dev/null || stat -c '%a' "$marker_file" 2>/dev/null)
    if [[ "$perms" != "600" && "$perms" != "644" ]]; then
        echo "WARNING: .tim-loop-active has unusual permissions: $perms" >&2
    fi

    return 0
}

# ============================================================================
# FILE VALIDATION FUNCTIONS
# ============================================================================

# Check file size before reading to prevent memory exhaustion
validate_file_size() {
    local file="$1"
    local max_size="${2:-$MAX_PROMPT_FILE_SIZE}"
    local size

    # Get file size (works on both macOS and Linux)
    size=$(stat -f '%z' "$file" 2>/dev/null || stat -c '%s' "$file" 2>/dev/null)

    if [[ -z "$size" ]]; then
        echo "ERROR: Cannot determine file size: $file" >&2
        return 1
    fi

    if [[ "$size" -gt "$max_size" ]]; then
        echo "ERROR: Prompt file too large: ${size} bytes (max: ${max_size})" >&2
        return 1
    fi

    return 0
}

# Check file for NUL bytes BEFORE reading into bash variable
validate_file_no_nul() {
    local file="$1"

    # Bash silently truncates at NUL - this could corrupt prompt
    # Compare file size before/after stripping NUL bytes
    local orig_size clean_size
    orig_size=$(wc -c < "$file" | tr -d ' ')
    clean_size=$(tr -d '\0' < "$file" | wc -c | tr -d ' ')

    if [[ "$orig_size" -ne "$clean_size" ]]; then
        echo "ERROR: File contains NUL bytes (would corrupt data in bash)" >&2
        return 1
    fi

    return 0
}

# Validate content is valid UTF-8
validate_utf8() {
    local content="$1"

    # Use iconv to check UTF-8 validity
    if ! printf '%s' "$content" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
        echo "ERROR: Content contains invalid UTF-8 sequences" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# HASH COMPUTATION AND VALIDATION
# ============================================================================

# Compute SHA-256 hash of ALL security-relevant fields
compute_content_hash() {
    local version="$1"
    local created_epoch="$2"
    local claude_session="$3"
    local project_path="$4"
    local prompt="$5"
    local hash

    # Hash ALL security-relevant fields with delimiter
    # Format: version|epoch|session|path|prompt
    local content_to_hash="${version}|${created_epoch}|${claude_session}|${project_path}|${prompt}"

    # Use printf '%s' to avoid adding newline or interpreting escapes
    if command -v shasum &>/dev/null; then
        hash=$(printf '%s' "$content_to_hash" | shasum -a 256 | cut -d' ' -f1)
    else
        hash=$(printf '%s' "$content_to_hash" | sha256sum | cut -d' ' -f1)
    fi

    echo "sha256:$hash"
}

# Validate stored hash matches computed hash
validate_content_hash() {
    local stored_hash="$1"
    local version="$2"
    local created_epoch="$3"
    local claude_session="$4"
    local project_path="$5"
    local prompt="$6"

    # CRITICAL: Validate algorithm prefix
    if [[ ! "$stored_hash" =~ ^sha256: ]]; then
        echo "ERROR: Unknown hash algorithm (expected sha256:): $stored_hash" >&2
        return 1
    fi

    # CRITICAL: Validate hash length (sha256: prefix + 64 hex chars = 71 total)
    if [[ ${#stored_hash} -ne 71 ]]; then
        echo "ERROR: Invalid hash length: ${#stored_hash} (expected 71)" >&2
        return 1
    fi

    # Validate hash contains only hex characters after prefix
    local hash_value="${stored_hash#sha256:}"
    if [[ ! "$hash_value" =~ ^[0-9a-f]{64}$ ]]; then
        echo "ERROR: Hash contains non-hex characters: $hash_value" >&2
        return 1
    fi

    local computed_hash
    computed_hash=$(compute_content_hash "$version" "$created_epoch" "$claude_session" "$project_path" "$prompt")

    if [[ "$stored_hash" != "$computed_hash" ]]; then
        echo "ERROR: Hash mismatch - content has been tampered" >&2
        echo "  Stored:   $stored_hash" >&2
        echo "  Computed: $computed_hash" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# JSON SCHEMA VALIDATION
# ============================================================================

# Validate all required fields exist and have correct types
validate_json_schema() {
    local json="$1"

    # Check version field exists and equals 1 (integer)
    local version version_type
    version=$(echo "$json" | jq -r '.version // empty')
    if [[ -z "$version" ]]; then
        echo "ERROR: Missing version field" >&2
        return 1
    fi
    version_type=$(echo "$json" | jq -r '.version | type')
    if [[ "$version_type" != "number" ]]; then
        echo "ERROR: Version must be number, got: $version_type" >&2
        return 1
    fi
    if [[ "$version" != "1" ]]; then
        echo "ERROR: Unknown version: $version (only version 1 supported)" >&2
        return 1
    fi

    # Check required string fields exist and are non-empty strings
    local required_strings=("created_at" "claude_session" "project_path" "prompt_hash" "prompt")
    for field in "${required_strings[@]}"; do
        local value field_type
        value=$(echo "$json" | jq -r --arg f "$field" '.[$f] // empty')
        if [[ -z "$value" ]]; then
            echo "ERROR: Missing or empty required field: $field" >&2
            return 1
        fi
        field_type=$(echo "$json" | jq -r --arg f "$field" '.[$f] | type')
        if [[ "$field_type" != "string" ]]; then
            echo "ERROR: Field $field must be string, got: $field_type" >&2
            return 1
        fi
    done

    # Check created_epoch exists and is a number
    local epoch epoch_type
    epoch=$(echo "$json" | jq -r '.created_epoch // empty')
    if [[ -z "$epoch" ]]; then
        echo "ERROR: Missing created_epoch field" >&2
        return 1
    fi
    epoch_type=$(echo "$json" | jq -r '.created_epoch | type')
    if [[ "$epoch_type" != "number" ]]; then
        echo "ERROR: created_epoch must be number, got: $epoch_type" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# CLOCK VALIDATION
# ============================================================================

# Validate ISO 8601 timestamp matches epoch and reject future timestamps
validate_clock_consistency() {
    local iso_timestamp="$1"
    local epoch_timestamp="$2"

    # Convert ISO 8601 to epoch (works on both macOS and Linux)
    local iso_epoch
    if date --version &>/dev/null 2>&1; then
        # GNU date
        iso_epoch=$(date -d "$iso_timestamp" +%s 2>/dev/null) || {
            echo "ERROR: Failed to parse ISO timestamp: $iso_timestamp" >&2
            return 1
        }
    else
        # macOS date - handle timezone suffix
        # The 'Z' suffix indicates UTC. We need to parse in UTC timezone.
        local clean_ts="${iso_timestamp%Z}"
        iso_epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%S" "$clean_ts" +%s 2>/dev/null) || {
            echo "ERROR: Failed to parse ISO timestamp: $iso_timestamp" >&2
            return 1
        }
    fi

    # Calculate difference between ISO and epoch timestamps
    local diff=$((iso_epoch - epoch_timestamp))
    if [[ "$diff" -lt 0 ]]; then
        diff=$((-diff))
    fi

    if [[ "$diff" -gt "$CLOCK_SKEW_TOLERANCE_SECONDS" ]]; then
        echo "ERROR: Clock skew detected: ISO=$iso_timestamp epoch=$epoch_timestamp diff=${diff}s" >&2
        return 1
    fi

    # CRITICAL: Reject timestamps in the future
    local now future_delta
    now=$(date +%s)
    future_delta=$((epoch_timestamp - now))

    if [[ "$future_delta" -gt "$FUTURE_TOLERANCE_SECONDS" ]]; then
        echo "ERROR: Timestamp is in the future by ${future_delta}s (max tolerance: ${FUTURE_TOLERANCE_SECONDS}s)" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# SESSION ID RESOLUTION
# ============================================================================

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

# ============================================================================
# JSON CREATION
# ============================================================================

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

# ============================================================================
# REINJECTION MARKER HANDLING
# ============================================================================

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

# ============================================================================
# LOG FILE HANDLING
# ============================================================================

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

# ============================================================================
# FILE SECURITY VALIDATION
# ============================================================================

# Validate file security (symlink, permissions, ownership)
validate_file_security() {
    local file="$1"

    # Must not be a symlink
    if [[ -L "$file" ]]; then
        echo "ERROR: File is a symlink - security violation: $file" >&2
        return 1
    fi

    # Must exist as regular file
    if [[ ! -f "$file" ]]; then
        echo "ERROR: File does not exist: $file" >&2
        return 1
    fi

    # Must have correct permissions (0600)
    local perms
    perms=$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null)
    if [[ "$perms" != "600" ]]; then
        echo "ERROR: Insecure file permissions: $perms (expected 600): $file" >&2
        return 1
    fi

    # Must be owned by current user
    local file_owner
    file_owner=$(stat -f '%u' "$file" 2>/dev/null || stat -c '%u' "$file" 2>/dev/null)
    if [[ "$file_owner" != "$(id -u)" ]]; then
        echo "ERROR: File owned by different user: $file" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# PROMPT INTEGRITY VALIDATION
# ============================================================================

# Validate prompt integrity (hash, non-empty, size)
validate_prompt_integrity() {
    local prompt_hash="$1"
    local version="$2"
    local created_epoch="$3"
    local claude_session="$4"
    local project_path="$5"
    local prompt="$6"

    # Verify hash
    if ! validate_content_hash "$prompt_hash" "$version" "$created_epoch" "$claude_session" "$project_path" "$prompt"; then
        return 1
    fi

    # Verify non-empty
    if [[ -z "$prompt" || "$prompt" =~ ^[[:space:]]*$ ]]; then
        echo "ERROR: Prompt is empty or whitespace-only" >&2
        return 1
    fi

    # Verify size
    local prompt_size=${#prompt}
    if [[ "$prompt_size" -gt "$PROMPT_MAX_SIZE_BYTES" ]]; then
        echo "ERROR: Prompt too large: ${prompt_size} bytes (max: ${PROMPT_MAX_SIZE_BYTES})" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# PROMPT METADATA VALIDATION
# ============================================================================

# Validate prompt metadata (freshness, session, project)
validate_prompt_metadata() {
    local created_at="$1"
    local created_epoch="$2"
    local claude_session="$3"
    local project_path="$4"
    local current_session="$5"
    local current_project="$6"

    # Validate clock consistency first
    if ! validate_clock_consistency "$created_at" "$created_epoch"; then
        return 1
    fi

    # Check freshness
    local now max_age_seconds age
    now=$(date +%s)
    max_age_seconds=$((PROMPT_MAX_AGE_HOURS * 3600))
    age=$((now - created_epoch))

    if [[ "$age" -gt "$max_age_seconds" ]]; then
        echo "ERROR: Prompt too old: ${age}s (max: ${max_age_seconds}s / ${PROMPT_MAX_AGE_HOURS}h)" >&2
        return 1
    fi

    # Check session match
    if [[ "$claude_session" != "$current_session" ]]; then
        echo "ERROR: Session mismatch: prompt=$claude_session current=$current_session" >&2
        return 1
    fi

    # Check project match (canonical comparison)
    local canonical_current
    canonical_current=$(get_canonical_path "$current_project")
    if [[ "$project_path" != "$canonical_current" ]]; then
        echo "ERROR: Project mismatch: prompt=$project_path current=$canonical_current" >&2
        return 1
    fi

    return 0
}

# ============================================================================
# COMMANDS
# ============================================================================

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

# SessionStart hook mode - outputs JSON for Claude Code
cmd_hook() {
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

    # Notify user
    echo "[tim-loop] Original task prompt reinjected (${prompt_len} chars, session ${sanitized_id})" >&2

    # Build and validate output JSON
    local output_json
    output_json=$(jq -n --arg prompt "$prompt" '{
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": ("=== ORIGINAL TASK (reinjected after context compaction) ===\n\nThe following is the original task prompt. Context was compacted but this task remains active. Continue working on this task:\n\n" + $prompt + "\n\n=== END ORIGINAL TASK ===")
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
