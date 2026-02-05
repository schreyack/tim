#!/usr/bin/env bash
# plan-ops/reset.sh - Plan status reset functionality
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, status.sh
# Exports: reset_for_full_review
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
