# TIM Environment Configuration Standard

All TIM projects must define environments using a standardized `environments.yaml` configuration file. This document specifies the schema, connection methods, and remote types supported.

## Core Principles

1. **Remote-first** - All standard environments (dev, uat, prod) run on remote servers. Local is opt-in.
2. **Environment isolation** - Each environment is completely isolated. Dev cannot access UAT or Prod.
3. **Single configuration file** - One `environments.yaml` defines all environments for a project.
4. **Never in git** - `environments.yaml` must be in `.gitignore`. Contains sensitive connection details.
5. **Human approval for local** - Local development requires explicit human approval via `tim-local-dev-enable`.

## File Location and Security

```text
project/
    ├── ops-config.yaml             # Committed - namespace and alias config
    └── (ops.sh lives in infra repo, accessed via alias)
```

**Security Requirements:**

- Kubeconfig permissions: `600` (owner read/write only)
- Never commit real hostnames, IPs, or credentials
- Use k8s Secrets for sensitive values

## Configuration Schema

### Full Example

```yaml
# ops-config.yaml - Project ops configuration (committed to repo)

version: "2.0"
project: "your-project-name"
alias: "myapp"  # Shell alias for ops.sh invocation

environments:
  dev:
    description: "Development environment for rapid iteration"
    type: "k8s"
    namespace: "myapp-dev"
    deploy:
      method: "argocd"
      app: "myapp-dev"

  uat:
    description: "User acceptance testing environment"
    type: "k8s"
    namespace: "myapp-uat"
    deploy:
      method: "argocd"
      app: "myapp-uat"

  prod:
    description: "Production environment - EXTREME CAUTION"
    type: "k8s"
    namespace: "myapp-prod"
    deploy:
      method: "argocd"
      app: "myapp-prod"
    protections:
      require_approval: true
      require_ticket: true
      backup_before_deploy: true
      canary_required: true
```

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Schema version (currently "1.0") |
| `project` | string | Project name (used in paths and logging) |
| `environments` | object | Map of environment name to configuration |

### Environment Configuration

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `description` | string | Yes | Human-readable description |
| `type` | string | Yes | Environment type (`k8s`, `local`) |
| `namespace` | string | Yes (k8s) | Kubernetes namespace |
| `deploy` | object | No | Deployment method configuration |
| `protections` | object | No | Additional safety rules (typically for prod) |

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

### Local Configuration

The local environment can be configured in `ops-config.yaml`, though this is optional:

```yaml
environments:
  local:
    description: "Local development environment"
    type: "local"
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
2. **RBAC role** — assigned per namespace (dev/uat/prod)
3. **ops.sh alias** — configured via shell profile

```bash
# Shell profile (~/.bashrc or ~/.zshrc)
# Aliases are generated from ops-config.yaml by the infra repo setup
alias myapp="/path/to/infra/ops.sh --project myapp"
```

## Deployment Method

### ArgoCD (Default)

All deployments are handled by ArgoCD, not ops.sh directly:

1. GHA builds container image on push/merge
2. ArgoCD detects manifest or image changes in the infra repo
3. ArgoCD syncs the k8s namespace automatically

ops.sh is for operational commands only (logs, status, shell, db operations).

## Isolation Configuration

Network and data isolation prevents cross-environment contamination.

**How Isolation is Enforced:**

1. k8s namespaces are environment-specific (dev, uat, prod)
2. NetworkPolicies deny cross-namespace traffic by default
3. RBAC roles restrict access per namespace
4. Separate kubeconfig contexts per environment (recommended)

## Protection Settings

Additional safety rules, typically for production.

```yaml
protections:
  require_approval: true      # Human approval for all operations
  require_ticket: true        # Ticket number required (e.g., JIRA-123)
  backup_before_deploy: true  # Automatic backup before deploy
  canary_required: true       # Canary deployment mandatory
```

**Enforcement:**

- If `require_approval: true`, all MODERATE+ commands become HUMAN_REQUIRED
- If `require_ticket: true`, commands fail without `--ticket PROJ-123`
- If `backup_before_deploy: true`, `db:backup` runs automatically before deploy
- If `canary_required: true`, deploys start at 10% traffic

## Environment Variable Substitution

Use `${VAR}` syntax for values that vary by operator or machine:

```yaml
connection:
  key_file: "${HOME}/.ssh/deploy_key"    # Expands to user's home
  user: "${DEPLOY_USER:-deploy}"         # Default value if not set

remote:
  path: "/opt/apps/${PROJECT}/prod"      # Uses project name
```

**Supported Variables:**

- `${HOME}` - User's home directory
- `${USER}` - Current username
- `${PROJECT}` - Project name from config
- `${ENV_NAME}` - Any environment variable
- `${VAR:-default}` - Default value syntax

## Operator Onboarding

New operators follow this process:

1. **Get kubeconfig from cluster admin:**

   ```bash
   # Place kubeconfig and set permissions
   cp kubeconfig-from-admin ~/.kube/config
   chmod 600 ~/.kube/config
   ```

2. **Set up ops.sh alias:**

   ```bash
   # Add to shell profile
   alias myapp="/path/to/infra/ops.sh --project myapp"
   ```

3. **Verify connectivity:**

   ```bash
   myapp --env dev status
   ```

## Access Levels

Operators only get credentials for environments they need:

| Role | Local | Dev | UAT | Prod |
|------|-------|-----|-----|------|
| Developer | Self-enable* | Yes | No | No |
| QA Engineer | Self-enable* | Yes | Yes | No |
| Tech Lead | Self-enable* | Yes | Yes | No |
| DevOps/SRE | Self-enable* | Yes | Yes | Yes |
| On-call Engineer | No | No | No | Yes (read-only) |

*Local requires running `tim-local-dev-enable` (human only, AI cannot)

## Validation

ops.sh validates `ops-config.yaml` on every command:

```bash
# Validation checks:
# 1. ops-config.yaml exists and is readable
# 2. YAML syntax is valid
# 3. Required fields present (project, alias, namespace)
# 4. Specified environment exists
# 5. Local environment has human approval (if --env local)

myapp --env dev status
# OK: Environment 'dev' loaded (namespace: myapp-dev)

myapp --env staging status
# ERROR: Environment 'staging' not found in ops-config.yaml

myapp --env local status
# ERROR: LOCAL DEVELOPMENT NOT ENABLED
# To enable: tim-local-dev-enable --project .
```

## Compliance Checklist

- [ ] `ops-config.yaml` committed with project, alias, and namespace config
- [ ] Kubeconfig permissions are `600`
- [ ] All three remote environments defined (dev, uat, prod) with namespaces
- [ ] Local environment is optional (requires human approval to use)
- [ ] Prod has `protections` section configured
- [ ] RBAC roles configured per namespace
- [ ] ArgoCD Application configured per environment
- [ ] `tim-local-dev-enable` tool is available for human opt-in
