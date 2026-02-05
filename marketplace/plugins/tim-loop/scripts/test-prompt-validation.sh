#!/usr/bin/env bash
# test-prompt-validation.sh - Comprehensive tests for prompt validation security
#
# This test script validates all security features of tim-loop-prompt-manager.sh
# Run with: ./test-prompt-validation.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_MANAGER="${SCRIPT_DIR}/tim-loop-prompt-manager.sh"

# Test configuration
TEST_DIR=$(mktemp -d)
TEST_PROMPT_DIR="${TEST_DIR}/prompt_dir"
TEST_SESSION_ID="test-session-12345"
TEST_PROJECT_PATH="${TEST_DIR}/project"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Cleanup on exit
cleanup() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Test helpers
pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    ((PASS_COUNT++)) || true
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    ((FAIL_COUNT++)) || true
}

skip() {
    echo -e "${YELLOW}SKIP${NC}: $1"
    ((SKIP_COUNT++)) || true
}

# Setup test environment
setup_test_env() {
    rm -rf "$TEST_PROMPT_DIR" 2>/dev/null || true
    mkdir -p "$TEST_PROMPT_DIR"
    chmod 700 "$TEST_PROMPT_DIR"
    mkdir -p "$TEST_PROJECT_PATH"

    # Create state file for session ID resolution
    echo "$TEST_PROMPT_DIR/.tim-loop-state-${TEST_SESSION_ID}" > "$TEST_PROMPT_DIR/.tim-loop-active"
    cat > "$TEST_PROMPT_DIR/.tim-loop-state-${TEST_SESSION_ID}" << EOF
SESSION_ID="${TEST_SESSION_ID}"
PROJECT_PATH="${TEST_PROJECT_PATH}"
EOF
}

# Run prompt manager command with test environment
# Note: We must cd to the test project path because $PWD environment variable
# doesn't override the shell's actual working directory, and realpath uses
# the actual cwd for canonicalization
run_pm() {
    (
        cd "$TEST_PROJECT_PATH" 2>/dev/null || true
        TIM_PROMPT_DIR="$TEST_PROMPT_DIR" \
        TIM_LOOP_SESSION_ID="$TEST_SESSION_ID" \
        "$PROMPT_MANAGER" "$@"
    ) 2>&1
}

# Run prompt manager hook and capture ONLY stdout (JSON output)
# This is needed for JSON validation tests where stderr messages would break parsing
run_pm_hook_stdout_only() {
    (
        cd "$TEST_PROJECT_PATH" 2>/dev/null || true
        TIM_PROMPT_DIR="$TEST_PROMPT_DIR" \
        TIM_LOOP_SESSION_ID="$TEST_SESSION_ID" \
        "$PROMPT_MANAGER" hook 2>/dev/null
    )
}

# Create a valid prompt file for testing
create_valid_prompt_file() {
    local prompt="${1:-Test prompt content}"
    run_pm save "$prompt" >/dev/null 2>&1
}

# ============================================================================
# TEST CATEGORIES
# ============================================================================

echo "=============================================="
echo "Tim Loop Prompt Validation Test Suite"
echo "=============================================="
echo ""

# ----------------------------------------------------------------------------
# TOOL AVAILABILITY TESTS
# ----------------------------------------------------------------------------
echo "--- Tool Availability Tests ---"

test_jq_required() {
    # This test verifies jq check happens at load time
    # We can't easily simulate missing jq, so we verify the script loads
    if "$PROMPT_MANAGER" help >/dev/null 2>&1; then
        pass "Script loads with jq available"
    else
        fail "Script failed to load"
    fi
}

test_shasum_required() {
    # Verify shasum or sha256sum is used
    if command -v shasum &>/dev/null || command -v sha256sum &>/dev/null; then
        pass "SHA-256 tool is available"
    else
        skip "SHA-256 tool test - tool not installed"
    fi
}

test_realpath_required() {
    if command -v realpath &>/dev/null || readlink -f / &>/dev/null 2>&1; then
        pass "Path canonicalization tool is available"
    else
        skip "Path canonicalization test - tool not installed"
    fi
}

test_iconv_required() {
    if command -v iconv &>/dev/null; then
        pass "iconv is available for UTF-8 validation"
    else
        skip "iconv test - tool not installed"
    fi
}

test_jq_required
test_shasum_required
test_realpath_required
test_iconv_required
echo ""

# ----------------------------------------------------------------------------
# SESSION ID SANITIZATION TESTS
# ----------------------------------------------------------------------------
echo "--- Session ID Sanitization Tests ---"

test_session_id_path_traversal_dotdot() {
    setup_test_env
    local output
    output=$(TIM_PROMPT_DIR="$TEST_PROMPT_DIR" TIM_LOOP_SESSION_ID="../../../tmp/evil" PWD="$TEST_PROJECT_PATH" "$PROMPT_MANAGER" save "test" 2>&1) || true
    if [[ "$output" == *"path traversal"* ]] || [[ "$output" == *"invalid characters"* ]]; then
        pass "Session ID with '..' rejected"
    else
        fail "Session ID with '..' should be rejected: $output"
    fi
}

test_session_id_path_traversal_slash() {
    setup_test_env
    local output
    output=$(TIM_PROMPT_DIR="$TEST_PROMPT_DIR" TIM_LOOP_SESSION_ID="foo/bar" PWD="$TEST_PROJECT_PATH" "$PROMPT_MANAGER" save "test" 2>&1) || true
    if [[ "$output" == *"path traversal"* ]] || [[ "$output" == *"invalid characters"* ]]; then
        pass "Session ID with '/' rejected"
    else
        fail "Session ID with '/' should be rejected: $output"
    fi
}

test_session_id_path_traversal_backslash() {
    setup_test_env
    local output
    output=$(TIM_PROMPT_DIR="$TEST_PROMPT_DIR" TIM_LOOP_SESSION_ID='foo\bar' PWD="$TEST_PROJECT_PATH" "$PROMPT_MANAGER" save "test" 2>&1) || true
    if [[ "$output" == *"path traversal"* ]] || [[ "$output" == *"invalid characters"* ]]; then
        pass "Session ID with backslash rejected"
    else
        fail "Session ID with backslash should be rejected: $output"
    fi
}

test_session_id_special_chars() {
    setup_test_env
    local output
    output=$(TIM_PROMPT_DIR="$TEST_PROMPT_DIR" TIM_LOOP_SESSION_ID='test${}' PWD="$TEST_PROJECT_PATH" "$PROMPT_MANAGER" save "test" 2>&1) || true
    if [[ "$output" == *"invalid characters"* ]]; then
        pass "Session ID with special chars rejected"
    else
        fail "Session ID with special chars should be rejected: $output"
    fi
}

test_session_id_too_long() {
    setup_test_env
    local long_id=$(printf 'a%.0s' {1..200})  # 200 chars
    local output
    output=$(TIM_PROMPT_DIR="$TEST_PROMPT_DIR" TIM_LOOP_SESSION_ID="$long_id" PWD="$TEST_PROJECT_PATH" "$PROMPT_MANAGER" save "test" 2>&1) || true
    if [[ "$output" == *"invalid characters"* ]]; then
        pass "Session ID over 128 chars rejected"
    else
        fail "Session ID over 128 chars should be rejected: $output"
    fi
}

test_session_id_empty() {
    setup_test_env
    local output
    output=$(TIM_PROMPT_DIR="$TEST_PROMPT_DIR" TIM_LOOP_SESSION_ID="" CLAUDE_CODE_SESSION="" PWD="$TEST_PROJECT_PATH" "$PROMPT_MANAGER" save "test" 2>&1) || true
    # Remove the .tim-loop-active file to ensure no session ID is available
    rm -f "$TEST_PROMPT_DIR/.tim-loop-active"
    output=$(TIM_PROMPT_DIR="$TEST_PROMPT_DIR" TIM_LOOP_SESSION_ID="" CLAUDE_CODE_SESSION="" PWD="$TEST_PROJECT_PATH" "$PROMPT_MANAGER" save "test" 2>&1) || true
    if [[ "$output" == *"No valid session ID"* ]] || [[ "$output" == *"Empty session ID"* ]]; then
        pass "Empty session ID rejected"
    else
        fail "Empty session ID should be rejected: $output"
    fi
}

test_session_id_whitespace() {
    setup_test_env
    rm -f "$TEST_PROMPT_DIR/.tim-loop-active"
    local output
    output=$(TIM_PROMPT_DIR="$TEST_PROMPT_DIR" TIM_LOOP_SESSION_ID="   " CLAUDE_CODE_SESSION="" PWD="$TEST_PROJECT_PATH" "$PROMPT_MANAGER" save "test" 2>&1) || true
    if [[ "$output" == *"Empty session ID"* ]] || [[ "$output" == *"invalid characters"* ]]; then
        pass "Whitespace-only session ID rejected"
    else
        fail "Whitespace-only session ID should be rejected: $output"
    fi
}

test_session_id_valid() {
    setup_test_env
    local output
    output=$(run_pm save "test prompt")
    if [[ "$output" == *"Prompt saved"* ]]; then
        pass "Valid alphanumeric session ID accepted"
    else
        fail "Valid session ID should be accepted: $output"
    fi
}

test_session_id_path_traversal_dotdot
test_session_id_path_traversal_slash
test_session_id_path_traversal_backslash
test_session_id_special_chars
test_session_id_too_long
test_session_id_empty
test_session_id_whitespace
test_session_id_valid
echo ""

# ----------------------------------------------------------------------------
# DIRECTORY SECURITY TESTS
# ----------------------------------------------------------------------------
echo "--- Directory Security Tests ---"

test_directory_symlink() {
    setup_test_env
    rm -rf "$TEST_PROMPT_DIR"
    mkdir -p "${TEST_DIR}/real_dir"
    ln -s "${TEST_DIR}/real_dir" "$TEST_PROMPT_DIR"

    local output
    output=$(run_pm save "test" 2>&1) || true
    if [[ "$output" == *"symlink"* ]]; then
        pass "Symlinked directory rejected"
    else
        fail "Symlinked directory should be rejected: $output"
    fi
    rm -f "$TEST_PROMPT_DIR"
}

test_directory_auto_created() {
    rm -rf "$TEST_PROMPT_DIR"
    local output
    output=$(run_pm save "test" 2>&1) || true
    if [[ -d "$TEST_PROMPT_DIR" ]]; then
        pass "Directory auto-created when missing"
    else
        fail "Directory should be auto-created"
    fi
}

test_directory_permissions_fixed() {
    setup_test_env
    chmod 777 "$TEST_PROMPT_DIR"
    local output
    output=$(run_pm save "test" 2>&1) || true
    local perms
    perms=$(stat -f '%Lp' "$TEST_PROMPT_DIR" 2>/dev/null || stat -c '%a' "$TEST_PROMPT_DIR" 2>/dev/null)
    if [[ "$perms" == "700" ]]; then
        pass "Directory permissions fixed to 0700"
    else
        fail "Directory permissions should be fixed to 0700, got: $perms"
    fi
}

test_directory_symlink
test_directory_auto_created
test_directory_permissions_fixed
echo ""

# ----------------------------------------------------------------------------
# PROMPT SAVE AND VALIDATION TESTS
# ----------------------------------------------------------------------------
echo "--- Prompt Save Tests ---"

test_save_valid_prompt() {
    setup_test_env
    local output
    output=$(run_pm save "This is a valid test prompt")
    if [[ "$output" == *"Prompt saved"* ]]; then
        pass "Valid prompt saved successfully"
    else
        fail "Valid prompt should be saved: $output"
    fi
}

test_save_prompt_creates_json() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"
    if [[ -f "$prompt_file" ]] && jq empty "$prompt_file" 2>/dev/null; then
        pass "Prompt saved as valid JSON"
    else
        fail "Prompt should be saved as valid JSON"
    fi
}

test_save_prompt_has_all_fields() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"
    local content
    content=$(cat "$prompt_file")

    local missing=""
    for field in version created_at created_epoch claude_session project_path prompt_hash prompt; do
        if ! echo "$content" | jq -e ".$field" >/dev/null 2>&1; then
            missing="$missing $field"
        fi
    done

    if [[ -z "$missing" ]]; then
        pass "Prompt JSON has all required fields"
    else
        fail "Prompt JSON missing fields:$missing"
    fi
}

test_save_prompt_has_correct_permissions() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"
    local perms
    perms=$(stat -f '%Lp' "$prompt_file" 2>/dev/null || stat -c '%a' "$prompt_file" 2>/dev/null)
    if [[ "$perms" == "600" ]]; then
        pass "Prompt file has 0600 permissions"
    else
        fail "Prompt file should have 0600 permissions, got: $perms"
    fi
}

test_save_empty_prompt() {
    setup_test_env
    local output
    output=$(run_pm save "" 2>&1) || true
    # Empty string causes bash to not see the argument, so usage error is expected
    if [[ "$output" == *"empty"* ]] || [[ "$output" == *"required"* ]]; then
        pass "Empty prompt rejected"
    else
        fail "Empty prompt should be rejected: $output"
    fi
}

test_save_whitespace_prompt() {
    setup_test_env
    local output
    output=$(run_pm save "   " 2>&1) || true
    if [[ "$output" == *"empty"* ]] || [[ "$output" == *"whitespace"* ]]; then
        pass "Whitespace-only prompt rejected"
    else
        fail "Whitespace-only prompt should be rejected: $output"
    fi
}

test_save_valid_prompt
test_save_prompt_creates_json
test_save_prompt_has_all_fields
test_save_prompt_has_correct_permissions
test_save_empty_prompt
test_save_whitespace_prompt
echo ""

# ----------------------------------------------------------------------------
# HASH VALIDATION TESTS
# ----------------------------------------------------------------------------
echo "--- Hash Validation Tests ---"

test_hash_has_prefix() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"
    local hash
    hash=$(jq -r '.prompt_hash' "$prompt_file")
    if [[ "$hash" =~ ^sha256: ]]; then
        pass "Hash has sha256: prefix"
    else
        fail "Hash should have sha256: prefix, got: $hash"
    fi
}

test_hash_correct_length() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"
    local hash
    hash=$(jq -r '.prompt_hash' "$prompt_file")
    if [[ ${#hash} -eq 71 ]]; then
        pass "Hash has correct length (71 chars)"
    else
        fail "Hash should be 71 chars, got: ${#hash}"
    fi
}

test_hash_consistency() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"
    local hash1
    hash1=$(jq -r '.prompt_hash' "$prompt_file")

    # Save again with same content
    sleep 1  # Ensure different timestamp
    run_pm save "Test prompt" >/dev/null 2>&1
    local hash2
    hash2=$(jq -r '.prompt_hash' "$prompt_file")

    # Hashes should be different because epoch is included
    if [[ "$hash1" != "$hash2" ]]; then
        pass "Hash changes with timestamp (epoch in hash)"
    else
        fail "Hash should change with different timestamp"
    fi
}

test_hash_tampering_detected() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"

    # Tamper with prompt content
    local content
    content=$(cat "$prompt_file")
    echo "$content" | jq '.prompt = "TAMPERED"' > "$prompt_file"
    chmod 600 "$prompt_file"

    local output
    output=$(run_pm hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "Hash tampering detected - reinjection blocked"
    else
        fail "Hash tampering should block reinjection: $output"
    fi
}

test_hash_session_tampering_detected() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"

    # Tamper with session ID
    local content
    content=$(cat "$prompt_file")
    echo "$content" | jq '.claude_session = "different-session"' > "$prompt_file"
    chmod 600 "$prompt_file"

    local output
    output=$(run_pm hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "Session tampering detected via hash - reinjection blocked"
    else
        fail "Session tampering should block reinjection: $output"
    fi
}

test_hash_wrong_algorithm() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"

    # Change hash algorithm prefix
    local content
    content=$(cat "$prompt_file")
    echo "$content" | jq '.prompt_hash = "sha1:abcdef1234567890abcdef1234567890abcdef12"' > "$prompt_file"
    chmod 600 "$prompt_file"

    local output
    output=$(run_pm hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "Wrong hash algorithm rejected"
    else
        fail "Wrong hash algorithm should be rejected: $output"
    fi
}

test_hash_truncated() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"

    # Truncate hash
    local content
    content=$(cat "$prompt_file")
    echo "$content" | jq '.prompt_hash = "sha256:abcdef"' > "$prompt_file"
    chmod 600 "$prompt_file"

    local output
    output=$(run_pm hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "Truncated hash rejected"
    else
        fail "Truncated hash should be rejected: $output"
    fi
}

test_hash_has_prefix
test_hash_correct_length
test_hash_consistency
test_hash_tampering_detected
test_hash_session_tampering_detected
test_hash_wrong_algorithm
test_hash_truncated
echo ""

# ----------------------------------------------------------------------------
# VERSION VALIDATION TESTS
# ----------------------------------------------------------------------------
echo "--- Version Validation Tests ---"

test_version_missing() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"

    # Remove version field
    local content
    content=$(cat "$prompt_file")
    echo "$content" | jq 'del(.version)' > "$prompt_file"
    chmod 600 "$prompt_file"

    local output
    output=$(run_pm hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "Missing version field rejected"
    else
        fail "Missing version should be rejected: $output"
    fi
}

test_version_wrong_type() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"

    # Change version to string
    local content
    content=$(cat "$prompt_file")
    echo "$content" | jq '.version = "1"' > "$prompt_file"
    chmod 600 "$prompt_file"

    local output
    output=$(run_pm hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "String version field rejected"
    else
        fail "String version should be rejected: $output"
    fi
}

test_version_unknown() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"

    # Change version to 2
    local content
    content=$(cat "$prompt_file")
    echo "$content" | jq '.version = 2' > "$prompt_file"
    chmod 600 "$prompt_file"

    local output
    output=$(run_pm hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "Unknown version (2) rejected"
    else
        fail "Unknown version should be rejected: $output"
    fi
}

test_version_missing
test_version_wrong_type
test_version_unknown
echo ""

# ----------------------------------------------------------------------------
# FILE SECURITY TESTS
# ----------------------------------------------------------------------------
echo "--- File Security Tests ---"

test_file_symlink_rejected() {
    setup_test_env
    local real_file="${TEST_DIR}/real_prompt"
    echo '{"version":1,"prompt":"test"}' > "$real_file"
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"
    ln -sf "$real_file" "$prompt_file"

    local output
    output=$(run_pm hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "Symlinked prompt file rejected"
    else
        fail "Symlinked prompt file should be rejected: $output"
    fi
}

test_file_wrong_permissions() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"
    chmod 644 "$prompt_file"

    local output
    output=$(run_pm hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "File with wrong permissions rejected"
    else
        fail "File with wrong permissions should be rejected: $output"
    fi
}

test_file_symlink_rejected
test_file_wrong_permissions
echo ""

# ----------------------------------------------------------------------------
# FILE SIZE TESTS
# ----------------------------------------------------------------------------
echo "--- File Size Tests ---"

test_file_size_at_limit() {
    setup_test_env
    # Create a prompt near the 100KB limit
    local large_prompt
    large_prompt=$(head -c 90000 /dev/zero | tr '\0' 'A')
    local output
    output=$(run_pm save "$large_prompt" 2>&1) || true
    if [[ "$output" == *"Prompt saved"* ]]; then
        pass "Prompt at size limit accepted"
    else
        fail "Prompt at size limit should be accepted: $output"
    fi
}

test_file_size_over_limit() {
    setup_test_env
    # Create a prompt over the 100KB limit
    local large_prompt
    large_prompt=$(head -c 110000 /dev/zero | tr '\0' 'A')
    local output
    output=$(run_pm save "$large_prompt" 2>&1) || true
    if [[ "$output" == *"too large"* ]]; then
        pass "Oversized prompt rejected"
    else
        fail "Oversized prompt should be rejected: $output"
    fi
}

test_file_size_at_limit
test_file_size_over_limit
echo ""

# ----------------------------------------------------------------------------
# CLOCK VALIDATION TESTS
# ----------------------------------------------------------------------------
echo "--- Clock Validation Tests ---"

test_clock_future_timestamp() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"

    # Set timestamp far in the future
    local future_epoch=$(($(date +%s) + 600))  # 10 minutes in future
    local content
    content=$(cat "$prompt_file")
    echo "$content" | jq --argjson epoch "$future_epoch" '.created_epoch = $epoch' > "$prompt_file"
    chmod 600 "$prompt_file"

    local output
    output=$(run_pm hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "Future timestamp rejected"
    else
        fail "Future timestamp should be rejected: $output"
    fi
}

test_clock_future_timestamp
echo ""

# ----------------------------------------------------------------------------
# METADATA VALIDATION TESTS
# ----------------------------------------------------------------------------
echo "--- Metadata Validation Tests ---"

test_session_mismatch() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1

    # Run hook with different session ID
    local output
    output=$(TIM_PROMPT_DIR="$TEST_PROMPT_DIR" TIM_LOOP_SESSION_ID="different-session" PWD="$TEST_PROJECT_PATH" "$PROMPT_MANAGER" hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "Session mismatch rejected"
    else
        fail "Session mismatch should be rejected: $output"
    fi
}

test_project_mismatch() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1

    # Run hook with different project path
    local output
    output=$(TIM_PROMPT_DIR="$TEST_PROMPT_DIR" TIM_LOOP_SESSION_ID="$TEST_SESSION_ID" PWD="/different/path" "$PROMPT_MANAGER" hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "Project mismatch rejected"
    else
        fail "Project mismatch should be rejected: $output"
    fi
}

test_session_mismatch
test_project_mismatch
echo ""

# ----------------------------------------------------------------------------
# LEGACY FORMAT TESTS
# ----------------------------------------------------------------------------
echo "--- Legacy Format Tests ---"

test_legacy_non_json() {
    setup_test_env
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"
    echo "This is plain text, not JSON" > "$prompt_file"
    chmod 600 "$prompt_file"

    local output
    output=$(run_pm hook 2>&1) || true
    if [[ "$output" == "{}" ]]; then
        pass "Legacy non-JSON format skipped"
    else
        fail "Legacy non-JSON format should be skipped: $output"
    fi
}

test_legacy_non_json
echo ""

# ----------------------------------------------------------------------------
# REINJECTION MARKER TESTS
# ----------------------------------------------------------------------------
echo "--- Reinjection Marker Tests ---"

test_marker_prevents_double_reinject() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1

    # Clear any existing marker first
    rm -f "${TEST_PROMPT_DIR}/.tim-loop-reinjected-${TEST_SESSION_ID}"

    # First reinjection should work
    local output1
    output1=$(run_pm hook 2>&1)

    # Debug: Check if first reinjection worked
    if [[ "$output1" != *"additionalContext"* ]]; then
        # First reinjection failed - check log for why
        local log_content=""
        [[ -f "${TEST_PROMPT_DIR}/.tim-loop-reinject.log" ]] && log_content=$(tail -5 "${TEST_PROMPT_DIR}/.tim-loop-reinject.log")
        fail "Marker should prevent double reinjection (first reinject failed: $log_content)"
        return
    fi

    # Second reinjection should be blocked by marker
    local output2
    output2=$(run_pm hook 2>&1)

    if [[ "$output2" == "{}" ]]; then
        pass "Marker prevents double reinjection"
    else
        fail "Marker should prevent double reinjection (second reinject should return {})"
    fi
}

test_marker_stale_allows_reinject() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1

    # Clear any existing marker first
    rm -f "${TEST_PROMPT_DIR}/.tim-loop-reinjected-${TEST_SESSION_ID}"

    # First reinjection
    run_pm hook >/dev/null 2>&1

    # Make marker stale by modifying its content to old timestamp
    local marker_file="${TEST_PROMPT_DIR}/.tim-loop-reinjected-${TEST_SESSION_ID}"
    local old_epoch=$(($(date +%s) - 600))  # 10 minutes ago
    echo "$old_epoch" > "$marker_file"
    chmod 600 "$marker_file"

    # Second reinjection should work
    local output
    output=$(run_pm hook 2>&1)

    if [[ "$output" == *"additionalContext"* ]]; then
        pass "Stale marker allows reinjection"
    else
        # Check log for why it failed
        local log_content=""
        [[ -f "${TEST_PROMPT_DIR}/.tim-loop-reinject.log" ]] && log_content=$(tail -5 "${TEST_PROMPT_DIR}/.tim-loop-reinject.log")
        fail "Stale marker should allow reinjection: $log_content"
    fi
}

test_marker_prevents_double_reinject
test_marker_stale_allows_reinject
echo ""

# ----------------------------------------------------------------------------
# UTF-8 VALIDATION TESTS
# ----------------------------------------------------------------------------
echo "--- UTF-8 Validation Tests ---"

test_utf8_valid() {
    setup_test_env
    local output
    output=$(run_pm save "Hello World with emoji: 😀 and unicode: 日本語" 2>&1)
    if [[ "$output" == *"Prompt saved"* ]]; then
        pass "Valid UTF-8 with emoji accepted"
    else
        fail "Valid UTF-8 should be accepted: $output"
    fi
}

test_utf8_valid
echo ""

# ----------------------------------------------------------------------------
# JSON OUTPUT TESTS
# ----------------------------------------------------------------------------
echo "--- JSON Output Tests ---"

test_output_valid_json() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1

    # First we need to clear any existing marker
    rm -f "${TEST_PROMPT_DIR}/.tim-loop-reinjected-${TEST_SESSION_ID}"

    # Capture only stdout (JSON), not stderr (status messages)
    local output
    output=$(run_pm_hook_stdout_only)

    if echo "$output" | jq empty 2>/dev/null; then
        pass "Hook output is valid JSON"
    else
        fail "Hook output should be valid JSON: $output"
    fi
}

test_output_has_hook_fields() {
    setup_test_env
    run_pm save "Test prompt content" >/dev/null 2>&1
    rm -f "${TEST_PROMPT_DIR}/.tim-loop-reinjected-${TEST_SESSION_ID}"

    # Capture only stdout (JSON), not stderr (status messages)
    local output
    output=$(run_pm_hook_stdout_only)

    if echo "$output" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1 && \
       echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        pass "Hook output has required fields"
    else
        # Check log for why it failed
        local log_content=""
        [[ -f "${TEST_PROMPT_DIR}/.tim-loop-reinject.log" ]] && log_content=$(tail -5 "${TEST_PROMPT_DIR}/.tim-loop-reinject.log")
        fail "Hook output should have hookSpecificOutput fields. Output: $output, Log: $log_content"
    fi
}

test_output_contains_prompt() {
    setup_test_env
    local test_prompt="UNIQUE_TEST_PROMPT_12345"
    run_pm save "$test_prompt" >/dev/null 2>&1
    rm -f "${TEST_PROMPT_DIR}/.tim-loop-reinjected-${TEST_SESSION_ID}"

    local output
    output=$(run_pm hook 2>&1)

    if echo "$output" | grep -q "$test_prompt"; then
        pass "Hook output contains original prompt"
    else
        # Check log for why it failed
        local log_content=""
        [[ -f "${TEST_PROMPT_DIR}/.tim-loop-reinject.log" ]] && log_content=$(tail -5 "${TEST_PROMPT_DIR}/.tim-loop-reinject.log")
        fail "Hook output should contain original prompt. Log: $log_content"
    fi
}

test_output_special_chars() {
    setup_test_env
    local test_prompt='Test with "quotes" and backslash \\ and newline
and another line'
    run_pm save "$test_prompt" >/dev/null 2>&1
    rm -f "${TEST_PROMPT_DIR}/.tim-loop-reinjected-${TEST_SESSION_ID}"

    # Capture only stdout (JSON), not stderr (status messages)
    local output
    output=$(run_pm_hook_stdout_only)

    if echo "$output" | jq empty 2>/dev/null; then
        pass "Special characters properly escaped in JSON"
    else
        fail "Special characters should be escaped: $output"
    fi
}

test_output_valid_json
test_output_has_hook_fields
test_output_contains_prompt
test_output_special_chars
echo ""

# ----------------------------------------------------------------------------
# CLEAR AND CLEANUP TESTS
# ----------------------------------------------------------------------------
echo "--- Clear and Cleanup Tests ---"

test_clear_removes_file() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    local prompt_file="${TEST_PROMPT_DIR}/.tim-loop-prompt-${TEST_SESSION_ID}"

    if [[ -f "$prompt_file" ]]; then
        run_pm clear >/dev/null 2>&1
        if [[ ! -f "$prompt_file" ]]; then
            pass "Clear removes prompt file"
        else
            fail "Clear should remove prompt file"
        fi
    else
        fail "Prompt file should exist before clear"
    fi
}

test_clear_removes_marker() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1
    run_pm hook >/dev/null 2>&1  # Creates marker
    local marker_file="${TEST_PROMPT_DIR}/.tim-loop-reinjected-${TEST_SESSION_ID}"

    run_pm clear >/dev/null 2>&1
    if [[ ! -f "$marker_file" ]]; then
        pass "Clear removes reinjection marker"
    else
        fail "Clear should remove reinjection marker"
    fi
}

test_clear_removes_file
test_clear_removes_marker
echo ""

# ----------------------------------------------------------------------------
# GET COMMAND TESTS
# ----------------------------------------------------------------------------
echo "--- Get Command Tests ---"

test_get_returns_prompt() {
    setup_test_env
    local test_prompt="This is the test prompt content"
    run_pm save "$test_prompt" >/dev/null 2>&1

    local output
    output=$(run_pm get 2>&1)

    if [[ "$output" == "$test_prompt" ]]; then
        pass "Get returns saved prompt"
    else
        fail "Get should return saved prompt: got '$output', expected '$test_prompt'"
    fi
}

test_get_returns_prompt
echo ""

# ============================================================================
# SUMMARY
# ============================================================================

echo "=============================================="
echo "Test Summary"
echo "=============================================="
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "${RED}Failed: $FAIL_COUNT${NC}"
echo -e "${YELLOW}Skipped: $SKIP_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
