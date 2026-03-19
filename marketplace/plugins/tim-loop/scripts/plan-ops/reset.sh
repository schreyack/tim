#!/usr/bin/env bash
# plan-ops/reset.sh - Plan status reset functionality
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, status.sh, security.sh
# Exports: reset_for_full_review, reset_for_reimplementation, cmd_reopen
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh
# shellcheck source=plan-ops/status.sh
# shellcheck source=plan-ops/security.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# RESET FOR FULL REVIEW
# =============================================================================

# Reset plan status fields to prepare for full review
# This resets Plan Review, PM Review, AI Developer Ready, and Implementation Verified
# Does NOT move the file - caller is responsible for that
reset_for_full_review() {
    local file="$1"
    local ts
    ts=$(timestamp)

    if [[ ! -f "$file" ]]; then
        log_error "Plan file not found: $file"
        return 1
    fi

    # Ensure all required Status Header fields exist before resetting
    ensure_status_header_fields "$file"

    # Reset Plan Review to required
    if grep -qE "\| Plan Review[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Plan Review[[:space:]]*|[^|]*|/| Plan Review | required |/" "$file"
    fi

    # Reset Review Date
    if grep -qE "\| Review Date[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Review Date[[:space:]]*|[^|]*|/| Review Date | - |/" "$file"
    fi

    # Reset PM Review to not-required (will be set to required after tech review if multi-phase)
    if grep -qE "\| PM Review[[:space:]]*\|" "$file"; then
        sed -i '' "s/| PM Review[[:space:]]*|[^|]*|/| PM Review | not-required |/" "$file"
    fi

    # Reset PM Review Date
    if grep -qE "\| PM Review Date[[:space:]]*\|" "$file"; then
        sed -i '' "s/| PM Review Date[[:space:]]*|[^|]*|/| PM Review Date | - |/" "$file"
    fi

    # Reset AI Developer Ready fields
    if grep -qE "\| AI Developer Ready[[:space:]]*\|" "$file"; then
        sed -i '' "s/| AI Developer Ready[[:space:]]*|[^|]*|/| AI Developer Ready | no |/" "$file"
    fi
    if grep -qE "\| AI Developer Ready By[[:space:]]*\|" "$file"; then
        sed -i '' "s/| AI Developer Ready By[[:space:]]*|[^|]*|/| AI Developer Ready By | - |/" "$file"
    fi
    if grep -qE "\| AI Developer Ready Date[[:space:]]*\|" "$file"; then
        sed -i '' "s/| AI Developer Ready Date[[:space:]]*|[^|]*|/| AI Developer Ready Date | - |/" "$file"
    fi
    if grep -qE "\| AI Developer Ready Iteration[[:space:]]*\|" "$file"; then
        sed -i '' "s/| AI Developer Ready Iteration[[:space:]]*|[^|]*|/| AI Developer Ready Iteration | - |/" "$file"
    fi

    # Reset Implementation Verified fields
    if grep -qE "\| Implementation Verified[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Implementation Verified[[:space:]]*|[^|]*|/| Implementation Verified | no |/" "$file"
    fi
    if grep -qE "\| Implementation Verified By[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Implementation Verified By[[:space:]]*|[^|]*|/| Implementation Verified By | - |/" "$file"
    fi
    if grep -qE "\| Implementation Verified Date[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Implementation Verified Date[[:space:]]*|[^|]*|/| Implementation Verified Date | - |/" "$file"
    fi

    # Reset Execution fields
    if grep -qE "\| Execution Approved[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Execution Approved[[:space:]]*|[^|]*|/| Execution Approved | no |/" "$file"
    fi
    if grep -qE "\| Execution Approved By[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Execution Approved By[[:space:]]*|[^|]*|/| Execution Approved By | - |/" "$file"
    fi
    if grep -qE "\| Execution Started[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Execution Started[[:space:]]*|[^|]*|/| Execution Started | - |/" "$file"
    fi

    # Update Stage to draft
    if grep -qE "\| Stage[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Stage[[:space:]]*|[^|]*|/| Stage | draft |/" "$file"
    fi

    # Update Last Updated
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$file"

    log_info "Reset plan status for full review"
}

# =============================================================================
# RESET FOR REIMPLEMENTATION
# =============================================================================

# Reset implementation fields only, keeping reviews and approvals intact
# Use when moving a completed/abandoned plan back to active for re-implementation
# Does NOT move the file - caller is responsible for that
reset_for_reimplementation() {
    local file="$1"
    local ts
    ts=$(timestamp)

    if [[ ! -f "$file" ]]; then
        log_error "Plan file not found: $file"
        return 1
    fi

    # Ensure all required Status Header fields exist before resetting
    ensure_status_header_fields "$file"

    # Reset Implementation Verified fields
    if grep -qE "\| Implementation Verified[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Implementation Verified[[:space:]]*|[^|]*|/| Implementation Verified | no |/" "$file"
    fi
    if grep -qE "\| Implementation Verified By[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Implementation Verified By[[:space:]]*|[^|]*|/| Implementation Verified By | - |/" "$file"
    fi
    if grep -qE "\| Implementation Verified Date[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Implementation Verified Date[[:space:]]*|[^|]*|/| Implementation Verified Date | - |/" "$file"
    fi

    # Reset Remediation Plan
    if grep -qE "\| Remediation Plan[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Remediation Plan[[:space:]]*|[^|]*|/| Remediation Plan | - |/" "$file"
    fi

    # Update Stage to active
    if grep -qE "\| Stage[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Stage[[:space:]]*|[^|]*|/| Stage | active |/" "$file"
    fi

    # Update Last Updated
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$file"

    log_info "Reset implementation fields for reimplementation"
}

# =============================================================================
# REOPEN COMMAND
# =============================================================================

# Reopen a completed or abandoned plan, moving it to drafts or active
cmd_reopen() {
    # Block AI from running this command
    verify_interactive_terminal

    local plan_file="${1:-}"
    local target=""
    local reason="Plan reopened"

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --to)
                target="$2"
                shift 2
                ;;
            --reason)
                reason="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH reopen <plan-file> --to <drafts|active> [--reason <reason>]"
        exit 1
    fi

    if [[ -z "$target" ]]; then
        log_error "Target stage required: --to <drafts|active>"
        exit 1
    fi

    if [[ "$target" != "drafts" && "$target" != "active" ]]; then
        log_error "Target must be 'drafts' or 'active', got: $target"
        exit 1
    fi

    # Resolve plan name or path (searches all stages including completed/abandoned)
    if [[ -f "$plan_file" ]]; then
        plan_file=$(to_absolute "$plan_file")
    elif [[ -d "$plan_file" && -f "${plan_file}/MASTER.md" ]]; then
        plan_file=$(to_absolute "${plan_file}/MASTER.md")
    else
        plan_file=$(resolve_plan_path "$plan_file") || exit 1
    fi

    # Determine current stage from folder location (authoritative) or Status Header
    local current_stage
    if [[ "$plan_file" == *"/plans/completed/"* ]]; then
        current_stage="completed"
    elif [[ "$plan_file" == *"/plans/abandoned/"* ]]; then
        current_stage="abandoned"
    elif [[ "$plan_file" == *"/plans/active/"* ]]; then
        current_stage="active"
    elif [[ "$plan_file" == *"/plans/drafts/"* ]]; then
        current_stage="draft"
    else
        current_stage=$(get_status_field "$plan_file" "Stage")
    fi

    # Block reopening to the same stage the plan is already in
    if [[ "$current_stage" == "$target" ]] || [[ "$current_stage" == "draft" && "$target" == "drafts" ]]; then
        log_error "Plan is already in ${current_stage}, nothing to reopen"
        exit 1
    fi

    # Track if package for logging
    local is_pkg=false
    is_master_plan "$plan_file" && is_pkg=true

    # Move plan/package to target stage
    plan_file=$(move_plan_to_stage "$plan_file" "$target")

    # Reset appropriate fields based on target
    if [[ "$target" == "drafts" ]]; then
        reset_for_full_review "$plan_file"
    else
        reset_for_reimplementation "$plan_file"
    fi

    # Update progress log
    if ! update_status "$plan_file" "$target" "Reopened from ${current_stage}: ${reason}"; then
        log_error "Failed to update status after reopen"
        exit 1
    fi

    if [[ "$is_pkg" == true ]]; then
        log_info "Reopened package to ${target}: $(dirname "$plan_file")"
    else
        log_info "Reopened to ${target}: $plan_file"
    fi

    echo ""
    log_info "NEXT STEP: Use the wizard to continue:"
    show_command "$SCRIPT_PATH wizard $plan_file"
}
