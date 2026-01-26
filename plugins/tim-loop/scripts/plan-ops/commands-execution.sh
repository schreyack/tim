#!/usr/bin/env bash
# plan-ops/commands-execution.sh - Execution approval commands
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, search.sh, security.sh, status.sh, approval.sh
# Exports: cmd_approve_execute, cmd_fast_track
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh
# shellcheck source=plan-ops/security.sh
# shellcheck source=plan-ops/approval.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# APPROVE-EXECUTE COMMAND
# =============================================================================

cmd_approve_execute() {
    # Block AI from running this command
    verify_interactive_terminal

    local request_id="${1:-}"
    local approver=""

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --approver)
                approver="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$request_id" ]]; then
        log_error "Usage: $SCRIPT_PATH approve-execute <request-id> --approver <name>"
        exit 1
    fi

    if [[ -z "$approver" ]]; then
        log_error "Approver required: --approver <name>"
        exit 1
    fi

    local request_file="${EXECUTION_REQUESTS_DIR}/${request_id}.json"

    if [[ ! -f "$request_file" ]]; then
        log_error "Request not found: $request_id"
        log_error "Request may have expired or ID is incorrect."
        exit 1
    fi

    # Check if already approved
    local already_approved
    already_approved=$(grep '"approved"' "$request_file" | grep -o 'true\|false')
    if [[ "$already_approved" == "true" ]]; then
        log_warn "Request already approved."
        exit 0
    fi

    # Check if expired
    local req_expiry now
    req_expiry=$(grep '"expires_at"' "$request_file" | sed 's/.*: *"\([^"]*\)".*/\1/')
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ "$req_expiry" < "$now" ]]; then
        log_error "Request has EXPIRED."
        log_error "AI must create a new request with: $SCRIPT_PATH execute <plan>"
        exit 1
    fi

    # Get plan file for display (already stored as absolute path)
    local plan_file
    plan_file=$(grep '"plan_file"' "$request_file" | sed 's/.*: *"\([^"]*\)".*/\1/')

    # Approve the request
    local approval_ts
    approval_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Update JSON file (using sed for portability)
    sed -i '' 's/"approved": false/"approved": true/' "$request_file"
    sed -i '' "s/\"approved_by\": null/\"approved_by\": \"${approver}\"/" "$request_file"
    sed -i '' "s/\"approved_at\": null/\"approved_at\": \"${approval_ts}\"/" "$request_file"

    echo ""
    log_info "APPROVED execution for: $plan_file"
    log_info "Approved by: $approver"

    log_info "NEXT STEP: Continue with the wizard to get the tim-loop command:"
    show_command "$SCRIPT_PATH wizard $plan_file"
}

# =============================================================================
# FAST-TRACK COMMAND
# =============================================================================

cmd_fast_track() {
    # Block AI from running this command
    verify_interactive_terminal

    local plan_file="${1:-}"
    local approver=""
    local reason=""

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --approver) approver="$2"; shift 2 ;;
            --reason) reason="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Validation
    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH fast-track <plan-file> --approver <name> [--reason <reason>]"
        exit 1
    fi
    if [[ -z "$approver" ]]; then
        log_error "Approver required: --approver <name>"
        exit 1
    fi

    # Resolve plan path (handles ~/.claude/plans/, drafts/, active/, names without paths)
    plan_file=$(resolve_plan_path "$plan_file") || exit 1

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    local ts
    ts=$(timestamp)
    local date_stamp
    date_stamp=$(datestamp)

    echo ""
    log_info "Fast-tracking plan: $(basename "$plan_file")"
    log_info "Approver: $approver"
    [[ -n "$reason" ]] && log_info "Reason: $reason"
    echo ""

    # Step 1: Import from ~/.claude/plans/ if needed
    if [[ "$plan_file" == *"/.claude/plans/"* ]]; then
        log_info "Importing plan from ~/.claude/plans/..."
        local name
        name=$(basename "$plan_file" .md)
        local dest
        if [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}- ]]; then
            dest=$(to_absolute "${PLANS_DIR}/drafts/${name}.md")
        else
            dest=$(to_absolute "${PLANS_DIR}/drafts/${date_stamp}-${name}.md")
        fi
        mkdir -p "${PLANS_DIR}/drafts"
        cp "$plan_file" "$dest"
        rm "$plan_file"
        plan_file="$dest"
        add_status_header "$plan_file" "Claude"
        ensure_status_header_fields "$plan_file"
        log_info "Imported to: $plan_file"
    fi

    # Step 2: Move from drafts/ to active/ if needed
    if [[ "$plan_file" == *"/drafts/"* ]]; then
        log_info "Promoting plan to active/..."
        local basename
        basename=$(basename "$plan_file")
        local plans_dir
        plans_dir=$(get_plans_dir_from_path "$plan_file")
        local dest="${plans_dir}/active/${basename}"
        mkdir -p "${plans_dir}/active"
        mv "$plan_file" "$dest"
        plan_file="$dest"
        log_info "Moved to: $plan_file"
    fi

    # Ensure Status Header exists and has all required fields
    add_status_header "$plan_file" "Claude"
    ensure_status_header_fields "$plan_file"

    # Step 3: Mark Plan Review as completed (or not-required for single-phase)
    local review_status
    if [[ "$(requires_review "$plan_file")" == "true" ]]; then
        review_status="completed"
    else
        review_status="not-required"
    fi
    update_review_status "$plan_file" "$review_status"
    log_info "Plan Review: $review_status"

    # Step 4: Update Stage and Approver (patterns handle variable whitespace)
    sed -i '' "s/| Stage[[:space:]]*|[^|]*|/| Stage | active |/" "$plan_file"
    sed -i '' "s/| Approver[[:space:]]*|[^|]*|/| Approver | ${approver} |/" "$plan_file"
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$plan_file"

    # Step 5: Mark AI Developer Ready
    update_ai_ready_status "$plan_file" "$approver" "1"
    log_info "AI Developer Ready: yes (reviewed by $approver)"

    # Step 6: Create and auto-approve execution request
    local request_id
    request_id=$(create_execution_request "$plan_file")
    local request_file="${EXECUTION_REQUESTS_DIR}/${request_id}.json"
    local approval_ts
    approval_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Approve the request
    sed -i '' 's/"approved": false/"approved": true/' "$request_file"
    sed -i '' "s/\"approved_by\": null/\"approved_by\": \"${approver}\"/" "$request_file"
    sed -i '' "s/\"approved_at\": null/\"approved_at\": \"${approval_ts}\"/" "$request_file"

    # Update execution status in plan
    update_execution_status "$plan_file" "$request_file"
    log_info "Execution Approved: yes (approved by $approver)"

    # Step 7: Add progress log entry
    local event_desc="Fast-tracked by ${approver}"
    [[ -n "$reason" ]] && event_desc="${event_desc}: ${reason}"
    update_status "$plan_file" "active" "$event_desc"

    # Cleanup claude plans
    cleanup_claude_plans

    echo ""
    log_info "Plan fast-tracked successfully!"
    log_info "All approvals granted."
    echo ""
    log_info "NEXT STEP: Run the wizard to continue with implementation:"
    show_command "$SCRIPT_PATH wizard $plan_file"
}
