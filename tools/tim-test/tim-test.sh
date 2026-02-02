#!/usr/bin/env bash
# tim-test - Unified test wrapper for TIM projects
# Detects test frameworks and runs the right command
#
# Usage:
#   tim-test unit              # Run unit tests
#   tim-test integration       # Run integration tests
#   tim-test e2e               # Run Playwright e2e tests
#   tim-test all               # Run everything
#   tim-test watch             # Watch mode
#   tim-test info              # Show detection results
#
# Monorepo flags:
#   --backend                  # Target backend only
#   --frontend                 # Target frontend only
#
# Pass-through:
#   tim-test unit -- -k "test_login"   # Pass args to underlying framework

set -euo pipefail

# Get the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source modules
source "$SCRIPT_DIR/modules/core.sh"
source "$SCRIPT_DIR/modules/detection.sh"
source "$SCRIPT_DIR/modules/commands.sh"

# Global variables
PROJECT_ROOT=""
TARGET_BACKEND=0
TARGET_FRONTEND=0
PASSTHROUGH_ARGS=()
PARSED_COMMAND=""

# Show usage information
show_usage() {
    cat << 'EOF'
tim-test - Unified test wrapper for TIM projects

USAGE:
    tim-test <command> [options] [-- pass-through-args]

COMMANDS:
    unit              Run unit tests
    integration       Run integration tests
    e2e               Run Playwright e2e tests
    all               Run all tests
    watch             Run tests in watch mode
    info              Show detection results

OPTIONS:
    --backend         Target backend only (monorepo)
    --frontend        Target frontend only (monorepo)
    --help, -h        Show this help message

PASS-THROUGH:
    Use -- to pass arguments directly to the underlying test framework.

    Examples:
        tim-test unit -- -k "test_login"     # pytest filter
        tim-test unit -- --coverage          # Jest coverage
        tim-test e2e -- --headed             # Playwright headed mode

EXAMPLES:
    tim-test info                            # Show what was detected
    tim-test unit                            # Run unit tests
    tim-test unit --backend                  # Run backend unit tests only
    tim-test e2e                             # Run Playwright e2e tests
    tim-test all                             # Run everything
    tim-test watch                           # Watch mode

DETECTION:
    tim-test automatically detects:
    - pytest:      pytest.ini, pyproject.toml [tool.pytest], conftest.py
    - Jest:        jest.config.*, package.json jest config
    - Vitest:      vitest.config.*, vite.config.ts with test
    - Playwright:  playwright.config.ts/.js
    - Monorepo:    frontend/ and backend/ directories
    - Pkg manager: pnpm-lock.yaml, yarn.lock, package-lock.json
EOF
}

# Parse command line arguments
# Sets PARSED_COMMAND global variable (avoids subshell issue)
parse_args() {
    PARSED_COMMAND=""
    local collecting_passthrough=0

    while [[ $# -gt 0 ]]; do
        if [[ "$collecting_passthrough" == "1" ]]; then
            PASSTHROUGH_ARGS+=("$1")
            shift
            continue
        fi

        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            --backend)
                TARGET_BACKEND=1
                shift
                ;;
            --frontend)
                TARGET_FRONTEND=1
                shift
                ;;
            --)
                collecting_passthrough=1
                shift
                ;;
            unit|integration|e2e|all|watch|info)
                PARSED_COMMAND="$1"
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
            *)
                if [[ -z "$PARSED_COMMAND" ]]; then
                    log_error "Unknown command: $1"
                    echo "Use --help for usage information."
                    exit 1
                else
                    # Treat as passthrough arg if command already set
                    PASSTHROUGH_ARGS+=("$1")
                fi
                shift
                ;;
        esac
    done

    # Validate flags
    if [[ "$TARGET_BACKEND" == "1" ]] && [[ "$TARGET_FRONTEND" == "1" ]]; then
        log_error "Cannot use both --backend and --frontend"
        exit 1
    fi
}

# Main function
main() {
    # Parse arguments (sets PARSED_COMMAND global)
    parse_args "$@"

    # Default to help if no command given
    if [[ -z "$PARSED_COMMAND" ]]; then
        show_usage
        exit 0
    fi

    # Find project root
    PROJECT_ROOT=$(find_project_root)
    if [[ -z "$PROJECT_ROOT" ]]; then
        log_error "Could not find project root (no package.json or pyproject.toml found)"
        exit 1
    fi

    log_debug "Project root: $PROJECT_ROOT"

    # Run detection
    detect_all "$PROJECT_ROOT"

    # Dispatch to command
    case "$PARSED_COMMAND" in
        unit)
            cmd_unit "${PASSTHROUGH_ARGS[@]}"
            ;;
        integration)
            cmd_integration "${PASSTHROUGH_ARGS[@]}"
            ;;
        e2e)
            cmd_e2e "${PASSTHROUGH_ARGS[@]}"
            ;;
        all)
            cmd_all "${PASSTHROUGH_ARGS[@]}"
            ;;
        watch)
            cmd_watch "${PASSTHROUGH_ARGS[@]}"
            ;;
        info)
            cmd_info
            ;;
        *)
            log_error "Unknown command: $PARSED_COMMAND"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
