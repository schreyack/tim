#!/usr/bin/env bash
# plan-ops/wizard.sh - Wizard orchestration
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, search.sh, security.sh, status.sh, approval.sh, verification.sh
# Exports: cmd_wizard, wizard_step_import, wizard_step_review, wizard_step_promote,
#          wizard_step_ai_ready, wizard_step_tim_loop, wizard_step_complete
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
# WIZARD COMMAND AND STEP FUNCTIONS
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

    # Validation
    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH wizard <plan-name-or-path> [--status]"
        log_info "Examples:"
        log_info "  $SCRIPT_PATH wizard new-ui-front-page"
        log_info "  $SCRIPT_PATH wizard ~/.claude/plans/my-plan.md"
        log_info "  $SCRIPT_PATH wizard plans/drafts/2026-02-01-my-package/  # Package folder"
        exit 1
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
            active|in_progress) target_folder="active" ;;
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

    # Check if plan is already completed - offer verification step
    if [[ "$state" == "done" ]]; then
        echo ""
        log_info "This plan is already marked as completed."
        run_verification_tim_loop "$WIZARD_PLAN_FILE" "Run verification tim-loop on completed plan? [y/N] "
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}✓ Plan lifecycle complete!${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
                        log_error "Plan has Status Header but Stage field is invalid or missing."
                        log_error "Please check the Status Header in: $WIZARD_PLAN_FILE"
                        exit 1
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
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✓ Plan lifecycle complete!${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

wizard_step_import() {
    print_step_header "import" "Import plan to drafts folder"

    local name
    echo -n "Enter a short name for this plan (press Enter for default): "
    read -r name </dev/tty
    [[ -z "$name" ]] && name=$(basename "$WIZARD_PLAN_FILE" .md)

    echo ""
    echo "Importing plan..."

    # Call existing import command and capture output
    local output
    output=$(cmd_import "$WIZARD_PLAN_FILE" --name "$name" 2>&1) || true
    echo "$output"

    # Extract new path from output (strip ANSI codes first)
    local clean_output new_path
    clean_output=$(strip_ansi "$output")
    new_path=$(echo "$clean_output" | grep "Copied to:" | sed 's/.*Copied to: //' | xargs)
    if [[ -n "$new_path" && -f "$new_path" ]]; then
        WIZARD_PLAN_FILE="$new_path"
        log_info "Updated path: $WIZARD_PLAN_FILE"
    fi
}

wizard_step_review() {
    print_step_header "review" "Full Review (Tech Review + AI-Ready + Spirit Check)"

    # Ensure all required Status Header fields exist (including Approver)
    ensure_status_header_fields "$WIZARD_PLAN_FILE"

    # Ensure Plan Review field exists and is set to "required" (use regex for variable whitespace)
    if ! grep -qE "\| Plan Review[[:space:]]*\|[[:space:]]*required[[:space:]]*\|" "$WIZARD_PLAN_FILE"; then
        update_review_status "$WIZARD_PLAN_FILE" "required"
    fi

    echo ""
    echo "This runs ALL review phases in a single session:"
    echo "  • Phase 1: Tech Review (technical accuracy, edge cases, testability)"
    echo "  • Phase 2: AI-Ready Review (unambiguous instructions, hallucination prevention)"
    echo "  • Phase 3: Goal Alignment Check (does it still achieve the original intent?)"
    echo ""
    echo "Run /clear first, then paste this command in Claude Code:"
    local cmd="/tim-loop:tim-loop --full-review $WIZARD_PLAN_FILE --max-iterations 15"
    show_command "$cmd"
    echo -n "Press Enter when Full Review completes..."
    read -r </dev/tty

    # Check for unexpected plan moves during review
    if ! handle_unexpected_plan_move "drafts"; then
        # User accepted the unexpected move - state will be refreshed by caller
        log_info "Continuing with plan in new location."
        return 0
    fi

    echo ""
    echo "Full Review complete. Updating plan status..."

    # Step 1: Mark Plan Review complete
    cmd_review "$WIZARD_PLAN_FILE" --mark-complete

    # Step 2: Promote to active
    echo ""
    if [[ "$WIZARD_IS_PACKAGE" == true ]]; then
        echo "Promoting package to active..."
    else
        echo "Promoting plan to active..."
    fi
    cmd_promote "$WIZARD_PLAN_FILE" --approver "$WIZARD_USER_NAME"
    wizard_update_paths_after_move "active"

    # Step 3: Mark as AI Developer Ready
    echo ""
    echo "Marking as AI Developer Ready..."
    if ! update_ai_ready_status "$WIZARD_PLAN_FILE" "$WIZARD_USER_NAME"; then
        log_error "Failed to update AI Developer Ready status"
        return 1
    fi
    if ! update_status "$WIZARD_PLAN_FILE" "active" "AI Developer Ready approved by ${WIZARD_USER_NAME}"; then
        log_error "Failed to update progress log"
        return 1
    fi
    log_info "AI Developer Ready approval recorded."
    log_info "Plan is now ready for implementation!"
}

wizard_step_pm_review() {
    print_step_header "pm-review" "PM Review (Organize Plan)"

    # Ensure PM Review field exists and is set to "required"
    if ! grep -qE "\| PM Review[[:space:]]*\|" "$WIZARD_PLAN_FILE"; then
        update_pm_review_status "$WIZARD_PLAN_FILE" "required"
    fi

    echo ""
    echo "The engineering team has completed technical reviews."
    echo "Now review as a senior project manager to:"
    echo "  - Organize the plan for logical flow"
    echo "  - Fix clerical errors"
    echo "  - Ensure implementation order makes sense"
    echo ""
    echo -e "${YELLOW}CRITICAL: Never reduce scope. This is organization, not scope change.${NC}"
    echo ""
    echo "Run /clear first, then paste this command in Claude Code:"
    local cmd="/tim-loop:tim-loop --pm-review $WIZARD_PLAN_FILE --max-iterations 10"
    show_command "$cmd"
    echo -n "Press Enter when PM Review completes..."
    read -r </dev/tty

    # Check for unexpected plan moves during review
    if ! handle_unexpected_plan_move "drafts"; then
        log_info "Continuing with plan in new location."
        return 0
    fi

    echo ""
    echo "PM Review complete. Updating plan status..."

    # Mark PM Review complete
    if ! update_pm_review_status "$WIZARD_PLAN_FILE" "completed"; then
        log_error "Failed to update PM review status"
        return 1
    fi
    if ! update_status "$WIZARD_PLAN_FILE" "draft" "PM Review completed by ${WIZARD_USER_NAME}"; then
        log_error "Failed to update progress log"
        return 1
    fi
    log_info "PM Review marked as completed."
}

wizard_step_promote() {
    print_step_header "promote" "Promote to active"

    # For single-phase plans that haven't been reviewed, offer the option
    local phase_count plan_review
    phase_count=$(count_phases "$WIZARD_PLAN_FILE")
    plan_review=$(get_status_field "$WIZARD_PLAN_FILE" "Plan Review")

    if [[ "$phase_count" -lt 2 ]] && [[ "$plan_review" != "completed" ]]; then
        echo ""
        echo "This is a single-phase plan. Tech Review is optional."
        echo -n "Run Full Review (Tech + AI-Ready + Spirit Check)? [y/N] "
        read -r response </dev/tty
        if [[ "$response" =~ ^[Yy] ]]; then
            # Update status to required and run the review step (which handles everything)
            update_review_status "$WIZARD_PLAN_FILE" "required"
            wizard_step_review
            return
        fi
        # If N, fall through to promote only - AI-ready step will still run separately
        log_info "Skipping Tech Review. AI-Ready review will still be required."
    fi

    echo ""
    if [[ "$WIZARD_IS_PACKAGE" == true ]]; then
        echo "Promoting package..."
    else
        echo "Promoting plan..."
    fi

    # cmd_promote calls verify_interactive_terminal, which will pass since wizard runs interactively
    cmd_promote "$WIZARD_PLAN_FILE" --approver "$WIZARD_USER_NAME"
    wizard_update_paths_after_move "active"
    # State machine will transition to ai-ready step next
}

wizard_step_ai_ready() {
    print_step_header "ai-ready" "AI Developer Ready Review"

    # Check if already approved - skip step if so
    if has_ai_ready_approval "$WIZARD_PLAN_FILE"; then
        log_info "Plan is already marked AI Developer Ready. Continuing..."
        return 0
    fi

    echo ""
    echo "Run /clear first, then paste this command in Claude Code:"
    local cmd="/tim-loop:tim-loop --ai-ready $WIZARD_PLAN_FILE --max-iterations 5"
    show_command "$cmd"
    echo -n "Press Enter when review completes..."
    read -r </dev/tty

    # Check for unexpected plan moves during ai-ready review
    if ! handle_unexpected_plan_move "active"; then
        # User accepted the unexpected move - state will be refreshed by caller
        log_info "Continuing with plan in new location."
        return 0
    fi

    echo ""
    echo "Marking as AI Developer Ready..."

    # Use helper directly to avoid cmd_ai_ready's exit calls
    if ! update_ai_ready_status "$WIZARD_PLAN_FILE" "$WIZARD_USER_NAME"; then
        log_error "Failed to update AI Developer Ready status"
        return 1
    fi
    if ! update_status "$WIZARD_PLAN_FILE" "active" "AI Developer Ready approved by ${WIZARD_USER_NAME}"; then
        log_error "Failed to update progress log"
        return 1
    fi
    log_info "AI Developer Ready approval recorded."
}

wizard_step_tim_loop() {
    print_step_header "tim-loop" "Run Tim Loop Implementation"

    # Determine project directory from plan file path
    # Go up from plans/active/ to find project root
    local project_dir
    project_dir=$(dirname "$(dirname "$(dirname "$WIZARD_PLAN_FILE")")")

    # Ensure tim-loop permissions are configured
    ensure_tim_loop_permissions "$project_dir"

    # Check if prompt manager exists for prompt preservation
    local prompt_manager="${project_dir}/tools/tim-loop-prompt-manager.sh"
    local has_prompt_manager=false
    if [[ -x "$prompt_manager" ]]; then
        has_prompt_manager=true
        # Save prompt automatically for compaction recovery
        "$prompt_manager" save "implement $WIZARD_PLAN_FILE with full TIM compliance" 2>/dev/null || true
    fi

    echo "Run /clear first, then paste this command in Claude Code:"
    local cmd="/tim-loop:tim-loop --implement $WIZARD_PLAN_FILE"
    show_command "$cmd"

    echo "Did Tim Loop complete successfully? (y/n)"
    echo -n "> "
    read -r response </dev/tty

    if [[ "$response" =~ ^[Yy] ]]; then
        # Check for unexpected plan moves during tim-loop
        if ! handle_unexpected_plan_move "active"; then
            # User accepted the unexpected move - state will be refreshed by caller
            log_info "Continuing with plan in new location."
            return 0
        fi

        # Mark implementation as verified so state transitions to 'complete'
        if ! update_verification_status "$WIZARD_PLAN_FILE" "$WIZARD_USER_NAME"; then
            log_error "Failed to update verification status"
            exit 1
        fi
        if ! update_status "$WIZARD_PLAN_FILE" "active" "Implementation verified by ${WIZARD_USER_NAME}"; then
            log_error "Failed to update progress log"
            exit 1
        fi
        log_info "Implementation marked as verified."
        # Clear saved prompt now that tim-loop is complete
        if [[ "$has_prompt_manager" == "true" ]]; then
            "$prompt_manager" clear 2>/dev/null || true
        fi
    else
        log_warn "Tim Loop not completed. Run the wizard again when ready."
        exit 0
    fi
}

wizard_step_complete() {
    if [[ "$WIZARD_IS_PACKAGE" == true ]]; then
        print_step_header "complete" "Mark package complete"
    else
        print_step_header "complete" "Mark plan complete"
    fi

    # Optional verification tim-loop step
    if ! run_verification_tim_loop "$WIZARD_PLAN_FILE" "Run verification tim-loop before marking complete? [y/N] "; then
        exit 0
    fi

    echo ""
    if [[ "$WIZARD_IS_PACKAGE" == true ]]; then
        echo "Marking package complete..."
    else
        echo "Marking plan complete..."
    fi

    # cmd_complete moves the file/package and updates status
    cmd_complete "$WIZARD_PLAN_FILE"
    wizard_update_paths_after_move "completed"
}
