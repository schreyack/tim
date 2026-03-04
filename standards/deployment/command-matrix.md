# TIM Command Matrix by Environment

This document defines what ops.sh commands are allowed in each environment and their safety tiers.

## Safety Tier Reference

| Tier | Exit Code (non-interactive) | Behavior |
|------|---------------------------|----------|
| **SAFE** | 0 | Always allowed, no confirmation, fully scriptable |
| **MODERATE** | 2 | Prompts `y/N` in interactive mode; exits 2 in non-interactive |
| **HUMAN_REQUIRED** | 3 | Prompts to type project name; exits 3 in non-interactive |
| **BLOCKED** | 1 | Hard deny — never allowed, no bypass flags |

## DEV Environment

**Philosophy:** Dev is a sandbox. Anything goes EXCEPT escaping the sandbox.

| Command | Tier | Notes |
|---------|------|-------|
| `status` | SAFE | Show deployment status |
| `health` | SAFE | Run health checks |
| `logs <service>` | SAFE | Tail application logs |
| `disk` | SAFE | PVC disk usage |
| `worker status` | SAFE | Queue and worker status |
| `build <svc\|all>` | SAFE | Build images via kaniko |
| `deploy [sha]` | SAFE | Run migrations + apply manifests |
| `ship` | SAFE | Full build-deploy-verify cycle |
| `restart <svc\|all>` | SAFE | Restart services |
| `stop <svc\|all>` | SAFE | Stop services |
| `start <svc\|all>` | SAFE | Start services |
| `shell <svc>` | SAFE | Open container shell |
| `exec <svc> <cmd>` | SAFE | Run arbitrary command |
| `rollback` | SAFE | Undo last rollout |
| `db migrate` | SAFE | Run migrations |
| `db rollback` | SAFE | Rollback migration |
| `db backup` | SAFE | Create backup |
| `db restore <file>` | SAFE | Restore from backup |
| `db shell` | SAFE | Read-only psql |
| `db shell --write` | MODERATE | Write-enabled psql (auto-backup first) |
| `db query "<SQL>"` | SAFE | Execute SQL |
| `db status` | SAFE | Database connection stats |
| `seed [name]` | SAFE | Load seed data |
| `script <name>` | SAFE | Run allowlisted script |
| `fetch <svc> <path>` | SAFE | Copy file from pod |
| `cleanup [logs]` | SAFE | Clean up pods/logs |
| `env check` | SAFE | Validate env config |
| `env list` | SAFE | List env vars |
| `env set KEY=VALUE` | SAFE | Set env var |
| `env diff` | SAFE | Diff template vs actual |

**Key Principle:** Developers can break dev freely. They cannot escape to other environments.

---

## PROD Environment

**Philosophy:** Production data cannot be lost, stolen, or corrupted. Every action is logged.

| Command | Tier | Notes |
|---------|------|-------|
| `status` | SAFE | Monitoring always allowed |
| `health` | SAFE | Monitoring always allowed |
| `logs <service>` | SAFE | Debugging allowed |
| `disk` | SAFE | Read-only |
| `worker status` | SAFE | Read-only |
| `build <svc\|all>` | SAFE | Build only, no deploy |
| `deploy [sha]` | HUMAN_REQUIRED | Always requires approval |
| `ship` | HUMAN_REQUIRED | Full cycle requires approval |
| `restart <svc\|all>` | HUMAN_REQUIRED | Service impact |
| `stop <svc\|all>` | BLOCKED | Never stop production |
| `start <svc\|all>` | HUMAN_REQUIRED | Service impact |
| `shell <svc>` | BLOCKED | No shell access |
| `exec <svc> <cmd>` | BLOCKED | No arbitrary commands |
| `rollback` | HUMAN_REQUIRED | Requires approval |
| `db migrate` | HUMAN_REQUIRED | Always requires approval |
| `db rollback` | HUMAN_REQUIRED or BLOCKED | Project-specific |
| `db backup` | SAFE | Always encouraged |
| `db restore <file>` | BLOCKED | Never via ops.sh |
| `db shell` | BLOCKED | No shell access |
| `db shell --write` | BLOCKED | No write access |
| `db query "<SQL>"` | HUMAN_REQUIRED | Logged, requires approval |
| `db status` | SAFE | Read-only |
| `seed [name]` | BLOCKED | No seed in prod (default) |
| `script <name>` | BLOCKED | Uses exec tier |
| `fetch <svc> <path>` | BLOCKED | Uses exec tier |
| `cleanup [logs]` | SAFE | Cleanup always allowed |
| `env check` | SAFE | Read-only |
| `env list` | SAFE | Secrets masked |
| `env set KEY=VALUE` | HUMAN_REQUIRED | Config changes need approval |
| `env diff` | SAFE | Read-only |

**Key Principle:** If it could lose data, expose data, or cause an outage, it's BLOCKED or HUMAN_REQUIRED.

---

## Command Comparison Table

| Command | Dev | Prod |
|---------|-----|------|
| `status` | SAFE | SAFE |
| `health` | SAFE | SAFE |
| `logs` | SAFE | SAFE |
| `disk` | SAFE | SAFE |
| `worker status` | SAFE | SAFE |
| `build` | SAFE | SAFE |
| `deploy` | SAFE | HUMAN_REQUIRED |
| `ship` | SAFE | HUMAN_REQUIRED |
| `restart` | SAFE | HUMAN_REQUIRED |
| `stop` | SAFE | BLOCKED |
| `start` | SAFE | HUMAN_REQUIRED |
| `shell` | SAFE | BLOCKED |
| `exec` | SAFE | BLOCKED |
| `rollback` | SAFE | HUMAN_REQUIRED |
| `db migrate` | SAFE | HUMAN_REQUIRED |
| `db rollback` | SAFE | HUMAN_REQUIRED/BLOCKED |
| `db backup` | SAFE | SAFE |
| `db restore` | SAFE | BLOCKED |
| `db shell` | SAFE | BLOCKED |
| `db shell --write` | MODERATE | BLOCKED |
| `db query` | SAFE | HUMAN_REQUIRED |
| `db status` | SAFE | SAFE |
| `seed` | SAFE | BLOCKED |
| `script` | SAFE | BLOCKED |
| `fetch` | SAFE | BLOCKED |
| `cleanup` | SAFE | SAFE |
| `env check` | SAFE | SAFE |
| `env list` | SAFE | SAFE |
| `env set` | SAFE | HUMAN_REQUIRED |
| `env diff` | SAFE | SAFE |

---

## Human Approval Workflow

For HUMAN_REQUIRED operations in interactive mode, ops.sh prompts the operator to type the project name to confirm:

```bash
# Example: restart in prod
myapp --env prod restart backend
# [WARN] Action: restart backend [HUMAN_REQUIRED]
# This action requires human approval.
# Type the project name (myapp) to confirm: myapp
# [OK] Restart initiated
```

For MODERATE operations, a simple `y/N` confirmation is prompted:

```bash
myapp --env dev db shell --write
# [WARN] Action: db shell --write [MODERATE]
# Proceed? (y/N) y
```

In non-interactive mode (e.g., piped or scripted), MODERATE exits with code 2 and HUMAN_REQUIRED exits with code 3 — no bypass flags exist.

---

## Audit Trail

All operations are logged to `~/.tim-ops/audit.log`:

```text
# Format: timestamp user project env command result
2026-01-17T10:30:00Z tim jamphoria dev deploy START
2026-01-17T10:30:45Z tim jamphoria dev deploy OK
2026-01-17T15:00:00Z tim jamphoria prod shell BLOCKED
```

---

## Compliance Checklist

- [ ] All commands have defined tiers for all environments
- [ ] BLOCKED operations exit with code 1
- [ ] MODERATE denied exits with code 2 (non-interactive)
- [ ] HUMAN_REQUIRED denied exits with code 3 (non-interactive)
- [ ] All operations are logged to audit trail
- [ ] Environment isolation prevents cross-environment access
