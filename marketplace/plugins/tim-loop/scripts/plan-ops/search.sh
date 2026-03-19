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
# Also searches for package folders (directories with MASTER.md)
# Returns: newline-separated list of matching absolute paths
#          For packages, returns path to MASTER.md
find_plans_by_name() {
    local pattern="$1"
    local results=()

    # Remove .md extension if present for broader matching
    local base_pattern="${pattern%.md}"

    # Search in current project's plans directory (top-level and all stages)
    if [[ -d "$PLANS_DIR" ]]; then
        local abs_plans_dir
        abs_plans_dir=$(to_absolute "$PLANS_DIR")

        # Search top-level plans/ directory first
        while IFS= read -r -d '' file; do
            results+=("$file")
        done < <(find "${abs_plans_dir}" -maxdepth 1 -name "*${base_pattern}*.md" -type f -print0 2>/dev/null)

        # Search stage subfolders for both files and packages
        for stage in drafts active completed abandoned playbooks; do
            if [[ -d "${abs_plans_dir}/${stage}" ]]; then
                # Search for standalone plan files
                while IFS= read -r -d '' file; do
                    results+=("$file")
                done < <(find "${abs_plans_dir}/${stage}" -maxdepth 1 -name "*${base_pattern}*.md" -type f -print0 2>/dev/null)

                # Search for package folders (directories matching pattern with MASTER.md)
                while IFS= read -r -d '' dir; do
                    if [[ -f "${dir}/MASTER.md" ]]; then
                        results+=("${dir}/MASTER.md")
                    fi
                done < <(find "${abs_plans_dir}/${stage}" -maxdepth 1 -name "*${base_pattern}*" -type d -print0 2>/dev/null)
            fi
        done
    fi

    # Search in ~/.claude/plans/ (root + subdirectories, with package support)
    if [[ -d "$CLAUDE_PLANS_DIR" ]]; then
        # Standalone .md files at root level
        while IFS= read -r -d '' file; do
            results+=("$file")
        done < <(find "$CLAUDE_PLANS_DIR" -maxdepth 1 -name "*${base_pattern}*.md" -type f -print0 2>/dev/null)

        # Check immediate subdirectories: packages (have MASTER.md) vs folders (like drafts/)
        while IFS= read -r -d '' subdir; do
            if [[ -f "${subdir}/MASTER.md" ]]; then
                # Package at root level — check if name matches pattern
                local pkg_name
                pkg_name=$(basename "$subdir")
                if [[ "$pkg_name" == *"${base_pattern}"* ]]; then
                    results+=("${subdir}/MASTER.md")
                fi
            else
                # Subdirectory — search for standalone files and packages within it
                while IFS= read -r -d '' file; do
                    results+=("$file")
                done < <(find "$subdir" -maxdepth 1 -name "*${base_pattern}*.md" -type f -print0 2>/dev/null)

                while IFS= read -r -d '' pkgdir; do
                    if [[ -f "${pkgdir}/MASTER.md" ]]; then
                        local inner_pkg_name
                        inner_pkg_name=$(basename "$pkgdir")
                        if [[ "$inner_pkg_name" == *"${base_pattern}"* ]]; then
                            results+=("${pkgdir}/MASTER.md")
                        fi
                    fi
                done < <(find "$subdir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
            fi
        done < <(find "$CLAUDE_PLANS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    # Output results (deduplicate in case of overlapping matches)
    printf '%s\n' "${results[@]}" | sort -u
}

# Try to relocate a plan file that might have been moved
# Supports both standalone plans and packages (folders with MASTER.md)
# Returns: new path if found, empty string if not found
# Unlike resolve_plan_path, this doesn't prompt for interactive selection
try_relocate_plan() {
    local original_path="$1"

    # If file exists, return as-is
    if [[ -f "$original_path" ]]; then
        echo "$original_path"
        return 0
    fi

    # If it's a package directory and exists, return MASTER.md
    if [[ -d "$original_path" && -f "${original_path}/MASTER.md" ]]; then
        echo "${original_path}/MASTER.md"
        return 0
    fi

    # Extract basename - handle both files and package MASTER.md paths
    local basename item_name
    basename=$(basename "$original_path")

    # Check if this was a MASTER.md inside a package folder
    local parent_dir
    parent_dir=$(dirname "$original_path")
    if [[ "$basename" == "MASTER.md" ]]; then
        # This was a package - look for the package folder
        item_name=$(basename "$parent_dir")
    else
        item_name="$basename"
    fi

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
    for stage in completed active drafts abandoned playbooks; do
        # Check for standalone file
        local candidate="${plans_dir}/${stage}/${item_name}"
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi

        # Check for package folder (remove .md if present for folder search)
        local folder_name="${item_name%.md}"
        local pkg_candidate="${plans_dir}/${stage}/${folder_name}"
        if [[ -d "$pkg_candidate" && -f "${pkg_candidate}/MASTER.md" ]]; then
            echo "${pkg_candidate}/MASTER.md"
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
# Supports both standalone plans and packages (directories with MASTER.md)
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

        # If it's a package directory, return MASTER.md
        if [[ -d "$abs_path" && -f "${abs_path}/MASTER.md" ]]; then
            echo "${abs_path}/MASTER.md"
            return 0
        fi

        # File/folder doesn't exist at given path - extract name and search
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
        # Indicate if this is a package MASTER.md
        if [[ "$match" == */MASTER.md ]]; then
            local pkg_dir
            pkg_dir=$(dirname "$match")
            display_path="${pkg_dir/#$HOME/~} [PACKAGE]"
        fi
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
