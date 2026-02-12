#!/usr/bin/env bash
# test-prompt-validation.sh - Test runner for prompt validation security tests
#
# This test runner defines shared helpers and sources test modules.
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
run_pm() {
    (
        cd "$TEST_PROJECT_PATH" 2>/dev/null || true
        TIM_PROMPT_DIR="$TEST_PROMPT_DIR" \
        TIM_LOOP_SESSION_ID="$TEST_SESSION_ID" \
        "$PROMPT_MANAGER" "$@"
    ) 2>&1
}

# Run prompt manager hook and capture ONLY stdout (JSON output)
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
# TEST SUITE
# ============================================================================

echo "=============================================="
echo "Tim Loop Prompt Validation Test Suite"
echo "=============================================="
echo ""

# Source test modules
source "$SCRIPT_DIR/test-security-validation.sh"
source "$SCRIPT_DIR/test-prompt-operations.sh"
source "$SCRIPT_DIR/test-commands.sh"

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
