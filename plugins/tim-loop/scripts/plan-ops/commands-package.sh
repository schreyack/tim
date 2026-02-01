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

# Check subfolders for potential packages
# Usage: check_subfolder_packages "/path/to/drafts"
check_subfolder_packages() {
    local stage_dir="$1"
    local found_any=false

    while IFS= read -r -d '' subdir; do
        local dirname
        dirname=$(basename "$subdir")
        [[ "$dirname" == .* ]] && continue

        local md_files=()
        while IFS= read -r -d '' file; do
            md_files+=("$file")
        done < <(find "$subdir" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)

        [[ ${#md_files[@]} -eq 0 ]] && continue
        [[ -f "${subdir}/MASTER.md" ]] && continue

        found_any=true
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}Found plans in subfolder:${NC} ${dirname}/"
        echo ""
        show_file_list md_files

        printf "\nConvert this folder to a package? [y/N] "
        read -r response </dev/tty

        if [[ "$response" =~ ^[Yy] ]]; then
            local master_file pkg_name
            master_file=$(prompt_for_master md_files) || continue
            printf "\nPackage name [%s]: " "$dirname"
            read -r pkg_name </dev/tty
            [[ -z "$pkg_name" ]] && pkg_name="$dirname"
            create_package_in_place "$pkg_name" "$subdir" "$master_file" "${md_files[@]}"
            echo ""
        fi
    done < <(find "$stage_dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

    [[ "$found_any" == true ]] && echo ""
}

# Display numbered list of files with sizes
show_file_list() {
    local -n arr=$1
    local i=1
    for file in "${arr[@]}"; do
        local basename size_kb
        basename=$(basename "$file")
        size_kb=$(( $(wc -c < "$file") / 1024 ))
        printf "  [%d] %s (%dKB)\n" "$i" "$basename" "$size_kb"
        ((i++))
    done
}

# Prompt user to select MASTER file, returns path or exits with error
prompt_for_master() {
    local -n arr=$1
    local count=${#arr[@]}
    printf "\nWhich file is the MASTER (implementation plan)? [1-%d]: " "$count" >/dev/tty
    read -r choice </dev/tty
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "$count" ]]; then
        log_warn "Invalid choice, skipping"
        return 1
    fi
    echo "${arr[$((choice-1))]}"
}

# Create a package in place (for existing subfolders)
# Usage: create_package_in_place "package-name" "/path/to/folder" "master-file" "file1" "file2" ...
create_package_in_place() {
    local pkg_name="$1"
    local folder_path="$2"
    local master_file="$3"
    shift 3
    local files=("$@")

    local parent_dir
    parent_dir=$(dirname "$folder_path")
    local pkg_dir="${parent_dir}/${pkg_name}"

    # If folder name differs from package name, rename the folder
    if [[ "$folder_path" != "$pkg_dir" ]]; then
        if [[ -d "$pkg_dir" ]]; then
            log_error "Package directory already exists: $pkg_dir"
            return 1
        fi
        mv "$folder_path" "$pkg_dir"
        log_info "Renamed folder: $(basename "$folder_path") → ${pkg_name}"
        # Update file paths after rename
        master_file="${pkg_dir}/$(basename "$master_file")"
        local new_files=()
        for file in "${files[@]}"; do
            new_files+=("${pkg_dir}/$(basename "$file")")
        done
        files=("${new_files[@]}")
    fi

    # Use shared helper for file operations
    finalize_package_files "$pkg_dir" "$master_file" "${files[@]}"
}

# Shared helper: finalize package files (rename master, clean names)
finalize_package_files() {
    local pkg_dir="$1"
    local master_file="$2"
    shift 2
    local files=("$@")

    # Rename master file to MASTER.md
    if [[ "$(basename "$master_file")" != "MASTER.md" ]]; then
        mv "$master_file" "${pkg_dir}/MASTER.md"
        log_info "  MASTER.md ← $(basename "$master_file")"
    fi

    # Rename other files with cleaner names
    for file in "${files[@]}"; do
        [[ "$file" == "$master_file" || ! -f "$file" ]] && continue
        [[ "$(basename "$file")" == "MASTER.md" ]] && continue
        local basename new_name
        basename=$(basename "$file")
        new_name=$(suggest_clean_name "$basename")
        [[ "${new_name}.md" == "$basename" ]] && continue
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

# Interactive package creation
package_interactive() {
    local stage_dir="${PLANS_DIR}/drafts"
    check_subfolder_packages "$stage_dir"

    local all_plans=()
    while IFS= read -r -d '' file; do
        all_plans+=("$file")
    done < <(find "$stage_dir" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null | sort -z)

    if [[ ${#all_plans[@]} -eq 0 ]]; then
        log_info "No loose plans found in drafts/"
        return
    fi

    echo ""
    echo "Found ${#all_plans[@]} loose plans in drafts/. Let's organize them."
    echo ""

    # Group plans by date prefix
    declare -A date_groups
    for file in "${all_plans[@]}"; do
        local basename date_prefix
        basename=$(basename "$file")
        date_prefix=$(echo "$basename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || echo "undated")
        date_groups["$date_prefix"]+="$file"$'\n'
    done

    local found_groups=false
    for date in $(echo "${!date_groups[@]}" | tr ' ' '\n' | sort -r); do
        local files_in_group options=()
        files_in_group=$(echo -n "${date_groups[$date]}" | grep -c .)
        [[ "$files_in_group" -lt 2 ]] && continue

        found_groups=true
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}Possible package:${NC} ${date} (${files_in_group} files)"
        echo ""

        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            options+=("$file")
        done <<< "${date_groups[$date]}"
        show_file_list_with_suggestions options

        printf "\nCreate package from these files? [y/N] "
        read -r response </dev/tty
        [[ ! "$response" =~ ^[Yy] ]] && continue

        local master_file pkg_name suggested_name
        master_file=$(prompt_for_master options) || continue
        suggested_name=$(suggest_clean_name "$(basename "$master_file")")
        printf "\nPackage name [%s]: " "$suggested_name"
        read -r pkg_name </dev/tty
        [[ -z "$pkg_name" ]] && pkg_name="$suggested_name"
        create_package "$pkg_name" "$master_file" "${options[@]}"
        echo ""
    done

    [[ "$found_groups" == false ]] && log_info "No groups of related plans found (need 2+ plans with same date)"
}

# Display numbered list of files with sizes and suggested clean names
show_file_list_with_suggestions() {
    local -n arr=$1
    local i=1
    for file in "${arr[@]}"; do
        local basename size_kb clean_name
        basename=$(basename "$file")
        size_kb=$(( $(wc -c < "$file") / 1024 ))
        clean_name=$(suggest_clean_name "$basename")
        printf "  [%d] %s (%dKB)\n" "$i" "$basename" "$size_kb"
        [[ "$clean_name" != "${basename%.md}" ]] && echo "      → suggested: ${clean_name}.md"
        ((i++))
    done
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

    if [[ -d "$pkg_dir" ]]; then
        log_error "Package already exists: $pkg_dir"
        return 1
    fi

    mkdir -p "$pkg_dir"
    log_info "Created package: $pkg_dir"

    # Move files to package directory, then finalize
    local moved_files=("${pkg_dir}/$(basename "$master_file")")
    mv "$master_file" "${moved_files[0]}"
    for file in "${files[@]}"; do
        [[ "$file" == "$master_file" || ! -f "$file" ]] && continue
        local dest="${pkg_dir}/$(basename "$file")"
        mv "$file" "$dest"
        moved_files+=("$dest")
    done
    finalize_package_files "$pkg_dir" "${moved_files[0]}" "${moved_files[@]}"
}
