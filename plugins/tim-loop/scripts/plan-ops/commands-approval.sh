#!/usr/bin/env bash
# plan-ops/commands-approval.sh - Approval workflow commands
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, status.sh, approval.sh, security.sh
# Exports: cmd_ralph, cmd_ai_ready, cmd_execute
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh
# shellcheck source=plan-ops/status.sh
# shellcheck source=plan-ops/approval.sh
# shellcheck source=plan-ops/security.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# REVIEW COMMAND (formerly RALPH)
# =============================================================================

cmd_review() {
    local plan_file="${1:-}"
    local mark_complete=false

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mark-complete)
                mark_complete=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH review <plan-file> [--mark-complete]"
        exit 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    # Convert to absolute path for output messages
    plan_file=$(to_absolute "$plan_file")

    # Verify plan is in drafts
    if [[ "$plan_file" != *"/drafts/"* ]]; then
        log_error "Plan Review only applies to plans in drafts/"
        exit 1
    fi

    local phase_count
    phase_count=$(count_phases "$plan_file")
    local plan_basename
    plan_basename=$(basename "$plan_file")

    if [[ "$mark_complete" == "true" ]]; then
        # Block AI from marking review as complete
        verify_interactive_terminal

        # Ensure all required Status Header fields exist (including Approver)
        ensure_status_header_fields "$plan_file"

        # Mark Plan Review as completed
        if ! update_review_status "$plan_file" "completed"; then
            log_error "Failed to update review status"
            exit 1
        fi
        if ! update_status "$plan_file" "draft" "Plan Review completed"; then
            log_error "Failed to update progress log"
            exit 1
        fi
        log_info "Marked Plan Review as completed for: $plan_file"

        log_info "NEXT STEP: Promote the plan to active:"
        show_command "$SCRIPT_PATH promote $plan_file --approver \"Your Name\""
    else
        # Show Plan Review command to run
        echo ""
        log_info "Plan: $plan_basename"
        log_info "Phases detected: $phase_count"

        if [[ "$phase_count" -lt 2 ]]; then
            log_warn "This is a single-phase plan. Plan Review is NOT required."
            log_info "NEXT STEP: Promote the plan directly:"
            show_command "$SCRIPT_PATH promote $plan_file --approver \"Your Name\""
            return 0
        fi

        echo ""
        log_info "Multi-phase plan detected. Plan Review is REQUIRED before promotion."
        echo ""
        log_info "STEP 1 of 2: Run /clear first, then paste this command in Claude Code:"
        show_command "/tim-loop:tim-loop --review ${plan_file} --max-iterations 10 --completion-promise \"DONEDONE\""
        log_info "STEP 2 of 2: After Plan Review completes, mark it done:"
        echo -e "  ${GREEN}$SCRIPT_PATH review $plan_file --mark-complete${NC}"
    fi
}

# Backward compatibility alias
cmd_ralph() {
    log_warn "DEPRECATED: 'ralph' command will be removed in future versions. Use 'review' instead."
    cmd_review "$@"
}

# =============================================================================
# AI-READY COMMAND
# =============================================================================

cmd_ai_ready() {
    # Block AI from running this command
    verify_interactive_terminal

    local plan_file="${1:-}"
    local reviewer=""
    local iteration=1

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reviewer) reviewer="$2"; shift 2 ;;
            --iteration) iteration="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Validation
    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH ai-ready <plan-file> --reviewer <name>"
        exit 1
    fi
    if [[ -z "$reviewer" ]]; then
        log_error "Reviewer required: --reviewer <name>"
        exit 1
    fi
    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    # Convert to absolute path for output messages
    plan_file=$(to_absolute "$plan_file")

    # Enforce active/ folder requirement
    if [[ "$plan_file" != *"/active/"* ]]; then
        log_error "Can only mark plans in active/ as AI Developer Ready"
        log_error "This plan is in: $(dirname "$plan_file")"
        echo ""
        log_error "Plans must be promoted to active/ before AI Developer Ready review."
        echo "Run: $SCRIPT_PATH promote <plan> --approver <name>"
        exit 1
    fi

    # Check if already approved
    if has_ai_ready_approval "$plan_file"; then
        log_warn "Plan is already marked AI Developer Ready"
        log_info "NEXT STEP: Continue with the wizard to request execution approval:"
        show_command "$SCRIPT_PATH wizard $plan_file"
        exit 0
    fi

    # Update Status Header
    if ! update_ai_ready_status "$plan_file" "$reviewer" "$iteration"; then
        log_error "Failed to update AI Developer Ready status"
        exit 1
    fi

    # Add approval stamp
    add_ai_ready_stamp "$plan_file" "$reviewer" "$(datestamp)" "$iteration"

    # Update progress log
    if ! update_status "$plan_file" "active" "AI Developer Ready approved by ${reviewer} (iteration ${iteration})"; then
        log_error "Failed to update progress log"
        exit 1
    fi

    echo ""
    log_info "Marked as AI Developer Ready: $plan_file"
    log_info "Reviewer: $reviewer"
    log_info "Iteration: $iteration (FINAL)"

    log_info "NEXT STEP: Continue with the wizard to request execution approval:"
    show_command "$SCRIPT_PATH wizard $plan_file"
}

# =============================================================================
# EXECUTE COMMAND
# =============================================================================

cmd_execute() {
    local plan_file="${1:-}"

    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH execute <plan-file>"
        exit 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    # Convert to absolute path for output messages
    plan_file=$(to_absolute "$plan_file")

    # Verify plan is in active/ folder
    if [[ "$plan_file" != *"/active/"* ]]; then
        log_error "Can only execute plans in active/ folder"
        log_error "This plan is not in active/: $plan_file"
        exit 1
    fi

    # Check AI Developer Ready approval (HARD REQUIREMENT)
    if ! has_ai_ready_approval "$plan_file"; then
        log_error "BLOCKED: Plan has not been marked AI Developer Ready."
        echo ""
        log_error "Before execution, a human must review this plan for AI implementation concerns."
        echo ""
        echo "To mark as AI Developer Ready, run:"
        echo -e "  ${GREEN}$SCRIPT_PATH ai-ready $plan_file --reviewer \"Your Name\"${NC}"
        echo ""
        echo "See: standards/enforcement/ai-developer-ready-checklist.md"
        exit 1
    fi

    # Check for existing valid approval
    local approval
    approval=$(find_valid_approval "$plan_file")

    if [[ -z "$approval" ]]; then
        # No approval - create request and block
        local request_id
        request_id=$(create_execution_request "$plan_file")

        log_error "BLOCKED: Execution requires human approval."
        echo ""
        log_info "STEP 1 of 2: A human must approve execution in a SEPARATE TERMINAL:"
        echo -e "  ${GREEN}$SCRIPT_PATH approve-execute ${request_id} --approver \"Your Name\"${NC}"
        echo ""
        log_info "STEP 2 of 2: Then retry this command:"
        echo -e "  ${GREEN}$SCRIPT_PATH execute $plan_file${NC}"
        echo ""
        log_warn "Approval expires in ${EXECUTION_EXPIRY_MINUTES} minutes."
        exit 1
    fi

    # Valid approval found - output tim-loop command
    if ! update_execution_status "$plan_file" "$approval"; then
        log_error "Failed to update execution status"
        exit 1
    fi
    if ! update_status "$plan_file" "active" "Execution approved, starting tim-loop"; then
        log_error "Failed to update progress log"
        exit 1
    fi

    echo ""
    log_info "Execution APPROVED!"
    echo ""

    # Check for prompt manager and save prompt automatically
    local project_dir
    project_dir=$(dirname "$(dirname "$(dirname "$plan_file")")")
    local prompt_manager="${project_dir}/tools/tim-loop-prompt-manager.sh"

    if [[ -x "$prompt_manager" ]]; then
        # Save prompt automatically for compaction recovery
        "$prompt_manager" save "implement ${plan_file} with full TIM compliance" 2>/dev/null || true
    fi

    log_info "STEP 1 of 2: Run /clear first, then paste this command in Claude Code:"
    echo -e "  ${GREEN}/tim-loop:tim-loop --implement ${plan_file}${NC}"
    echo ""

    log_info "STEP 2 of 2: When tim-loop completes successfully, mark the plan as complete:"
    echo -e "  ${GREEN}$SCRIPT_PATH complete $plan_file${NC}"
}
