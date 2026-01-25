#!/usr/bin/env bash
# plan-ops/commands-lifecycle.sh - Plan lifecycle commands
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh, search.sh, status.sh, approval.sh
# Exports: cmd_init, cmd_import, cmd_promote, cmd_complete, cmd_abandon,
#          cmd_cleanup_drafts, cleanup_claude_plans
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh
# shellcheck source=plan-ops/status.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

cmd_init() {
    log_info "Initializing plan folder structure..."

    mkdir -p "${PLANS_DIR}"/{drafts,active,completed,abandoned}

    # Create .gitkeep files to preserve empty directories
    for dir in drafts active completed abandoned; do
        touch "${PLANS_DIR}/${dir}/.gitkeep"
    done

    log_info "Created: ${PLANS_DIR}/{drafts,active,completed,abandoned}/"
    echo ""

    # Show PATH setup instructions
    local bin_dir="${DESIGN_STANDARDS_DIR}/bin"
    echo "========================================"
    log_info "PATH SETUP (optional but recommended)"
    echo "========================================"
    echo ""
    echo "Add plan-ops to your PATH to run it from anywhere:"
    echo ""
    echo "  # Add to ~/.bashrc or ~/.zshrc:"
    echo -e "  ${GREEN}export PATH=\"${bin_dir}:\$PATH\"${NC}"
    echo ""
    echo "  # Then reload your shell or run:"
    echo -e "  ${GREEN}source ~/.bashrc${NC}  # or source ~/.zshrc"
    echo ""
    echo "  # After setup, you can run:"
    echo -e "  ${GREEN}plan-ops import ...${NC}"
    echo -e "  ${GREEN}plan-ops wizard ...${NC}"
    echo ""
    echo "========================================"
    echo ""

    log_info "NEXT STEP: Import a plan from ~/.claude/plans:"
    show_command "$SCRIPT_PATH import ~/.claude/plans/<plan-name>.md"
}

cmd_import() {
    local source="${1:-}"
    local name=""

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                name="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$source" ]]; then
        log_error "Usage: $SCRIPT_PATH import <source-file> [--name <description>]"
        exit 1
    fi

    # Try to resolve the source - first as literal path, then by searching
    if [[ -f "$source" ]]; then
        # File exists at given path - convert to absolute
        source=$(to_absolute "$source")
    else
        # File not found - try to resolve by name (searches plans/ and ~/.claude/plans/)
        local resolved
        resolved=$(resolve_plan_path "$source" 2>/dev/null) || true
        if [[ -n "$resolved" && -f "$resolved" ]]; then
            source="$resolved"
        else
            log_error "Source file not found: $source"
            log_info "Searched in: current directory, $PLANS_DIR/*, $CLAUDE_PLANS_DIR"
            exit 1
        fi
    fi

    # Check if file is already in plans/drafts/ (already imported)
    if [[ "$source" == *"/plans/drafts/"* ]]; then
        log_info "Plan is already in drafts folder: $source"

        # Ensure Status Header has all required fields (fix incomplete headers)
        ensure_status_header_fields "$source"

        echo ""

        # Check current state and provide next steps
        local state
        state=$(get_plan_state "$source")

        case "$state" in
            ralph)
                local phase_count
                phase_count=$(count_phases "$source")
                log_info "This is a multi-phase plan (${phase_count} phases). Ralph Loop review is required."
                ;;
            promote)
                log_info "Plan is ready for promotion to active."
                ;;
            *)
                log_info "Current state: $state"
                ;;
        esac
        log_info "NEXT STEP: Use the wizard to continue the plan lifecycle:"
        show_command "$SCRIPT_PATH wizard $source"
        exit 0
    fi

    # Generate destination filename
    if [[ -z "$name" ]]; then
        name=$(basename "$source" .md)
    fi

    # If name already has a date prefix (YYYY-MM-DD-), use it as-is; otherwise prepend today's date
    local dest
    if [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}- ]]; then
        dest=$(to_absolute "${PLANS_DIR}/drafts/${name}.md")
    else
        dest=$(to_absolute "${PLANS_DIR}/drafts/$(datestamp)-${name}.md")
    fi

    # Copy the file
    cp "$source" "$dest"
    log_info "Copied to: $dest"

    # Ensure Status Header exists and has all required fields
    add_status_header "$dest" "Claude"
    ensure_status_header_fields "$dest"

    # Delete the original
    rm "$source"
    log_info "Deleted original: $source"

    # Cleanup any other files in ~/.claude/plans
    cleanup_claude_plans

    log_info "Import complete: $dest"

    # Show next step - always recommend wizard
    local phase_count
    phase_count=$(count_phases "$dest")
    echo ""
    if [[ "$phase_count" -ge 2 ]]; then
        log_info "This is a multi-phase plan (${phase_count} phases). Ralph Loop review is required."
    else
        log_info "This is a single-phase plan. Can be promoted directly."
    fi
    log_info "NEXT STEP: Use the wizard to continue the plan lifecycle:"
    show_command "$SCRIPT_PATH wizard $dest"
}

cmd_promote() {
    # Block AI from running this command
    verify_interactive_terminal

    local plan_file="${1:-}"
    local approver=""
    local skip_ralph=false

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --approver)
                approver="$2"
                shift 2
                ;;
            --skip-ralph)
                skip_ralph=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH promote <plan-file> --approver <name>"
        exit 1
    fi

    if [[ -z "$approver" ]]; then
        log_error "Approver required: --approver <name>"
        exit 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    # Convert to absolute path for output messages
    plan_file=$(to_absolute "$plan_file")

    # Check Ralph Loop requirement for multi-phase plans
    local needs_ralph
    needs_ralph=$(requires_ralph "$plan_file")
    local has_ralph
    has_ralph=$(has_ralph_completed "$plan_file")
    local phase_count
    phase_count=$(count_phases "$plan_file")

    if [[ "$needs_ralph" == "true" && "$has_ralph" != "true" ]]; then
        log_error "BLOCKED: Multi-phase plan (${phase_count} phases) requires Ralph Loop review."
        log_error "Ralph Loop review has NOT been completed for this plan."
        echo ""
        echo "To start: $SCRIPT_PATH ralph $plan_file"
        echo "Then:     $SCRIPT_PATH ralph $plan_file --mark-complete"
        echo "Then retry promotion."
        exit 1
    fi

    if [[ "$skip_ralph" == "true" && "$needs_ralph" == "true" ]]; then
        log_error "BLOCKED: Cannot skip Ralph Loop for multi-phase plans."
        log_error "--skip-ralph only works for single-phase plans."
        exit 1
    fi

    local basename
    basename=$(basename "$plan_file")
    local plans_dir
    plans_dir=$(get_plans_dir_from_path "$plan_file")
    local dest="${plans_dir}/active/${basename}"

    # Ensure destination directory exists
    mkdir -p "${plans_dir}/active"

    # Only move if source and destination are different
    if [[ "$plan_file" != "$dest" ]]; then
        mv "$plan_file" "$dest"
    fi

    # Update status
    if ! update_status "$dest" "active" "Approved by ${approver}, promoted to active" "$approver"; then
        log_error "Failed to update status after promotion"
        exit 1
    fi

    # Cleanup claude plans
    cleanup_claude_plans

    log_info "Promoted to active: $dest"

    echo ""
    log_info "STEP 1 of 2: Run Ralph Loop to review plan for AI implementation concerns:"
    echo ""
    echo -e "${GREEN}/ralph-loop:ralph-loop \"review ${dest} for AI implementation concerns using standards/enforcement/ai-developer-ready-checklist.md. Verify: (1) instructions are unambiguous (AI has one interpretation), (2) no hallucination opportunities (referenced APIs/files exist), (3) guard rails are explicit (error handling specified), (4) verification criteria are code-checkable. <promise>AI-READY</promise>\" --max-iterations 5 --completion-promise \"AI-READY\"${NC}"
    echo ""
    log_info "STEP 2 of 2: After Ralph Loop completes, human confirms and approves:"
    echo -e "  ${GREEN}$SCRIPT_PATH ai-ready $dest --reviewer \"Your Name\"${NC}"
}

cmd_complete() {
    local plan_file="${1:-}"

    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH complete <plan-file>"
        exit 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    # Convert to absolute path
    plan_file=$(to_absolute "$plan_file")

    local basename
    basename=$(basename "$plan_file")
    local plans_dir
    plans_dir=$(get_plans_dir_from_path "$plan_file")
    local dest="${plans_dir}/completed/${basename}"

    # Ensure destination directory exists and move file
    mkdir -p "${plans_dir}/completed"
    mv "$plan_file" "$dest"

    # Update status
    if ! update_status "$dest" "completed" "All phases completed, verification passed"; then
        log_error "Failed to update status after completion"
        exit 1
    fi

    # Clear saved prompt now that plan is complete
    local project_dir
    project_dir=$(dirname "$plans_dir")
    local prompt_manager="${project_dir}/tools/tim-loop-prompt-manager.sh"
    if [[ -x "$prompt_manager" ]]; then
        "$prompt_manager" clear 2>/dev/null || true
    fi

    log_info "Completed: $dest"
    log_info "Plan lifecycle complete! To see all completed plans:"
    echo -e "  ${GREEN}$SCRIPT_PATH list completed${NC}"
}

cmd_abandon() {
    local plan_file="${1:-}"
    local reason="No reason provided"

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
        log_error "Usage: $SCRIPT_PATH abandon <plan-file> [--reason <reason>]"
        exit 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    # Convert to absolute path
    plan_file=$(to_absolute "$plan_file")

    local basename
    basename=$(basename "$plan_file")
    local plans_dir
    plans_dir=$(get_plans_dir_from_path "$plan_file")
    local dest="${plans_dir}/abandoned/${basename}"

    # Ensure destination directory exists and move file
    mkdir -p "${plans_dir}/abandoned"
    mv "$plan_file" "$dest"

    # Update status
    if ! update_status "$dest" "abandoned" "Abandoned: ${reason}"; then
        log_error "Failed to update status after abandonment"
        exit 1
    fi

    log_info "Abandoned: $dest"

    echo ""
    log_info "Plan abandoned. To see all abandoned plans:"
    echo -e "  ${GREEN}$SCRIPT_PATH list abandoned${NC}"
}

cmd_cleanup_drafts() {
    local days=30

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --older-than)
                days="${2%d}"  # Remove 'd' suffix if present
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    log_info "Finding drafts older than ${days} days..."

    local found=0
    while IFS= read -r -d '' file; do
        echo "  $file"
        found=1
    done < <(find "${PLANS_DIR}/drafts" -name "*.md" -mtime +"$days" -print0 2>/dev/null)

    if [[ $found -eq 0 ]]; then
        log_info "No stale drafts found."
        return 0
    fi

    echo ""
    echo -n "Delete these files? [y/N] "
    read -r response </dev/tty
    if [[ "$response" =~ ^[Yy]$ ]]; then
        find "${PLANS_DIR}/drafts" -name "*.md" -mtime +"$days" -delete
        log_info "Deleted stale drafts."
    else
        log_info "Skipped deletion."
    fi
}

cleanup_claude_plans() {
    if [[ -d "$CLAUDE_PLANS_DIR" ]]; then
        local count
        count=$(find "$CLAUDE_PLANS_DIR" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$count" -gt 0 ]]; then
            find "$CLAUDE_PLANS_DIR" -name "*.md" -delete 2>/dev/null || true
            log_info "Cleaned up ${count} file(s) from ${CLAUDE_PLANS_DIR}"
        fi
    fi
}
