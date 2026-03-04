# TIM Environment Configuration Standard

All TIM projects define environments via `ops-config.yaml`. This document specifies the schema, access patterns, and environment conventions.

## Core Principles

1. **Remote-first** - All standard environments (dev, prod) run on a remote k8s cluster. Local is opt-in.
2. **Environment isolation** - Each environment has its own namespace. No cross-environment access.
3. **Single configuration file** - One `ops-config.yaml` defines all settings for a project.
4. **Human approval for local** - Local development requires explicit human approval via `tim-local-dev-enable`.

## File Location

```text
project/
    └── ops-config.yaml     # Committed — project config (namespace, services, build, tiers)
    └── (ops.sh lives in infra repo, accessed via alias)
```

**Security Requirements:**

- Kubeconfig permissions: `600` (owner read/write only)
- Never commit real hostnames, IPs, or credentials
- Use k8s Secrets for sensitive values

## Configuration Schema

### Full Example

```yaml
# ops-config.yaml — committed to project repo

project:
  name: "myapp"
  namespaces:
    dev: "myapp-dev"
    prod: "myapp-prod"

cluster:
  control_plane: "192.168.1.100"
  control_plane_user: "deploy"
  ssh_key: "~/.ssh/id_rsa"

services:
  backend:
    deployment: "myapp-backend"
    type: "Deployment"
    port: 8000
    health_endpoint: "/health"
    aliases: ["server", "api"]
  frontend:
    deployment: "myapp-frontend"
    type: "Deployment"
    port: 3000
    health_endpoint: "/"
    aliases: ["client", "web"]

database:
  type: "postgresql"
  statefulset: "myapp-db"
  service: "myapp-db"
  user: "myapp"
  name: "myapp"
  migration_command: "alembic upgrade head"
  migration_service: "backend"
  rollback_command: "alembic downgrade -1"

backup:
  minio_bucket: "myapp-backups"
  minio_alias: "minio"

build:
  registry: "registry.registry.svc.cluster.local:5000"
  git_url: "https://github.com/org/myapp.git"
  git_secret: "github-pat"
  branches:
    dev: "dev"
    prod: "main"
  services:
    backend:
      context: "backend"
      dockerfile: "backend/Dockerfile"
    frontend:
      context: "frontend"
      dockerfile: "frontend/Dockerfile"

tiers:
  dev:
    restart: "SAFE"
    stop: "SAFE"
    shell: "SAFE"
    exec: "SAFE"
    build: "SAFE"
    deploy: "SAFE"
    "db:migrate": "SAFE"
    "db:rollback": "SAFE"
    "db:restore": "SAFE"
    "db:shell": "SAFE"
    "db:shell:write": "MODERATE"
    "db:query": "SAFE"
  prod:
    restart: "HUMAN_REQUIRED"
    stop: "BLOCKED"
    shell: "BLOCKED"
    exec: "BLOCKED"
    build: "SAFE"
    deploy: "HUMAN_REQUIRED"
    "db:migrate": "HUMAN_REQUIRED"
    "db:rollback": "BLOCKED"
    "db:restore": "BLOCKED"
    "db:shell": "BLOCKED"
    "db:shell:write": "BLOCKED"
    "db:query": "HUMAN_REQUIRED"
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `project.name` | string | Project name (used in paths, logging, image names) |
| `project.namespaces.<env>` | string | Kubernetes namespace per environment |

### Optional Sections

Each section enables its associated commands. If absent, those commands return "not configured."

| Section | Enables |
|---------|---------|
| `cluster` | SSH-based node operations (cleanup logs, disk) |
| `services` | Service-aware commands (logs, restart, shell, health) |
| `database` | All `db` commands |
| `backup` | Backup/restore operations |
| `build` | Build, deploy, and ship commands |
| `workers` | Worker status command |
| `seed` | Seed commands |
| `env` | Environment variable management |
| `scripts` | Script execution |
| `fetch` | File fetch from pods |
| `tiers` | Per-command safety tier overrides |

## Local Environment (Optional)

Local development is disabled by default but can be enabled by a human for specific projects.

### Enabling Local Development

```bash
# Human must run (AI cannot):
tim-local-dev-enable --project /path/to/project

# Check status
tim-local-dev-enable --check --project /path/to/project

# Revoke
tim-local-dev-enable --revoke --project /path/to/project
```

### Local Behavior

| Aspect | Behavior |
|--------|----------|
| Connection method | Direct local access |
| Command tiers | All SAFE (no restrictions) |
| Approval required | Yes, via `tim-local-dev-enable` |
| AI can enable | No (multiple bypass prevention layers) |

### Storage

Local development approvals are stored in `~/.tim-ops/local-dev-approvals/` with one file per project. Operations are logged to `~/.tim-ops/local-dev-audit.log`.

## Cluster Access

ops.sh accesses the k8s cluster via kubeconfig. Each operator needs:

1. **kubeconfig** — provided by cluster admin, stored at `~/.kube/config`
2. **RBAC role** — assigned per namespace (dev/prod)
3. **ops.sh alias** — configured via shell profile

### Alias Setup

Aliases are generated from `.tim-projects` by the `ops-aliases` command in the infra repo:

```bash
# .tim-projects defines project paths and names
# ops-aliases reads .tim-projects and generates shell aliases
# Result added to shell profile:
alias myapp="/path/to/infra/ops/ops.sh --config /path/to/myapp/ops-config.yaml"
```

Usage:

```bash
myapp --env dev status
myapp --env prod db backup
```

## Deployment Method

All deployments are handled by ops.sh using kaniko for in-cluster builds:

1. `build <svc|all>` — creates a kaniko Job that clones the repo (via init container with GitHub PAT) and builds + pushes images to the in-cluster registry
2. `deploy [sha]` — updates kustomize overlay image tags, runs migrations if configured, applies manifests, waits for rollouts
3. `ship` — runs preflight checks, build, deploy, health verification, and commits the overlay change to git

No external CI/CD, no external registries, no webhooks. The full pipeline runs from the operator's machine via ops.sh.

## Isolation Configuration

Network and data isolation prevents cross-environment contamination.

**How Isolation is Enforced:**

1. k8s namespaces are environment-specific (dev, prod)
2. NetworkPolicies deny cross-namespace traffic by default
3. RBAC roles restrict access per namespace
4. Separate kubeconfig contexts per environment (recommended)

## Access Levels

Operators only get credentials for environments they need:

| Role | Local | Dev | Prod |
|------|-------|-----|------|
| Developer | Self-enable* | Yes | No |
| Tech Lead | Self-enable* | Yes | No |
| DevOps/SRE | Self-enable* | Yes | Yes |

*Local requires running `tim-local-dev-enable` (human only, AI cannot)

## Validation

ops.sh validates `ops-config.yaml` on every command:

```bash
# Validation checks:
# 1. ops-config.yaml exists and is readable
# 2. YAML syntax is valid (yq v4+ required)
# 3. project.name is set
# 4. project.namespaces.<env> is set for the specified --env
# 5. kubectl cluster-info succeeds

myapp --env dev status
# [INFO] Status for myapp (dev)

myapp --env staging status
# [ERROR] project.namespaces.staging not set in config
```

## Compliance Checklist

- [ ] `ops-config.yaml` committed with project name and namespace config
- [ ] Kubeconfig permissions are `600`
- [ ] Both dev and prod namespaces defined
- [ ] Tiers section defines safety levels for all environments
- [ ] ops.sh alias configured via ops-aliases
- [ ] `tim-local-dev-enable` tool available for human opt-in
