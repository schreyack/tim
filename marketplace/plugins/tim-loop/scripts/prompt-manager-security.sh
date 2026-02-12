# prompt-manager-security.sh - Security and validation functions for prompt manager
#
# This module is sourced by tim-loop-prompt-manager.sh. Do not execute directly.
# All global variables (PROMPT_DIR, PROMPT_MAX_SIZE_BYTES, etc.) are inherited.

# Verify required tools are available (run once at script load)
verify_required_tools() {
    local missing=()
    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi
    if ! command -v shasum &>/dev/null && ! command -v sha256sum &>/dev/null; then
        missing+=("shasum or sha256sum")
    fi
    if ! command -v realpath &>/dev/null; then
        if ! readlink -f / &>/dev/null 2>&1; then
            missing+=("realpath or GNU readlink")
        fi
    fi
    if ! command -v iconv &>/dev/null; then
        missing+=("iconv")
    fi
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "FATAL: Required tools missing: ${missing[*]}" >&2
        exit 1
    fi
}

# Validate and sanitize session ID to prevent directory traversal
sanitize_session_id() {
    local session_id="$1"
    if [[ -z "$session_id" || "$session_id" =~ ^[[:space:]]*$ ]]; then
        echo "ERROR: Empty session ID" >&2
        return 1
    fi
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

# Verify prompt directory is secure
verify_directory_security() {
    local dir="$1"
    # CRITICAL: Check for symlink BEFORE creating directory
    if [[ -L "$dir" ]]; then
        echo "ERROR: Prompt directory is a symlink: $dir" >&2
        return 1
    fi
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
    if [[ ! -e "$marker_file" ]]; then
        return 0
    fi
    if [[ -L "$marker_file" ]]; then
        echo "WARNING: .tim-loop-active is a symlink, ignoring" >&2
        return 1
    fi
    local perms
    perms=$(stat -f '%Lp' "$marker_file" 2>/dev/null || stat -c '%a' "$marker_file" 2>/dev/null)
    if [[ "$perms" != "600" && "$perms" != "644" ]]; then
        echo "WARNING: .tim-loop-active has unusual permissions: $perms" >&2
    fi
    return 0
}

# Check file size before reading to prevent memory exhaustion
validate_file_size() {
    local file="$1"
    local max_size="${2:-$MAX_PROMPT_FILE_SIZE}"
    local size
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
    # Bash silently truncates at NUL - compare size before/after stripping
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
    if ! printf '%s' "$content" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
        echo "ERROR: Content contains invalid UTF-8 sequences" >&2
        return 1
    fi
    return 0
}

# Compute SHA-256 hash of ALL security-relevant fields
# Format: version|epoch|session|path|prompt
compute_content_hash() {
    local version="$1"
    local created_epoch="$2"
    local claude_session="$3"
    local project_path="$4"
    local prompt="$5"
    local hash
    local content_to_hash="${version}|${created_epoch}|${claude_session}|${project_path}|${prompt}"
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

# Validate ISO 8601 timestamp matches epoch and reject future timestamps
validate_clock_consistency() {
    local iso_timestamp="$1"
    local epoch_timestamp="$2"
    local iso_epoch
    if date --version &>/dev/null 2>&1; then
        # GNU date
        iso_epoch=$(date -d "$iso_timestamp" +%s 2>/dev/null) || {
            echo "ERROR: Failed to parse ISO timestamp: $iso_timestamp" >&2
            return 1
        }
    else
        # macOS date - handle timezone suffix
        local clean_ts="${iso_timestamp%Z}"
        iso_epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%S" "$clean_ts" +%s 2>/dev/null) || {
            echo "ERROR: Failed to parse ISO timestamp: $iso_timestamp" >&2
            return 1
        }
    fi
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

# Validate file security (symlink, permissions, ownership)
validate_file_security() {
    local file="$1"
    if [[ -L "$file" ]]; then
        echo "ERROR: File is a symlink - security violation: $file" >&2
        return 1
    fi
    if [[ ! -f "$file" ]]; then
        echo "ERROR: File does not exist: $file" >&2
        return 1
    fi
    local perms
    perms=$(stat -f '%Lp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null)
    if [[ "$perms" != "600" ]]; then
        echo "ERROR: Insecure file permissions: $perms (expected 600): $file" >&2
        return 1
    fi
    local file_owner
    file_owner=$(stat -f '%u' "$file" 2>/dev/null || stat -c '%u' "$file" 2>/dev/null)
    if [[ "$file_owner" != "$(id -u)" ]]; then
        echo "ERROR: File owned by different user: $file" >&2
        return 1
    fi
    return 0
}

# Validate prompt integrity (hash, non-empty, size)
validate_prompt_integrity() {
    local prompt_hash="$1"
    local version="$2"
    local created_epoch="$3"
    local claude_session="$4"
    local project_path="$5"
    local prompt="$6"
    if ! validate_content_hash "$prompt_hash" "$version" "$created_epoch" "$claude_session" "$project_path" "$prompt"; then
        return 1
    fi
    if [[ -z "$prompt" || "$prompt" =~ ^[[:space:]]*$ ]]; then
        echo "ERROR: Prompt is empty or whitespace-only" >&2
        return 1
    fi
    local prompt_size=${#prompt}
    if [[ "$prompt_size" -gt "$PROMPT_MAX_SIZE_BYTES" ]]; then
        echo "ERROR: Prompt too large: ${prompt_size} bytes (max: ${PROMPT_MAX_SIZE_BYTES})" >&2
        return 1
    fi
    return 0
}

# Validate prompt metadata (freshness, session, project)
validate_prompt_metadata() {
    local created_at="$1"
    local created_epoch="$2"
    local claude_session="$3"
    local project_path="$4"
    local current_session="$5"
    local current_project="$6"
    if ! validate_clock_consistency "$created_at" "$created_epoch"; then
        return 1
    fi
    local now max_age_seconds age
    now=$(date +%s)
    max_age_seconds=$((PROMPT_MAX_AGE_HOURS * 3600))
    age=$((now - created_epoch))
    if [[ "$age" -gt "$max_age_seconds" ]]; then
        echo "ERROR: Prompt too old: ${age}s (max: ${max_age_seconds}s / ${PROMPT_MAX_AGE_HOURS}h)" >&2
        return 1
    fi
    if [[ "$claude_session" != "$current_session" ]]; then
        echo "ERROR: Session mismatch: prompt=$claude_session current=$current_session" >&2
        return 1
    fi
    local canonical_current
    canonical_current=$(get_canonical_path "$current_project")
    if [[ "$project_path" != "$canonical_current" ]]; then
        echo "ERROR: Project mismatch: prompt=$project_path current=$canonical_current" >&2
        return 1
    fi
    return 0
}
