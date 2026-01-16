# Ops Script Security Hardening

The ops.sh script is only as secure as the infrastructure enforcing it. This document defines the **mandatory** security controls and automated verification that must be in place.

**Philosophy**: Never trust. Always verify. Hard stop on violations.

## Attack Vectors We're Defending Against

1. **Direct SSH bypass** - Developer SSHs in and runs `docker stop` directly
2. **Rsync overwrites** - Rsync replaces protected config files
3. **Container escape** - Attacker gains shell and modifies host
4. **Config tampering** - ops-config.yaml modified to bypass safety tiers
5. **Library tampering** - tim-ops-lib.sh modified to remove safety checks

## Required Security Controls

### 1. Immutable Files (Local)

These files must be protected from modification:

```bash
# Files that must be immutable locally
.tim-ops/tim-ops-lib.sh      # Shared library (if using auto-download)
ops-config.yaml              # After initial setup, controlled via PR
```

**Implementation**:
```bash
# Make immutable (requires sudo)
sudo chattr +i ops-config.yaml
sudo chattr +i .tim-ops/tim-ops-lib.sh

# Verify immutability
lsattr ops-config.yaml  # Should show 'i' flag
```

**macOS Alternative** (no chattr):
```bash
# Lock file
sudo chflags uchg ops-config.yaml
sudo chflags schg ops-config.yaml  # System immutable (survives reboot)

# Verify
ls -lO ops-config.yaml  # Should show 'uchg' or 'schg'
```

### 2. Immutable Files (Remote)

Critical files on the remote server:

```bash
# Remote files that must be immutable
/home/tim/apps/project/docker-compose.yml     # Container definitions
/home/tim/apps/project/.env                   # Secrets
/etc/sudoers.d/tim-ops                        # Sudo rules
```

**Implementation**:
```bash
# On remote server
sudo chattr +i /home/tim/apps/project/docker-compose.yml
sudo chattr +i /home/tim/apps/project/.env
```

### 3. SSH Command Restriction

The deployment user should ONLY be able to run ops-approved commands.

**Implementation** (`/home/tim/.ssh/authorized_keys`):
```
# Restrict SSH key to specific commands via forced command
command="/home/tim/bin/ops-gateway.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-rsa AAAA... deploy@local
```

**ops-gateway.sh** (Allowlist of permitted commands):
```bash
#!/usr/bin/env bash
# /home/tim/bin/ops-gateway.sh
# SSH command gateway - only allows approved operations

set -euo pipefail

LOG_FILE="/var/log/ops-gateway.log"
ALLOWED_COMMANDS=(
    "docker compose"
    "docker ps"
    "docker logs"
    "docker exec"
    "docker inspect"
    "rsync --server"
    "cat"
    "echo ok"
    "pg_dump"
)

log() {
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | $USER | $SSH_ORIGINAL_COMMAND" >> "$LOG_FILE"
}

is_allowed() {
    local cmd="$1"
    for allowed in "${ALLOWED_COMMANDS[@]}"; do
        if [[ "$cmd" == "$allowed"* ]]; then
            return 0
        fi
    done
    return 1
}

# Log all attempts
log

# Check if command is allowed
if [[ -z "${SSH_ORIGINAL_COMMAND:-}" ]]; then
    echo "ERROR: Interactive SSH not permitted. Use ops.sh commands."
    exit 1
fi

if is_allowed "$SSH_ORIGINAL_COMMAND"; then
    eval "$SSH_ORIGINAL_COMMAND"
else
    echo "ERROR: Command not permitted: $SSH_ORIGINAL_COMMAND"
    echo "Contact infrastructure team if this command should be allowed."
    exit 1
fi
```

### 4. Rsync Restrictions

Rsync must not be able to overwrite protected files.

**Implementation** (rsync daemon or wrapper):
```bash
# /home/tim/bin/rsync-wrapper.sh
#!/usr/bin/env bash
# Rsync wrapper that protects certain paths

PROTECTED_FILES=(
    "docker-compose.yml"
    "docker-compose.*.yml"
    ".env"
    ".env.*"
    "ops-config.yaml"
)

# Check if any protected file is in the transfer
for arg in "$@"; do
    for protected in "${PROTECTED_FILES[@]}"; do
        if [[ "$arg" == *"$protected"* ]]; then
            echo "ERROR: Cannot overwrite protected file: $protected"
            echo "Protected files can only be modified via infrastructure PR"
            exit 1
        fi
    done
done

# Run actual rsync
/usr/bin/rsync "$@"
```

**Alternative: rsync exclude on server**:
```bash
# /etc/rsyncd.conf
[project]
    path = /home/tim/apps/project
    read only = false
    exclude = docker-compose.yml .env ops-config.yaml
```

### 5. Sudoers Restrictions

The ops user should have limited sudo access:

```bash
# /etc/sudoers.d/tim-ops
tim ALL=(ALL) NOPASSWD: /usr/bin/docker
tim ALL=(ALL) NOPASSWD: /usr/bin/docker-compose
tim ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart docker
# NO other sudo access
```

## Automated Verification

### Verification Script

This script runs on every ops.sh invocation and periodically via cron:

```bash
#!/usr/bin/env bash
# verify-ops-security.sh
# Runs automated security checks - HARD STOP on any failure

set -euo pipefail

VIOLATIONS=()
CHECKS_PASSED=0
CHECKS_FAILED=0

log_pass() {
    echo "✓ $1"
    ((CHECKS_PASSED++))
}

log_fail() {
    echo "✗ $1"
    VIOLATIONS+=("$1")
    ((CHECKS_FAILED++))
}

# =============================================================================
# LOCAL CHECKS
# =============================================================================

echo "=== Local Security Checks ==="

# Check tim-ops-lib hasn't been modified
if [[ -f ".tim-ops/tim-ops-lib.sh" ]]; then
    EXPECTED_HASH="${TIM_OPS_LIB_HASH:-}"
    if [[ -n "$EXPECTED_HASH" ]]; then
        ACTUAL_HASH=$(sha256sum .tim-ops/tim-ops-lib.sh | cut -d' ' -f1)
        if [[ "$ACTUAL_HASH" == "$EXPECTED_HASH" ]]; then
            log_pass "tim-ops-lib.sh integrity verified"
        else
            log_fail "tim-ops-lib.sh has been modified (hash mismatch)"
        fi
    fi
fi

# Check ops-config.yaml is immutable (Linux)
if command -v lsattr &> /dev/null; then
    if lsattr ops-config.yaml 2>/dev/null | grep -q 'i'; then
        log_pass "ops-config.yaml is immutable"
    else
        log_fail "ops-config.yaml is NOT immutable (run: sudo chattr +i ops-config.yaml)"
    fi
fi

# Check for unauthorized changes to ops-config.yaml
if git diff --quiet ops-config.yaml 2>/dev/null; then
    log_pass "ops-config.yaml matches git"
else
    log_fail "ops-config.yaml has local modifications not in git"
fi

# =============================================================================
# REMOTE CHECKS
# =============================================================================

echo ""
echo "=== Remote Security Checks ==="

REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_USER="${REMOTE_USER:-}"
REMOTE_PATH="${REMOTE_PATH:-}"

if [[ -z "$REMOTE_HOST" ]]; then
    echo "Skipping remote checks (REMOTE_HOST not set)"
else
    # Check SSH gateway is in place
    SSH_CHECK=$(ssh -o BatchMode=yes "${REMOTE_USER}@${REMOTE_HOST}" "cat /etc/passwd" 2>&1 || true)
    if [[ "$SSH_CHECK" == *"not permitted"* ]] || [[ "$SSH_CHECK" == *"Command not permitted"* ]]; then
        log_pass "SSH command restriction active"
    else
        log_fail "SSH allows unrestricted commands (gateway not configured)"
    fi

    # Check docker-compose.yml is immutable
    IMMUTABLE_CHECK=$(ssh "${REMOTE_USER}@${REMOTE_HOST}" "lsattr ${REMOTE_PATH}/docker-compose.yml 2>/dev/null" || echo "")
    if [[ "$IMMUTABLE_CHECK" == *"i"* ]]; then
        log_pass "Remote docker-compose.yml is immutable"
    else
        log_fail "Remote docker-compose.yml is NOT immutable"
    fi

    # Check .env is immutable
    ENV_CHECK=$(ssh "${REMOTE_USER}@${REMOTE_HOST}" "lsattr ${REMOTE_PATH}/.env 2>/dev/null" || echo "")
    if [[ "$ENV_CHECK" == *"i"* ]]; then
        log_pass "Remote .env is immutable"
    else
        log_fail "Remote .env is NOT immutable"
    fi

    # Check sudoers is restricted
    SUDO_CHECK=$(ssh "${REMOTE_USER}@${REMOTE_HOST}" "sudo -l 2>/dev/null" || echo "")
    if [[ "$SUDO_CHECK" != *"ALL"* ]] || [[ "$SUDO_CHECK" == *"NOPASSWD: /usr/bin/docker"* ]]; then
        log_pass "Sudo access is restricted"
    else
        log_fail "Sudo access is too permissive"
    fi
fi

# =============================================================================
# RESULTS
# =============================================================================

echo ""
echo "=== Results ==="
echo "Passed: $CHECKS_PASSED"
echo "Failed: $CHECKS_FAILED"

if [[ $CHECKS_FAILED -gt 0 ]]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🛑 SECURITY VIOLATIONS DETECTED               ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║ Deployment is BLOCKED until these issues are resolved:          ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    for violation in "${VIOLATIONS[@]}"; do
        printf "║ • %-62s ║\n" "$violation"
    done
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║ REQUIRED ACTIONS:                                                ║"
    echo "║ 1. Fix each violation listed above                              ║"
    echo "║ 2. Run: ./ops.sh verify --fix (for auto-fixable issues)         ║"
    echo "║ 3. Contact infrastructure team for SSH/sudoers changes          ║"
    echo "║ 4. Re-run: ./ops.sh verify                                      ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    exit 10
fi

echo "All security checks passed."
exit 0
```

### Integration with ops.sh

Add verification as a pre-flight check:

```bash
# In tim-ops-lib.sh - add to tim_ops_main()

# Security verification before any operation
verify_security() {
    if [[ "${SKIP_SECURITY_CHECK:-}" == "1" ]]; then
        log_warn "Security check skipped (SKIP_SECURITY_CHECK=1)"
        return 0
    fi

    log_info "Running security verification..."

    if ! "$PROJECT_ROOT/scripts/verify-ops-security.sh"; then
        log_error "Security verification failed"
        log_error "Deployment BLOCKED until issues are resolved"
        return 10
    fi
}

# Call before any deployment operation
tim_ops_main() {
    # ... argument parsing ...

    # Verify security before protected/blocked operations
    local info="${COMMANDS[$command]}"
    local tier="${info%%|*}"

    if [[ "$tier" == "MODERATE" ]] || [[ "$tier" == "PROTECTED" ]] || [[ "$tier" == "BLOCKED" ]]; then
        verify_security || return $?
    fi

    # ... rest of main ...
}
```

### Cron Verification

Run verification automatically:

```bash
# /etc/cron.d/tim-ops-verify
# Verify ops security every hour
0 * * * * tim /home/tim/apps/project/scripts/verify-ops-security.sh >> /var/log/ops-verify.log 2>&1

# If verification fails, alert immediately
0 * * * * tim /home/tim/apps/project/scripts/verify-ops-security.sh || curl -X POST -d '{"text":"🚨 Ops security verification FAILED on $(hostname)"}' $SLACK_WEBHOOK
```

## Initial Setup Checklist

When setting up a new TIM project, infrastructure team must:

### Local Machine
- [ ] ops-config.yaml created and locked (`chattr +i` / `chflags uchg`)
- [ ] tim-ops-lib.sh downloaded and hash verified
- [ ] SSH key created specifically for ops deployment
- [ ] Verification script in place

### Remote Server
- [ ] Deployment user created (non-root)
- [ ] SSH authorized_keys with command restriction
- [ ] ops-gateway.sh installed and tested
- [ ] rsync restrictions configured
- [ ] sudoers limited to docker commands only
- [ ] docker-compose.yml made immutable
- [ ] .env made immutable
- [ ] Cron verification job installed
- [ ] Alert webhook configured

### Verification
- [ ] Run `ops.sh verify` - all checks pass
- [ ] Test SSH restriction: `ssh user@host "cat /etc/passwd"` should fail
- [ ] Test rsync restriction: attempt to overwrite docker-compose.yml should fail
- [ ] Test sudo restriction: `ssh user@host "sudo rm -rf /"` should fail

## Responding to Violations

When a violation is detected:

1. **Immediate**: All ops.sh operations blocked (exit code 10)
2. **Alert**: Slack notification sent to team
3. **Log**: Violation logged with timestamp and details
4. **Action Required**: Human must investigate and fix
5. **Verification**: ops.sh verify must pass before operations resume

**Example violation response**:
```
╔══════════════════════════════════════════════════════════════════╗
║                    🛑 SECURITY VIOLATIONS DETECTED               ║
╠══════════════════════════════════════════════════════════════════╣
║ Deployment is BLOCKED until these issues are resolved:          ║
╠══════════════════════════════════════════════════════════════════╣
║ • Remote docker-compose.yml is NOT immutable                    ║
║ • SSH allows unrestricted commands (gateway not configured)     ║
╠══════════════════════════════════════════════════════════════════╣
║ REQUIRED ACTIONS:                                                ║
║ 1. Fix each violation listed above                              ║
║ 2. Run: ./ops.sh verify --fix (for auto-fixable issues)         ║
║ 3. Contact infrastructure team for SSH/sudoers changes          ║
║ 4. Re-run: ./ops.sh verify                                      ║
╚══════════════════════════════════════════════════════════════════╝
```

## Escape Hatches

For genuine emergencies requiring bypass:

1. **Break-glass procedure**: Documented, requires 2-person approval
2. **Temporary key**: Different SSH key without command restrictions
3. **Audit trail**: All bypass usage logged and reviewed
4. **Post-incident**: Root cause analysis required

The break-glass key should:
- Be stored in a secure vault (not on developer machines)
- Require manager approval to retrieve
- Auto-expire after 4 hours
- Trigger immediate alert when used
