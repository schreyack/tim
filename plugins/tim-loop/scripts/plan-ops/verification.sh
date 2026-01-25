#!/usr/bin/env bash
# plan-ops/verification.sh - Verification loop and UI helpers
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, status.sh
# Exports: print_step_header, prompt_for_name, read_from_tty, copy_to_clipboard,
#          show_command, find_remediation_plan, run_verification_tim_loop
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
# UI HELPERS
# =============================================================================

# Print step header with state name
print_step_header() {
    local state="$1"
    local title="$2"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local upper_state
    upper_state=$(echo "$state" | tr '[:lower:]' '[:upper:]')
    echo "[$upper_state] $title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Prompt for name input with validation loop
# Usage: name=$(prompt_for_name "Enter your name")
prompt_for_name() {
    local prompt="$1"
    local name=""
    while [[ -z "$name" ]]; do
        echo -n "$prompt: " >&2
        read -r name </dev/tty
        if [[ -z "$name" ]]; then
            echo "Name required. Please enter a name." >&2
        fi
    done
    echo "$name"
}

# Read a line from the terminal (works even when stdin is redirected)
read_from_tty() {
    local prompt="$1"
    local var_name="${2:-REPLY}"
    echo -n "$prompt" >&2
    read -r "$var_name" </dev/tty
}

# Copy text to clipboard (cross-platform)
copy_to_clipboard() {
    local text="$1"
    if command -v pbcopy &>/dev/null; then
        # macOS
        echo -n "$text" | pbcopy
        return 0
    elif command -v xclip &>/dev/null; then
        # Linux with xclip
        echo -n "$text" | xclip -selection clipboard
        return 0
    elif command -v xsel &>/dev/null; then
        # Linux with xsel
        echo -n "$text" | xsel --clipboard --input
        return 0
    fi
    return 1
}

# Display a command and copy it to clipboard
show_command() {
    local cmd="$1"
    echo ""
    echo -e "  ${GREEN}${cmd}${NC}"
    echo ""
    if copy_to_clipboard "$cmd"; then
        echo -e "  ${YELLOW}(Copied to clipboard)${NC}"
    fi
    echo ""
}

# =============================================================================
# REMEDIATION PLAN DISCOVERY
# =============================================================================

# Find the most recent remediation plan in drafts/
# Returns: path to remediation plan if found, empty otherwise
find_remediation_plan() {
    local plans_dir="${1:-$PLANS_DIR}"
    local drafts_dir="${plans_dir}/drafts"

    if [[ ! -d "$drafts_dir" ]]; then
        return
    fi

    # Find most recent file with "remediation" in the name (created in last 30 min)
    local recent_file
    recent_file=$(find "$drafts_dir" -maxdepth 1 -name "*remediation*.md" -type f -mmin -30 2>/dev/null | head -1)

    if [[ -n "$recent_file" ]]; then
        echo "$recent_file"
    fi
}

# =============================================================================
# VERIFICATION TIM-LOOP
# =============================================================================

# Run optional verification tim-loop
# Returns: 0 if verification passed or skipped, 1 if verification failed (with remediation plan offered)
run_verification_tim_loop() {
    local plan_file="$1"
    local prompt_text="${2:-Run verification tim-loop? [y/N] }"

    echo ""
    echo "You can run a verification tim-loop to ensure the plan was fully implemented."
    echo "This will:"
    echo "  - Review the original intent of the plan"
    echo "  - Check if it was actually implemented"
    echo "  - Verify TIM Project rules were followed"
    echo "  - Create remediation plans if gaps are found"
    echo "  - Iterate until fully complete (no stubs, no deferred work)"
    echo ""
    echo -n "$prompt_text"
    read -r run_verification </dev/tty

    if [[ ! "$run_verification" =~ ^[Yy] ]]; then
        return 0  # Skipped, treat as success
    fi

    # Determine project directory and plans directory from plan file path
    local project_dir plans_dir
    plans_dir=$(get_plans_dir_from_path "$plan_file")
    project_dir=$(dirname "$plans_dir")

    # Ensure tim-loop permissions are configured
    ensure_tim_loop_permissions "$project_dir"

    echo ""
    echo "Run this command in Claude Code:"
    local cmd="/tim-loop:tim-loop \"VERIFICATION AUDIT for $plan_file

Your task is to verify that this plan was FULLY implemented with NO shortcuts.

PHASE 1 - INTENT REVIEW:
1. Read the plan file completely
2. Extract the ORIGINAL INTENT - what was this plan supposed to accomplish?
3. List all explicit requirements and deliverables

PHASE 2 - IMPLEMENTATION AUDIT:
1. For each requirement/deliverable, find the actual implementation
2. Check: Is the code REAL and FUNCTIONAL, or stubbed/placeholder?
3. Check: Are there any TODO comments, NotImplementedError, 'pass' statements?
4. Check: Is anything marked as 'future work' or 'deferred'?

PHASE 3 - TIM RULES VERIFICATION:
1. Verify type safety (mypy --strict / tsc --strict passes)
2. Verify test coverage (90% minimum, tests actually test the functionality)
3. Verify no secrets in code
4. Verify file size limits (400 lines max)
5. Verify no bypass flags or shortcuts

PHASE 4 - GAP REMEDIATION:
If ANY gaps are found:
1. Create a detailed remediation plan in ${plans_dir}/drafts/ with 'remediation' in filename
2. The remediation plan MUST include proper Status Header (use plan-ops.sh format)
3. DO NOT implement the remediation - it requires approval workflow first
4. Output verification status as FAILED

CRITICAL:
- If gaps found: Create remediation plan, report FAILED, and EXIT
- If no gaps: Report PASSED
- The remediation plan will go through its own approval workflow before implementation\""
    show_command "$cmd"
    echo -n "Press Enter when verification tim-loop completes..."
    read -r </dev/tty

    echo ""
    echo "Did the verification tim-loop complete successfully with all checks passing? (y/n)"
    echo -n "> "
    read -r verification_passed </dev/tty

    if [[ ! "$verification_passed" =~ ^[Yy] ]]; then
        log_warn "Verification FAILED - gaps were found."
        echo ""

        # Look for remediation plan
        local remediation_plan
        remediation_plan=$(find_remediation_plan "$plans_dir")

        if [[ -n "$remediation_plan" ]]; then
            log_info "Found remediation plan: $(basename "$remediation_plan")"
            echo ""
            echo "The remediation plan must go through the full approval workflow before implementation."
            echo ""
            echo -n "Start wizard on remediation plan? [Y/n] "
            read -r start_remediation </dev/tty

            if [[ ! "$start_remediation" =~ ^[Nn] ]]; then
                echo ""
                log_info "Starting wizard on remediation plan..."
                echo ""
                # Recursive call to wizard with the remediation plan
                WIZARD_PLAN_FILE="$remediation_plan"
                cmd_wizard "$remediation_plan"
                exit 0  # Exit after remediation wizard completes
            fi
        else
            log_warn "No remediation plan found in ${plans_dir}/drafts/"
            log_info "Check if tim-loop created a remediation plan and run wizard on it manually."
        fi

        return 1
    fi

    log_info "Verification passed!"
    return 0
}
