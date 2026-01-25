#!/usr/bin/env bash
# plan-ops/approval.sh - Approval and verification tracking
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, status.sh
# Exports: has_ai_ready_approval, update_ai_ready_status, update_verification_status,
#          add_ai_ready_stamp, update_ralph_status, generate_request_id,
#          create_execution_request, find_valid_approval, find_pending_request,
#          update_execution_status
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

    # Find the best anchor field (last existing field before AI Developer Ready section)
    # Use regex to handle variable whitespace in markdown tables
    local anchor=""
    for candidate in "Execution Started" "Execution Approved By" "Execution Approved" "Ralph Date" "Ralph Review" "Approver"; do
        if grep -qE "\| ${candidate}[[:space:]]*\|" "$file"; then
            anchor="$candidate"
            break
        fi
    done

    if [[ -z "$anchor" ]]; then
        log_error "Cannot find anchor field in Status Header to add AI Developer Ready fields"
        return 1
    fi

    # Helper to add or update a field
    # Usage: add_or_update_field "field_name" "value" "anchor_field"
    add_or_update_field() {
        local field="$1"
        local value="$2"
        local anchor_field="$3"
        # Use regex to handle variable whitespace in markdown tables
        if grep -qE "\| ${field}[[:space:]]*\|" "$file"; then
            # Pattern handles variable whitespace in markdown tables
            sed -i '' "s/| ${field}[[:space:]]*|[^|]*|/| ${field} | ${value} |/" "$file"
        else
            # Add after anchor field
            insert_line_after "| ${anchor_field} |" "| ${field} | ${value} |" "$file"
            log_warn "Added missing ${field} field to Status Header"
        fi
    }

    # Add/update fields in order (each anchors to the previous, starting from found anchor)
    add_or_update_field "AI Developer Ready" "yes" "$anchor"
    add_or_update_field "AI Developer Ready By" "${reviewer}" "AI Developer Ready"
    add_or_update_field "AI Developer Ready Date" "${date}" "AI Developer Ready By"
    add_or_update_field "AI Developer Ready Iteration" "${iteration}" "AI Developer Ready Date"

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

    # Find the best anchor field (use regex to handle variable whitespace)
    local anchor=""
    for candidate in "AI Developer Ready Iteration" "AI Developer Ready Date" "AI Developer Ready By" "AI Developer Ready" "Execution Started" "Ralph Date" "Approver"; do
        if grep -qE "\| ${candidate}[[:space:]]*\|" "$file"; then
            anchor="$candidate"
            break
        fi
    done

    if [[ -z "$anchor" ]]; then
        log_error "Cannot find anchor field in Status Header to add Implementation Verification fields"
        return 1
    fi

    # Helper to add or update a field (use regex to handle variable whitespace)
    _add_or_update_field() {
        local field="$1"
        local value="$2"
        local anchor_field="$3"
        local target_file="$4"
        if grep -qE "\| ${field}[[:space:]]*\|" "$target_file"; then
            # Pattern handles variable whitespace in markdown tables
            sed -i '' "s/| ${field}[[:space:]]*|[^|]*|/| ${field} | ${value} |/" "$target_file"
        else
            insert_line_after "| ${anchor_field} |" "| ${field} | ${value} |" "$target_file"
            log_warn "Added missing ${field} field to Status Header"
        fi
    }

    # Add/update fields in order
    _add_or_update_field "Implementation Verified" "yes" "$anchor" "$file"
    _add_or_update_field "Implementation Verified By" "${reviewer}" "Implementation Verified" "$file"
    _add_or_update_field "Implementation Verified Date" "${date}" "Implementation Verified By" "$file"

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
# RALPH REVIEW STATUS
# =============================================================================

# Update Ralph Review fields in Status Header
# If fields don't exist, adds them after Approver row
update_ralph_status() {
    local file="$1"
    local status="$2"  # required / completed / not-required
    local ts
    ts=$(timestamp)
    local date_val="-"
    if [[ "$status" == "completed" ]]; then
        date_val=$(datestamp)
    fi

    # Check if Ralph Review field exists (use regex to handle variable whitespace)
    if grep -qE "\| Ralph Review[[:space:]]*\|" "$file"; then
        # Update existing field (pattern handles variable whitespace)
        sed -i '' "s/| Ralph Review[[:space:]]*|[^|]*|/| Ralph Review | ${status} |/" "$file"
    else
        # Add Ralph Review field after Approver row
        if grep -qE "\| Approver[[:space:]]*\|" "$file"; then
            insert_line_after "| Approver |" "| Ralph Review | ${status} |" "$file"
            log_warn "Added missing Ralph Review field to Status Header"
        else
            log_error "Cannot find Approver row to insert Ralph Review field"
            return 1
        fi
    fi

    # Check if Ralph Date field exists (use regex to handle variable whitespace)
    if grep -qE "\| Ralph Date[[:space:]]*\|" "$file"; then
        # Update existing field (pattern handles variable whitespace)
        sed -i '' "s/| Ralph Date[[:space:]]*|[^|]*|/| Ralph Date | ${date_val} |/" "$file"
    else
        # Add Ralph Date field after Ralph Review row
        if grep -qE "\| Ralph Review[[:space:]]*\|" "$file"; then
            insert_line_after "| Ralph Review |" "| Ralph Date | ${date_val} |" "$file"
            log_warn "Added missing Ralph Date field to Status Header"
        fi
    fi

    # Update Last Updated
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$file"
}

# =============================================================================
# EXECUTION REQUEST MANAGEMENT
# =============================================================================

# Generate a random request ID
generate_request_id() {
    # Use uuidgen if available, otherwise fallback to date-based
    if command -v uuidgen &> /dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8
    else
        date +%s%N | sha256sum | cut -c1-8
    fi
}

# Create an execution request file
create_execution_request() {
    local plan_file="$1"
    local request_id
    request_id=$(generate_request_id)
    local request_file="${EXECUTION_REQUESTS_DIR}/${request_id}.json"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local expiry
    expiry=$(date -u -v+${EXECUTION_EXPIRY_MINUTES}M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
             date -u -d "+${EXECUTION_EXPIRY_MINUTES} minutes" +"%Y-%m-%dT%H:%M:%SZ")

    # Ensure directory exists
    mkdir -p "${EXECUTION_REQUESTS_DIR}"

    # Create request file
    cat > "$request_file" << EOF
{
  "request_id": "${request_id}",
  "plan_file": "${plan_file}",
  "created_at": "${ts}",
  "expires_at": "${expiry}",
  "approved": false,
  "approved_by": null,
  "approved_at": null
}
EOF
    echo "$request_id"
}

# Find a valid (approved, not expired) execution request for a plan
find_valid_approval() {
    local plan_file="$1"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [[ ! -d "$EXECUTION_REQUESTS_DIR" ]]; then
        return
    fi

    for request_file in "${EXECUTION_REQUESTS_DIR}"/*.json; do
        [[ -f "$request_file" ]] || continue

        # Parse JSON (simple grep-based for portability)
        local req_plan req_approved req_expiry
        req_plan=$(grep '"plan_file"' "$request_file" | sed 's/.*: *"\([^"]*\)".*/\1/')
        req_approved=$(grep '"approved"' "$request_file" | grep -o 'true\|false')
        req_expiry=$(grep '"expires_at"' "$request_file" | sed 's/.*: *"\([^"]*\)".*/\1/')

        # Check if this is for our plan and is approved
        if [[ "$req_plan" == "$plan_file" && "$req_approved" == "true" ]]; then
            # Check if not expired (simple string comparison works for ISO 8601)
            if [[ "$req_expiry" > "$now" ]]; then
                echo "$request_file"
                return
            fi
        fi
    done
}

# Find an unapproved (pending) execution request for a plan
# Returns: request file path if found, empty otherwise
find_pending_request() {
    local plan_file="$1"

    if [[ ! -d "$EXECUTION_REQUESTS_DIR" ]]; then
        return
    fi

    for request_file in "${EXECUTION_REQUESTS_DIR}"/*.json; do
        [[ -f "$request_file" ]] || continue

        # Parse JSON (simple grep-based for portability)
        local req_plan req_approved
        req_plan=$(grep '"plan_file"' "$request_file" | sed 's/.*: *"\([^"]*\)".*/\1/')
        req_approved=$(grep '"approved"' "$request_file" | grep -o 'true\|false')

        # Check if this is for our plan and is NOT yet approved
        if [[ "$req_plan" == "$plan_file" && "$req_approved" == "false" ]]; then
            echo "$request_file"
            return
        fi
    done
}

# =============================================================================
# EXECUTION STATUS UPDATES
# =============================================================================

# Update execution status in plan's Status Header
# Adds fields if they don't exist
update_execution_status() {
    local plan_file="$1"
    local approval_file="$2"
    local ts
    ts=$(timestamp)

    # Get approver from approval file
    local approver
    approver=$(grep '"approved_by"' "$approval_file" | sed 's/.*: *"\([^"]*\)".*/\1/')

    # Find the best anchor field (use regex to handle variable whitespace)
    local anchor=""
    for candidate in "Ralph Date" "Ralph Review" "Approver"; do
        if grep -qE "\| ${candidate}[[:space:]]*\|" "$plan_file"; then
            anchor="$candidate"
            break
        fi
    done

    if [[ -z "$anchor" ]]; then
        log_error "Cannot find anchor field in Status Header to add Execution fields"
        return 1
    fi

    # Helper to add or update a field (use regex to handle variable whitespace)
    _add_or_update_exec_field() {
        local field="$1"
        local value="$2"
        local anchor_field="$3"
        local target_file="$4"
        if grep -qE "\| ${field}[[:space:]]*\|" "$target_file"; then
            # Pattern handles variable whitespace in markdown tables
            sed -i '' "s/| ${field}[[:space:]]*|[^|]*|/| ${field} | ${value} |/" "$target_file"
        else
            insert_line_after "| ${anchor_field} |" "| ${field} | ${value} |" "$target_file"
            log_warn "Added missing ${field} field to Status Header"
        fi
    }

    # Add/update fields in order
    _add_or_update_exec_field "Execution Approved" "yes" "$anchor" "$plan_file"
    _add_or_update_exec_field "Execution Approved By" "${approver}" "Execution Approved" "$plan_file"
    _add_or_update_exec_field "Execution Started" "${ts}" "Execution Approved By" "$plan_file"

    # Update Last Updated (pattern handles variable whitespace)
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$plan_file"
}
