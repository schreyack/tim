# TIM Command Matrix by Environment

This document defines what ops.sh commands are allowed in each environment (dev, uat, prod) and their safety tiers.

## Safety Tier Reference

| Tier | Exit Code | Behavior |
|------|-----------|----------|
| **SAFE** | 0 | Always allowed, no confirmation, fully scriptable |
| **MODERATE** | 0 | Allowed with logging, may warn in interactive mode |
| **HUMAN_REQUIRED** | 2 | Requires human approval via `tim-ops-approve` |
| **BLOCKED** | 3 | Never allowed in this environment |

## DEV Environment

**Philosophy:** Dev is a sandbox. Anything goes EXCEPT escaping the sandbox.

| Command | Tier | Notes |
|---------|------|-------|
| `status` | SAFE | Show deployment status |
| `health` | SAFE | Run health checks |
| `logs` | SAFE | Tail application logs |
| `logs --full` | SAFE | Full log access |
| `deploy` | SAFE | Deploy changes |
| `deploy --force` | SAFE | Force full rebuild |
| `deploy --sync-only` | SAFE | Sync files only |
| `restart` | SAFE | Restart services |
| `stop` | SAFE | Stop services |
| `start` | SAFE | Start services |
| `shell` | SAFE | Open container shell |
| `exec <command>` | SAFE | Run arbitrary command |
| `build` | SAFE | Build images |
| `pull` | SAFE | Pull images |
| `db:migrate` | SAFE | Run migrations |
| `db:migrate --dry-run` | SAFE | Preview migrations |
| `db:rollback` | SAFE | Rollback migration |
| `db:backup` | SAFE | Create backup |
| `db:restore` | SAFE | Restore from backup |
| `db:seed` | SAFE | Load test data |
| `db:reset` | SAFE | Reset database |
| `env:get` | SAFE | View env vars |
| `env:set` | SAFE | Set env vars |
| `rollback` | SAFE | Rollback deployment |
| `rollback --version` | SAFE | Rollback to version |

**BLOCKED Operations (Sandbox Escape):**

| Blocked | Reason |
|---------|--------|
| Access UAT | Environment isolation |
| Access PROD | Environment isolation |
| SSH to other environments | Environment isolation |
| Modify environments.yaml | Security control |
| Disable logging | Audit requirement |

**Key Principle:** Developers can break dev freely. They cannot escape to other environments.

---

## UAT Environment

**Philosophy:** UAT mirrors production restrictions with more flexibility for testing.

| Command | Tier | Notes |
|---------|------|-------|
| `status` | SAFE | Always allowed |
| `health` | SAFE | Always allowed |
| `logs` | SAFE | Always allowed |
| `logs --full` | SAFE | Full logs allowed |
| `deploy` | MODERATE | Logged, auto-rollback on failure |
| `deploy --force` | HUMAN_REQUIRED | Requires approval |
| `deploy --sync-only` | MODERATE | Logged |
| `restart` | MODERATE | Logged |
| `stop` | HUMAN_REQUIRED | Business impact |
| `start` | MODERATE | Logged |
| `shell` | MODERATE | Allowed for debugging, logged |
| `exec <command>` | MODERATE | Allowed, all commands logged |
| `build` | MODERATE | Logged |
| `pull` | SAFE | Read-only |
| `db:migrate` | MODERATE | Forward migrations allowed |
| `db:migrate --dry-run` | SAFE | Preview only |
| `db:rollback` | HUMAN_REQUIRED | Data risk |
| `db:backup` | SAFE | Always allowed |
| `db:restore` | HUMAN_REQUIRED | Data overwrite risk |
| `db:seed` | HUMAN_REQUIRED | Test data deliberate |
| `db:reset` | BLOCKED | Never in UAT |
| `env:get` | SAFE | Read environment |
| `env:set` | HUMAN_REQUIRED | Config changes need approval |
| `rollback` | HUMAN_REQUIRED | Affects testing |
| `rollback --version` | HUMAN_REQUIRED | Affects testing |

**BLOCKED Operations:**

| Blocked | Reason |
|---------|--------|
| `db:reset` | Would destroy test data |
| Access DEV | Environment isolation |
| Access PROD | Environment isolation |

**Key Principle:** UAT should be stable for testing. Destructive operations need approval.

---

## PROD Environment

**Philosophy:** Production data cannot be lost, stolen, or corrupted. Every action is logged. Most actions require approval.

| Command | Tier | Notes |
|---------|------|-------|
| `status` | SAFE | Monitoring allowed |
| `health` | SAFE | Monitoring allowed |
| `logs` | SAFE | Debugging allowed (PII redacted) |
| `logs --full` | MODERATE | May contain PII, logged |
| `deploy` | HUMAN_REQUIRED | Always requires approval + ticket |
| `deploy --force` | BLOCKED | Never bypass canary |
| `deploy --canary` | HUMAN_REQUIRED | Explicit canary request |
| `deploy --sync-only` | HUMAN_REQUIRED | File changes need approval |
| `restart` | HUMAN_REQUIRED | Service impact |
| `stop` | BLOCKED | Never stop production |
| `start` | HUMAN_REQUIRED | Service impact |
| `shell` | BLOCKED | No shell access |
| `exec <command>` | BLOCKED | No arbitrary commands |
| `build` | MODERATE | Build only, no deploy |
| `pull` | SAFE | Read-only |
| `db:migrate` | HUMAN_REQUIRED | Always requires approval |
| `db:migrate --dry-run` | SAFE | Preview allowed |
| `db:rollback` | BLOCKED | Use restore from backup |
| `db:backup` | SAFE | Always encouraged |
| `db:restore` | BLOCKED | Never via ops.sh |
| `db:seed` | BLOCKED | No test data in prod |
| `db:reset` | BLOCKED | Catastrophic |
| `env:get` | MODERATE | Logged, may expose secrets |
| `env:set` | BLOCKED | Config changes via git + deploy |
| `rollback` | HUMAN_REQUIRED | Requires approval |
| `rollback --version` | HUMAN_REQUIRED | Requires approval |

**BLOCKED Operations:**

| Blocked | Reason |
|---------|--------|
| `stop` | Would cause outage |
| `shell` | Data theft risk |
| `exec` | Data theft risk |
| `db:rollback` | Use backup restoration |
| `db:restore` | Must be done manually |
| `db:seed` | No test data |
| `db:reset` | Catastrophic |
| `env:set` | Config via deployment |
| `deploy --force` | Must use canary |
| Access DEV | Environment isolation |
| Access UAT | Environment isolation |

**Key Principle:** If it could lose data, expose data, or cause an outage, it's BLOCKED or HUMAN_REQUIRED.

---

## Command Comparison Table

| Command | Dev | UAT | Prod |
|---------|-----|-----|------|
| `status` | SAFE | SAFE | SAFE |
| `health` | SAFE | SAFE | SAFE |
| `logs` | SAFE | SAFE | SAFE |
| `logs --full` | SAFE | SAFE | MODERATE |
| `deploy` | SAFE | MODERATE | HUMAN_REQUIRED |
| `deploy --force` | SAFE | HUMAN_REQUIRED | BLOCKED |
| `deploy --canary` | SAFE | MODERATE | HUMAN_REQUIRED |
| `restart` | SAFE | MODERATE | HUMAN_REQUIRED |
| `stop` | SAFE | HUMAN_REQUIRED | BLOCKED |
| `start` | SAFE | MODERATE | HUMAN_REQUIRED |
| `shell` | SAFE | MODERATE | BLOCKED |
| `exec` | SAFE | MODERATE | BLOCKED |
| `db:migrate` | SAFE | MODERATE | HUMAN_REQUIRED |
| `db:migrate --dry-run` | SAFE | SAFE | SAFE |
| `db:rollback` | SAFE | HUMAN_REQUIRED | BLOCKED |
| `db:backup` | SAFE | SAFE | SAFE |
| `db:restore` | SAFE | HUMAN_REQUIRED | BLOCKED |
| `db:seed` | SAFE | HUMAN_REQUIRED | BLOCKED |
| `db:reset` | SAFE | BLOCKED | BLOCKED |
| `env:get` | SAFE | SAFE | MODERATE |
| `env:set` | SAFE | HUMAN_REQUIRED | BLOCKED |
| `rollback` | SAFE | HUMAN_REQUIRED | HUMAN_REQUIRED |

---

## Human Approval Workflow

For HUMAN_REQUIRED operations:

```bash
# 1. AI or developer attempts operation
./ops.sh --env prod deploy --ticket PROJ-123
# OUTPUT: Approval required. Request ID: abc123
# OUTPUT: Run: tim-ops-approve abc123

# 2. Human reviews and approves (separate terminal)
tim-ops-approve abc123
# OUTPUT: Approved by: jane@example.com
# OUTPUT: Expires in: 15 minutes

# 3. Retry the operation (same terminal)
./ops.sh --env prod deploy --ticket PROJ-123
# OUTPUT: Approval verified. Deploying...
```

**Approval Requirements:**
- Approval tokens expire after 15 minutes
- Cannot approve your own requests (in production)
- Requires --ticket for prod deploys
- All approvals logged with timestamp and approver

---

## Audit Trail

All operations are logged:

```
# Format: timestamp | user | env | command | ticket | approver | result | duration
2026-01-17T10:30:00Z | tim | dev | deploy | - | - | SUCCESS | 45s
2026-01-17T11:00:00Z | tim | uat | db:migrate | - | - | SUCCESS | 3s
2026-01-17T14:22:00Z | tim | prod | deploy | PROJ-123 | jane | SUCCESS | 120s
2026-01-17T15:00:00Z | tim | prod | shell | - | - | BLOCKED | 0s
```

**Audit Location:** `~/.tim-ops/audit.log` and remote `/var/log/tim-ops/audit.log`

---

## Environment Protection Settings

Additional protections can be configured per environment:

```yaml
# environments.yaml
prod:
  protections:
    require_approval: true      # All MODERATE+ become HUMAN_REQUIRED
    require_ticket: true        # --ticket flag required
    backup_before_deploy: true  # Auto-backup before deploy
    canary_required: true       # No --force, must use canary
```

When `require_approval: true`:
- All MODERATE operations become HUMAN_REQUIRED
- Provides extra safety layer for production

When `require_ticket: true`:
- Commands fail without `--ticket PROJ-123`
- Ensures traceability to issue tracker

---

## Enforcement Implementation

ops.sh enforces tiers based on environment:

```bash
# Pseudocode for tier enforcement
execute_command() {
    local env="$1"
    local cmd="$2"
    local tier=$(get_tier "$env" "$cmd")

    case "$tier" in
        SAFE)
            run_command "$cmd"
            ;;
        MODERATE)
            log_operation "$env" "$cmd"
            run_command "$cmd"
            ;;
        HUMAN_REQUIRED)
            if ! check_approval "$cmd"; then
                request_approval "$cmd"
                exit 2
            fi
            log_operation "$env" "$cmd"
            run_command "$cmd"
            ;;
        BLOCKED)
            log_blocked_attempt "$env" "$cmd"
            echo "ERROR: $cmd is blocked in $env environment"
            exit 3
            ;;
    esac
}
```

---

## Compliance Checklist

- [ ] All commands have defined tiers for all environments
- [ ] BLOCKED operations return exit code 3
- [ ] HUMAN_REQUIRED operations return exit code 2 until approved
- [ ] All operations are logged to audit trail
- [ ] Prod requires --ticket for deploys
- [ ] Approval tokens expire after 15 minutes
- [ ] Environment isolation prevents cross-environment access
