# TIM Ops Script Standard

All TIM projects use a standardized `ops.sh` deployment interface. This document defines the required commands, safety model, and implementation pattern.

## Architecture: Shared Library Model

```
tim-ops-lib (central repository)
    │
    ├── tim-ops-lib.sh          # Core library - shared by all projects
    │
    └── Updates flow to all projects via git submodule or direct sync

project/
    │
    ├── ops.sh                  # Project wrapper - sources tim-ops-lib
    ├── ops-config.yaml         # Project-specific configuration
    └── ops-hooks/              # Optional project-specific hooks
        ├── pre-deploy.sh
        ├── post-deploy.sh
        └── custom-commands.sh
```

## Required Commands

Every TIM project ops.sh must implement these commands with identical behavior:

### Deployment Commands

| Command | Safety Tier | Description |
|---------|-------------|-------------|
| `ops.sh deploy` | MODERATE | Smart deploy (detect changes, rebuild as needed) |
| `ops.sh deploy --sync-only` | SAFE | Sync files without rebuild |
| `ops.sh deploy --force` | PROTECTED | Force full rebuild |
| `ops.sh rollback` | PROTECTED | Rollback to previous deployment |
| `ops.sh rollback --version <tag>` | PROTECTED | Rollback to specific version |

### Status Commands

| Command | Safety Tier | Description |
|---------|-------------|-------------|
| `ops.sh status` | SAFE | Show deployment status |
| `ops.sh health` | SAFE | Run health checks |
| `ops.sh logs` | SAFE | Tail application logs |
| `ops.sh logs --service <name>` | SAFE | Tail specific service logs |

### Database Commands

| Command | Safety Tier | Description |
|---------|-------------|-------------|
| `ops.sh db:migrate` | MODERATE | Run pending migrations |
| `ops.sh db:migrate --dry-run` | SAFE | Preview migrations |
| `ops.sh db:rollback` | PROTECTED | Rollback last migration |
| `ops.sh db:backup` | SAFE | Create database backup |
| `ops.sh db:restore <file>` | BLOCKED | Restore from backup (requires confirmation) |

### Maintenance Commands

| Command | Safety Tier | Description |
|---------|-------------|-------------|
| `ops.sh shell` | MODERATE | Open shell in container |
| `ops.sh restart` | MODERATE | Restart services |
| `ops.sh stop` | PROTECTED | Stop all services |
| `ops.sh destroy` | BLOCKED | Remove all containers/data |

## Safety Tier Model

### SAFE (Exit Code: 0)
- Read-only operations
- No confirmation required
- Can be scripted freely

### MODERATE (Exit Code: 0 with warnings)
- Makes changes but recoverable
- Logs all actions
- May prompt for confirmation in interactive mode

### PROTECTED (Exit Code: 2 without --confirm)
- Potentially destructive
- Requires `--confirm` flag or interactive confirmation
- Logged with timestamp and user

### BLOCKED (Exit Code: 3)
- Extremely dangerous
- Requires `--confirm --i-understand-this-is-dangerous`
- Sends alert to team channel
- Logged with full audit trail

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Requires confirmation (PROTECTED) |
| 3 | Blocked operation (BLOCKED) |
| 4 | Configuration error |
| 5 | Health check failed |
| 6 | Migration failed |

## Configuration (ops-config.yaml)

```yaml
# ops-config.yaml - Project-specific configuration
project:
  name: "jamphoria"
  environment: "production"  # production, staging, development

remote:
  host: "192.168.86.14"
  user: "tim"
  path: "/home/tim/apps/jamphoria-v2"
  ssh_key: "~/.ssh/id_rsa"  # Optional

services:
  backend:
    container: "jamphoria-v2"
    port: 5002
    health_endpoint: "/health"
    dockerfile: "backend/Dockerfile"
    watch_paths:
      - "backend/app/**/*.py"
      - "backend/requirements.txt"
      - "backend/Dockerfile"

  frontend:
    container: "jamphoria-v2-frontend"
    port: 3000
    health_endpoint: "/"
    dockerfile: "frontend/Dockerfile"
    watch_paths:
      - "frontend/src/**/*.ts"
      - "frontend/src/**/*.tsx"
      - "frontend/package.json"
      - "frontend/Dockerfile"

  worker:
    container: "jamphoria-v2-worker"
    dockerfile: "backend/Dockerfile"
    # No health endpoint - background worker

database:
  type: "postgresql"
  container: "jamphoria-v2-db"
  migration_command: "alembic upgrade head"
  rollback_command: "alembic downgrade -1"
  backup_path: "/backups"

docker:
  compose_file: "docker/docker-compose.v2.yml"

deploy:
  strategy: "rolling"  # rolling, blue-green, recreate
  health_timeout: 60   # seconds to wait for healthy
  rollback_on_failure: true

notifications:
  slack_webhook: "${SLACK_WEBHOOK_URL}"  # Optional
  on_deploy: true
  on_failure: true
  on_rollback: true
```

## Implementation Pattern

### Project ops.sh (Wrapper)

```bash
#!/usr/bin/env bash
# ops.sh - Project deployment script
# Sources tim-ops-lib for core functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Source the shared TIM ops library
# Option 1: Git submodule
# source "$PROJECT_ROOT/lib/tim-ops/tim-ops-lib.sh"

# Option 2: Direct path (if ops lib is installed system-wide)
# source "/usr/local/lib/tim-ops/tim-ops-lib.sh"

# Option 3: Download on first run
TIM_OPS_LIB="${TIM_OPS_LIB:-$PROJECT_ROOT/.tim-ops/tim-ops-lib.sh}"
if [[ ! -f "$TIM_OPS_LIB" ]]; then
    echo "Downloading tim-ops-lib..."
    mkdir -p "$(dirname "$TIM_OPS_LIB")"
    curl -sSL "https://raw.githubusercontent.com/your-org/tim-ops/main/tim-ops-lib.sh" \
        -o "$TIM_OPS_LIB"
fi
source "$TIM_OPS_LIB"

# Load project configuration
load_config "$PROJECT_ROOT/ops-config.yaml"

# Project-specific hooks (optional)
if [[ -d "$PROJECT_ROOT/ops-hooks" ]]; then
    for hook in "$PROJECT_ROOT/ops-hooks"/*.sh; do
        [[ -f "$hook" ]] && source "$hook"
    done
fi

# Run the command
tim_ops_main "$@"
```

### Custom Hooks

Projects can extend ops.sh with custom commands via hooks:

```bash
# ops-hooks/custom-commands.sh

# Register custom command
register_command "analyze" "SAFE" "Run audio analysis on test files"

cmd_analyze() {
    local service="${1:-backend}"
    log_info "Running analysis tests..."
    docker exec "$PROJECT_NAME-$service" python -m pytest tests/analysis/
}

# Hook into deploy lifecycle
hook_pre_deploy() {
    log_info "Running pre-deploy checks..."
    # Custom validation
}

hook_post_deploy() {
    log_info "Running post-deploy tasks..."
    # Cache warming, etc.
}
```

## Change Detection

The library implements smart change detection to minimize rebuild time:

```bash
# Checks file modification times against last deploy
# Only rebuilds services with changed files

deploy_smart() {
    local changed_services=()

    for service in "${SERVICES[@]}"; do
        if files_changed_since_deploy "$service"; then
            changed_services+=("$service")
        fi
    done

    if [[ ${#changed_services[@]} -eq 0 ]]; then
        log_info "No changes detected"
        return 0
    fi

    log_info "Rebuilding: ${changed_services[*]}"
    for service in "${changed_services[@]}"; do
        rebuild_service "$service"
    done
}
```

## Logging and Audit Trail

All operations are logged with:
- Timestamp
- User (from $USER or git config)
- Command executed
- Exit code
- Duration

```
# ~/.tim-ops/audit.log
2025-01-15T10:30:00Z | tim | jamphoria | deploy | SUCCESS | 45s
2025-01-15T11:00:00Z | tim | jamphoria | db:migrate | SUCCESS | 3s
2025-01-15T14:22:00Z | tim | jamphoria | rollback --confirm | SUCCESS | 12s
```

## Health Check Protocol

Standard health check sequence:

```bash
health_check() {
    local timeout="${HEALTH_TIMEOUT:-60}"
    local interval=5
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if all_services_healthy; then
            log_success "All services healthy"
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        log_info "Waiting for health... ${elapsed}s/${timeout}s"
    done

    log_error "Health check timeout"
    return 5
}

all_services_healthy() {
    for service in "${SERVICES[@]}"; do
        local endpoint=$(get_health_endpoint "$service")
        [[ -z "$endpoint" ]] && continue

        local url="http://${REMOTE_HOST}:$(get_port "$service")${endpoint}"
        if ! curl -sf "$url" > /dev/null 2>&1; then
            return 1
        fi
    done
    return 0
}
```

## Rollback Strategy

Automatic rollback on deployment failure:

```bash
deploy_with_rollback() {
    # Save current state
    local previous_commit=$(get_deployed_commit)

    # Attempt deployment
    if ! deploy_services; then
        log_error "Deployment failed, initiating rollback"
        rollback_to "$previous_commit"
        notify_failure "Deployment failed, rolled back to $previous_commit"
        return 1
    fi

    # Health check
    if ! health_check; then
        log_error "Health check failed, initiating rollback"
        rollback_to "$previous_commit"
        notify_failure "Health check failed, rolled back to $previous_commit"
        return 5
    fi

    log_success "Deployment complete"
    notify_success "Deployed $(get_current_commit)"
}
```

## Integration with CI/CD

ops.sh is designed to be called from CI pipelines:

```yaml
# .github/workflows/deploy.yml
deploy:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v4

    - name: Deploy to staging
      env:
        SSH_PRIVATE_KEY: ${{ secrets.SSH_KEY }}
      run: |
        ./ops.sh deploy --environment staging --confirm

    - name: Run integration tests
      run: |
        ./ops.sh health --environment staging
        npm run test:integration

    - name: Deploy to production
      if: github.ref == 'refs/heads/main'
      run: |
        ./ops.sh deploy --environment production --confirm
```

## Compliance Checklist

For a project to be TIM-compliant, its ops.sh must:

- [ ] Source tim-ops-lib.sh (not copy/paste)
- [ ] Have ops-config.yaml with all required fields
- [ ] Implement all required commands
- [ ] Respect safety tiers
- [ ] Log all operations to audit trail
- [ ] Support `--help` for all commands
- [ ] Support `--dry-run` for destructive commands
- [ ] Pass ops.sh self-test: `./ops.sh test`
