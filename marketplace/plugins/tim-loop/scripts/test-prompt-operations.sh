# test-prompt-operations.sh - Prompt save, hash, version, and metadata tests
# Sourced by test-prompt-validation.sh - do not run directly

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

    sleep 1  # Ensure different timestamp
    run_pm save "Test prompt" >/dev/null 2>&1
    local hash2
    hash2=$(jq -r '.prompt_hash' "$prompt_file")

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
# METADATA VALIDATION TESTS
# ----------------------------------------------------------------------------
echo "--- Metadata Validation Tests ---"

test_session_mismatch() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1

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
