#!/usr/bin/env bash
# plan-ops/verification.sh - Verification loop and UI helpers
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, status.sh
# Exports: print_step_header, prompt_for_name, read_from_tty, copy_to_clipboard,
#          show_command, find_remediation_plan, run_verification_tim_loop,
#          handle_unexpected_plan_move
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
    echo "Run /clear first, then paste this command in Claude Code:"
    local cmd="/tim-loop:tim-loop --verify $plan_file --max-iterations 10"
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

# =============================================================================
# UNEXPECTED PLAN MOVE DETECTION
# =============================================================================

# Handle unexpected plan moves during wizard steps
# Usage: handle_unexpected_plan_move <expected_folder>
# Returns: 0 if plan is in expected location (or moved back)
#          1 if plan was moved and user accepted the new location
# Updates WIZARD_PLAN_FILE to current location
handle_unexpected_plan_move() {
    local expected_folder="$1"  # drafts, active, completed, abandoned
    local basename plans_dir

    basename=$(basename "$WIZARD_PLAN_FILE")
    plans_dir=$(get_plans_dir_from_path "$WIZARD_PLAN_FILE")

    # If file exists at expected location, all good
    if [[ -f "$WIZARD_PLAN_FILE" ]] && [[ "$WIZARD_PLAN_FILE" == *"/plans/${expected_folder}/"* ]]; then
        return 0
    fi

    # File doesn't exist or is in wrong folder - search for it
    local found_in="" found_path=""
    for folder in drafts active completed abandoned; do
        local check_path="${plans_dir}/${folder}/${basename}"
        if [[ -f "$check_path" ]]; then
            found_in="$folder"
            found_path="$check_path"
            break
        fi
    done

    # File not found anywhere
    if [[ -z "$found_in" ]]; then
        log_error "Plan file not found: $WIZARD_PLAN_FILE"
        log_error "The file may have been moved or deleted."
        exit 1
    fi

    # File is in expected folder (handles case where WIZARD_PLAN_FILE path was wrong)
    if [[ "$found_in" == "$expected_folder" ]]; then
        WIZARD_PLAN_FILE="$found_path"
        return 0
    fi

    # File was unexpectedly moved to a different folder
    echo ""
    log_warn "Plan was unexpectedly moved to ${found_in}/"
    echo ""
    echo "This happens when Claude moves the plan without going through the"
    echo "proper approval workflow. You can undo this to continue normally."
    echo ""
    echo -n "Move plan back to ${expected_folder}/ and continue? [Y/n] "
    read -r undo_response </dev/tty

    if [[ ! "$undo_response" =~ ^[Nn] ]]; then
        # User wants to undo - move it back
        local target_path="${plans_dir}/${expected_folder}/${basename}"
        mkdir -p "${plans_dir}/${expected_folder}"
        mv "$found_path" "$target_path"
        WIZARD_PLAN_FILE="$target_path"
        log_info "Moved plan back to ${expected_folder}/"

        # Update Stage field to match folder
        local stage_value
        case "$expected_folder" in
            drafts) stage_value="draft" ;;
            active) stage_value="active" ;;
            completed) stage_value="completed" ;;
            abandoned) stage_value="abandoned" ;;
        esac
        sed -i '' "s/| Stage[[:space:]]*|[^|]*|/| Stage | ${stage_value} |/" "$target_path"

        # Reset verification fields if moving back from completed
        if [[ "$found_in" == "completed" ]]; then
            sed -i '' "s/| Implementation Verified[[:space:]]*|[^|]*|/| Implementation Verified | no |/" "$target_path"
            sed -i '' "s/| Implementation Verified By[[:space:]]*|[^|]*|/| Implementation Verified By | - |/" "$target_path"
            sed -i '' "s/| Implementation Verified Date[[:space:]]*|[^|]*|/| Implementation Verified Date | - |/" "$target_path"
            log_info "Reset verification fields for re-verification."
        fi

        return 0
    else
        # User accepts the unexpected move
        WIZARD_PLAN_FILE="$found_path"
        log_info "Accepted move to ${found_in}/"
        return 1
    fi
}
