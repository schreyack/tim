#!/usr/bin/env bash
# plan-ops.sh - Bundled with tim-loop plugin
# Version: Synced from plugin.json (currently 1.6.0)
# Source: https://github.com/schreyack/design_standards
# Note: This file is auto-copied to projects on first /tim-loop run
#
# Modular refactor: This is the main entry point that sources modular components.
# Each module is under 400 lines to comply with TIM standards.
set -euo pipefail

# plan-ops.sh - TIM Plan Lifecycle Management
# Usage: $SCRIPT_PATH <command> [args]
#
# Commands:
#   init              Initialize plan folder structure
#   import            Import plan from ~/.claude/plans to drafts
#   ralph             Start Ralph Loop review for a draft plan
#   promote           Move plan from drafts to active
#   execute           Request execution approval for active plan
#   approve-execute   Human approval for plan execution
#   fast-track        Skip workflow and go directly to implementation
#   complete          Move plan from active to completed
#   abandon           Move plan to abandoned
#   cleanup-drafts    Remove stale drafts
#   list              List plans by stage

# =============================================================================
# SCRIPT PATH RESOLUTION
# =============================================================================

# Resolve script's absolute path (works even when called via symlink)
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
# Resolve tim repo root directory (3 levels up: scripts/ -> tim-loop/ -> plugins/ -> root)
DESIGN_STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# Module directory (plan-ops/ subdirectory next to this script)
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plan-ops"

# =============================================================================
# MODULE LOADING
# =============================================================================

# Required modules in dependency order
MODULES=(
    core
    search
    security
    status
    approval
    verification
    wizard
    commands-lifecycle
    commands-approval
    commands-execution
    commands-utility
)

# Verify all modules exist before sourcing any
for module in "${MODULES[@]}"; do
    if [[ ! -f "${MODULE_DIR}/${module}.sh" ]]; then
        echo "ERROR: Missing module: ${MODULE_DIR}/${module}.sh" >&2
        echo "The plan-ops.sh modular structure is incomplete." >&2
        echo "Expected modules in: ${MODULE_DIR}/" >&2
        exit 1
    fi
done

# Source all modules
for module in "${MODULES[@]}"; do
    # shellcheck source=/dev/null
    source "${MODULE_DIR}/${module}.sh"
done

# =============================================================================
# MAIN DISPATCH
# =============================================================================

case "${1:-help}" in
    init) cmd_init ;;
    import) cmd_import "${@:2}" ;;
    review) cmd_review "${@:2}" ;;
    ralph) cmd_ralph "${@:2}" ;;
    promote) cmd_promote "${@:2}" ;;
    ai-ready) cmd_ai_ready "${@:2}" ;;
    execute) cmd_execute "${@:2}" ;;
    approve-execute) cmd_approve_execute "${@:2}" ;;
    fast-track) cmd_fast_track "${@:2}" ;;
    complete) cmd_complete "${@:2}" ;;
    abandon) cmd_abandon "${@:2}" ;;
    cleanup-drafts) cmd_cleanup_drafts "${@:2}" ;;
    list) cmd_list "${@:2}" ;;
    wizard) cmd_wizard "${@:2}" ;;
    help|--help|-h) cmd_help ;;
    *)
        log_error "Unknown command: $1"
        echo "Run '$SCRIPT_PATH help' for usage."
        exit 1
        ;;
esac
