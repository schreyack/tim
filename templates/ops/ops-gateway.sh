#!/usr/bin/env bash
# ops-gateway.sh - SSH Command Gateway for TIM Projects
# =====================================================
#
# This script runs on the REMOTE SERVER and restricts what commands
# can be executed via SSH. It's the server-side enforcement of ops.sh safety.
#
# INSTALLATION:
#   1. Copy this file to /home/<deploy_user>/bin/ops-gateway.sh on the remote server
#   2. chmod 755 /home/<deploy_user>/bin/ops-gateway.sh
#   3. Update ~/.ssh/authorized_keys with command restriction (see below)
#
# AUTHORIZED_KEYS FORMAT:
#   command="/home/deploy/bin/ops-gateway.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-rsa AAAA... deploy@local
#
# This ensures that ANY SSH connection using this key is forced through the gateway.
#
# VERSION: 1.0.0
# SOURCE: tim/templates/ops/ops-gateway.sh

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

LOG_FILE="/var/log/ops-gateway.log"
AUDIT_LOG="/var/log/ops-gateway-audit.log"

# Environment this server belongs to (MUST be set correctly)
# This should match the server's role: dev, uat, or prod
SERVER_ENVIRONMENT="${SERVER_ENVIRONMENT:-unknown}"

# Allowed commands - WHITELIST approach
# Only these command prefixes are permitted
ALLOWED_COMMANDS=(
    # Docker operations
    "docker compose"
    "docker-compose"
    "docker ps"
    "docker logs"
    "docker exec"
    "docker inspect"
    "docker images"
    "docker network"

    # Rsync for file sync (ops.sh deploy)
    "rsync --server"

    # Basic utilities
    "cat"
    "ls"
    "pwd"
    "echo ok"
    "test"

    # Database operations (container-based)
    "pg_dump"

    # Health checks
    "curl"
    "wget"
)

# Explicitly BLOCKED commands - even if they match allowed prefixes
BLOCKED_COMMANDS=(
    # Destructive docker commands
    "docker rm"
    "docker rmi"
    "docker system prune"
    "docker volume rm"
    "docker network rm"

    # Shell access (blocked in prod)
    "docker exec.*bash"
    "docker exec.*sh"

    # Dangerous file operations
    "rm -rf"
    "mv /"
    "chmod 777"
)

# Production-specific blocks
PROD_BLOCKED_COMMANDS=(
    # No shell access in production
    "docker exec"
    "bash"
    "/bin/bash"
    "sh"
    "/bin/sh"

    # No direct database access
    "psql"
    "mysql"
)

# =============================================================================
# LOGGING
# =============================================================================

log() {
    local level="$1"
    shift
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "$timestamp | $level | $USER | $SSH_CLIENT | $*" >> "$LOG_FILE" 2>/dev/null || true
}

audit() {
    local result="$1"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local client_ip=$(echo "$SSH_CLIENT" | cut -d' ' -f1)
    echo "$timestamp | $USER | $client_ip | $SERVER_ENVIRONMENT | $result | $SSH_ORIGINAL_COMMAND" >> "$AUDIT_LOG" 2>/dev/null || true
}

# =============================================================================
# VALIDATION
# =============================================================================

is_allowed() {
    local cmd="$1"

    for allowed in "${ALLOWED_COMMANDS[@]}"; do
        if [[ "$cmd" == "$allowed"* ]]; then
            return 0
        fi
    done
    return 1
}

is_blocked() {
    local cmd="$1"

    # Check global blocks
    for blocked in "${BLOCKED_COMMANDS[@]}"; do
        if [[ "$cmd" =~ $blocked ]]; then
            return 0
        fi
    done

    # Check production-specific blocks
    if [[ "$SERVER_ENVIRONMENT" == "prod" ]]; then
        for blocked in "${PROD_BLOCKED_COMMANDS[@]}"; do
            if [[ "$cmd" =~ $blocked ]]; then
                return 0
            fi
        done
    fi

    return 1
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    # Log every attempt
    log "INFO" "Command attempted: ${SSH_ORIGINAL_COMMAND:-<interactive>}"

    # Reject interactive sessions
    if [[ -z "${SSH_ORIGINAL_COMMAND:-}" ]]; then
        log "BLOCKED" "Interactive SSH session rejected"
        audit "BLOCKED_INTERACTIVE"
        echo "============================================================"
        echo "ERROR: Interactive SSH sessions are not permitted."
        echo ""
        echo "Use ops.sh to interact with this server:"
        echo "  ./ops.sh --env $SERVER_ENVIRONMENT <command>"
        echo ""
        echo "For emergency access, contact the infrastructure team."
        echo "============================================================"
        exit 1
    fi

    local cmd="$SSH_ORIGINAL_COMMAND"

    # Check if explicitly blocked first
    if is_blocked "$cmd"; then
        log "BLOCKED" "Blocked command attempted: $cmd"
        audit "BLOCKED_DANGEROUS"
        echo "============================================================"
        echo "ERROR: This command is blocked on $SERVER_ENVIRONMENT servers."
        echo ""
        echo "Command: $cmd"
        echo ""
        echo "If you need to perform this operation:"
        echo "  1. Contact the infrastructure team"
        echo "  2. Use the break-glass procedure if it's an emergency"
        echo "============================================================"
        exit 1
    fi

    # Check if allowed
    if is_allowed "$cmd"; then
        log "ALLOWED" "Executing: $cmd"
        audit "ALLOWED"
        eval "$cmd"
        exit $?
    fi

    # Not in allowed list
    log "BLOCKED" "Unknown command: $cmd"
    audit "BLOCKED_UNKNOWN"
    echo "============================================================"
    echo "ERROR: Command not permitted: $cmd"
    echo ""
    echo "Only ops.sh approved commands can be executed on this server."
    echo ""
    echo "Contact the infrastructure team if this command should be allowed."
    echo "============================================================"
    exit 1
}

# Run main
main
