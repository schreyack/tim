# test-commands.sh - Reinjection, JSON output, clear, and get command tests
# Sourced by test-prompt-validation.sh - do not run directly

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

    if [[ "$output1" != *"additionalContext"* ]]; then
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
        local log_content=""
        [[ -f "${TEST_PROMPT_DIR}/.tim-loop-reinject.log" ]] && log_content=$(tail -5 "${TEST_PROMPT_DIR}/.tim-loop-reinject.log")
        fail "Stale marker should allow reinjection: $log_content"
    fi
}

test_marker_prevents_double_reinject
test_marker_stale_allows_reinject
echo ""

# ----------------------------------------------------------------------------
# JSON OUTPUT TESTS
# ----------------------------------------------------------------------------
echo "--- JSON Output Tests ---"

test_output_valid_json() {
    setup_test_env
    run_pm save "Test prompt" >/dev/null 2>&1

    rm -f "${TEST_PROMPT_DIR}/.tim-loop-reinjected-${TEST_SESSION_ID}"

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

    local output
    output=$(run_pm_hook_stdout_only)

    if echo "$output" | jq -e '.hookSpecificOutput.hookEventName' >/dev/null 2>&1 && \
       echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
        pass "Hook output has required fields"
    else
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
