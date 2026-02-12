#!/usr/bin/env bash
# tim-loop-prompt-manager.sh - Manage tim-loop prompts with security validation
#
# This script handles saving, retrieving, and cleaning up tim-loop prompts
# to preserve prompt fidelity across context compaction, with comprehensive
# security validation to prevent reinjection of stale, tampered, or wrong prompts.
#
# SECURITY FEATURES:
# - SHA-256 hash verification (covers version, epoch, session, path, prompt)
# - Session ID sanitization (prevents directory traversal)
# - Symlink attack prevention
# - TOCTOU attack prevention (read-once pattern)
# - Clock skew and future timestamp detection
# - File size limits (prevents memory exhaustion)
# - NUL byte detection (prevents silent truncation)
# - UTF-8 validation
# - Restrictive file permissions (0600)
# - Atomic writes with mktemp
#
# Usage:
#   tim-loop-prompt-manager.sh save <prompt-text>   # Save prompt for current session
#   tim-loop-prompt-manager.sh save-file <file>     # Save prompt from file
#   tim-loop-prompt-manager.sh get                  # Get prompt for current session
#   tim-loop-prompt-manager.sh clear                # Clear prompt for current session
#   tim-loop-prompt-manager.sh cleanup              # Remove stale prompts (>24h)
#   tim-loop-prompt-manager.sh hook                 # SessionStart hook mode (outputs JSON)

set -euo pipefail

# ============================================================================
# CONFIGURATION (global constants used by all modules)
# ============================================================================

PROMPT_DIR="${TIM_PROMPT_DIR:-$HOME/.claude}"
STALE_MINUTES="${TIM_PROMPT_STALE_MINUTES:-1440}"  # 24 hours default

# Validation parameters
PROMPT_MAX_AGE_HOURS="${TIM_PROMPT_MAX_AGE_HOURS:-4}"
PROMPT_MAX_SIZE_BYTES="${TIM_PROMPT_MAX_SIZE_BYTES:-102400}"  # 100KB for prompt content
MAX_PROMPT_FILE_SIZE="${TIM_MAX_PROMPT_FILE_SIZE:-204800}"    # 200KB for JSON file

# Clock validation
CLOCK_SKEW_TOLERANCE_SECONDS=300  # 5 minutes
FUTURE_TOLERANCE_SECONDS=300      # 5 minutes

# Marker freshness
MARKER_MAX_AGE_SECONDS=300  # 5 minutes

# ============================================================================
# SOURCE MODULES
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/prompt-manager-security.sh"
source "$SCRIPT_DIR/prompt-manager-core.sh"
source "$SCRIPT_DIR/prompt-manager-commands.sh"

# ============================================================================
# INITIALIZATION
# ============================================================================

# Verify required tools at script load time
verify_required_tools

# Trap signals to clean up temp files on interrupt
trap cleanup_temp_files EXIT SIGTERM SIGINT

# ============================================================================
# MAIN DISPATCH
# ============================================================================

case "${1:-help}" in
    save)
        if [[ -z "${2:-}" ]]; then
            echo "Error: Prompt text required" >&2
            echo "Usage: $0 save <prompt-text>" >&2
            exit 1
        fi
        cmd_save "$2"
        ;;
    save-file)
        if [[ -z "${2:-}" ]]; then
            echo "Error: File path required" >&2
            echo "Usage: $0 save-file <file>" >&2
            exit 1
        fi
        cmd_save_file "$2"
        ;;
    get)
        cmd_get
        ;;
    clear)
        cmd_clear
        ;;
    cleanup)
        cmd_cleanup
        ;;
    hook)
        cmd_hook
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        echo "Unknown command: $1" >&2
        echo "Run '$0 help' for usage." >&2
        exit 1
        ;;
esac
