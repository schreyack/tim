#!/usr/bin/env bash
# plan-ops/core.sh - Constants, logging, and path utilities
# Part of plan-ops.sh modular refactor
#
# Dependencies: none
# Exports: log_info, log_warn, log_error, to_absolute, get_plans_dir_from_path,
#          timestamp, datestamp, strip_ansi, insert_line_after
#
# This file is sourced by plan-ops.sh, not executed directly.

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# CONSTANTS
# =============================================================================

PLANS_DIR="${PLANS_DIR:-plans}"
CLAUDE_PLANS_DIR="${HOME}/.claude/plans"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Global for tracking plan file path (updated by wizard steps after moves)
WIZARD_PLAN_FILE=""

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# =============================================================================
# PATH UTILITIES
# =============================================================================

# Convert a path to absolute (resolves relative paths against cwd)
to_absolute() {
    local path="$1"
    if [[ "$path" = /* ]]; then
        echo "$path"
    else
        echo "$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")"
    fi
}

# Extract the plans directory from a plan file's absolute path.
# Input:  /path/to/project/plans/active/my-plan.md
# Output: /path/to/project/plans
# Falls back to PLANS_DIR if pattern doesn't match.
get_plans_dir_from_path() {
    local path="$1"
    # Match paths like .../plans/stage/filename.md where stage is drafts/active/completed/abandoned
    if [[ "$path" =~ ^(.*/plans)/(drafts|active|completed|abandoned)/[^/]+$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        # Fallback to local PLANS_DIR
        to_absolute "$PLANS_DIR"
    fi
}

# =============================================================================
# TIME UTILITIES
# =============================================================================

# Get current timestamp
timestamp() {
    date "+%Y-%m-%d %H:%M"
}

# Get current date for filenames
datestamp() {
    date "+%Y-%m-%d"
}

# =============================================================================
# STRING UTILITIES
# =============================================================================

# Strip ANSI color/formatting codes from string
# Usage: clean_text=$(strip_ansi "$colored_text")
strip_ansi() {
    # Remove color codes (\e[...m), bold, underline, etc.
    echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# =============================================================================
# FILE EDITING HELPERS
# =============================================================================

# Insert a line after a pattern in a file (more reliable than sed -a on macOS)
# Usage: insert_line_after "pattern" "new line content" "file"
# Note: Uses regex matching to handle variable whitespace in markdown tables
# Pattern should be like "| Field |" - whitespace around field name is handled automatically
insert_line_after() {
    local pattern="$1"
    local new_line="$2"
    local file="$3"
    # Convert pattern like "| Field |" to regex that handles whitespace
    # e.g., "| Approver |" becomes regex matching "| Approver" followed by spaces and "|"
    local field_name
    field_name=$(echo "$pattern" | sed 's/^|[[:space:]]*//; s/[[:space:]]*|$//')
    awk -v field="$field_name" -v line="$new_line" '
        { print }
        /\|[[:space:]]*'"$field_name"'[[:space:]]*\|/ && !done { print line; done=1 }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}
