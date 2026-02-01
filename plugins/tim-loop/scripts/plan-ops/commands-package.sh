#!/usr/bin/env bash
# plan-ops/commands-package.sh - Package management commands
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, search.sh
# Exports: cmd_package, create_package
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# PACKAGE COMMAND
# =============================================================================

# Extract keywords from a plan filename for grouping
# Usage: keywords=$(extract_keywords "2026-02-01-feature-auth.md")
extract_keywords() {
    local filename="$1"
    # Remove date prefix and extension, split on dashes
    echo "$filename" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//; s/\.md$//' | tr '-' '\n' | sort -u
}

# Find related plans based on date and keywords
# Usage: related=$(find_related_plans "2026-02-01" "feature auth login")
find_related_plans() {
    local date_prefix="$1"
    local keywords="$2"
    local stage_dir="${PLANS_DIR}/drafts"
    local results=()

    [[ ! -d "$stage_dir" ]] && return

    while IFS= read -r -d '' file; do
        local basename
        basename=$(basename "$file")
        # Check date prefix match
        if [[ "$basename" == "${date_prefix}-"* ]]; then
            # Check keyword overlap
            local file_keywords
            file_keywords=$(extract_keywords "$basename")
            for kw in $keywords; do
                if echo "$file_keywords" | grep -qiw "$kw"; then
                    results+=("$file")
                    break
                fi
            done
        fi
    done < <(find "$stage_dir" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)

    printf '%s\n' "${results[@]}" | sort -u
}

# Suggest a clean name for a plan file (strips auto-generated suffixes)
# Usage: clean_name=$(suggest_clean_name "2026-02-01-review-plansdrafts2026...md")
suggest_clean_name() {
    local filename="$1"
    local clean

    # Remove common auto-generated patterns
    clean=$(echo "$filename" | sed '
        s/\.md$//;
        s/-review-plansdrafts[^-]*//gi;
        s/-review-docsinternalwhat[^-]*//gi;
        s/-again-review[^-]*//gi;
        s/-with-[^-]*$//gi;
        s/-as$//gi;
    ')

    # If the result is just a date, try to extract meaningful words
    if [[ "$clean" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        clean="${filename%.md}"
    fi

    echo "$clean"
}

cmd_package() {
    local first_arg="${1:-}"
    local master_file=""
    local include_pattern=""
    local package_name=""

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --master)
                master_file="$2"
                shift 2
                ;;
            --include)
                include_pattern="$2"
                shift 2
                ;;
            --name)
                package_name="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local stage_dir="${PLANS_DIR}/drafts"

    # Ensure drafts directory exists
    if [[ ! -d "$stage_dir" ]]; then
        log_error "Drafts directory not found: $stage_dir"
        log_info "Run '$SCRIPT_PATH init' first"
        exit 1
    fi

    # Interactive mode if no arguments specified
    if [[ -z "$first_arg" ]]; then
        package_interactive
        return
    fi

    # Smart mode: if first arg looks like a file, use it as master
    if [[ -z "$master_file" ]]; then
        # Check if first_arg is a file (ends with .md or can be resolved)
        if [[ "$first_arg" == *.md ]] || [[ -f "$first_arg" ]]; then
            # Resolve the file path
            if [[ -f "$first_arg" ]]; then
                master_file="$first_arg"
            else
                master_file=$(resolve_plan_path "$first_arg" 2>/dev/null) || {
                    log_error "Could not find plan file: $first_arg"
                    exit 1
                }
            fi
            master_file=$(to_absolute "$master_file")

            # Derive package name from filename if not specified
            if [[ -z "$package_name" ]]; then
                package_name=$(suggest_clean_name "$(basename "$master_file")")
            fi

            # Auto-find related files by date prefix
            local date_prefix
            date_prefix=$(basename "$master_file" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || echo "")
            if [[ -n "$date_prefix" && -z "$include_pattern" ]]; then
                include_pattern="${date_prefix}-*.md"
            fi
        else
            # First arg is a package name, require --master
            package_name="$first_arg"
            if [[ -z "$master_file" ]]; then
                log_error "Usage: $SCRIPT_PATH package <file.md> [--name <name>] [--include <pattern>]"
                log_error "   or: $SCRIPT_PATH package <name> --master <file> [--include <pattern>]"
                log_error "   or: $SCRIPT_PATH package  (interactive mode)"
                exit 1
            fi
        fi
    else
        # --master was specified, first_arg is the package name
        package_name="$first_arg"
    fi

    # Resolve master file if not already done
    if [[ ! -f "$master_file" ]]; then
        master_file=$(resolve_plan_path "$master_file") || exit 1
        master_file=$(to_absolute "$master_file")
    fi

    # Find files to include
    local files_to_include=()
    files_to_include+=("$master_file")

    if [[ -n "$include_pattern" ]]; then
        local search_dir
        search_dir=$(dirname "$master_file")
        while IFS= read -r file; do
            [[ -f "$file" && "$file" != "$master_file" ]] && files_to_include+=("$file")
        done < <(find "$search_dir" -maxdepth 1 -name "$include_pattern" -type f 2>/dev/null)
    fi

    create_package "$package_name" "$master_file" "${files_to_include[@]}"
}

# Interactive package creation
package_interactive() {
    local stage_dir="${PLANS_DIR}/drafts"

    # Find all draft plans
    local all_plans=()
    while IFS= read -r -d '' file; do
        all_plans+=("$file")
    done < <(find "$stage_dir" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null | sort -z)

    if [[ ${#all_plans[@]} -eq 0 ]]; then
        log_info "No plans found in drafts/"
        return
    fi

    echo ""
    echo "Found ${#all_plans[@]} plans in drafts/. Let's organize them."
    echo ""

    # Group plans by date prefix
    declare -A date_groups
    for file in "${all_plans[@]}"; do
        local basename date_prefix
        basename=$(basename "$file")
        date_prefix=$(echo "$basename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || echo "undated")
        date_groups["$date_prefix"]+="$file"$'\n'
    done

    # Find potential packages (groups with 2+ files on same date)
    local found_groups=false
    for date in $(echo "${!date_groups[@]}" | tr ' ' '\n' | sort -r); do
        local files_in_group
        files_in_group=$(echo -n "${date_groups[$date]}" | grep -c .)

        if [[ "$files_in_group" -ge 2 ]]; then
            found_groups=true
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo -e "${GREEN}Possible package:${NC} ${date} (${files_in_group} files)"
            echo ""

            local i=1
            local options=()
            while IFS= read -r file; do
                [[ -z "$file" ]] && continue
                local basename size_kb
                basename=$(basename "$file")
                size_kb=$(( $(wc -c < "$file") / 1024 ))
                local clean_name
                clean_name=$(suggest_clean_name "$basename")
                printf "  [%d] %s (%dKB)\n" "$i" "$basename" "$size_kb"
                if [[ "$clean_name" != "${basename%.md}" ]]; then
                    echo "      → suggested: ${clean_name}.md"
                fi
                options+=("$file")
                ((i++))
            done <<< "${date_groups[$date]}"

            echo ""
            echo -n "Create package from these files? [y/N] "
            read -r response </dev/tty

            if [[ "$response" =~ ^[Yy] ]]; then
                # Ask which file is MASTER
                echo ""
                echo -n "Which file is the MASTER (implementation plan)? [1-$((i-1))]: "
                read -r master_choice </dev/tty

                if [[ ! "$master_choice" =~ ^[0-9]+$ ]] || \
                   [[ "$master_choice" -lt 1 ]] || \
                   [[ "$master_choice" -gt $((i-1)) ]]; then
                    log_warn "Invalid choice, skipping this group"
                    continue
                fi

                local master_file="${options[$((master_choice-1))]}"

                # Suggest package name
                local suggested_name
                suggested_name=$(suggest_clean_name "$(basename "$master_file")")
                echo ""
                echo -n "Package name [${suggested_name}]: "
                read -r pkg_name </dev/tty
                [[ -z "$pkg_name" ]] && pkg_name="$suggested_name"

                # Create the package
                create_package "$pkg_name" "$master_file" "${options[@]}"
                echo ""
            fi
        fi
    done

    if [[ "$found_groups" == false ]]; then
        log_info "No groups of related plans found (need 2+ plans with same date)"
    fi
}

# Create a package folder and move files into it
# Usage: create_package "package-name" "master-file" "file1" "file2" ...
create_package() {
    local pkg_name="$1"
    local master_file="$2"
    shift 2
    local files=("$@")

    local stage_dir
    stage_dir=$(dirname "$master_file")
    local pkg_dir="${stage_dir}/${pkg_name}"

    # Check if package already exists
    if [[ -d "$pkg_dir" ]]; then
        log_error "Package already exists: $pkg_dir"
        return 1
    fi

    # Create package directory
    mkdir -p "$pkg_dir"
    log_info "Created package: $pkg_dir"

    # Move master file as MASTER.md
    mv "$master_file" "${pkg_dir}/MASTER.md"
    log_info "  MASTER.md ← $(basename "$master_file")"

    # Move other files with suggested clean names
    for file in "${files[@]}"; do
        [[ "$file" == "$master_file" ]] && continue
        [[ ! -f "$file" ]] && continue

        local basename new_name
        basename=$(basename "$file")
        new_name=$(suggest_clean_name "$basename")

        # Avoid naming conflicts
        local dest="${pkg_dir}/${new_name}.md"
        local counter=1
        while [[ -f "$dest" ]]; do
            dest="${pkg_dir}/${new_name}-${counter}.md"
            ((counter++))
        done

        mv "$file" "$dest"
        log_info "  $(basename "$dest") ← ${basename}"
    done

    echo ""
    log_info "Package created successfully!"
    log_info "NEXT STEP: Run the wizard on the package:"
    show_command "$SCRIPT_PATH wizard ${pkg_dir}"
}
