# test-security-validation.sh - Security-related tests for prompt validation
# Sourced by test-prompt-validation.sh - do not run directly

# ----------------------------------------------------------------------------
# TOOL AVAILABILITY TESTS
# ----------------------------------------------------------------------------
echo "--- Tool Availability Tests ---"

test_jq_required() {
    if "$PROMPT_MANAGER" help >/dev/null 2>&1; then
        pass "Script loads with jq available"
    else
        fail "Script failed to load"
    fi
}

test_shasum_required() {
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
