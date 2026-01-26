#!/usr/bin/env bash
# plan-ops/search.sh - Plan discovery and resolution
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh
# Exports: find_plans_by_name, resolve_plan_path
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# PLAN DISCOVERY FUNCTIONS
# =============================================================================

# Find plan files matching a name pattern
# Searches: current project's plans/ (top-level and subfolders), ~/.claude/plans/
# Returns: newline-separated list of matching absolute paths
find_plans_by_name() {
    local pattern="$1"
    local results=()

    # Add .md extension if not present
    [[ "$pattern" != *.md ]] && pattern="${pattern}.md"

    # Search in current project's plans directory (top-level and all stages)
    if [[ -d "$PLANS_DIR" ]]; then
        local abs_plans_dir
        abs_plans_dir=$(to_absolute "$PLANS_DIR")

        # Search top-level plans/ directory first
        while IFS= read -r -d '' file; do
            results+=("$file")
        done < <(find "${abs_plans_dir}" -maxdepth 1 -name "*${pattern}" -type f -print0 2>/dev/null)

        # Search stage subfolders
        for stage in drafts active completed abandoned; do
            if [[ -d "${abs_plans_dir}/${stage}" ]]; then
                while IFS= read -r -d '' file; do
                    results+=("$file")
                done < <(find "${abs_plans_dir}/${stage}" -maxdepth 1 -name "*${pattern}" -type f -print0 2>/dev/null)
            fi
        done
    fi

    # Search in ~/.claude/plans/
    if [[ -d "$CLAUDE_PLANS_DIR" ]]; then
        while IFS= read -r -d '' file; do
            results+=("$file")
        done < <(find "$CLAUDE_PLANS_DIR" -maxdepth 1 -name "*${pattern}" -type f -print0 2>/dev/null)
    fi

    # Output results
    printf '%s\n' "${results[@]}"
}

# Try to relocate a plan file that might have been moved
# Returns: new path if found, empty string if not found
# Unlike resolve_plan_path, this doesn't prompt for interactive selection
try_relocate_plan() {
    local original_path="$1"

    # If file exists, return as-is
    if [[ -f "$original_path" ]]; then
        echo "$original_path"
        return 0
    fi

    # Extract basename and try common locations
    local basename
    basename=$(basename "$original_path")

    # Determine plans directory from original path
    local plans_dir=""
    if [[ "$original_path" == *"/plans/"* ]]; then
        # Extract the plans directory path
        plans_dir="${original_path%%/plans/*}/plans"
    fi

    # If we can't determine plans_dir, try current project
    if [[ -z "$plans_dir" ]] || [[ ! -d "$plans_dir" ]]; then
        plans_dir="$PLANS_DIR"
    fi

    # Search order: completed, active, drafts, abandoned (most likely moves)
    for stage in completed active drafts abandoned; do
        local candidate="${plans_dir}/${stage}/${basename}"
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    # Not found
    return 1
}

# Resolve a plan argument to an absolute path
# If it's a path and exists, use it directly
# If it's a path but doesn't exist, extract filename and search
# If it's just a name, search for it and handle duplicates
resolve_plan_path() {
    local arg="$1"
    local search_name=""

    # If it looks like a path
    if [[ "$arg" == */* ]]; then
        local abs_path
        abs_path=$(to_absolute "$arg")

        # If file exists at this path, use it
        if [[ -f "$abs_path" ]]; then
            echo "$abs_path"
            return 0
        fi

        # File doesn't exist at given path - extract filename and search
        search_name=$(basename "$arg" .md)
        log_warn "File not found at: $arg"
        log_info "Searching for plan by name: $search_name"
    else
        search_name="$arg"
    fi

    # Search for plans matching the name
    local matches
    matches=$(find_plans_by_name "$search_name")

    if [[ -z "$matches" ]]; then
        log_error "No plan found matching: $arg"
        log_info "Searched in: $PLANS_DIR, $PLANS_DIR/*, $CLAUDE_PLANS_DIR"
        return 1
    fi

    # Count matches
    local count
    count=$(echo "$matches" | grep -c .)

    if [[ "$count" -eq 1 ]]; then
        echo "$matches"
        return 0
    fi

    # Multiple matches - let user choose
    log_warn "Multiple plans found matching '$arg':"
    echo ""
    local i=1
    local options=()
    while IFS= read -r match; do
        # Show relative path from home or absolute
        local display_path="${match/#$HOME/~}"
        echo "  [$i] $display_path"
        options+=("$match")
        ((i++))
    done <<< "$matches"
    echo ""

    local choice
    while true; do
        echo -n "Select plan [1-$count]: "
        read -r choice </dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        echo "Invalid choice. Enter a number between 1 and $count."
    done
}
