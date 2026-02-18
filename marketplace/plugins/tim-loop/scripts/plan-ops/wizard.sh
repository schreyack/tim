#!/usr/bin/env bash
# plan-ops/wizard.sh - Wizard orchestration
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, search.sh, security.sh, status.sh, approval.sh, verification.sh, wizard-steps.sh
# Exports: cmd_wizard, wizard_update_paths_after_move
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh
# shellcheck source=plan-ops/search.sh
# shellcheck source=plan-ops/status.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# WIZARD HELPERS
# =============================================================================

# Reset plan for full review - moves to drafts and resets status fields
# Usage: reset_plan_for_full_review "$current_state"
# Uses global: WIZARD_PLAN_FILE, WIZARD_IS_PACKAGE, WIZARD_PACKAGE_DIR, WIZARD_USER_NAME
reset_plan_for_full_review() {
    local current_state="$1"
    echo ""
    log_info "Resetting plan for full review..."

    # Move plan to drafts if not already there
    if [[ "$WIZARD_PLAN_FILE" != *"/drafts/"* ]]; then
        local plans_dir
        plans_dir=$(get_plans_dir_from_path "$WIZARD_PLAN_FILE")
        mkdir -p "${plans_dir}/drafts"

        if [[ "$WIZARD_IS_PACKAGE" == true ]]; then
            local pkg_name="${WIZARD_PACKAGE_DIR##*/}"
            local new_pkg_dir="${plans_dir}/drafts/${pkg_name}"
            mv "$WIZARD_PACKAGE_DIR" "$new_pkg_dir"
            WIZARD_PACKAGE_DIR="$new_pkg_dir"
            WIZARD_PLAN_FILE="${new_pkg_dir}/MASTER.md"
            log_info "Moved package to: $WIZARD_PACKAGE_DIR"
        else
            local basename new_path
            basename=$(basename "$WIZARD_PLAN_FILE")
            new_path="${plans_dir}/drafts/${basename}"
            mv "$WIZARD_PLAN_FILE" "$new_path"
            WIZARD_PLAN_FILE="$new_path"
            log_info "Moved plan to: $WIZARD_PLAN_FILE"
        fi
    fi

    # Reset status fields for full review
    reset_for_full_review "$WIZARD_PLAN_FILE"

    # Ensure all required Status Header fields exist (fixes plans with missing fields)
    ensure_status_header_fields "$WIZARD_PLAN_FILE"

    # Add progress log entry
    update_status "$WIZARD_PLAN_FILE" "draft" "Reset for full review by ${WIZARD_USER_NAME}"

    local new_state
    new_state=$(get_plan_state "$WIZARD_PLAN_FILE")
    log_info "Plan reset complete. New state: $new_state"
}

# Update wizard path variables after a stage move
# Usage: wizard_update_paths_after_move "active"
wizard_update_paths_after_move() {
    local new_stage="$1"
    local plans_dir
    plans_dir=$(get_plans_dir_from_path "$WIZARD_PLAN_FILE")

    if [[ "$WIZARD_IS_PACKAGE" == true ]]; then
        local pkg_name="${WIZARD_PACKAGE_DIR##*/}"
        local new_pkg_dir="${plans_dir}/${new_stage}/${pkg_name}"
        if [[ -d "$new_pkg_dir" ]]; then
            WIZARD_PACKAGE_DIR="$new_pkg_dir"
            WIZARD_PLAN_FILE="${new_pkg_dir}/MASTER.md"
            log_info "Updated package path: $WIZARD_PACKAGE_DIR"
        fi
    else
        local basename="${WIZARD_PLAN_FILE##*/}"
        local new_path="${plans_dir}/${new_stage}/${basename}"
        if [[ -f "$new_path" ]]; then
            WIZARD_PLAN_FILE="$new_path"
            log_info "Updated path: $WIZARD_PLAN_FILE"
        fi
    fi
}

# =============================================================================
# PLAN PICKER (no-argument wizard)
# =============================================================================

# Show a numbered list of recent plans and let user pick one
# Searches plans/ stages and ~/.claude/plans/
# Sorted by filename (which contains timestamp) most recent first
# Outputs: selected plan's absolute path
wizard_pick_plan() {
    local all_plans=()

    # Collect plans from all stage directories
    if [[ -d "$PLANS_DIR" ]]; then
        local abs_plans_dir
        abs_plans_dir=$(to_absolute "$PLANS_DIR")

        for stage in drafts active; do
            local stage_dir="${abs_plans_dir}/${stage}"
            [[ -d "$stage_dir" ]] || continue

            # Standalone plans
            while IFS= read -r -d '' file; do
                all_plans+=("$file")
            done < <(find "$stage_dir" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)

            # Package plans (directories with MASTER.md)
            while IFS= read -r -d '' dir; do
                if [[ -f "${dir}/MASTER.md" ]]; then
                    all_plans+=("${dir}/MASTER.md")
                fi
            done < <(find "$stage_dir" -maxdepth 1 -type d ! -name "$stage" -print0 2>/dev/null)
        done
    fi

    # Also check ~/.claude/plans/
    if [[ -d "$CLAUDE_PLANS_DIR" ]]; then
        while IFS= read -r -d '' file; do
            all_plans+=("$file")
        done < <(find "$CLAUDE_PLANS_DIR" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)
    fi

    if [[ ${#all_plans[@]} -eq 0 ]]; then
        log_error "No plans found."
        log_info "Searched in: $(to_absolute "$PLANS_DIR")/{drafts,active}, $CLAUDE_PLANS_DIR"
        exit 1
    fi

    # Build sortable entries: "sortkey|path"
    # Sort key is the plan/package name (starts with timestamp)
    local sort_entries=()
    for plan in "${all_plans[@]}"; do
        local name
        if [[ "$(basename "$plan")" == "MASTER.md" ]]; then
            name=$(basename "$(dirname "$plan")")
        else
            name=$(basename "$plan" .md)
        fi
        sort_entries+=("${name}|${plan}")
    done

    # Sort reverse by name (timestamp prefix = most recent first)
    local sorted
    sorted=$(printf '%s\n' "${sort_entries[@]}" | sort -t'|' -k1 -r)

    # Display numbered list (all display output to stderr since stdout is captured)
    echo "" >&2
    echo "=== Recent Plans ===" >&2
    echo "" >&2
    local i=1
    local paths=()
    while IFS='|' read -r name path; do
        local stage_label=""
        case "$path" in
            */drafts/*)    stage_label="draft" ;;
            */active/*)    stage_label="active" ;;
            */completed/*) stage_label="done" ;;
            */abandoned/*) stage_label="abandoned" ;;
            *)             stage_label="import" ;;
        esac

        local pkg_label=""
        if [[ "$(basename "$path")" == "MASTER.md" ]]; then
            pkg_label=" [PACKAGE]"
        fi

        printf "  [%2d] %-12s %s%s\n" "$i" "($stage_label)" "$name" "$pkg_label" >&2
        paths+=("$path")
        ((i++))
    done <<< "$sorted"

    echo "" >&2
    local count=${#paths[@]}
    local choice
    while true; do
        echo -n "Select plan [1-${count}]: " >&2
        read -r choice </dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
            echo "${paths[$((choice-1))]}"
            return 0
        fi
        echo "Invalid choice. Enter a number between 1 and $count." >&2
    done
}

# =============================================================================
# WIZARD COMMAND
# =============================================================================

cmd_wizard() {
    local plan_file="${1:-}"
    local status_only=false

    # Parse --status flag
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status) status_only=true; shift ;;
            *) shift ;;
        esac
    done

    # No argument: show interactive plan picker
    if [[ -z "$plan_file" ]]; then
        plan_file=$(wizard_pick_plan)
    fi

    # Handle package directories - if user passes a folder with MASTER.md, use that
    if [[ -d "$plan_file" && -f "${plan_file}/MASTER.md" ]]; then
        plan_file="${plan_file}/MASTER.md"
    fi

    # Resolve plan name or path to absolute path
    WIZARD_PLAN_FILE=$(resolve_plan_path "$plan_file") || exit 1

    # Track if we're working with a package
    WIZARD_IS_PACKAGE=false
    WIZARD_PACKAGE_DIR=""
    if is_master_plan "$WIZARD_PLAN_FILE"; then
        WIZARD_IS_PACKAGE=true
        WIZARD_PACKAGE_DIR=$(dirname "$WIZARD_PLAN_FILE")
    fi

    # Get current state
    local state
    state=$(get_plan_state "$WIZARD_PLAN_FILE")

    # Status-only mode - show status and exit without entering interactive wizard
    if [[ "$status_only" == "true" ]]; then
        show_plan_status "$WIZARD_PLAN_FILE" "$state"
        exit 0
    fi

    # Ctrl+C handler for graceful exit
    trap 'echo ""; log_warn "Wizard cancelled. Run again to resume."; exit 1' INT

    # Header
    echo ""
    echo "=== Plan Wizard ==="
    if [[ "$WIZARD_IS_PACKAGE" == true ]]; then
        local pkg_name file_count
        pkg_name=$(basename "$WIZARD_PACKAGE_DIR")
        file_count=$(find "$WIZARD_PACKAGE_DIR" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
        echo -e "Package: ${GREEN}${pkg_name}/${NC} (${file_count} files)"
        echo "Master:  $WIZARD_PLAN_FILE"
    else
        echo "Plan: $WIZARD_PLAN_FILE"
    fi

    # Ask for user name once, reuse across all steps
    WIZARD_USER_NAME=$(prompt_for_name "Enter your name")

    # Check if plan is in plans/ root but not in a subfolder - move to appropriate folder
    if [[ "$WIZARD_PLAN_FILE" == *"/plans/"* ]] && \
       [[ "$WIZARD_PLAN_FILE" != *"/plans/drafts/"* ]] && \
       [[ "$WIZARD_PLAN_FILE" != *"/plans/active/"* ]] && \
       [[ "$WIZARD_PLAN_FILE" != *"/plans/completed/"* ]] && \
       [[ "$WIZARD_PLAN_FILE" != *"/plans/abandoned/"* ]]; then

        # Determine which folder based on Stage field
        local stage
        stage=$(get_status_field "$WIZARD_PLAN_FILE" "Stage")
        local target_folder="drafts"  # default
        case "$stage" in
            active) target_folder="active" ;;
            completed) target_folder="completed" ;;
            abandoned) target_folder="abandoned" ;;
        esac

        local basename plans_dir new_path
        basename=$(basename "$WIZARD_PLAN_FILE")
        plans_dir=$(dirname "$WIZARD_PLAN_FILE")
        new_path="${plans_dir}/${target_folder}/${basename}"

        echo ""
        log_info "Plan is in plans/ root, moving to ${target_folder}/..."
        mkdir -p "${plans_dir}/${target_folder}"
        mv "$WIZARD_PLAN_FILE" "$new_path"
        WIZARD_PLAN_FILE="$new_path"
        log_info "Moved to: $WIZARD_PLAN_FILE"

        # Refresh state after move
        state=$(get_plan_state "$WIZARD_PLAN_FILE")
    fi

    # Offer full review option for any valid plan state
    if [[ "$state" != "not-found" && "$state" != "import" && "$state" != "unknown" ]]; then
        echo ""
        echo "Current state: $state"
        echo -n "Would you like to run a full review on this plan? [y/N] "
        read -r response </dev/tty
        if [[ "$response" =~ ^[Yy] ]]; then
            reset_plan_for_full_review "$state"
            state=$(get_plan_state "$WIZARD_PLAN_FILE")
        fi
    fi

    # Check if plan is already completed - offer verification step
    if [[ "$state" == "done" ]]; then
        echo ""
        log_info "This plan is already marked as completed."
        run_verification_tim_loop "$WIZARD_PLAN_FILE" "Run verification tim-loop on completed plan? [y/N] "

        # Move plan to completed/ folder if not already there
        if [[ "$WIZARD_PLAN_FILE" != *"/plans/completed/"* ]]; then
            echo ""
            log_info "Moving plan to completed/ folder..."
            cmd_complete "$WIZARD_PLAN_FILE"
            wizard_update_paths_after_move "completed"
        fi

        echo ""
        echo "------------------------------------------------------------"
        echo -e "${GREEN}Plan lifecycle complete!${NC}"
        echo "------------------------------------------------------------"
        return
    fi

    # Main wizard loop - continues until plan is completed
    while [[ "$state" != "done" ]]; do
        case "$state" in
            import)          wizard_step_import ;;
            review)          wizard_step_review ;;
            pm-review)       wizard_step_pm_review ;;
            promote)         wizard_step_promote ;;
            ai-ready)        wizard_step_ai_ready ;;
            tim-loop)        wizard_step_tim_loop ;;
            complete)        wizard_step_complete ;;
            not-found)
                log_error "Plan file not found: $WIZARD_PLAN_FILE"
                exit 1
                ;;
            abandoned)
                log_warn "Plan was abandoned. Cannot continue."
                exit 0
                ;;
            unknown)
                # Try to add Status Header for files in plans/ folder
                if [[ "$WIZARD_PLAN_FILE" == *"/plans/"* ]]; then
                    log_info "Adding Status Header to plan..."
                    add_status_header "$WIZARD_PLAN_FILE" "Unknown"
                    ensure_status_header_fields "$WIZARD_PLAN_FILE"
                    local new_state
                    new_state=$(get_plan_state "$WIZARD_PLAN_FILE")
                    if [[ "$new_state" == "unknown" ]]; then
                        # Status header exists but Stage is invalid - try to fix it
                        log_info "Attempting to fix invalid Stage field..."
                        if fix_invalid_stage "$WIZARD_PLAN_FILE"; then
                            new_state=$(get_plan_state "$WIZARD_PLAN_FILE")
                            if [[ "$new_state" == "unknown" ]]; then
                                log_error "Unable to fix Status Header. Stage field is still invalid."
                                log_error "Please manually check: $WIZARD_PLAN_FILE"
                                exit 1
                            fi
                            log_info "Stage field fixed successfully."
                        else
                            log_error "Plan has Status Header but Stage field could not be fixed."
                            log_error "Please check the Status Header in: $WIZARD_PLAN_FILE"
                            exit 1
                        fi
                    fi
                    state="$new_state"
                    continue
                else
                    log_error "Plan has no Status Header and is not in plans/ folder"
                    exit 1
                fi
                ;;
        esac

        # Refresh state after each step (path may have changed due to move)
        state=$(get_plan_state "$WIZARD_PLAN_FILE")
    done

    # Success - plan reached completed state
    echo ""
    echo "------------------------------------------------------------"
    echo -e "${GREEN}Plan lifecycle complete!${NC}"
    echo "------------------------------------------------------------"
}
