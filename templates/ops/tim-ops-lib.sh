#!/usr/bin/env bash
# tim-ops-lib.sh - TIM Operations Library
# Shared deployment operations for all TIM projects
#
# VERSION: 2.0.0
# SOURCE: https://github.com/your-org/design_standards/templates/ops/tim-ops-lib.sh
#
# PHILOSOPHY: Operations are either ALLOWED or require HUMAN APPROVAL.
# There are NO bypass flags. AI developers cannot override safety checks.
# If an operation needs to happen and is blocked, a human must approve it
# through the approval workflow.
#
# Usage: Source this file from your project's ops.sh wrapper
#   source "/path/to/tim-ops-lib.sh"
#   load_config "ops-config.yaml"
#   tim_ops_main "$@"

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

TIM_OPS_VERSION="3.0.0"
TIM_OPS_AUDIT_LOG="${TIM_OPS_AUDIT_LOG:-$HOME/.tim-ops/audit.log}"
TIM_OPS_STATE_DIR="${TIM_OPS_STATE_DIR:-$HOME/.tim-ops/state}"
TIM_OPS_APPROVAL_DIR="${TIM_OPS_APPROVAL_DIR:-$HOME/.tim-ops/approvals}"

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

# Safety tiers - NO BYPASS OPTIONS
# SAFE: Always allowed
# MODERATE: Allowed with warning logged
# HUMAN_REQUIRED: Requires pre-approved human authorization
# BLOCKED: Never allowed through ops.sh (manual intervention only)
declare -A SAFETY_TIERS=(
    [SAFE]=0
    [MODERATE]=1
    [HUMAN_REQUIRED]=2
    [BLOCKED]=3
)

# Registered commands: command -> "TIER|description"
declare -A COMMANDS=()

# Project configuration (loaded from ops-config.yaml)
declare -A CONFIG=()
declare -a SERVICES=()

# Environment configuration (loaded from environments.yaml)
declare -A ENV_CONFIG=()
CURRENT_ENV=""

# Per-environment command tier matrix
# Format: ENV:COMMAND -> TIER
# This implements the command-matrix.md specification
declare -A ENV_COMMAND_TIERS=(
    # DEV - Permissive (sandbox)
    ["dev:status"]="SAFE"
    ["dev:health"]="SAFE"
    ["dev:logs"]="SAFE"
    ["dev:deploy"]="SAFE"
    ["dev:deploy:force"]="SAFE"
    ["dev:deploy:sync"]="SAFE"
    ["dev:restart"]="SAFE"
    ["dev:stop"]="SAFE"
    ["dev:shell"]="SAFE"
    ["dev:exec"]="SAFE"
    ["dev:db:migrate"]="SAFE"
    ["dev:db:migrate:dry"]="SAFE"
    ["dev:db:rollback"]="SAFE"
    ["dev:db:backup"]="SAFE"
    ["dev:db:restore"]="SAFE"
    ["dev:db:seed"]="SAFE"
    ["dev:db:reset"]="SAFE"
    ["dev:env:get"]="SAFE"
    ["dev:env:set"]="SAFE"
    ["dev:rollback"]="SAFE"

    # UAT - Moderate restrictions
    ["uat:status"]="SAFE"
    ["uat:health"]="SAFE"
    ["uat:logs"]="SAFE"
    ["uat:deploy"]="MODERATE"
    ["uat:deploy:force"]="HUMAN_REQUIRED"
    ["uat:deploy:sync"]="MODERATE"
    ["uat:restart"]="MODERATE"
    ["uat:stop"]="HUMAN_REQUIRED"
    ["uat:shell"]="MODERATE"
    ["uat:exec"]="MODERATE"
    ["uat:db:migrate"]="MODERATE"
    ["uat:db:migrate:dry"]="SAFE"
    ["uat:db:rollback"]="HUMAN_REQUIRED"
    ["uat:db:backup"]="SAFE"
    ["uat:db:restore"]="HUMAN_REQUIRED"
    ["uat:db:seed"]="HUMAN_REQUIRED"
    ["uat:db:reset"]="BLOCKED"
    ["uat:env:get"]="SAFE"
    ["uat:env:set"]="HUMAN_REQUIRED"
    ["uat:rollback"]="HUMAN_REQUIRED"

    # PROD - Maximum restrictions
    ["prod:status"]="SAFE"
    ["prod:health"]="SAFE"
    ["prod:logs"]="SAFE"
    ["prod:deploy"]="HUMAN_REQUIRED"
    ["prod:deploy:force"]="BLOCKED"
    ["prod:deploy:sync"]="HUMAN_REQUIRED"
    ["prod:restart"]="HUMAN_REQUIRED"
    ["prod:stop"]="BLOCKED"
    ["prod:shell"]="BLOCKED"
    ["prod:exec"]="BLOCKED"
    ["prod:db:migrate"]="HUMAN_REQUIRED"
    ["prod:db:migrate:dry"]="SAFE"
    ["prod:db:rollback"]="BLOCKED"
    ["prod:db:backup"]="SAFE"
    ["prod:db:restore"]="BLOCKED"
    ["prod:db:seed"]="BLOCKED"
    ["prod:db:reset"]="BLOCKED"
    ["prod:env:get"]="MODERATE"
    ["prod:env:set"]="BLOCKED"
    ["prod:rollback"]="HUMAN_REQUIRED"
)

# =============================================================================
# LOGGING
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    [[ "${DEBUG:-0}" == "1" ]] && echo -e "[DEBUG] $*"
}

# =============================================================================
# AUDIT LOGGING
# =============================================================================

audit_log() {
    local command="$1"
    local result="$2"
    local duration="${3:-0}"

    mkdir -p "$(dirname "$TIM_OPS_AUDIT_LOG")"

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local user="${USER:-unknown}"
    local project="${CONFIG[project_name]:-unknown}"

    echo "$timestamp | $user | $project | $command | $result | ${duration}s" >> "$TIM_OPS_AUDIT_LOG"
}

# =============================================================================
# CONFIGURATION LOADING
# =============================================================================

load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        exit 4
    fi

    # Parse YAML (basic parser - for complex configs, consider yq)
    local current_section=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Detect section headers (no leading whitespace, ends with :)
        if [[ "$line" =~ ^([a-z_]+):$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi

        # Parse key: value pairs
        if [[ "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Remove quotes
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"

            # Expand environment variables
            value=$(eval echo "$value")

            if [[ -n "$current_section" ]]; then
                CONFIG["${current_section}_${key}"]="$value"
            else
                CONFIG["$key"]="$value"
            fi
        fi
    done < "$config_file"

    # Extract service names
    SERVICES=($(grep -E "^  [a-z_]+:$" "$config_file" 2>/dev/null | sed 's/://g' | tr -d ' ' || true))

    # Set convenience variables
    PROJECT_NAME="${CONFIG[project_name]:-}"
    REMOTE_HOST="${CONFIG[remote_host]:-}"
    REMOTE_USER="${CONFIG[remote_user]:-}"
    REMOTE_PATH="${CONFIG[remote_path]:-}"
    COMPOSE_FILE="${CONFIG[docker_compose_file]:-docker-compose.yml}"

    log_debug "Loaded config: PROJECT_NAME=$PROJECT_NAME, REMOTE_HOST=$REMOTE_HOST"
}

# =============================================================================
# ENVIRONMENT LOADING (environments.yaml)
# =============================================================================
#
# Loads environment-specific configuration from environments.yaml
# This file is NOT in git - each operator maintains their own copy
# See: standards/deployment/environments.md

load_environment() {
    local env_name="$1"
    local env_file="${PROJECT_ROOT:-$(pwd)}/environments.yaml"

    # Validate environment name
    if [[ ! "$env_name" =~ ^(dev|uat|prod)$ ]]; then
        log_error "Invalid environment: $env_name"
        log_error "Valid environments: dev, uat, prod"
        return 1
    fi

    # Check environments.yaml exists
    if [[ ! -f "$env_file" ]]; then
        log_error "environments.yaml not found at: $env_file"
        log_error ""
        log_error "This file is required but NOT committed to git."
        log_error "To set up:"
        log_error "  1. Copy environments.yaml.example to environments.yaml"
        log_error "  2. Configure with real connection details"
        log_error "  3. chmod 600 environments.yaml"
        log_error ""
        log_error "See: standards/deployment/environments.md"
        return 4
    fi

    # Check file permissions (should be 600)
    local perms
    if [[ "$(uname)" == "Darwin" ]]; then
        perms=$(stat -f "%Lp" "$env_file" 2>/dev/null || echo "000")
    else
        perms=$(stat -c "%a" "$env_file" 2>/dev/null || echo "000")
    fi
    if [[ "$perms" != "600" ]]; then
        log_warn "environments.yaml has permissions $perms (should be 600)"
        log_warn "Fix with: chmod 600 environments.yaml"
    fi

    CURRENT_ENV="$env_name"

    # Parse environment section from YAML
    # This is a simple parser - for complex YAML, use yq
    local in_env_section=false
    local in_target_env=false
    local current_subsection=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Detect environments: section
        if [[ "$line" == "environments:" ]]; then
            in_env_section=true
            continue
        fi

        # Only process if in environments section
        if [[ "$in_env_section" == "true" ]]; then
            # Detect target environment (e.g., "  dev:")
            if [[ "$line" =~ ^[[:space:]]{2}([a-z]+):$ ]]; then
                local env_key="${BASH_REMATCH[1]}"
                if [[ "$env_key" == "$env_name" ]]; then
                    in_target_env=true
                else
                    in_target_env=false
                fi
                continue
            fi

            # If in target environment, parse its contents
            if [[ "$in_target_env" == "true" ]]; then
                # Detect subsection (e.g., "    connection:")
                if [[ "$line" =~ ^[[:space:]]{4}([a-z_]+):$ ]]; then
                    current_subsection="${BASH_REMATCH[1]}"
                    continue
                fi

                # Parse key: value pairs
                if [[ "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(.*)$ ]]; then
                    local key="${BASH_REMATCH[1]}"
                    local value="${BASH_REMATCH[2]}"

                    # Remove quotes
                    value="${value#\"}"
                    value="${value%\"}"
                    value="${value#\'}"
                    value="${value%\'}"

                    # Expand environment variables
                    value=$(eval echo "$value" 2>/dev/null || echo "$value")

                    # Store with subsection prefix
                    if [[ -n "$current_subsection" ]]; then
                        ENV_CONFIG["${current_subsection}_${key}"]="$value"
                    else
                        ENV_CONFIG["$key"]="$value"
                    fi
                fi
            fi
        fi
    done < "$env_file"

    # Set convenience variables from loaded environment
    REMOTE_HOST="${ENV_CONFIG[host]:-}"
    REMOTE_USER="${ENV_CONFIG[connection_user]:-}"
    REMOTE_PATH="${ENV_CONFIG[remote_path]:-}"
    SSH_KEY_FILE="${ENV_CONFIG[connection_key_file]:-}"
    CONNECTION_METHOD="${ENV_CONFIG[connection_method]:-ssh}"

    if [[ -z "$REMOTE_HOST" ]]; then
        log_error "Environment '$env_name' not found or missing 'host' in environments.yaml"
        return 4
    fi

    log_debug "Loaded environment: $env_name (host=$REMOTE_HOST, user=$REMOTE_USER)"
    log_info "Environment: ${BOLD}$env_name${NC} ($REMOTE_HOST)"
}

# Get tier for command based on current environment
get_env_tier() {
    local command="$1"
    local env="${CURRENT_ENV:-}"

    if [[ -z "$env" ]]; then
        log_error "No environment set. Use --env flag."
        return 1
    fi

    local tier_key="${env}:${command}"
    local tier="${ENV_COMMAND_TIERS[$tier_key]:-}"

    # If no specific tier defined, fall back to command's default tier
    if [[ -z "$tier" ]]; then
        local cmd_info="${COMMANDS[$command]:-}"
        if [[ -n "$cmd_info" ]]; then
            tier="${cmd_info%%|*}"
        else
            tier="BLOCKED"  # Unknown commands are blocked by default
        fi
    fi

    echo "$tier"
}

# =============================================================================
# SECURITY VERIFICATION
# =============================================================================
#
# Runs security checks before operations. Blocks on violations.
# See: standards/deployment/ops-security.md

verify_security() {
    local verify_script="${PROJECT_ROOT:-$(pwd)}/scripts/verify-ops-security.sh"

    # Also check in templates location
    if [[ ! -f "$verify_script" ]]; then
        verify_script="${PROJECT_ROOT:-$(pwd)}/verify-ops-security.sh"
    fi

    if [[ ! -f "$verify_script" ]]; then
        log_warn "Security verification script not found"
        log_warn "Recommended: Add scripts/verify-ops-security.sh from design_standards"
        return 0  # Warning only if script missing
    fi

    log_info "Running security verification..."

    if ! bash "$verify_script"; then
        log_error "============================================================"
        log_error "SECURITY VERIFICATION FAILED"
        log_error "============================================================"
        log_error ""
        log_error "Operations are BLOCKED until security issues are resolved."
        log_error "Run: ./scripts/verify-ops-security.sh --fix"
        log_error ""
        log_error "============================================================"
        return 10
    fi

    log_success "Security verification passed"
    return 0
}

# =============================================================================
# HUMAN APPROVAL SYSTEM
# =============================================================================
#
# HUMAN_REQUIRED operations cannot be executed directly by AI developers.
# Instead, they must:
# 1. Request approval (creates a ticket file)
# 2. A human reviews the request and creates an approval token
# 3. The operation can then execute with the valid approval token
#
# Approval tokens are one-time use and expire after 1 hour.

request_human_approval() {
    local command="$1"
    local reason="$2"
    local project="${CONFIG[project_name]:-unknown}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local request_id=$(date +%s)-$$-$RANDOM

    mkdir -p "$TIM_OPS_APPROVAL_DIR/pending"

    local request_file="$TIM_OPS_APPROVAL_DIR/pending/${project}_${command//:/--}_${request_id}.request"

    cat > "$request_file" << EOF
# Human Approval Request
# Generated: $timestamp
# Project: $project
# Command: $command
# Request ID: $request_id

reason: |
  $reason

requested_by: ${USER:-unknown}
requested_at: $timestamp
expires_at: $(date -u -d '+1 hour' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -v+1H +"%Y-%m-%dT%H:%M:%SZ")

# To approve this request, a human must:
# 1. Review the reason and verify it's appropriate
# 2. Run: tim-ops-approve $request_id
# OR
# 3. Create file: $TIM_OPS_APPROVAL_DIR/approved/${request_id}.approval
#    with content: APPROVED_BY=<your_email>
EOF

    echo "$request_id"
    log_info "Approval request created: $request_file"
    log_info "Request ID: $request_id"
}

check_human_approval() {
    local command="$1"
    local request_id="${2:-}"

    # If no request ID provided, check for any valid approval for this command
    if [[ -z "$request_id" ]]; then
        local project="${CONFIG[project_name]:-unknown}"
        local approval_pattern="$TIM_OPS_APPROVAL_DIR/approved/${project}_${command//:/--}_*.approval"

        # Find most recent valid approval
        local approval_file=$(ls -t $approval_pattern 2>/dev/null | head -1)
        if [[ -z "$approval_file" ]]; then
            return 1
        fi
        request_id=$(basename "$approval_file" .approval | sed "s/${project}_${command//:/--}_//")
    fi

    local approval_file="$TIM_OPS_APPROVAL_DIR/approved/${request_id}.approval"

    if [[ ! -f "$approval_file" ]]; then
        return 1
    fi

    # Check expiration
    local expires_at=$(grep "^expires_at:" "$approval_file" 2>/dev/null | cut -d: -f2- | tr -d ' ')
    if [[ -n "$expires_at" ]]; then
        local expires_epoch=$(date -d "$expires_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expires_at" +%s 2>/dev/null || echo 0)
        local now_epoch=$(date +%s)
        if [[ $now_epoch -gt $expires_epoch ]]; then
            log_warn "Approval token expired"
            rm -f "$approval_file"
            return 1
        fi
    fi

    # Check if already used
    if grep -q "^used: true" "$approval_file" 2>/dev/null; then
        log_warn "Approval token already used"
        return 1
    fi

    # Mark as used
    echo "used: true" >> "$approval_file"
    echo "used_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$approval_file"

    local approved_by=$(grep "^APPROVED_BY=" "$approval_file" | cut -d= -f2)
    log_info "Using approval from: $approved_by"
    audit_log "$command" "HUMAN_APPROVED_BY:$approved_by" "0"

    return 0
}

# =============================================================================
# SAFETY CHECKS - NO BYPASS FLAGS
# =============================================================================

check_safety() {
    local tier="$1"
    local command="$2"

    case "$tier" in
        SAFE)
            return 0
            ;;
        MODERATE)
            log_warn "This operation will make changes"
            audit_log "$command" "MODERATE_EXECUTED" "0"
            return 0
            ;;
        HUMAN_REQUIRED)
            # Check for valid human approval
            if check_human_approval "$command"; then
                log_info "Human approval verified"
                return 0
            fi

            # No bypass - request approval and block
            log_error "============================================================"
            log_error "HUMAN APPROVAL REQUIRED"
            log_error "============================================================"
            log_error ""
            log_error "This operation ($command) requires human approval."
            log_error "AI developers cannot execute this operation directly."
            log_error ""
            log_error "To proceed:"
            log_error "  1. A human must review why this operation is needed"
            log_error "  2. The human runs: tim-ops-approve <request_id>"
            log_error "  3. Then retry this command"
            log_error ""

            # Create approval request
            local request_id=$(request_human_approval "$command" "Requested via ops.sh")

            log_error "Approval request created: $request_id"
            log_error ""
            log_error "============================================================"

            audit_log "$command" "BLOCKED_NEEDS_APPROVAL:$request_id" "0"
            notify_alert "Human approval requested: $command (request: $request_id)"
            return 2
            ;;
        BLOCKED)
            # These operations are NEVER allowed through ops.sh
            # They require manual intervention outside the ops.sh system
            log_error "============================================================"
            log_error "OPERATION BLOCKED"
            log_error "============================================================"
            log_error ""
            log_error "This operation ($command) is blocked in ops.sh."
            log_error ""
            log_error "These operations are too dangerous for automated execution."
            log_error "They must be performed manually by a human with direct access."
            log_error ""
            log_error "If you need to perform this operation:"
            log_error "  1. SSH directly to the server"
            log_error "  2. Execute the commands manually"
            log_error "  3. Document why it was necessary"
            log_error ""
            log_error "============================================================"

            audit_log "$command" "BLOCKED_NEVER_ALLOWED" "0"
            notify_alert "BLOCKED operation attempted: $command"
            return 3
            ;;
    esac
}

# =============================================================================
# REMOTE EXECUTION
# =============================================================================

ssh_cmd() {
    local cmd="$1"
    local ssh_opts="-o BatchMode=yes -o ConnectTimeout=10"

    if [[ -n "${CONFIG[remote_ssh_key]:-}" ]]; then
        ssh_opts="$ssh_opts -i ${CONFIG[remote_ssh_key]}"
    fi

    ssh $ssh_opts "${REMOTE_USER}@${REMOTE_HOST}" "$cmd"
}

rsync_files() {
    local src="$1"
    local dest="$2"
    local rsync_opts="-avz --delete --exclude='.git' --exclude='node_modules' --exclude='__pycache__' --exclude='.env'"

    if [[ -n "${CONFIG[remote_ssh_key]:-}" ]]; then
        rsync_opts="$rsync_opts -e 'ssh -i ${CONFIG[remote_ssh_key]}'"
    fi

    eval rsync $rsync_opts "$src" "${REMOTE_USER}@${REMOTE_HOST}:$dest"
}

# =============================================================================
# DOCKER OPERATIONS
# =============================================================================

docker_compose() {
    local action="$1"
    shift

    ssh_cmd "cd $REMOTE_PATH && docker compose -f $COMPOSE_FILE $action $*"
}

get_container_status() {
    local service="$1"
    local container="${PROJECT_NAME}-${service}"

    ssh_cmd "docker inspect -f '{{.State.Status}}' $container 2>/dev/null" || echo "not found"
}

# =============================================================================
# CHANGE DETECTION
# =============================================================================

get_last_deploy_time() {
    local state_file="$TIM_OPS_STATE_DIR/${PROJECT_NAME}/last_deploy"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo "0"
    fi
}

save_deploy_time() {
    local state_dir="$TIM_OPS_STATE_DIR/${PROJECT_NAME}"
    mkdir -p "$state_dir"
    date +%s > "$state_dir/last_deploy"
    git rev-parse HEAD 2>/dev/null > "$state_dir/last_commit" || true
}

get_deployed_commit() {
    local state_file="$TIM_OPS_STATE_DIR/${PROJECT_NAME}/last_commit"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo ""
    fi
}

files_changed_since_deploy() {
    local service="$1"
    local last_deploy=$(get_last_deploy_time)

    local service_dir="${service}"
    [[ "$service" == "backend" ]] && service_dir="backend"
    [[ "$service" == "frontend" ]] && service_dir="frontend"

    if [[ -d "$PROJECT_ROOT/$service_dir" ]]; then
        local changed=$(find "$PROJECT_ROOT/$service_dir" -type f -newer "$TIM_OPS_STATE_DIR/${PROJECT_NAME}/last_deploy" 2>/dev/null | head -1)
        [[ -n "$changed" ]]
    else
        return 1
    fi
}

# =============================================================================
# HEALTH CHECKS
# =============================================================================

check_service_health() {
    local service="$1"
    local port="${CONFIG[services_${service}_port]:-}"
    local endpoint="${CONFIG[services_${service}_health_endpoint]:-}"

    if [[ -z "$port" ]] || [[ -z "$endpoint" ]]; then
        log_debug "No health check configured for $service"
        return 0
    fi

    local url="http://${REMOTE_HOST}:${port}${endpoint}"
    log_debug "Checking health: $url"

    if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

wait_for_healthy() {
    local timeout="${CONFIG[deploy_health_timeout]:-60}"
    local interval=5
    local elapsed=0

    log_info "Waiting for services to be healthy (timeout: ${timeout}s)..."

    while [[ $elapsed -lt $timeout ]]; do
        local all_healthy=true

        for service in "${SERVICES[@]}"; do
            if ! check_service_health "$service"; then
                all_healthy=false
                break
            fi
        done

        if $all_healthy; then
            log_success "All services healthy"
            return 0
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
        log_info "Waiting... ${elapsed}s/${timeout}s"
    done

    log_error "Health check timeout after ${timeout}s"
    return 5
}

# =============================================================================
# NOTIFICATIONS
# =============================================================================

notify_success() {
    local message="$1"

    if [[ -n "${CONFIG[notifications_slack_webhook]:-}" ]] && [[ "${CONFIG[notifications_on_deploy]:-}" == "true" ]]; then
        curl -sf -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\":white_check_mark: ${PROJECT_NAME}: ${message}\"}" \
            "${CONFIG[notifications_slack_webhook]}" > /dev/null 2>&1 || true
    fi
}

notify_failure() {
    local message="$1"

    if [[ -n "${CONFIG[notifications_slack_webhook]:-}" ]] && [[ "${CONFIG[notifications_on_failure]:-}" == "true" ]]; then
        curl -sf -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\":x: ${PROJECT_NAME}: ${message}\"}" \
            "${CONFIG[notifications_slack_webhook]}" > /dev/null 2>&1 || true
    fi
}

notify_alert() {
    local message="$1"

    if [[ -n "${CONFIG[notifications_slack_webhook]:-}" ]]; then
        curl -sf -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\":rotating_light: ALERT ${PROJECT_NAME}: ${message}\"}" \
            "${CONFIG[notifications_slack_webhook]}" > /dev/null 2>&1 || true
    fi
}

# =============================================================================
# CORE COMMANDS
# =============================================================================

register_command() {
    local name="$1"
    local tier="$2"
    local description="$3"

    COMMANDS["$name"]="${tier}|${description}"
}

# Register default commands with appropriate safety tiers
# SAFE: Read-only or low-risk operations
# MODERATE: Operations that make changes (deploys, restarts)
# HUMAN_REQUIRED: Destructive operations that need human approval
# BLOCKED: Never allowed through ops.sh

register_command "deploy" "MODERATE" "Deploy application (smart rebuild)"
register_command "deploy:force" "MODERATE" "Force full rebuild and deploy"
register_command "deploy:sync" "SAFE" "Sync files only (no rebuild)"
register_command "rollback" "HUMAN_REQUIRED" "Rollback to previous deployment"
register_command "status" "SAFE" "Show deployment status"
register_command "health" "SAFE" "Check service health"
register_command "logs" "SAFE" "View application logs"
register_command "db:migrate" "MODERATE" "Run database migrations"
register_command "db:migrate:dry" "SAFE" "Preview database migrations"
register_command "db:rollback" "HUMAN_REQUIRED" "Rollback last migration"
register_command "db:backup" "SAFE" "Backup database"
register_command "db:restore" "BLOCKED" "Restore database from backup"
register_command "shell" "MODERATE" "Open shell in container"
register_command "restart" "MODERATE" "Restart services"
register_command "stop" "HUMAN_REQUIRED" "Stop all services"
register_command "destroy" "BLOCKED" "Remove all containers and data"
register_command "test" "SAFE" "Run ops.sh self-test"
register_command "help" "SAFE" "Show this help message"
register_command "version" "SAFE" "Show version information"
register_command "approval:list" "SAFE" "List pending approval requests"

# -----------------------------------------------------------------------------
# Command implementations
# -----------------------------------------------------------------------------

cmd_deploy() {
    local force="${1:-false}"
    local sync_only="${2:-false}"
    local start_time=$(date +%s)

    log_info "Starting deployment for ${PROJECT_NAME}..."

    # Sync files
    log_info "Syncing files to ${REMOTE_HOST}..."
    rsync_files "$PROJECT_ROOT/" "$REMOTE_PATH/"

    if [[ "$sync_only" == "true" ]]; then
        log_success "Files synced (no rebuild)"
        audit_log "deploy:sync" "SUCCESS" "$(($(date +%s) - start_time))"
        return 0
    fi

    # Determine what needs rebuilding
    local services_to_rebuild=()

    if [[ "$force" == "true" ]]; then
        services_to_rebuild=("${SERVICES[@]}")
        log_info "Force rebuild: all services"
    else
        for service in "${SERVICES[@]}"; do
            if files_changed_since_deploy "$service"; then
                services_to_rebuild+=("$service")
            fi
        done
    fi

    if [[ ${#services_to_rebuild[@]} -eq 0 ]]; then
        log_info "No changes detected, restarting services..."
        docker_compose "restart"
    else
        log_info "Rebuilding: ${services_to_rebuild[*]}"
        docker_compose "build ${services_to_rebuild[*]}"
        docker_compose "up -d ${services_to_rebuild[*]}"
    fi

    # Health check
    if ! wait_for_healthy; then
        # Note: Automatic rollback still happens, but the ROLLBACK command
        # itself requires human approval if done manually later
        if [[ "${CONFIG[deploy_rollback_on_failure]:-true}" == "true" ]]; then
            log_error "Deployment failed - attempting automatic rollback..."
            # This is an automatic safety mechanism, not a manual rollback
            local prev_commit=$(get_deployed_commit)
            if [[ -n "$prev_commit" ]]; then
                git checkout "$prev_commit" 2>/dev/null || true
                rsync_files "$PROJECT_ROOT/" "$REMOTE_PATH/"
                docker_compose "build"
                docker_compose "up -d"
            fi
            notify_failure "Deployment failed, automatic rollback attempted"
            audit_log "deploy" "FAILED_AUTO_ROLLBACK" "$(($(date +%s) - start_time))"
            return 5
        fi
        notify_failure "Deployment failed, health check timeout"
        audit_log "deploy" "FAILED" "$(($(date +%s) - start_time))"
        return 5
    fi

    save_deploy_time
    notify_success "Deployed successfully"
    audit_log "deploy" "SUCCESS" "$(($(date +%s) - start_time))"
    log_success "Deployment complete"
}

cmd_rollback() {
    local target="${1:-}"
    local start_time=$(date +%s)

    if [[ -z "$target" ]]; then
        target=$(get_deployed_commit)
    fi

    if [[ -z "$target" ]]; then
        log_error "No previous deployment found"
        return 1
    fi

    log_info "Rolling back to $target..."

    # Checkout target commit
    git checkout "$target"

    # Sync and rebuild
    rsync_files "$PROJECT_ROOT/" "$REMOTE_PATH/"
    docker_compose "build"
    docker_compose "up -d"

    if ! wait_for_healthy; then
        log_error "Rollback failed - manual intervention required"
        notify_alert "Rollback failed for ${PROJECT_NAME}"
        audit_log "rollback" "FAILED" "$(($(date +%s) - start_time))"
        return 5
    fi

    notify_success "Rolled back to $target"
    audit_log "rollback" "SUCCESS" "$(($(date +%s) - start_time))"
    log_success "Rollback complete"
}

cmd_status() {
    echo -e "${BOLD}${PROJECT_NAME} Status${NC}"
    echo "----------------------------------------"
    echo "Remote: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
    echo "Deployed commit: $(get_deployed_commit)"
    echo "Last deploy: $(date -r $(get_last_deploy_time) 2>/dev/null || echo 'never')"
    echo ""
    echo -e "${BOLD}Services:${NC}"

    for service in "${SERVICES[@]}"; do
        local status=$(get_container_status "$service")
        local color="$RED"
        [[ "$status" == "running" ]] && color="$GREEN"
        echo -e "  $service: ${color}${status}${NC}"
    done
}

cmd_health() {
    echo -e "${BOLD}Health Check${NC}"
    local all_healthy=true

    for service in "${SERVICES[@]}"; do
        local port="${CONFIG[services_${service}_port]:-}"
        local endpoint="${CONFIG[services_${service}_health_endpoint]:-}"

        if [[ -z "$port" ]] || [[ -z "$endpoint" ]]; then
            echo -e "  $service: ${YELLOW}no health check${NC}"
            continue
        fi

        if check_service_health "$service"; then
            echo -e "  $service: ${GREEN}healthy${NC}"
        else
            echo -e "  $service: ${RED}unhealthy${NC}"
            all_healthy=false
        fi
    done

    $all_healthy && return 0 || return 5
}

cmd_logs() {
    local service="${1:-}"
    local follow="${2:-true}"

    local follow_flag=""
    [[ "$follow" == "true" ]] && follow_flag="-f"

    if [[ -n "$service" ]]; then
        docker_compose "logs $follow_flag $service"
    else
        docker_compose "logs $follow_flag"
    fi
}

cmd_db_migrate() {
    local dry_run="${1:-false}"
    local migration_cmd="${CONFIG[database_migration_command]:-}"

    if [[ -z "$migration_cmd" ]]; then
        log_error "No migration command configured"
        return 4
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_info "Migration dry-run:"
        ssh_cmd "cd $REMOTE_PATH && docker compose -f $COMPOSE_FILE exec backend $migration_cmd --sql"
    else
        log_info "Running migrations..."
        ssh_cmd "cd $REMOTE_PATH && docker compose -f $COMPOSE_FILE exec backend $migration_cmd"
        audit_log "db:migrate" "SUCCESS" "0"
        log_success "Migrations complete"
    fi
}

cmd_db_rollback() {
    local rollback_cmd="${CONFIG[database_rollback_command]:-}"

    if [[ -z "$rollback_cmd" ]]; then
        log_error "No rollback command configured"
        return 4
    fi

    log_info "Rolling back last migration..."
    ssh_cmd "cd $REMOTE_PATH && docker compose -f $COMPOSE_FILE exec backend $rollback_cmd"
    audit_log "db:rollback" "SUCCESS" "0"
    log_success "Rollback complete"
}

cmd_db_backup() {
    local backup_path="${CONFIG[database_backup_path]:-/backups}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local filename="${PROJECT_NAME}_${timestamp}.sql"

    log_info "Creating database backup..."
    ssh_cmd "cd $REMOTE_PATH && docker compose -f $COMPOSE_FILE exec -T db pg_dump -U postgres > ${backup_path}/${filename}"
    audit_log "db:backup" "SUCCESS" "0"
    log_success "Backup created: ${backup_path}/${filename}"
}

cmd_db_restore() {
    # This is BLOCKED - will never execute through ops.sh
    # Kept here for documentation purposes
    log_error "Database restore is BLOCKED in ops.sh"
    log_error "This operation must be performed manually"
    return 3
}

cmd_shell() {
    local service="${1:-backend}"
    log_info "Opening shell in $service..."
    ssh_cmd "cd $REMOTE_PATH && docker compose -f $COMPOSE_FILE exec $service /bin/bash"
}

cmd_restart() {
    local service="${1:-}"
    log_info "Restarting services..."

    if [[ -n "$service" ]]; then
        docker_compose "restart $service"
    else
        docker_compose "restart"
    fi

    wait_for_healthy
    audit_log "restart" "SUCCESS" "0"
    log_success "Restart complete"
}

cmd_stop() {
    log_warn "Stopping all services..."
    docker_compose "stop"
    audit_log "stop" "SUCCESS" "0"
    log_success "Services stopped"
}

cmd_destroy() {
    # This is BLOCKED - will never execute through ops.sh
    log_error "Destroy is BLOCKED in ops.sh"
    log_error "This operation must be performed manually"
    return 3
}

cmd_approval_list() {
    echo -e "${BOLD}Pending Approval Requests${NC}"
    echo "----------------------------------------"

    local pending_dir="$TIM_OPS_APPROVAL_DIR/pending"

    if [[ ! -d "$pending_dir" ]] || [[ -z "$(ls -A "$pending_dir" 2>/dev/null)" ]]; then
        echo "No pending requests"
        return 0
    fi

    for request_file in "$pending_dir"/*.request; do
        [[ -f "$request_file" ]] || continue
        local filename=$(basename "$request_file")
        local request_id=$(echo "$filename" | grep -oE '[0-9]+-[0-9]+-[0-9]+')

        echo ""
        echo -e "${YELLOW}Request: $request_id${NC}"
        grep -E "^(reason:|requested_by:|requested_at:|expires_at:)" "$request_file" | head -5
    done

    echo ""
    echo "To approve: tim-ops-approve <request_id>"
}

cmd_test() {
    echo -e "${BOLD}Running ops.sh self-test${NC}"
    local passed=0
    local failed=0

    # Test config loading
    if [[ -n "${CONFIG[project_name]:-}" ]]; then
        echo -e "  Config loading: ${GREEN}PASS${NC}"
        ((passed++))
    else
        echo -e "  Config loading: ${RED}FAIL${NC}"
        ((failed++))
    fi

    # Test remote connectivity
    if ssh_cmd "echo ok" > /dev/null 2>&1; then
        echo -e "  Remote connectivity: ${GREEN}PASS${NC}"
        ((passed++))
    else
        echo -e "  Remote connectivity: ${RED}FAIL${NC}"
        ((failed++))
    fi

    # Test docker access
    if ssh_cmd "docker ps" > /dev/null 2>&1; then
        echo -e "  Docker access: ${GREEN}PASS${NC}"
        ((passed++))
    else
        echo -e "  Docker access: ${RED}FAIL${NC}"
        ((failed++))
    fi

    echo ""
    echo "Results: $passed passed, $failed failed"
    [[ $failed -eq 0 ]] && return 0 || return 1
}

cmd_help() {
    echo -e "${BOLD}TIM Ops - ${PROJECT_NAME:-Project}${NC}"
    echo "Usage: ops.sh --env <environment> <command> [options]"
    echo ""
    echo -e "${BOLD}REQUIRED:${NC}"
    echo "  --env <env>            Environment: dev, uat, or prod (MANDATORY)"
    echo ""
    echo -e "${BOLD}Environments:${NC}"
    echo "  dev   - Development (permissive, sandbox)"
    echo "  uat   - User Acceptance Testing (moderate restrictions)"
    echo "  prod  - Production (maximum restrictions)"
    echo ""
    echo -e "${BOLD}Safety Tiers (vary by environment):${NC}"
    echo "  SAFE           - Always allowed"
    echo "  MODERATE       - Allowed (changes logged)"
    echo "  HUMAN_REQUIRED - Requires human approval (no bypass)"
    echo "  BLOCKED        - Never allowed in ops.sh (manual only)"
    echo ""
    echo -e "${BOLD}Commands:${NC}"

    for cmd in $(echo "${!COMMANDS[@]}" | tr ' ' '\n' | sort); do
        local info="${COMMANDS[$cmd]}"
        local default_tier="${info%%|*}"
        local desc="${info#*|}"

        # Show environment-specific tier if current env is set
        local display_tier="$default_tier"
        if [[ -n "$CURRENT_ENV" ]]; then
            display_tier=$(get_env_tier "$cmd")
        fi

        local tier_color="$NC"
        case "$display_tier" in
            SAFE) tier_color="$GREEN" ;;
            MODERATE) tier_color="$YELLOW" ;;
            HUMAN_REQUIRED) tier_color="$RED" ;;
            BLOCKED) tier_color="$RED${BOLD}" ;;
        esac
        printf "  %-20s [${tier_color}%-14s${NC}] %s\n" "$cmd" "$display_tier" "$desc"
    done

    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --env <env>            REQUIRED: dev, uat, or prod"
    echo "  --ticket <id>          Ticket reference (required for prod deploys)"
    echo "  --dry-run              Preview changes without executing"
    echo "  -v, --verbose          Verbose output"
    echo "  -h, --help             Show this help"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  ./ops.sh --env dev deploy              Deploy to development"
    echo "  ./ops.sh --env uat status              Check UAT status"
    echo "  ./ops.sh --env prod deploy --ticket PROJ-123"
    echo ""
    echo -e "${BOLD}NOTE:${NC} There are NO bypass flags. HUMAN_REQUIRED operations"
    echo "require pre-approval from a human. BLOCKED operations must"
    echo "be performed manually outside of ops.sh."
    echo ""
    echo "Command tiers vary by environment. Use --env with 'help' to see"
    echo "tiers for a specific environment."
    echo ""
    echo "Version: $TIM_OPS_VERSION"
}

cmd_version() {
    echo "tim-ops-lib $TIM_OPS_VERSION"
    echo "Project: ${PROJECT_NAME:-not loaded}"
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

tim_ops_main() {
    local command=""
    local environment=""
    local ticket=""
    local dry_run=false
    local verbose=false
    local args=()

    # Parse arguments - NOTE: No --confirm or dangerous bypass flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --env)
                if [[ -z "${2:-}" ]]; then
                    log_error "ERROR: --env requires a value (dev, uat, or prod)"
                    return 1
                fi
                environment="$2"
                shift 2
                ;;
            --ticket)
                if [[ -z "${2:-}" ]]; then
                    log_error "ERROR: --ticket requires a value (e.g., PROJ-123)"
                    return 1
                fi
                ticket="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                export DEBUG=1
                shift
                ;;
            -h|--help)
                cmd_help
                return 0
                ;;
            -*)
                log_error "Unknown option: $1"
                log_error "NOTE: There are no bypass flags. See 'ops.sh help'"
                return 1
                ;;
            *)
                if [[ -z "$command" ]]; then
                    command="$1"
                else
                    args+=("$1")
                fi
                shift
                ;;
        esac
    done

    # Default to help
    [[ -z "$command" ]] && command="help"

    # =========================================================================
    # ENVIRONMENT REQUIREMENT - MANDATORY
    # =========================================================================
    # The --env flag is REQUIRED for all commands except help/version
    # This is the cornerstone of environment isolation
    # See: standards/deployment/remote-only.md
    #
    if [[ "$command" != "help" ]] && [[ "$command" != "version" ]]; then
        if [[ -z "$environment" ]]; then
            log_error "============================================================"
            log_error "ERROR: --env flag is REQUIRED"
            log_error "============================================================"
            log_error ""
            log_error "All TIM operations require explicit environment specification."
            log_error ""
            log_error "Usage:"
            log_error "  ./ops.sh --env dev <command>    # Development"
            log_error "  ./ops.sh --env uat <command>    # User Acceptance Testing"
            log_error "  ./ops.sh --env prod <command>   # Production"
            log_error ""
            log_error "Example:"
            log_error "  ./ops.sh --env dev deploy"
            log_error "  ./ops.sh --env prod deploy --ticket PROJ-123"
            log_error ""
            log_error "See: standards/deployment/remote-only.md"
            log_error "============================================================"
            return 1
        fi

        # Load the specified environment
        if ! load_environment "$environment"; then
            return $?
        fi
    fi

    # Normalize command (deploy --force -> deploy:force)
    case "$command" in
        deploy)
            if [[ " ${args[*]} " =~ " --force " ]]; then
                command="deploy:force"
                args=("${args[@]/--force/}")
            elif [[ " ${args[*]} " =~ " --sync-only " ]]; then
                command="deploy:sync"
                args=("${args[@]/--sync-only/}")
            fi
            ;;
        db:migrate)
            if [[ "$dry_run" == "true" ]]; then
                command="db:migrate:dry"
            fi
            ;;
    esac

    # Look up command
    if [[ -z "${COMMANDS[$command]:-}" ]]; then
        log_error "Unknown command: $command"
        log_info "Run 'ops.sh help' for available commands"
        return 1
    fi

    # =========================================================================
    # ENVIRONMENT-SPECIFIC TIER LOOKUP
    # =========================================================================
    # Get tier based on environment + command combination
    # This implements standards/deployment/command-matrix.md
    #
    local tier
    if [[ -n "$CURRENT_ENV" ]]; then
        tier=$(get_env_tier "$command")
    else
        # For help/version commands without env, use default tier
        local info="${COMMANDS[$command]}"
        tier="${info%%|*}"
    fi

    # =========================================================================
    # PRODUCTION TICKET REQUIREMENT
    # =========================================================================
    # Production deploys require --ticket for traceability
    #
    if [[ "$CURRENT_ENV" == "prod" ]] && [[ "$command" =~ ^deploy ]]; then
        if [[ -z "$ticket" ]]; then
            log_error "============================================================"
            log_error "ERROR: Production deploys require --ticket"
            log_error "============================================================"
            log_error ""
            log_error "Example: ./ops.sh --env prod deploy --ticket PROJ-123"
            log_error ""
            log_error "============================================================"
            return 1
        fi
        log_info "Ticket: $ticket"
    fi

    # =========================================================================
    # SECURITY VERIFICATION (for non-SAFE operations)
    # =========================================================================
    # Run security checks before potentially dangerous operations
    #
    if [[ "$tier" != "SAFE" ]] && [[ -n "$CURRENT_ENV" ]]; then
        if ! verify_security; then
            return $?
        fi
    fi

    # Check safety tier - NO bypass flags passed
    if ! check_safety "$tier" "$command"; then
        return $?
    fi

    # Execute command
    case "$command" in
        deploy)
            cmd_deploy "false" "false"
            ;;
        deploy:force)
            cmd_deploy "true" "false"
            ;;
        deploy:sync)
            cmd_deploy "false" "true"
            ;;
        rollback)
            cmd_rollback "${args[0]:-}"
            ;;
        status)
            cmd_status
            ;;
        health)
            cmd_health
            ;;
        logs)
            cmd_logs "${args[0]:-}" "true"
            ;;
        db:migrate)
            cmd_db_migrate "false"
            ;;
        db:migrate:dry)
            cmd_db_migrate "true"
            ;;
        db:rollback)
            cmd_db_rollback
            ;;
        db:backup)
            cmd_db_backup
            ;;
        db:restore)
            cmd_db_restore "${args[0]:-}"
            ;;
        shell)
            cmd_shell "${args[0]:-}"
            ;;
        restart)
            cmd_restart "${args[0]:-}"
            ;;
        stop)
            cmd_stop
            ;;
        destroy)
            cmd_destroy
            ;;
        test)
            cmd_test
            ;;
        approval:list)
            cmd_approval_list
            ;;
        help)
            cmd_help
            ;;
        version)
            cmd_version
            ;;
        *)
            # Check for custom command function
            if declare -f "cmd_${command//:/_}" > /dev/null; then
                "cmd_${command//:/_}" "${args[@]}"
            else
                log_error "Command not implemented: $command"
                return 1
            fi
            ;;
    esac
}

# Export functions for hooks
export -f log_info log_success log_warn log_error log_debug
export -f ssh_cmd rsync_files docker_compose
export -f check_service_health wait_for_healthy
export -f notify_success notify_failure notify_alert
export -f audit_log register_command
