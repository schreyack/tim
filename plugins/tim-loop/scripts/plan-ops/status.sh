#!/usr/bin/env bash
# plan-ops/status.sh - Status header management
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh
# Exports: get_status_field, get_plan_state, show_plan_status, get_state_description,
#          update_status, ensure_status_header_fields, add_status_header,
#          count_phases, requires_ralph, has_ralph_completed
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# Count phases in a plan file (detects multi-phase plans)
# Returns: number of phases found
count_phases() {
    local file="$1"
    local count
    # Match: ## Phase, ### Phase, Phase 1:, Phase 2:, ### Step N:, etc.
    count=$(grep -cE "(^#{1,3}\s*(Phase|Step)\s*[0-9]*:?|^(Phase|Step)\s*[0-9]+:)" "$file" 2>/dev/null) || count=0
    echo "$count"
}

# Check if plan requires Ralph Loop review
# Returns: "true" if 2+ phases, "false" otherwise
requires_ralph() {
    local file="$1"
    local phase_count
    phase_count=$(count_phases "$file")
    if [[ "$phase_count" -ge 2 ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Check if plan has completed Ralph Loop review
# Returns: "true" if Ralph Review: completed, "false" otherwise
has_ralph_completed() {
    local file="$1"
    # Use regex to handle variable whitespace in markdown tables
    if grep -qE "\| Ralph Review[[:space:]]*\|[[:space:]]*completed[[:space:]]*\|" "$file" 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# Extract a field value from Status Header markdown table
# Usage: get_status_field "$plan_file" "Stage"
# Returns: field value (e.g., "draft", "active") or empty if not found
get_status_field() {
    local file="$1"
    local field="$2"
    # Match: | Field | value | where Field is at the START of the row (first column)
    # This avoids matching table headers like "| Timestamp | Stage | Event |"
    grep -E "^\\| *${field} *\\|" "$file" 2>/dev/null | head -1 | sed -E "s/^\\| *${field} *\\| *([^|]*) *\\|.*/\\1/" | xargs
}

# Get current workflow state for a plan
# Returns: import|ralph|promote|ai-ready|execute-request|execute-approve|tim-loop|complete|done|abandoned|unknown|not-found
get_plan_state() {
    local plan_file="$1"

    # Check if file exists
    if [[ ! -f "$plan_file" ]]; then
        echo "not-found"
        return
    fi

    # Check if in ~/.claude/plans (needs import)
    if [[ "$plan_file" == *"/.claude/plans/"* ]]; then
        echo "import"
        return
    fi

    # Read status fields from Status Header using helper
    local stage ralph_review ai_ready exec_approved impl_verified
    stage=$(get_status_field "$plan_file" "Stage")
    ralph_review=$(get_status_field "$plan_file" "Ralph Review")
    ai_ready=$(get_status_field "$plan_file" "AI Developer Ready")
    exec_approved=$(get_status_field "$plan_file" "Execution Approved")
    impl_verified=$(get_status_field "$plan_file" "Implementation Verified")

    # State machine
    case "$stage" in
        draft)
            # Ralph Review: required (needs loop) | completed (done) | not-required (skip)
            if [[ "$ralph_review" == "required" ]]; then
                echo "ralph"
            elif [[ "$ralph_review" == "completed" || "$ralph_review" == "not-required" ]]; then
                echo "promote"
            else
                # Ralph Review field missing or empty - check if multi-phase
                local needs_ralph
                needs_ralph=$(requires_ralph "$plan_file")
                if [[ "$needs_ralph" == "true" ]]; then
                    echo "ralph"
                else
                    echo "promote"
                fi
            fi
            ;;
        active|in_progress)
            if [[ "$ai_ready" != "yes" ]]; then
                echo "ai-ready"
            elif [[ "$exec_approved" != "yes" ]]; then
                # Check for pending approval request
                local pending
                pending=$(find_pending_request "$plan_file")
                if [[ -n "$pending" ]]; then
                    echo "execute-approve"
                else
                    echo "execute-request"
                fi
            elif [[ "$impl_verified" == "yes" ]]; then
                echo "complete"
            else
                echo "tim-loop"
            fi
            ;;
        completed)
            echo "done"
            ;;
        abandoned)
            echo "abandoned"
            ;;
        *)
            # No Status Header or unrecognized stage
            echo "unknown"
            ;;
    esac
}

# Display plan status for --status mode
show_plan_status() {
    local plan_file="$1"
    local state="$2"

    # Read status fields using the helper
    local stage ralph_review ai_ready exec_approved impl_verified
    stage=$(get_status_field "$plan_file" "Stage")
    ralph_review=$(get_status_field "$plan_file" "Ralph Review")
    ai_ready=$(get_status_field "$plan_file" "AI Developer Ready")
    exec_approved=$(get_status_field "$plan_file" "Execution Approved")
    impl_verified=$(get_status_field "$plan_file" "Implementation Verified")

    # Default empty fields to "-"
    [[ -z "$stage" ]] && stage="-"
    [[ -z "$ralph_review" ]] && ralph_review="-"
    [[ -z "$ai_ready" ]] && ai_ready="-"
    [[ -z "$exec_approved" ]] && exec_approved="-"
    [[ -z "$impl_verified" ]] && impl_verified="-"

    echo ""
    echo "Plan: $plan_file"
    echo "Stage: $stage"
    echo "Ralph Review: $ralph_review"
    echo "AI Developer Ready: $ai_ready"
    echo "Execution Approved: $exec_approved"
    echo "Implementation Verified: $impl_verified"
    echo ""
    echo "Current State: $state"
    echo "Next Action: $(get_state_description "$state")"
}

# Human-readable state descriptions
get_state_description() {
    case "$1" in
        import)          echo "Import plan to drafts folder" ;;
        ralph)           echo "Run Ralph Loop review, then mark complete" ;;
        promote)         echo "Promote plan to active" ;;
        ai-ready)        echo "Run AI-ready review, then mark ai-ready" ;;
        execute-request) echo "Create execution request" ;;
        execute-approve) echo "Approve execution in separate terminal" ;;
        tim-loop)        echo "Run Tim Loop implementation" ;;
        complete)        echo "Mark plan complete" ;;
        done)            echo "Plan already complete" ;;
        abandoned)       echo "Plan was cancelled" ;;
        unknown)         echo "Unknown state - check Status Header" ;;
        not-found)       echo "Plan file not found" ;;
        *)               echo "Unknown state" ;;
    esac
}

# Update the Status Header in a plan file
# Returns 1 if required fields are missing
update_status() {
    local file="$1"
    local stage="$2"
    local event="$3"
    local approver="${4:-}"
    local ts
    ts=$(timestamp)

    # Verify required fields exist (use regex to handle variable whitespace)
    if ! grep -qE "\| Stage[[:space:]]*\|" "$file"; then
        log_error "Status Header missing required 'Stage' field in: $file"
        return 1
    fi
    if ! grep -qE "\| Last Updated[[:space:]]*\|" "$file"; then
        log_error "Status Header missing required 'Last Updated' field in: $file"
        return 1
    fi

    # Update Stage field (pattern handles variable whitespace in markdown tables)
    sed -i '' "s/| Stage[[:space:]]*|[^|]*|/| Stage | ${stage} |/" "$file"

    # Update Last Updated field
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$file"

    # Update Approver if provided
    if [[ -n "$approver" ]]; then
        if grep -qE "\| Approver[[:space:]]*\|" "$file"; then
            sed -i '' "s/| Approver[[:space:]]*|[^|]*|/| Approver | ${approver} |/" "$file"
        else
            log_warn "Status Header missing 'Approver' field, skipping update"
        fi
    fi

    # Append to Progress Log (find the table and add a row before the next ---)
    # This is a simple append - in practice you'd want more robust parsing
    local log_line="| ${ts} | ${stage} | ${event} |"

    # Find line number of "### Progress Log" and append after the header row
    if grep -q "### Progress Log" "$file"; then
        # Use awk to insert after the last table row before the ---
        awk -v line="$log_line" '
            /^\| Timestamp \| Stage \| Event \|/ { in_table=1 }
            in_table && /^---/ { print line; in_table=0 }
            { print }
        ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    fi
}

# Ensure all required Status Header fields exist
# Adds missing fields with appropriate defaults
ensure_status_header_fields() {
    local file="$1"
    local ts
    ts=$(timestamp)

    # If no Status Header at all, add_status_header will handle it
    if ! grep -q "## Status" "$file"; then
        return 0
    fi

    # Define required fields with their default values
    # Format: "field_name|default_value|anchor_field"
    # anchor_field is where to insert after if missing
    local ralph_status="not-required"
    if [[ "$(requires_ralph "$file")" == "true" ]]; then
        ralph_status="required"
    fi

    local required_fields=(
        "Stage|draft|Field"
        "Created|${ts}|Stage"
        "Last Updated|${ts}|Created"
        "Author|Claude|Last Updated"
        "Approver|-|Author"
        "Ralph Review|${ralph_status}|Approver"
        "Ralph Date|-|Ralph Review"
        "Execution Approved|no|Ralph Date"
        "Execution Approved By|-|Execution Approved"
        "Execution Started|-|Execution Approved By"
        "AI Developer Ready|no|Execution Started"
        "AI Developer Ready By|-|AI Developer Ready"
        "AI Developer Ready Date|-|AI Developer Ready By"
        "AI Developer Ready Iteration|-|AI Developer Ready Date"
        "Implementation Verified|no|AI Developer Ready Iteration"
        "Implementation Verified By|-|Implementation Verified"
        "Implementation Verified Date|-|Implementation Verified By"
        "Remediation Plan|-|Implementation Verified Date"
    )

    local added_fields=()

    for field_spec in "${required_fields[@]}"; do
        local field_name default_value anchor_field
        field_name=$(echo "$field_spec" | cut -d'|' -f1)
        default_value=$(echo "$field_spec" | cut -d'|' -f2)
        anchor_field=$(echo "$field_spec" | cut -d'|' -f3)

        # Check if field exists (use regex to handle variable whitespace)
        if ! grep -qE "\| ${field_name}[[:space:]]*\|" "$file"; then
            # Add field after anchor
            if grep -qE "\| ${anchor_field}[[:space:]]*\|" "$file"; then
                insert_line_after "| ${anchor_field} |" "| ${field_name} | ${default_value} |" "$file"
                added_fields+=("$field_name")
            fi
        fi
    done

    # Check for Progress Log section
    if ! grep -q "### Progress Log" "$file"; then
        # Find the last table row and add Progress Log section after it
        # Using awk for multi-line insertion
        local last_field_line
        last_field_line=$(grep -n "^| " "$file" | tail -1 | cut -d: -f1)
        if [[ -n "$last_field_line" ]]; then
            local progress_section="
### Progress Log

| Timestamp | Stage | Event |
|-----------|-------|-------|
| ${ts} | draft | Plan imported |

---"
            awk -v n="$last_field_line" -v text="$progress_section" '
                NR == n { print; print text; next }
                { print }
            ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
            added_fields+=("Progress Log")
        fi
    fi

    # Report what was added
    if [[ ${#added_fields[@]} -gt 0 ]]; then
        log_info "Added missing Status Header fields: ${added_fields[*]}"
    fi
}

# Add Status Header to a plan that doesn't have one
add_status_header() {
    local file="$1"
    local author="${2:-Claude}"
    local ts
    ts=$(timestamp)

    # Check if Status header already exists
    if grep -q "## Status" "$file"; then
        return 0
    fi

    # Determine Ralph Review status based on phase count
    local ralph_status="not-required"
    if [[ "$(requires_ralph "$file")" == "true" ]]; then
        ralph_status="required"
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
| Ralph Review | ${ralph_status} |
| Ralph Date | - |
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
