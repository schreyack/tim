#!/usr/bin/env bash
# plan-ops/approval.sh - Approval and verification tracking
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, status.sh
# Exports: has_ai_ready_approval, update_ai_ready_status, update_verification_status,
#          add_ai_ready_stamp, update_review_status, update_execution_status
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh
# shellcheck source=plan-ops/status.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# AI DEVELOPER READY CHECKS
# =============================================================================

# Check if plan has AI Developer Ready approval
# Returns: 0 (true) if approved, 1 (false) otherwise
has_ai_ready_approval() {
    local file="$1"
    # Use regex to handle variable whitespace in markdown tables
    grep -qE "\| AI Developer Ready[[:space:]]*\|[[:space:]]*yes[[:space:]]*\|" "$file" 2>/dev/null
}

# Update AI Developer Ready fields in Status Header
# Adds fields if they don't exist
update_ai_ready_status() {
    local file="$1"
    local reviewer="$2"
    local iteration="${3:-1}"  # Default to iteration 1
    local ts date
    ts=$(timestamp)
    date=$(datestamp)

    # Check file exists first, try to relocate if moved
    if [[ ! -f "$file" ]]; then
        local relocated
        relocated=$(try_relocate_plan "$file")
        if [[ -n "$relocated" ]]; then
            log_info "Plan was moved to: $relocated"
            file="$relocated"
        else
            log_error "Plan file not found: $file"
            return 1
        fi
    fi

    # Find the best anchor field (last existing field before AI Developer Ready section)
    # Use regex to handle variable whitespace in markdown tables
    local anchor=""
    for candidate in "Execution Started" "Execution Approved By" "Execution Approved" "Review Date" "Plan Review" "Approver"; do
        if grep -qE "\| ${candidate}[[:space:]]*\|" "$file"; then
            anchor="$candidate"
            break
        fi
    done

    if [[ -z "$anchor" ]]; then
        log_error "Cannot find anchor field in Status Header to add AI Developer Ready fields"
        return 1
    fi

    # Add/update fields in order (each anchors to the previous, starting from found anchor)
    _add_or_update_status_field "AI Developer Ready" "yes" "$anchor" "$file"
    _add_or_update_status_field "AI Developer Ready By" "${reviewer}" "AI Developer Ready" "$file"
    _add_or_update_status_field "AI Developer Ready Date" "${date}" "AI Developer Ready By" "$file"
    _add_or_update_status_field "AI Developer Ready Iteration" "${iteration}" "AI Developer Ready Date" "$file"

    # Update Last Updated
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$file"
}

# Update Implementation Verification fields in Status Header
# Adds fields if they don't exist
update_verification_status() {
    local file="$1"
    local reviewer="$2"
    local ts date
    ts=$(timestamp)
    date=$(datestamp)

    # Check file exists first, try to relocate if moved
    if [[ ! -f "$file" ]]; then
        local relocated
        relocated=$(try_relocate_plan "$file")
        if [[ -n "$relocated" ]]; then
            log_info "Plan was moved to: $relocated"
            file="$relocated"
        else
            log_error "Plan file not found: $file"
            log_error "Searched in drafts/, active/, completed/, abandoned/, playbooks/"
            return 1
        fi
    fi

    # Find the best anchor field (use regex to handle variable whitespace)
    local anchor=""
    for candidate in "AI Developer Ready Iteration" "AI Developer Ready Date" "AI Developer Ready By" "AI Developer Ready" "Execution Started" "Review Date" "Plan Review" "Approver"; do
        if grep -qE "\| ${candidate}[[:space:]]*\|" "$file"; then
            anchor="$candidate"
            break
        fi
    done

    if [[ -z "$anchor" ]]; then
        log_error "Cannot find anchor field in Status Header to add Implementation Verification fields"
        return 1
    fi

    # Add/update fields in order
    _add_or_update_status_field "Implementation Verified" "yes" "$anchor" "$file"
    _add_or_update_status_field "Implementation Verified By" "${reviewer}" "Implementation Verified" "$file"
    _add_or_update_status_field "Implementation Verified Date" "${date}" "Implementation Verified By" "$file"

    # Update Last Updated
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$file"
}

# Add AI Developer Ready approval stamp to plan file
add_ai_ready_stamp() {
    local file="$1"
    local reviewer="$2"
    local date="$3"
    local iteration="$4"

    # Create stamp content in a temp file (avoids awk multiline issues)
    local stamp_file
    stamp_file=$(mktemp)
    cat > "$stamp_file" << EOF

### AI Developer Ready Approval

**Reviewer**: ${reviewer}
**Date**: ${date}
**Iteration**: ${iteration} (FINAL)
**Status**: APPROVED

---
EOF

    # Find the line number of first --- after ### Progress Log
    local progress_line separator_line
    progress_line=$(grep -n "^### Progress Log" "$file" | head -1 | cut -d: -f1)

    if [[ -n "$progress_line" ]]; then
        # Find first --- after Progress Log
        separator_line=$(tail -n +"$progress_line" "$file" | grep -n "^---$" | head -1 | cut -d: -f1)
        if [[ -n "$separator_line" ]]; then
            separator_line=$((progress_line + separator_line - 1))
            # Insert stamp after the separator
            head -n "$separator_line" "$file" > "${file}.tmp"
            cat "$stamp_file" >> "${file}.tmp"
            tail -n +"$((separator_line + 1))" "$file" >> "${file}.tmp"
            mv "${file}.tmp" "$file"
        fi
    fi

    rm -f "$stamp_file"
}

# =============================================================================
# PLAN REVIEW STATUS
# =============================================================================

# Update Plan Review fields in Status Header
# If fields don't exist, adds them after Approver row
update_review_status() {
    local file="$1"
    local status="$2"  # required / completed / not-required
    local ts
    ts=$(timestamp)
    local date_val="-"
    if [[ "$status" == "completed" ]]; then
        date_val=$(datestamp)
    fi

    # Update or add Plan Review field
    if grep -qE "\| Plan Review[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Plan Review[[:space:]]*|[^|]*|/| Plan Review | ${status} |/" "$file"
    else
        if grep -qE "\| Approver[[:space:]]*\|" "$file"; then
            insert_line_after "| Approver |" "| Plan Review | ${status} |" "$file"
            log_warn "Added missing Plan Review field to Status Header"
        else
            log_error "Cannot find Approver row to insert Plan Review field"
            return 1
        fi
    fi

    # Update or add Review Date field
    if grep -qE "\| Review Date[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Review Date[[:space:]]*|[^|]*|/| Review Date | ${date_val} |/" "$file"
    else
        if grep -qE "\| Plan Review[[:space:]]*\|" "$file"; then
            insert_line_after "| Plan Review |" "| Review Date | ${date_val} |" "$file"
            log_warn "Added missing Review Date field to Status Header"
        fi
    fi

    # Update Last Updated
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$file"
}

# =============================================================================
# PM REVIEW STATUS
# =============================================================================

# Update PM Review fields in Status Header
# If fields don't exist, adds them after Review Date row
update_pm_review_status() {
    local file="$1"
    local status="$2"  # required / completed / not-required
    local ts
    ts=$(timestamp)
    local date_val="-"
    if [[ "$status" == "completed" ]]; then
        date_val=$(datestamp)
    fi

    # Update or add PM Review field
    if grep -qE "\| PM Review[[:space:]]*\|" "$file"; then
        sed -i '' "s/| PM Review[[:space:]]*|[^|]*|/| PM Review | ${status} |/" "$file"
    else
        if grep -qE "\| Review Date[[:space:]]*\|" "$file"; then
            insert_line_after "| Review Date |" "| PM Review | ${status} |" "$file"
            log_warn "Added missing PM Review field to Status Header"
        else
            log_error "Cannot find Review Date row to insert PM Review field"
            return 1
        fi
    fi

    # Update or add PM Review Date field
    if grep -qE "\| PM Review Date[[:space:]]*\|" "$file"; then
        sed -i '' "s/| PM Review Date[[:space:]]*|[^|]*|/| PM Review Date | ${date_val} |/" "$file"
    else
        if grep -qE "\| PM Review[[:space:]]*\|" "$file"; then
            insert_line_after "| PM Review |" "| PM Review Date | ${date_val} |" "$file"
            log_warn "Added missing PM Review Date field to Status Header"
        fi
    fi

    # Update Last Updated
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$file"
}

# =============================================================================
# EXECUTION STATUS UPDATES
# =============================================================================

# Update execution status in plan's Status Header
# Adds fields if they don't exist
# Usage: update_execution_status "$plan_file" ["$approver"]
#   - If approver is provided, uses it directly
#   - If no approver, stamps "auto" as approver
update_execution_status() {
    local plan_file="$1"
    local approver="${2:-auto}"
    local ts
    ts=$(timestamp)

    # Check plan file exists first, try to relocate if moved
    if [[ ! -f "$plan_file" ]]; then
        local relocated
        relocated=$(try_relocate_plan "$plan_file")
        if [[ -n "$relocated" ]]; then
            log_info "Plan was moved to: $relocated"
            plan_file="$relocated"
        else
            log_error "Plan file not found: $plan_file"
            return 1
        fi
    fi

    # Find the best anchor field (use regex to handle variable whitespace)
    local anchor=""
    for candidate in "Review Date" "Plan Review" "Approver"; do
        if grep -qE "\| ${candidate}[[:space:]]*\|" "$plan_file"; then
            anchor="$candidate"
            break
        fi
    done

    if [[ -z "$anchor" ]]; then
        log_error "Cannot find anchor field in Status Header to add Execution fields"
        return 1
    fi

    # Add/update fields in order
    _add_or_update_status_field "Execution Approved" "yes" "$anchor" "$plan_file"
    _add_or_update_status_field "Execution Approved By" "${approver}" "Execution Approved" "$plan_file"
    _add_or_update_status_field "Execution Started" "${ts}" "Execution Approved By" "$plan_file"

    # Update Last Updated (pattern handles variable whitespace)
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$plan_file"
}
