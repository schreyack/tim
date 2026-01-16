#!/usr/bin/env bash
# tim-ops-lib.sh - TIM Operations Library
# Shared deployment operations for all TIM projects
#
# VERSION: 1.0.0
# SOURCE: https://github.com/your-org/design_standards/templates/ops/tim-ops-lib.sh
#
# Usage: Source this file from your project's ops.sh wrapper
#   source "/path/to/tim-ops-lib.sh"
#   load_config "ops-config.yaml"
#   tim_ops_main "$@"

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

TIM_OPS_VERSION="1.0.0"
TIM_OPS_AUDIT_LOG="${TIM_OPS_AUDIT_LOG:-$HOME/.tim-ops/audit.log}"
TIM_OPS_STATE_DIR="${TIM_OPS_STATE_DIR:-$HOME/.tim-ops/state}"

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

# Safety tiers
declare -A SAFETY_TIERS=(
    [SAFE]=0
    [MODERATE]=1
    [PROTECTED]=2
    [BLOCKED]=3
)

# Registered commands: command -> "TIER|description"
declare -A COMMANDS=()

# Project configuration (loaded from ops-config.yaml)
declare -A CONFIG=()
declare -a SERVICES=()

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
    # This handles simple key: value and nested structures

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
# SAFETY CHECKS
# =============================================================================

check_safety() {
    local tier="$1"
    local command="$2"
    local confirm="${3:-false}"
    local dangerous="${4:-false}"

    case "$tier" in
        SAFE)
            return 0
            ;;
        MODERATE)
            log_warn "This operation will make changes"
            return 0
            ;;
        PROTECTED)
            if [[ "$confirm" != "true" ]]; then
                log_error "This operation requires confirmation"
                log_error "Run with --confirm to proceed"
                return 2
            fi
            log_warn "PROTECTED operation confirmed"
            return 0
            ;;
        BLOCKED)
            if [[ "$confirm" != "true" ]] || [[ "$dangerous" != "true" ]]; then
                log_error "This operation is BLOCKED"
                log_error "Run with --confirm --i-understand-this-is-dangerous to proceed"
                notify_alert "BLOCKED operation attempted: $command"
                return 3
            fi
            log_warn "BLOCKED operation confirmed - proceeding with caution"
            notify_alert "BLOCKED operation executed: $command"
            return 0
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

    # Get watch paths for service from config
    # This is simplified - real implementation would parse YAML arrays
    local watch_key="services_${service}_watch_paths"

    # For now, check if any files in service directory changed
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

# Register default commands
register_command "deploy" "MODERATE" "Deploy application (smart rebuild)"
register_command "deploy:force" "PROTECTED" "Force full rebuild and deploy"
register_command "deploy:sync" "SAFE" "Sync files only (no rebuild)"
register_command "rollback" "PROTECTED" "Rollback to previous deployment"
register_command "status" "SAFE" "Show deployment status"
register_command "health" "SAFE" "Check service health"
register_command "logs" "SAFE" "View application logs"
register_command "db:migrate" "MODERATE" "Run database migrations"
register_command "db:migrate:dry" "SAFE" "Preview database migrations"
register_command "db:rollback" "PROTECTED" "Rollback last migration"
register_command "db:backup" "SAFE" "Backup database"
register_command "db:restore" "BLOCKED" "Restore database from backup"
register_command "shell" "MODERATE" "Open shell in container"
register_command "restart" "MODERATE" "Restart services"
register_command "stop" "PROTECTED" "Stop all services"
register_command "destroy" "BLOCKED" "Remove all containers and data"
register_command "test" "SAFE" "Run ops.sh self-test"
register_command "help" "SAFE" "Show this help message"
register_command "version" "SAFE" "Show version information"

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
        if [[ "${CONFIG[deploy_rollback_on_failure]:-true}" == "true" ]]; then
            log_error "Deployment failed, rolling back..."
            cmd_rollback "$(get_deployed_commit)"
            notify_failure "Deployment failed, rolled back"
            audit_log "deploy" "FAILED_ROLLBACK" "$(($(date +%s) - start_time))"
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
    local backup_file="$1"

    if [[ -z "$backup_file" ]]; then
        log_error "Usage: ops.sh db:restore <backup_file>"
        return 1
    fi

    log_warn "This will OVERWRITE the current database!"
    log_info "Restoring from: $backup_file"

    ssh_cmd "cd $REMOTE_PATH && docker compose -f $COMPOSE_FILE exec -T db psql -U postgres < ${backup_file}"
    audit_log "db:restore" "SUCCESS" "0"
    log_success "Database restored"
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
    log_warn "DESTROYING all containers and data..."
    docker_compose "down -v --remove-orphans"
    audit_log "destroy" "SUCCESS" "0"
    log_success "Destroyed"
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
    echo "Usage: ops.sh <command> [options]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"

    for cmd in $(echo "${!COMMANDS[@]}" | tr ' ' '\n' | sort); do
        local info="${COMMANDS[$cmd]}"
        local tier="${info%%|*}"
        local desc="${info#*|}"
        printf "  %-20s [%-9s] %s\n" "$cmd" "$tier" "$desc"
    done

    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo "  --confirm              Confirm protected operations"
    echo "  --i-understand-this-is-dangerous"
    echo "                         Confirm blocked operations"
    echo "  --dry-run              Preview changes without executing"
    echo "  -v, --verbose          Verbose output"
    echo "  -h, --help             Show this help"
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
    local confirm=false
    local dangerous=false
    local dry_run=false
    local verbose=false
    local args=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --confirm)
                confirm=true
                shift
                ;;
            --i-understand-this-is-dangerous)
                dangerous=true
                shift
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

    local info="${COMMANDS[$command]}"
    local tier="${info%%|*}"

    # Check safety tier
    if ! check_safety "$tier" "$command" "$confirm" "$dangerous"; then
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
