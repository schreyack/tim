#!/usr/bin/env bash
# plan-ops/wizard.sh - Wizard orchestration
# Sourced by plan-ops.sh. Dependencies: core, search, security, status, approval, verification, wizard-steps
# See also: wizard-steps.sh for reset_plan_for_full_review, wizard_update_paths_after_move
# shellcheck source=plan-ops/core.sh
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && { echo "ERROR: Must be sourced" >&2; exit 1; }

# Show plans and playbooks in separate sections, return selected path
wizard_pick_plan() {
    local plan_files=() playbook_files=()

    if [[ -d "$PLANS_DIR" ]]; then
        local abs_plans_dir
        abs_plans_dir=$(to_absolute "$PLANS_DIR")

        # Plans: drafts and active
        for stage in drafts active; do
            local stage_dir="${abs_plans_dir}/${stage}"
            [[ -d "$stage_dir" ]] || continue
            while IFS= read -r -d '' file; do
                plan_files+=("$file")
            done < <(find "$stage_dir" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)
            while IFS= read -r -d '' dir; do
                [[ -f "${dir}/MASTER.md" ]] && plan_files+=("${dir}/MASTER.md")
            done < <(find "$stage_dir" -maxdepth 1 -type d ! -name "$stage" -print0 2>/dev/null)
        done

        # Playbooks: root + orchestrations/ + automations/
        local pb_dir="${abs_plans_dir}/playbooks"
        if [[ -d "$pb_dir" ]]; then
            while IFS= read -r -d '' file; do
                playbook_files+=("$file")
            done < <(find "$pb_dir" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)
            for subdir in orchestrations automations; do
                [[ -d "${pb_dir}/${subdir}" ]] || continue
                while IFS= read -r -d '' file; do
                    playbook_files+=("$file")
                done < <(find "${pb_dir}/${subdir}" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)
            done
        fi
    fi

    # CLAUDE_PLANS_DIR — always plan territory
    if [[ -d "$CLAUDE_PLANS_DIR" ]]; then
        while IFS= read -r -d '' file; do
            plan_files+=("$file")
        done < <(find "$CLAUDE_PLANS_DIR" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)
        while IFS= read -r -d '' subdir; do
            if [[ -f "${subdir}/MASTER.md" ]]; then
                plan_files+=("${subdir}/MASTER.md")
            else
                while IFS= read -r -d '' file; do
                    plan_files+=("$file")
                done < <(find "$subdir" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)
                while IFS= read -r -d '' pkgdir; do
                    [[ -f "${pkgdir}/MASTER.md" ]] && plan_files+=("${pkgdir}/MASTER.md")
                done < <(find "$subdir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
            fi
        done < <(find "$CLAUDE_PLANS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    fi

    if [[ ${#plan_files[@]} -eq 0 && ${#playbook_files[@]} -eq 0 ]]; then
        log_error "No plans or playbooks found."
        log_info "Searched in: $(to_absolute "$PLANS_DIR")/{drafts,active,playbooks}, $CLAUDE_PLANS_DIR"
        exit 1
    fi

    # Build unified numbered list across both sections (stderr — stdout is captured)
    local paths=() i=1

    # --- Plans section ---
    if [[ ${#plan_files[@]} -gt 0 ]]; then
        local plan_sort=()
        for f in "${plan_files[@]}"; do
            local name
            [[ "$(basename "$f")" == "MASTER.md" ]] && name=$(basename "$(dirname "$f")") || name=$(basename "$f" .md)
            plan_sort+=("${name}|${f}")
        done
        echo "" >&2
        echo "=== Plans ===" >&2
        echo "" >&2
        while IFS='|' read -r name path; do
            local label=""
            case "$path" in
                */drafts/*) label="draft" ;; */active/*) label="active" ;; *) label="import" ;;
            esac
            local pkg=""
            [[ "$(basename "$path")" == "MASTER.md" ]] && pkg=" [PKG]"
            printf "  [%2d] %-10s %s%s\n" "$i" "($label)" "$name" "$pkg" >&2
            paths+=("$path"); ((i++))
        done < <(printf '%s\n' "${plan_sort[@]}" | sort -t'|' -k1 -r)
    fi

    # --- Playbooks section ---
    if [[ ${#playbook_files[@]} -gt 0 ]]; then
        local pb_sort=()
        for f in "${playbook_files[@]}"; do
            local name tier_key
            name=$(basename "$f" .md)
            case "$f" in
                */orchestrations/*) tier_key="0" ;; */automations/*) tier_key="1" ;; *) tier_key="2" ;;
            esac
            pb_sort+=("${tier_key}|${name}|${f}")
        done
        echo "" >&2
        echo "=== Playbooks ===" >&2
        echo "" >&2
        while IFS='|' read -r tier_key name path; do
            local tier=""
            case "$tier_key" in
                0) tier="orch" ;; 1) tier="auto" ;; 2) tier="root" ;;
            esac
            printf "  [%2d] %-10s %s\n" "$i" "($tier)" "$name" >&2
            paths+=("$path"); ((i++))
        done < <(printf '%s\n' "${pb_sort[@]}" | sort -t'|' -k1,1 -k2,2)
    fi

    echo "" >&2
    local count=${#paths[@]}
    local choice
    while true; do
        echo -n "Select [1-${count}]: " >&2
        read -r choice </dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
            echo "${paths[$((choice-1))]}"
            return 0
        fi
        echo "Invalid choice. Enter a number between 1 and $count." >&2
    done
}

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

    # Playbook launcher: automations/orchestrations bypass plan lifecycle
    if [[ "$plan_file" == *"/playbooks/orchestrations/"* || "$plan_file" == *"/playbooks/automations/"* ]]; then
        wizard_playbook_launcher "$plan_file"
        return
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
       [[ "$WIZARD_PLAN_FILE" != *"/plans/abandoned/"* ]] && \
       [[ "$WIZARD_PLAN_FILE" != *"/plans/playbooks/"* ]]; then

        # Determine which folder based on Stage field
        local stage
        stage=$(get_status_field "$WIZARD_PLAN_FILE" "Stage")
        local target_folder="drafts"  # default
        case "$stage" in
            active) target_folder="active" ;;
            completed) target_folder="completed" ;;
            abandoned) target_folder="abandoned" ;;
            playbook) target_folder="playbooks" ;;
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

    # Completed plan - offer verification or reopen
    if [[ "$state" == "done" ]]; then
        echo ""
        log_info "This plan is already marked as completed."
        echo "  [1] Run verification tim-loop  [2] Reopen to drafts"
        echo "  [3] Reopen to active           [4] Exit"
        echo -n "Choice [1-4]: "
        read -r done_choice </dev/tty
        case "$done_choice" in
            1)
                run_verification_tim_loop "$WIZARD_PLAN_FILE" "Confirm: run verification? [Y/n] "
                if [[ "$WIZARD_PLAN_FILE" != *"/plans/completed/"* ]]; then
                    cmd_complete "$WIZARD_PLAN_FILE"
                    wizard_update_paths_after_move "completed"
                fi
                ;;
            2|3)
                local reopen_target="drafts"
                [[ "$done_choice" == "3" ]] && reopen_target="active"
                cmd_reopen "$WIZARD_PLAN_FILE" --to "$reopen_target" --reason "Reopened via wizard"
                wizard_update_paths_after_move "$reopen_target"
                state=$(get_plan_state "$WIZARD_PLAN_FILE")
                ;;
        esac
        if [[ "$done_choice" == "2" || "$done_choice" == "3" ]]; then
            :  # Continue to main wizard loop
        else
            echo ""
            echo "------------------------------------------------------------"
            echo -e "${GREEN}Plan lifecycle complete!${NC}"
            echo "------------------------------------------------------------"
            return
        fi
    fi

    # Playbook-ready state - offer run/history/reopen
    if [[ "$state" == "playbook-ready" ]]; then
        echo ""
        log_info "This is a completed playbook, ready to run."
        # Show run stats
        local run_count last_run last_result
        run_count=$(get_status_field "$WIZARD_PLAN_FILE" "Run Count")
        last_run=$(get_status_field "$WIZARD_PLAN_FILE" "Last Run")
        last_result=$(get_status_field "$WIZARD_PLAN_FILE" "Last Result")
        [[ "$run_count" != "-" && "$run_count" != "0" ]] && \
            echo "  Run Count: $run_count | Last Run: $last_run | Last Result: $last_result"
        echo ""
        echo "  [1] Run playbook  [2] Show run history  [3] Reopen to drafts  [4] Exit"
        echo -n "Choice [1-4]: "
        read -r pb_choice </dev/tty
        case "$pb_choice" in
            1) cmd_playbook_run "$WIZARD_PLAN_FILE" ;;
            2) cmd_playbook_show "$WIZARD_PLAN_FILE" ;;
            3) cmd_reopen "$WIZARD_PLAN_FILE" --to drafts --reason "Reopened via wizard"
               wizard_update_paths_after_move "drafts"
               state=$(get_plan_state "$WIZARD_PLAN_FILE") ;;
        esac
        if [[ "$pb_choice" != "3" ]]; then return; fi
    fi

    # Main wizard loop - continues until plan is completed
    while [[ "$state" != "done" && "$state" != "playbook-ready" ]]; do
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
                log_warn "Plan was abandoned."
                echo -n "Reopen? [y/N] "
                read -r response </dev/tty
                if [[ "$response" =~ ^[Yy] ]]; then
                    echo "  [1] drafts (full review)  [2] active (re-implement)"
                    echo -n "Choice [1-2]: "
                    read -r reopen_choice </dev/tty
                    local reopen_target="drafts"
                    [[ "$reopen_choice" == "2" ]] && reopen_target="active"
                    cmd_reopen "$WIZARD_PLAN_FILE" --to "$reopen_target" --reason "Reopened via wizard"
                    wizard_update_paths_after_move "$reopen_target"
                    state=$(get_plan_state "$WIZARD_PLAN_FILE")
                    continue
                fi
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

    # Playbook completed through lifecycle
    if [[ "$state" == "playbook-ready" ]]; then
        echo ""
        echo "------------------------------------------------------------"
        echo -e "${GREEN}Playbook ready to run!${NC}"
        echo "------------------------------------------------------------"
        cmd_playbook_show "$WIZARD_PLAN_FILE"
        echo ""
        echo "Run with:"
        show_command "plan-ops playbook run $(basename "$WIZARD_PLAN_FILE" .md)"
        return
    fi

    # Success - plan reached completed state
    echo ""
    echo "------------------------------------------------------------"
    echo -e "${GREEN}Plan lifecycle complete!${NC}"
    echo "------------------------------------------------------------"
}
