#!/usr/bin/env bash
# plan-ops/status-init.sh - Status Header initialization and repair
# Extracted from status.sh to comply with 400-line limit
#
# Dependencies: core.sh, status.sh
# Exports: fix_invalid_stage, add_status_header
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh
# shellcheck source=plan-ops/status.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# Fix invalid or missing Stage field in a plan's Status Header
# Determines correct stage from folder location and repairs the field
# Returns: 0 if fixed, 1 if file has no Status Header
fix_invalid_stage() {
    local file="$1"
    local ts
    ts=$(timestamp)

    # Check if Status header exists
    if ! grep -qE "^## Status[[:space:]]*$" "$file"; then
        return 1
    fi

    # Determine expected stage from folder location
    local expected_stage="draft"
    if [[ "$file" == *"/plans/active/"* ]]; then
        expected_stage="active"
    elif [[ "$file" == *"/plans/completed/"* ]]; then
        expected_stage="completed"
    elif [[ "$file" == *"/plans/abandoned/"* ]]; then
        expected_stage="abandoned"
    fi

    # Check current stage value
    local current_stage
    current_stage=$(get_status_field "$file" "Stage")

    # Validate stage value
    if [[ "$current_stage" =~ ^(draft|active|completed|abandoned)$ ]]; then
        # Stage is valid, no fix needed
        return 0
    fi

    # Stage is missing or invalid - fix it
    if grep -qE "\| Stage[[:space:]]*\|" "$file"; then
        # Stage row exists but value is invalid - update it
        log_info "Fixing invalid Stage value '${current_stage}' -> '${expected_stage}'"
        sed -i '' "s/| Stage[[:space:]]*|[^|]*|/| Stage | ${expected_stage} |/" "$file"
    else
        # Stage row is missing - add it after Field header
        if grep -qE "\| Field[[:space:]]*\|[[:space:]]*Value[[:space:]]*\|" "$file"; then
            log_info "Adding missing Stage field with value '${expected_stage}'"
            # Insert Stage row after the table header row
            awk -v stage="$expected_stage" '
                /\| Field[[:space:]]*\|[[:space:]]*Value[[:space:]]*\|/ {
                    print
                    getline  # Print the separator row
                    print
                    print "| Stage | " stage " |"
                    next
                }
                { print }
            ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
        else
            # No proper table structure - try adding after ## Status
            log_info "Adding Stage field after Status header"
            sed -i '' '/## Status/a\
\
| Field | Value |\
|-------|-------|\
| Stage | '"${expected_stage}"' |' "$file"
        fi
    fi

    # Update Last Updated if it exists
    if grep -qE "\| Last Updated[[:space:]]*\|" "$file"; then
        sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$file"
    fi

    return 0
}

# Add Status Header to a plan that doesn't have one
add_status_header() {
    local file="$1"
    local author="${2:-Claude}"
    local ts
    ts=$(timestamp)

    # Check if Status header already exists
    if grep -qE "^## Status[[:space:]]*$" "$file"; then
        return 0
    fi

    # Determine Plan Review status based on phase count
    local review_status="not-required"
    if [[ "$(requires_review "$file")" == "true" ]]; then
        review_status="required"
    fi

    # Determine PM Review status based on phase count
    local pm_review_status="not-required"
    if [[ "$(requires_pm_review "$file")" == "true" ]]; then
        pm_review_status="required"
    fi

    # Create header content
    local header="## Status

| Field | Value |
|-------|-------|
| Stage | draft |
| Created | ${ts} |
| Last Updated | ${ts} |
| Author | ${author} |
| Approver | - |
| Plan Review | ${review_status} |
| Review Date | - |
| PM Review | ${pm_review_status} |
| PM Review Date | - |
| Execution Approved | no |
| Execution Approved By | - |
| Execution Started | - |
| AI Developer Ready | no |
| AI Developer Ready By | - |
| AI Developer Ready Date | - |
| AI Developer Ready Iteration | - |
| Implementation Verified | no |
| Implementation Verified By | - |
| Implementation Verified Date | - |
| Remediation Plan | - |

### Progress Log

| Timestamp | Stage | Event |
|-----------|-------|-------|
| ${ts} | draft | Plan created |

---

"

    # Insert after the first line (title)
    local title
    title=$(head -n 1 "$file")
    local rest
    rest=$(tail -n +2 "$file")

    echo "$title" > "$file"
    echo "" >> "$file"
    echo "$header" >> "$file"
    echo "$rest" >> "$file"
}
