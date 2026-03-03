# TIM Ops Script Standard

Modular, config-driven operational CLI for Kubernetes workloads. ops.sh is the sole operational interface for all TIM projects running on k8s. Deploys are handled separately by CI/CD (GHA + ArgoCD) — ops.sh covers everything else.

**CRITICAL**: The `--env` flag is REQUIRED for every command. See `standards/deployment/remote-only.md` for the policy and `standards/deployment/environments.md` for configuration.

## Architecture

```text
infra-repo/
    ops/
        ops.sh              # Entry point: config loader, dispatch, core framework
        modules/
            commands.sh      # Status, logs, shell, exec, restart, stop, start, etc.
            db.sh            # Backup, restore, migrate, rollback, shell, query
            env.sh           # Check, list, set, diff

project-repo/
    ops-config.yaml          # Project-specific configuration (only file needed)
    k8s/                     # Kubernetes manifests (ArgoCD syncs these)
```

**No ops.sh copies in project repos.** ops.sh lives only in the infra repo. Projects provide only `ops-config.yaml`. Access via shell aliases:

```bash
alias myapp="~/infra/ops/ops.sh --config ~/myapp/ops-config.yaml"
myapp --env dev status
myapp --env prod db backup
```

### Config-Driven Feature Gating

Features are enabled by the presence of their config section. If a section is absent, its commands are hidden from help and return "not configured" if invoked.

---

## ops-config.yaml Schema

```yaml
project:
  name: "<project>"
  namespace: "<namespace>"

cluster:
  control_plane: "<ip>"
  control_plane_user: "<user>"
  ssh_key: "~/.ssh/id_rsa"

services:
  <service-name>:
    deployment: "<k8s-deployment-name>"
    type: "Deployment"            # Deployment or StatefulSet
    port: 8000                    # Container port
    health_endpoint: "/health"    # Optional
    aliases: ["api", "server"]    # Optional shorthand names

database:
  type: "postgresql"
  statefulset: "<statefulset-name>"
  service: "<k8s-service-name>"
  user: "<db-user>"
  name: "<db-name>"
  migration_command: "<cmd>"
  migration_service: "<service>"
  rollback_command: "<cmd>"       # Optional

backup:
  minio_bucket: "<bucket-name>"
  minio_alias: "minio"
  gpg_recipient: "<key-id>"      # Optional — enables GPG encryption
  uploads_pvc: "<pvc-name>"      # Optional — enables file backup commands
  uploads_mount_path: "/app/uploads"

workers:
  queue_name: "<queue>"
  redis_service: "redis"
  scaledobject: "<scaledobject-name>"

seed:
  <seed-name>:
    service: "<service>"
    command: "<cmd>"
    tier: { dev: "SAFE", prod: "BLOCKED" }

env:
  template_path: "<path>"        # Relative to project root
  configmap: "<configmap-name>"
  secret: "<secret-name>"

scripts:
  allowed: ["<script-1>", "<script-2>"]
  service: "<service>"

fetch:
  allowed_paths: ["logs", "tmp"]

tiers:
  dev:
    restart: "SAFE"
    stop: "SAFE"
    shell: "SAFE"
    "db:migrate": "SAFE"
    "db:rollback": "SAFE"
    "db:restore": "SAFE"
    "db:query": "SAFE"
  prod:
    restart: "HUMAN_REQUIRED"
    stop: "BLOCKED"
    shell: "BLOCKED"
    "db:migrate": "HUMAN_REQUIRED"
    "db:rollback": "BLOCKED"
    "db:restore": "BLOCKED"
    "db:query": "HUMAN_REQUIRED"
```

---

## Commands

### Status and Monitoring

| Command | Description |
|---------|-------------|
| `status` | Show pods, services, and deployments |
| `health` | Pod readiness + health endpoint checks |
| `logs <service>` | Tail logs (`-f` for follow, `--tail N`) |
| `disk` | Show PVC disk usage per service |
| `worker status` | KEDA ScaledObject status, replica counts, queue depth |
| `version` | Show ops.sh version |
| `help` | Auto-generated command list |

### Service Management

| Command | Description |
|---------|-------------|
| `restart <service\|all>` | Rolling restart via `kubectl rollout restart` |
| `stop <service\|all>` | Scale to 0 replicas (Deployments only, not StatefulSets) |
| `start <service\|all>` | Scale to 1 replica (restore after stop) |
| `rollback` | `kubectl rollout undo` (dev only; prod = revert git commit) |
| `shell <service>` | Interactive shell in pod |
| `exec <service> <cmd>` | Run command in pod |
| `cleanup` | Delete completed pods + old ReplicaSets |
| `cleanup logs` | Truncate container logs on node (requires SSH) |

### Database

| Command | Description |
|---------|-------------|
| `db backup` | pg_dump to MinIO (optional GPG encryption) |
| `db backup:list` | List backups in MinIO bucket |
| `db restore <file>` | Auto-backup-first, then restore from MinIO |
| `db migrate` | Run migration command via kubectl exec |
| `db rollback` | Run rollback command via kubectl exec |
| `db shell [--write]` | psql session (read-only by default; `--write` triggers auto-backup) |
| `db query "<SQL>"` | SQL validation + execution via `psql -c` |
| `db status` | Database connection stats |
| `files backup` | Tar uploads PVC to MinIO (requires `backup.uploads_pvc`) |
| `files restore <file>` | Restore uploads from MinIO |

### Environment

| Command | Description |
|---------|-------------|
| `env check` | Validate ConfigMap/Secret against env template |
| `env list` | List vars from ConfigMap/Secret (secrets masked) |
| `env set KEY=VALUE` | Update var + rollout restart affected deployments |
| `env diff` | Compare template vs actual values |

### Other

| Command | Description |
|---------|-------------|
| `seed [name]` | Run configured seed command in pod |
| `script <name>` | Execute allowlisted script in pod |
| `fetch <service> <path>` | Copy file from pod (path validated against allowlist) |

---

## Safety Tiers

### SAFE

- Read-only operations (status, health, logs, backup, backup:list)
- No confirmation required
- Can be scripted freely

### MODERATE

- Makes changes but recoverable (restart, deploy, db:migrate)
- Logged with audit trail
- Prompts for confirmation in interactive mode
- Non-interactive: exits with code 2 if `--confirm` not passed

### HUMAN_REQUIRED

- Potentially destructive (rollback, stop, db:rollback)
- AI cannot bypass — requires human approval workflow
- Logged with timestamp, user, and approver

### BLOCKED

- Extremely dangerous (destroy, db:restore in prod)
- Requires `--confirm --i-understand-this-is-dangerous`
- Logged with full audit trail

### Tier Resolution Precedence

1. **Command-level override** — e.g., `seed.test.tier.dev = "SAFE"`
2. **Global tiers section** — e.g., `tiers.dev.restart = "SAFE"`
3. **Default** — `MODERATE` (if no tier defined for a command + environment)

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Requires confirmation (MODERATE in non-interactive mode) |
| 3 | Requires human approval (HUMAN_REQUIRED/BLOCKED) |
| 4 | Configuration error |
| 5 | Health check failed |
| 6 | Migration failed |

---

## Deploy Model

ops.sh does **not** handle deploys. Deployment is fully automated:

1. Developer pushes to a mapped branch (e.g., `dev`, `main`)
2. GHA workflow triggers, builds container images for changed services
3. GHA pushes images to container registry (tag = full git SHA)
4. ArgoCD detects new image tags via Image Updater
5. ArgoCD runs PreSync hook (migration Job) if configured
6. ArgoCD applies updated Deployments with new image tags
7. k8s rolls out new pods; readiness probes gate traffic

**Branch-to-environment mapping:**

- `dev` branch deploys to dev namespace
- `main` branch deploys to prod namespace

**Image tag strategy:** Full git SHA ensures every deploy is traceable. Rollback = ArgoCD reverts to previous image tag. Kustomize image transformer rewrites tags at sync time.

**Manual sync (escape hatch):**

```bash
argocd app sync <project>-<env>
```

**Migration ordering:** Migrations run pre-deploy (PreSync hook) because new code often requires new schema. Additive migrations are safe with old code if deploy fails after migration.

---

## Dependencies

| Tool | Version | Purpose |
|------|---------|---------|
| yq | v4+ (Go version, NOT Python wrapper) | Config loading from ops-config.yaml |
| kubectl | Latest stable | All k8s operations |
| mc | Latest (MinIO client) | Backup/restore to object storage |
| kubeconfig | N/A | `~/.kube/config` must exist and be valid |
| ssh | N/A | Node-level operations only (log truncation, disk checks) |

**Preflight checks** (run on every invocation):

- `yq` exists and reports v4+
- kubeconfig exists and `kubectl cluster-info` succeeds
- SSH connectivity to control plane (warn-only — only needed for node-level commands)

---

## Security

### Shell Injection Protection

All user-supplied arguments (service names, SQL queries, env values, script names) must be double-quoted in shell commands. Never use unquoted variables.

- Service names and script names validated against config-defined allowlists
- `exec` and `script` commands use `--` to separate kubectl options from user arguments
- `env set` validates KEY format (`^[A-Z_][A-Z0-9_]*$`) before passing to kubectl

### SQL Validation

`db query` blocks dangerous patterns:

- `DELETE`/`UPDATE` without `WHERE`
- `DROP`, `TRUNCATE`, `ALTER`, `COPY`, `CREATE FUNCTION`
- Multi-statement (`;` separator)

All queries execute via `psql -c` (single-statement mode) to prevent semicolon injection. `SELECT` and `EXPLAIN` are always SAFE tier.

### Path Traversal Protection

`fetch` command rejects paths containing `..` and validates against `fetch.allowed_paths` after normalization. Uses `kubectl exec tar` (which does not follow symlinks by default) instead of `kubectl cp`.

### Audit Logging

All operations logged to `~/.tim-ops/audit.log`:

```text
<ISO-8601> <user> <project> <env> <command> <result>
```

Format: one line per invocation with timestamp, user, project, environment, full command, and exit status.
