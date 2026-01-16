#!/usr/bin/env bash
# verify-ops-security.sh
# TIM Ops Security Verification Script
#
# Runs automated security checks and BLOCKS operations on any failure.
# This script should run:
#   1. Before every deployment operation (called by ops.sh)
#   2. Periodically via cron (hourly minimum)
#   3. After any infrastructure change
#
# Exit codes:
#   0  - All checks passed
#   10 - Security violations detected (HARD STOP)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"

# Load config if available
if [[ -f "$PROJECT_ROOT/ops-config.yaml" ]]; then
    # Simple YAML parsing for required values
    REMOTE_HOST=$(grep "host:" "$PROJECT_ROOT/ops-config.yaml" | head -1 | awk '{print $2}' | tr -d '"')
    REMOTE_USER=$(grep "user:" "$PROJECT_ROOT/ops-config.yaml" | head -1 | awk '{print $2}' | tr -d '"')
    REMOTE_PATH=$(grep "path:" "$PROJECT_ROOT/ops-config.yaml" | head -1 | awk '{print $2}' | tr -d '"')
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

# Results tracking
declare -a VIOLATIONS=()
CHECKS_PASSED=0
CHECKS_FAILED=0

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    VIOLATIONS+=("$1")
    ((CHECKS_FAILED++))
}

log_skip() {
    echo -e "${YELLOW}○${NC} $1 (skipped)"
}

log_info() {
    echo -e "  $1"
}

# =============================================================================
# LOCAL SECURITY CHECKS
# =============================================================================

check_local_security() {
    echo -e "\n${BOLD}=== Local Security Checks ===${NC}"

    # Check 1: tim-ops-lib.sh integrity
    if [[ -f "$PROJECT_ROOT/.tim-ops/tim-ops-lib.sh" ]]; then
        local expected_hash="${TIM_OPS_LIB_HASH:-}"
        if [[ -n "$expected_hash" ]]; then
            local actual_hash
            if command -v sha256sum &> /dev/null; then
                actual_hash=$(sha256sum "$PROJECT_ROOT/.tim-ops/tim-ops-lib.sh" | cut -d' ' -f1)
            elif command -v shasum &> /dev/null; then
                actual_hash=$(shasum -a 256 "$PROJECT_ROOT/.tim-ops/tim-ops-lib.sh" | cut -d' ' -f1)
            fi

            if [[ "$actual_hash" == "$expected_hash" ]]; then
                log_pass "tim-ops-lib.sh integrity verified"
            else
                log_fail "tim-ops-lib.sh has been modified (expected: ${expected_hash:0:16}..., got: ${actual_hash:0:16}...)"
            fi
        else
            log_skip "tim-ops-lib.sh hash not configured (set TIM_OPS_LIB_HASH)"
        fi
    else
        log_skip "tim-ops-lib.sh not found (using alternative source)"
    fi

    # Check 2: ops-config.yaml immutability (Linux)
    if [[ -f "$PROJECT_ROOT/ops-config.yaml" ]]; then
        if command -v lsattr &> /dev/null; then
            local attrs
            attrs=$(lsattr "$PROJECT_ROOT/ops-config.yaml" 2>/dev/null || echo "")
            if [[ "$attrs" == *"i"* ]]; then
                log_pass "ops-config.yaml is immutable"
            else
                log_fail "ops-config.yaml is NOT immutable (fix: sudo chattr +i ops-config.yaml)"
            fi
        elif command -v ls &> /dev/null && [[ "$(uname)" == "Darwin" ]]; then
            # macOS check
            local flags
            flags=$(ls -lO "$PROJECT_ROOT/ops-config.yaml" 2>/dev/null || echo "")
            if [[ "$flags" == *"uchg"* ]] || [[ "$flags" == *"schg"* ]]; then
                log_pass "ops-config.yaml is locked (macOS)"
            else
                log_fail "ops-config.yaml is NOT locked (fix: sudo chflags uchg ops-config.yaml)"
            fi
        else
            log_skip "Cannot check file immutability on this platform"
        fi
    else
        log_fail "ops-config.yaml not found"
    fi

    # Check 3: ops-config.yaml not modified from git
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        if git -C "$PROJECT_ROOT" diff --quiet ops-config.yaml 2>/dev/null; then
            log_pass "ops-config.yaml matches committed version"
        else
            log_fail "ops-config.yaml has uncommitted modifications"
        fi
    else
        log_skip "Not a git repository, skipping git diff check"
    fi

    # Check 4: ops.sh is executable
    if [[ -x "$PROJECT_ROOT/ops.sh" ]]; then
        log_pass "ops.sh is executable"
    else
        log_fail "ops.sh is not executable (fix: chmod +x ops.sh)"
    fi

    # Check 5: No .env in git
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        if git -C "$PROJECT_ROOT" ls-files --error-unmatch .env &> /dev/null; then
            log_fail ".env is tracked in git (SECURITY RISK - remove immediately)"
        else
            log_pass ".env is not tracked in git"
        fi
    fi
}

# =============================================================================
# REMOTE SECURITY CHECKS
# =============================================================================

check_remote_security() {
    echo -e "\n${BOLD}=== Remote Security Checks ===${NC}"

    if [[ -z "${REMOTE_HOST:-}" ]]; then
        log_skip "Remote checks (REMOTE_HOST not configured)"
        return 0
    fi

    log_info "Checking ${REMOTE_USER}@${REMOTE_HOST}..."

    # Check 1: SSH connectivity
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" "echo ok" &> /dev/null; then
        log_fail "Cannot connect to remote host (SSH failed)"
        log_info "Skipping remaining remote checks"
        return 0
    fi
    log_pass "SSH connectivity verified"

    # Check 2: SSH command restriction
    local ssh_test
    ssh_test=$(ssh -o BatchMode=yes "${REMOTE_USER}@${REMOTE_HOST}" "cat /etc/passwd" 2>&1 || true)
    if [[ "$ssh_test" == *"not permitted"* ]] || [[ "$ssh_test" == *"Command not permitted"* ]] || [[ "$ssh_test" == *"not allowed"* ]]; then
        log_pass "SSH command restriction is active"
    elif [[ "$ssh_test" == *"root:"* ]]; then
        log_fail "SSH allows unrestricted commands (ops-gateway not configured)"
    else
        log_skip "SSH restriction check inconclusive"
    fi

    # Check 3: docker-compose.yml immutability
    local dc_attrs
    dc_attrs=$(ssh "${REMOTE_USER}@${REMOTE_HOST}" "lsattr ${REMOTE_PATH}/docker-compose.yml 2>/dev/null || lsattr ${REMOTE_PATH}/docker/docker-compose.yml 2>/dev/null" 2>/dev/null || echo "")
    if [[ "$dc_attrs" == *"i"* ]]; then
        log_pass "Remote docker-compose.yml is immutable"
    elif [[ -z "$dc_attrs" ]]; then
        log_skip "Cannot check docker-compose.yml immutability"
    else
        log_fail "Remote docker-compose.yml is NOT immutable"
    fi

    # Check 4: .env immutability
    local env_attrs
    env_attrs=$(ssh "${REMOTE_USER}@${REMOTE_HOST}" "lsattr ${REMOTE_PATH}/.env 2>/dev/null" 2>/dev/null || echo "")
    if [[ "$env_attrs" == *"i"* ]]; then
        log_pass "Remote .env is immutable"
    elif [[ -z "$env_attrs" ]]; then
        log_skip "Cannot check .env immutability (may not exist or lsattr unavailable)"
    else
        log_fail "Remote .env is NOT immutable"
    fi

    # Check 5: Sudoers restrictions
    local sudo_check
    sudo_check=$(ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo -l 2>/dev/null" 2>/dev/null || echo "restricted")
    if [[ "$sudo_check" == *"(ALL : ALL) ALL"* ]]; then
        log_fail "Sudo is unrestricted (user has full sudo access)"
    elif [[ "$sudo_check" == *"NOPASSWD"* ]] && [[ "$sudo_check" == *"docker"* ]]; then
        log_pass "Sudo is restricted to docker commands"
    else
        log_pass "Sudo access appears restricted"
    fi

    # Check 6: Docker is accessible
    if ssh "${REMOTE_USER}@${REMOTE_HOST}" "docker ps" &> /dev/null; then
        log_pass "Docker is accessible"
    else
        log_fail "Docker is not accessible to deployment user"
    fi
}

# =============================================================================
# FIX MODE
# =============================================================================

fix_issues() {
    echo -e "\n${BOLD}=== Attempting Auto-Fix ===${NC}"

    local fixed=0

    # Fix: Make ops-config.yaml immutable
    if [[ -f "$PROJECT_ROOT/ops-config.yaml" ]]; then
        if command -v chattr &> /dev/null; then
            if sudo chattr +i "$PROJECT_ROOT/ops-config.yaml" 2>/dev/null; then
                echo "Fixed: ops-config.yaml is now immutable"
                ((fixed++))
            fi
        elif [[ "$(uname)" == "Darwin" ]]; then
            if sudo chflags uchg "$PROJECT_ROOT/ops-config.yaml" 2>/dev/null; then
                echo "Fixed: ops-config.yaml is now locked (macOS)"
                ((fixed++))
            fi
        fi
    fi

    # Fix: Make ops.sh executable
    if [[ -f "$PROJECT_ROOT/ops.sh" ]] && [[ ! -x "$PROJECT_ROOT/ops.sh" ]]; then
        chmod +x "$PROJECT_ROOT/ops.sh"
        echo "Fixed: ops.sh is now executable"
        ((fixed++))
    fi

    echo ""
    if [[ $fixed -gt 0 ]]; then
        echo "Auto-fixed $fixed issue(s). Re-running verification..."
        echo ""
        exec "$0"
    else
        echo "No auto-fixable issues found."
        echo "Remote issues require infrastructure team action."
    fi
}

# =============================================================================
# RESULTS
# =============================================================================

print_results() {
    echo ""
    echo -e "${BOLD}=== Verification Results ===${NC}"
    echo "Passed: $CHECKS_PASSED"
    echo "Failed: $CHECKS_FAILED"

    if [[ $CHECKS_FAILED -gt 0 ]]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════════╗"
        echo "║              🛑 SECURITY VIOLATIONS DETECTED                         ║"
        echo "╠══════════════════════════════════════════════════════════════════════╣"
        echo "║ Deployment is BLOCKED until these issues are resolved:              ║"
        echo "╠══════════════════════════════════════════════════════════════════════╣"
        for violation in "${VIOLATIONS[@]}"; do
            # Wrap long lines
            while [[ ${#violation} -gt 64 ]]; do
                printf "║   %-66s ║\n" "${violation:0:64}"
                violation="${violation:64}"
            done
            printf "║   %-66s ║\n" "$violation"
        done
        echo "╠══════════════════════════════════════════════════════════════════════╣"
        echo "║ REQUIRED ACTIONS:                                                    ║"
        echo "║   1. Fix each violation listed above                                ║"
        echo "║   2. Run: ./ops.sh verify --fix (for auto-fixable issues)           ║"
        echo "║   3. Contact infrastructure team for SSH/sudoers changes            ║"
        echo "║   4. Re-run: ./ops.sh verify                                        ║"
        echo "╚══════════════════════════════════════════════════════════════════════╝"
        return 10
    fi

    echo ""
    echo -e "${GREEN}All security checks passed.${NC}"
    return 0
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo -e "${BOLD}TIM Ops Security Verification${NC}"
    echo "Project: ${PROJECT_ROOT}"
    echo "Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Check for --fix flag
    if [[ "${1:-}" == "--fix" ]]; then
        check_local_security
        check_remote_security
        fix_issues
        exit 0
    fi

    # Run checks
    check_local_security
    check_remote_security

    # Print results and exit with appropriate code
    print_results
}

main "$@"
