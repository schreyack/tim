# TIM Environment Configuration Standard

All TIM projects must define environments using a standardized `environments.yaml` configuration file. This document specifies the schema, connection methods, and remote types supported.

## Core Principles

1. **Remote-first** - All standard environments (dev, uat, prod) run on remote servers. Local is opt-in.
2. **Environment isolation** - Each environment is completely isolated. Dev cannot access UAT or Prod.
3. **Single configuration file** - One `environments.yaml` defines all environments for a project.
4. **Never in git** - `environments.yaml` must be in `.gitignore`. Contains sensitive connection details.
5. **Human approval for local** - Local development requires explicit human approval via `tim-local-dev-enable`.

## File Location and Security

```
project/
    ├── environments.yaml           # NEVER committed - in .gitignore
    ├── environments.yaml.example   # Committed - shows structure without real values
    └── ops.sh                      # Uses environments.yaml
```

**Security Requirements:**
- `environments.yaml` permissions: `600` (owner read/write only)
- Never commit real hostnames, IPs, or credentials
- Use `${ENV_VAR}` syntax for values that vary by operator

## Configuration Schema

### Full Example

```yaml
# environments.yaml - Remote Environment Configuration
# DO NOT COMMIT THIS FILE - add to .gitignore

version: "1.0"
project: "your-project-name"

environments:
  dev:
    description: "Development environment for rapid iteration"
    host: "dev.example.com"
    connection:
      method: "ssh"
      user: "deploy"
      port: 22
      key_file: "${HOME}/.ssh/dev_deploy_key"
    remote:
      type: "docker-compose"
      path: "/opt/apps/${PROJECT}/dev"
      compose_file: "docker-compose.dev.yml"
    isolation:
      network: "dev-network"
      data_prefix: "dev_"
      allowed_cidrs: ["10.0.1.0/24"]

  uat:
    description: "User acceptance testing environment"
    host: "uat.example.com"
    connection:
      method: "ssh"
      user: "deploy"
      port: 22
      key_file: "${HOME}/.ssh/uat_deploy_key"
    remote:
      type: "docker-compose"
      path: "/opt/apps/${PROJECT}/uat"
      compose_file: "docker-compose.uat.yml"
    isolation:
      network: "uat-network"
      data_prefix: "uat_"
      allowed_cidrs: ["10.0.2.0/24"]

  prod:
    description: "Production environment - EXTREME CAUTION"
    host: "prod.example.com"
    connection:
      method: "ssh"
      user: "deploy"
      port: 22
      key_file: "${HOME}/.ssh/prod_deploy_key"
    remote:
      type: "docker-compose"
      path: "/opt/apps/${PROJECT}/prod"
      compose_file: "docker-compose.prod.yml"
    isolation:
      network: "prod-network"
      data_prefix: "prod_"
      allowed_cidrs: ["10.0.3.0/24"]
    protections:
      require_approval: true
      require_ticket: true
      backup_before_deploy: true
      canary_required: true

  # Optional: Local development (requires human approval to use)
  # local:
  #   description: "Local development environment"
  #   connection:
  #     method: "local"
  #   remote:
  #     type: "docker-compose"
  #     compose_file: "docker-compose.local.yml"
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
| `host` | string | Yes | Hostname or IP address |
| `connection` | object | Yes | Connection method configuration |
| `remote` | object | Yes | Remote execution environment |
| `isolation` | object | No | Network and data isolation settings |
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

The local environment can be configured in `environments.yaml`, though this is optional:

```yaml
environments:
  local:
    description: "Local development environment"
    connection:
      method: "local"  # Special method for local execution
    remote:
      type: "docker-compose"
      compose_file: "docker-compose.local.yml"  # Defaults to this if not specified
```

### Local Behavior

| Aspect | Behavior |
|--------|----------|
| Connection method | Direct Docker access (no SSH) |
| File sync | Not needed (already local) |
| Command tiers | All SAFE (no restrictions) |
| Compose file | `docker-compose.local.yml` (fallback: `docker-compose.yml`) |
| Approval required | Yes, via `tim-local-dev-enable` |
| AI can enable | No (multiple bypass prevention layers) |

### Storage

Local development approvals are stored in `~/.tim-ops/local-dev-approvals/` with one file per project. Operations are logged to `~/.tim-ops/local-dev-audit.log`.

## Connection Methods

### SSH (Recommended)

Standard SSH connection. Most common for self-hosted infrastructure.

```yaml
connection:
  method: "ssh"
  user: "deploy"              # Required: SSH username
  port: 22                    # Optional: SSH port (default: 22)
  key_file: "${HOME}/.ssh/deploy_key"  # Required: Path to private key
```

**With Bastion/Jump Host:**

```yaml
connection:
  method: "ssh"
  user: "deploy"
  port: 22
  key_file: "${HOME}/.ssh/deploy_key"
  jump_host: "bastion.example.com"    # Jump through this host
  jump_user: "jump"                    # Username on jump host
  jump_port: 22                        # Optional: Jump host port
  jump_key: "${HOME}/.ssh/bastion_key" # Key for jump host
```

### AWS Systems Manager (SSM)

Keyless access through AWS IAM. Recommended for AWS infrastructure.

```yaml
connection:
  method: "ssm"
  instance_id: "i-0123456789abcdef"  # Required: EC2 instance ID
  region: "us-east-1"                # Required: AWS region
  profile: "production"              # Optional: AWS CLI profile
```

**Requirements:**
- AWS CLI v2 installed
- Session Manager plugin installed
- IAM permissions for `ssm:StartSession`
- SSM Agent running on target instance

### Google Cloud SSH

Access through gcloud CLI. Recommended for GCP infrastructure.

```yaml
connection:
  method: "gcloud"
  project: "my-gcp-project"   # Required: GCP project ID
  zone: "us-central1-a"       # Required: Compute zone
  instance: "prod-server"     # Required: Instance name
```

**Requirements:**
- gcloud CLI installed and authenticated
- IAM permissions for compute instance access
- OS Login enabled (recommended)

### Azure Bastion

Access through Azure CLI. Recommended for Azure infrastructure.

```yaml
connection:
  method: "azure"
  resource_group: "my-rg"              # Required: Resource group
  vm_name: "prod-vm"                   # Required: VM name
  subscription: "xxx-xxx-xxx-xxx"      # Optional: Subscription ID
```

**Requirements:**
- Azure CLI installed and authenticated
- Azure Bastion configured for the VNet
- RBAC permissions for VM access

## Remote Types

### Docker Compose (Default)

Most common for single-server deployments.

```yaml
remote:
  type: "docker-compose"
  path: "/opt/apps/project"           # Required: Deployment directory
  compose_file: "docker-compose.yml"  # Optional: Compose file name
  project_name: "myproject"           # Optional: Docker project name
```

**Generated Commands:**
- `docker compose -f <compose_file> up -d`
- `docker compose -f <compose_file> logs`
- `docker compose -f <compose_file> ps`

### Kubernetes

For Kubernetes cluster deployments.

```yaml
remote:
  type: "kubernetes"
  namespace: "production"                    # Required: K8s namespace
  context: "prod-cluster"                    # Optional: kubectl context
  kubeconfig: "/etc/kubernetes/admin.conf"   # Optional: Kubeconfig path
  manifests_path: "k8s/"                     # Optional: Path to manifests
```

**Generated Commands:**
- `kubectl apply -f <manifests_path>`
- `kubectl rollout status deployment/<name>`
- `kubectl logs -n <namespace>`

### AWS ECS

For Amazon ECS deployments.

```yaml
remote:
  type: "ecs"
  cluster: "prod-cluster"              # Required: ECS cluster name
  service: "api-service"               # Required: Service name
  region: "us-east-1"                  # Required: AWS region
  task_definition: "api-task:latest"   # Optional: Task definition
```

**Generated Commands:**
- `aws ecs update-service --force-new-deployment`
- `aws ecs describe-services`
- `aws logs tail`

### Google Cloud Run

For Cloud Run deployments.

```yaml
remote:
  type: "cloud-run"
  project: "my-gcp-project"   # Required: GCP project
  region: "us-central1"       # Required: Region
  service: "api-service"      # Required: Service name
```

**Generated Commands:**
- `gcloud run deploy`
- `gcloud run services describe`
- `gcloud logging read`

## Isolation Configuration

Network and data isolation prevents cross-environment contamination.

```yaml
isolation:
  network: "prod-network"         # Docker network name
  data_prefix: "prod_"            # Database/table prefix
  allowed_cidrs: ["10.0.3.0/24"]  # Allowed source IPs
```

**How Isolation is Enforced:**
1. Docker networks are environment-specific (no cross-network communication)
2. Database names/tables use environment prefix
3. SSH gateway validates source IP against allowed CIDRs
4. Separate SSH keys per environment (cannot use dev key for prod)

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

Since `environments.yaml` is not in git, new operators follow this process:

1. **Copy the example file:**
   ```bash
   cp environments.yaml.example environments.yaml
   chmod 600 environments.yaml
   ```

2. **Request credentials from team lead:**
   - SSH key for each environment needed
   - Or cloud CLI access (AWS/GCP/Azure)

3. **Configure SSH keys:**
   ```bash
   # Dev only (developers)
   ssh-keygen -t ed25519 -f ~/.ssh/dev_deploy_key

   # UAT (QA team)
   ssh-keygen -t ed25519 -f ~/.ssh/uat_deploy_key

   # Prod (DevOps/SRE only)
   ssh-keygen -t ed25519 -f ~/.ssh/prod_deploy_key
   ```

4. **Verify connectivity:**
   ```bash
   ./ops.sh --env dev status
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

ops.sh validates `environments.yaml` on every command:

```bash
# Validation checks:
# 1. File exists and is readable
# 2. YAML syntax is valid
# 3. Required fields present
# 4. Connection method is supported
# 5. Remote type is supported
# 6. Specified environment exists
# 7. Local environment has human approval (if --env local)

./ops.sh --env dev status
# OK: Environment 'dev' loaded from environments.yaml

./ops.sh --env staging status
# ERROR: Environment 'staging' not found in environments.yaml

./ops.sh --env local status
# ERROR: LOCAL DEVELOPMENT NOT ENABLED
# To enable: tim-local-dev-enable --project .

# After human enables local dev:
./ops.sh --env local status
# OK: Environment 'local' (direct Docker access)
```

## Compliance Checklist

- [ ] `environments.yaml` exists (not committed to git)
- [ ] `environments.yaml.example` committed (without real values)
- [ ] `.gitignore` includes `environments.yaml`
- [ ] File permissions are `600`
- [ ] All three remote environments defined (dev, uat, prod)
- [ ] Local environment is optional (requires human approval to use)
- [ ] Prod has `protections` section configured
- [ ] Separate SSH keys per environment
- [ ] `docker-compose.local.yml` is gitignored (if used)
- [ ] `tim-local-dev-enable` tool is available for human opt-in
