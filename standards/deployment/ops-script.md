# TIM Ops Script Standard

Modular, config-driven operational CLI for Kubernetes workloads. ops.sh is the sole interface for all TIM projects running on k8s — handling both operations (status, logs, shell, db) and deployment (build, deploy, ship).

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
            deploy.sh        # Build (kaniko), deploy (kustomize), ship

project-repo/
    ops-config.yaml          # Project-specific configuration (only file needed)
    k8s/                     # Kubernetes manifests (kustomize base + overlays)
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
  namespaces:
    dev: "<namespace-dev>"
    prod: "<namespace-prod>"

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

build:
  registry: "<in-cluster-registry>"
  git_url: "<repo-url>"
  git_secret: "<k8s-secret-name>"
  source_registry: "<source-registry>"  # Optional, default: ghcr.io/schreyack
  branches:
    dev: "<branch>"
    prod: "<branch>"
  services:
    <service-name>:
      context: "<build-context>"
      dockerfile: "<dockerfile-path>"
      image_name: "<image-name>"        # Optional, default: <project>-<service>

tiers:
  dev:
    restart: "SAFE"
    stop: "SAFE"
    shell: "SAFE"
    "db:migrate": "SAFE"
    "db:rollback": "SAFE"
    # ... per-command overrides
  prod:
    restart: "HUMAN_REQUIRED"
    stop: "BLOCKED"
    shell: "BLOCKED"
    "db:migrate": "HUMAN_REQUIRED"
    "db:rollback": "BLOCKED"
```

---

## Commands

### Status and Monitoring

| Command | Description |
|---------|-------------|
| `status` | Show pods, services, and deployments |
| `health` | Pod readiness + health endpoint checks |
| `logs <service> [-f] [--tail N]` | Tail service logs |
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
| `cleanup [logs]` | Delete completed pods + old ReplicaSets; `logs` truncates node logs |

### Build and Deploy

| Command | Description |
|---------|-------------|
| `build <service\|all>` | Build image(s) via kaniko Job (in-cluster) |
| `deploy [sha]` | Update kustomize overlay, run migrations, apply manifests, wait for rollouts |
| `ship` | Preflight checks + build all + deploy + health check + commit overlay |

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
| `seed [name]` | Run configured seed command in pod (default: test) |
| `script <name>` | Execute allowlisted script in pod |
| `fetch <service> <path>` | Copy file from pod (path validated against allowlist) |

---

## Safety Tiers

### SAFE

- Read-only operations (status, health, logs, backup, backup:list)
- No confirmation required
- Can be scripted freely

### MODERATE

- Makes changes but recoverable (restart, deploy, db migrate)
- Logged with audit trail
- Prompts for confirmation (`y/N`) in interactive mode
- Non-interactive: exits with code 2

### HUMAN_REQUIRED

- Potentially destructive (rollback, stop, db rollback)
- AI cannot bypass — requires human to type the project name to confirm
- Logged with timestamp and user

### BLOCKED

- Extremely dangerous or not permitted (db restore in prod, shell in prod)
- Hard deny — no flags or workarounds bypass this
- Exits with code 1

### Tier Resolution Precedence

1. **Command-level override** — e.g., `seed.test.tier.dev = "SAFE"`
2. **Global tiers section** — e.g., `tiers.dev.restart = "SAFE"`
3. **Default** — `MODERATE` (if no tier defined for a command + environment)

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error / BLOCKED |
| 2 | MODERATE action denied (non-interactive mode) |
| 3 | HUMAN_REQUIRED action denied (non-interactive mode) |

---

## Deploy Model

ops.sh handles the full build-deploy lifecycle using kaniko for in-cluster image builds.

### Build (`build <service|all>`)

1. ops.sh copies the GitHub PAT secret from the `registry` namespace to the target namespace (if not present)
2. Creates a k8s Job with an init container (`alpine/git`) that clones the repo using `x-access-token` authentication
3. The kaniko container builds from the cloned workspace and pushes to the in-cluster registry
4. Waits for the Job to complete (timeout: 10 minutes)

### Deploy (`deploy [sha]`)

1. Updates kustomize overlay with new image tags (SHA-based)
2. Runs migration Job if `database.migration_command` is configured
3. Applies manifests via `kustomize build | kubectl apply`
4. Waits for all deployment rollouts to complete

### Ship (`ship`)

End-to-end deployment with safety checks:

1. **Preflight**: Verify clean working tree, HEAD pushed to remote, not detached HEAD
2. **Build**: `build all`
3. **Deploy**: `deploy` with current HEAD SHA
4. **Health check**: Verify all services with health endpoints respond
5. **Commit overlay**: Stage and push `k8s/overlays/<env>/kustomization.yaml` to git

**Branch-to-environment mapping** is configured per project:

```yaml
build:
  branches:
    dev: "dev"      # dev environment builds from dev branch
    prod: "main"    # prod environment builds from main branch
```

**Image tag strategy:** Short git SHA ensures every deploy is traceable. The kustomize overlay records the deployed image tags.

---

## Dependencies

| Tool | Version | Purpose |
|------|---------|---------|
| yq | v4+ (Go version, NOT Python wrapper) | Config loading from ops-config.yaml |
| kubectl | Latest stable | All k8s operations |
| kustomize | Latest stable | Manifest rendering for deploys |
| jq | Latest | Secret manipulation (credential provisioning) |
| mc | Latest (MinIO client) | Backup/restore to object storage |
| kubeconfig | N/A | `~/.kube/config` must exist and be valid |
| ssh | N/A | Node-level operations only (log truncation, disk checks) |

**Preflight checks** (run on every invocation):

- `yq` exists and reports v4+
- `kubectl`, `kustomize`, and `jq` exist
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
