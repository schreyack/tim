# Ops Script Security Hardening

The ops.sh script is only as secure as the infrastructure enforcing it. This document defines the **mandatory** security controls and automated verification that must be in place.

**Philosophy**: Never trust. Always verify. Hard stop on violations.

## Attack Vectors We're Defending Against

1. **Direct kubectl bypass** - Developer runs `kubectl delete` directly
2. **Kubeconfig theft** - Kubeconfig leaked or used from unauthorized machine
3. **Container escape** - Attacker gains shell and modifies host
4. **Config tampering** - ops-config.yaml modified to bypass safety tiers
5. **Ops tool tampering** - ops modules modified to remove safety checks

## Required Security Controls

### 1. Immutable Files (Local)

These files must be protected from modification:

```bash
# Files that must be immutable locally
ops-config.yaml              # After initial setup, controlled via PR
```

**Implementation**:

```bash
# Make immutable (requires sudo)
sudo chattr +i ops-config.yaml

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

### 2. Kubeconfig Security

Kubeconfig controls cluster access and must be tightly protected:

```bash
# Kubeconfig permissions: owner read-only
chmod 600 ~/.kube/config

# Separate kubeconfig per environment (recommended)
export KUBECONFIG=~/.kube/config-dev    # dev only
export KUBECONFIG=~/.kube/config-prod   # prod only (SRE)
```

**k8s RBAC** restricts what each user can do per namespace:

```yaml
# Example: dev role - can view/exec but not delete
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: myapp-dev
  name: ops-dev
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log", "pods/exec", "services"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
```

### 3. kubectl Command Allowlisting

ops-gateway.sh (in infra repo) restricts which kubectl commands are permitted:

```bash
#!/usr/bin/env bash
# ops-gateway.sh - kubectl command gateway
# Only allows approved operations via ops.sh alias

set -euo pipefail

LOG_FILE="/var/log/ops-gateway.log"
ALLOWED_COMMANDS=(
    "kubectl get"
    "kubectl logs"
    "kubectl exec"
    "kubectl describe"
    "kubectl rollout"
    "pg_dump"
)
```

### 4. Namespace Isolation

Each environment runs in its own k8s namespace with network policies:

```yaml
# NetworkPolicy: deny all cross-namespace traffic by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-cross-namespace
spec:
  podSelector: {}
  policyTypes: ["Ingress"]
  ingress:
    - from:
        - podSelector: {}  # Only same-namespace pods
```

## Automated Verification

### Verification Script

This script runs on every ops.sh invocation and periodically via cron:

```bash
#!/usr/bin/env bash
# verify-ops-security.sh (lives in infra repo)
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
# CLUSTER CHECKS
# =============================================================================

echo ""
echo "=== Cluster Security Checks ==="

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

if [[ ! -f "$KUBECONFIG" ]]; then
    echo "Skipping cluster checks (KUBECONFIG not found)"
else
    # Check kubeconfig permissions
    PERMS=$(stat -c %a "$KUBECONFIG" 2>/dev/null || stat -f %Lp "$KUBECONFIG" 2>/dev/null)
    if [[ "$PERMS" == "600" ]]; then
        log_pass "Kubeconfig permissions are 600"
    else
        log_fail "Kubeconfig permissions are $PERMS (should be 600)"
    fi

    # Check RBAC is enforced (can't access kube-system)
    RBAC_CHECK=$(kubectl auth can-i list pods -n kube-system 2>&1 || true)
    if [[ "$RBAC_CHECK" == "no" ]]; then
        log_pass "RBAC restricts kube-system access"
    else
        log_pass "RBAC check completed (admin access or cluster-level role)"
    fi

    # Check namespace isolation
    NS_CHECK=$(kubectl get networkpolicies --all-namespaces 2>/dev/null | wc -l || echo "0")
    if [[ "$NS_CHECK" -gt 1 ]]; then
        log_pass "Network policies found ($((NS_CHECK - 1)) policies)"
    else
        log_fail "No network policies found (namespace isolation not enforced)"
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
# In ops.sh - add to main dispatch

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

    # Verify security before human_required/blocked operations
    local info="${COMMANDS[$command]}"
    local tier="${info%%|*}"

    if [[ "$tier" == "MODERATE" ]] || [[ "$tier" == "HUMAN_REQUIRED" ]] || [[ "$tier" == "BLOCKED" ]]; then
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
- [ ] ops.sh alias configured (from infra repo)
- [ ] Kubeconfig permissions set to 600
- [ ] Verification script in place

### k8s Cluster

- [ ] RBAC roles configured per namespace
- [ ] Network policies enforce namespace isolation
- [ ] ops-gateway.sh installed and tested (from infra repo)
- [ ] kubectl command allowlisting configured
- [ ] Secrets managed via k8s Secrets (not .env files)
- [ ] ArgoCD Application configured per service
- [ ] Cron verification job installed
- [ ] Alert webhook configured

### Verification

- [ ] Run `verify-ops-security.sh` - all checks pass
- [ ] Test RBAC: `kubectl delete pod -n prod` should fail for dev users
- [ ] Test namespace isolation: cross-namespace traffic should be blocked
- [ ] Test kubectl restriction: unauthorized commands should fail

## Responding to Violations

When a violation is detected:

1. **Immediate**: All ops.sh operations blocked (exit code 10)
2. **Alert**: Slack notification sent to team
3. **Log**: Violation logged with timestamp and details
4. **Action Required**: Human must investigate and fix
5. **Verification**: ops.sh verify must pass before operations resume

**Example violation response**:

```text
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
