#!/usr/bin/env bash
set -euo pipefail

# plan-ops.sh - TIM Plan Lifecycle Management
# Usage: ./tools/plan-ops.sh <command> [args]
#
# Commands:
#   init              Initialize plan folder structure
#   import            Import plan from ~/.claude/plans to drafts
#   ralph             Start Ralph Loop review for a draft plan
#   promote           Move plan from drafts to active
#   execute           Request execution approval for active plan
#   approve-execute   Human approval for plan execution
#   complete          Move plan from active to completed
#   abandon           Move plan to abandoned
#   cleanup-drafts    Remove stale drafts
#   list              List plans by stage

PLANS_DIR="${PLANS_DIR:-plans}"
CLAUDE_PLANS_DIR="${HOME}/.claude/plans"
EXECUTION_REQUESTS_DIR=".tim-execution-requests"
EXECUTION_EXPIRY_MINUTES=15

# Resolve script's absolute path (works even when called via symlink)
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Convert a path to absolute (resolves relative paths against cwd)
to_absolute() {
    local path="$1"
    if [[ "$path" = /* ]]; then
        echo "$path"
    else
        echo "$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")"
    fi
}

# Check if process is a descendant of Claude Code
# Returns: 0 (true) if descendant, 1 (false) otherwise
is_claude_descendant() {
    local pid=$$
    while [[ $pid -ne 1 ]]; do
        local parent_cmd
        parent_cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "")
        if [[ "$parent_cmd" == *"claude"* ]]; then
            return 0  # Is a descendant
        fi
        pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
        [[ -z "$pid" ]] && break
    done
    return 1  # Not a descendant
}

# Verify command is running from interactive terminal (human, not AI)
# Used by approval commands to block AI bypass attempts
verify_interactive_terminal() {
    # Check if stdin is a terminal (interactive)
    if [[ ! -t 0 ]]; then
        log_error "BLOCKED: This command must be run interactively."
        log_error "AI/scripts cannot run approval commands."
        log_error ""
        log_error "Open a terminal and run this command manually."
        exit 1
    fi

    # Check if we're running under Claude Code session
    if [[ -n "${CLAUDE_CODE_SESSION:-}" ]] || [[ -n "${TIM_LOOP_SESSION_ID:-}" ]]; then
        log_error "BLOCKED: Cannot approve from within Claude Code session."
        log_error "Open a SEPARATE terminal to approve."
        exit 1
    fi

    # Check process lineage for Claude Code
    if is_claude_descendant; then
        log_error "BLOCKED: Cannot approve from within Claude Code process tree."
        log_error "Open a SEPARATE terminal to approve."
        exit 1
    fi
}

# Get current timestamp
timestamp() {
    date "+%Y-%m-%d %H:%M"
}

# Get current date for filenames
datestamp() {
    date "+%Y-%m-%d"
}

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
    if grep -q "| Ralph Review | completed |" "$file" 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# Check if plan has AI Developer Ready approval
# Returns: 0 (true) if approved, 1 (false) otherwise
has_ai_ready_approval() {
    local file="$1"
    grep -q "| AI Developer Ready | yes |" "$file" 2>/dev/null
}

# Update AI Developer Ready fields in Status Header
update_ai_ready_status() {
    local file="$1"
    local reviewer="$2"
    local iteration="$3"
    local ts date
    ts=$(timestamp)
    date=$(datestamp)

    # Update AI Developer Ready fields
    sed -i '' "s/| AI Developer Ready | .* |/| AI Developer Ready | yes |/" "$file"
    sed -i '' "s/| AI Developer Ready By | .* |/| AI Developer Ready By | ${reviewer} |/" "$file"
    sed -i '' "s/| AI Developer Ready Date | .* |/| AI Developer Ready Date | ${date} |/" "$file"
    sed -i '' "s/| AI Developer Ready Iteration | .* |/| AI Developer Ready Iteration | ${iteration} |/" "$file"

    # Update Last Updated
    sed -i '' "s/| Last Updated | .* |/| Last Updated | ${ts} |/" "$file"
}

# Update Implementation Verification fields in Status Header
update_verification_status() {
    local file="$1"
    local reviewer="$2"
    local ts date
    ts=$(timestamp)
    date=$(datestamp)

    # Update Implementation Verification fields
    sed -i '' "s/| Implementation Verified | .* |/| Implementation Verified | yes |/" "$file"
    sed -i '' "s/| Implementation Verified By | .* |/| Implementation Verified By | ${reviewer} |/" "$file"
    sed -i '' "s/| Implementation Verified Date | .* |/| Implementation Verified Date | ${date} |/" "$file"

    # Update Last Updated
    sed -i '' "s/| Last Updated | .* |/| Last Updated | ${ts} |/" "$file"
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

    # Check if Ralph Review field exists
    if grep -q "| Ralph Review |" "$file"; then
        # Update existing field
        sed -i '' "s/| Ralph Review | .* |/| Ralph Review | ${status} |/" "$file"
    else
        # Add Ralph Review field after Approver row
        if grep -q "| Approver |" "$file"; then
            sed -i '' "/| Approver |/a\\
| Ralph Review | ${status} |" "$file"
            log_warn "Added missing Ralph Review field to Status Header"
        else
            log_error "Cannot find Approver row to insert Ralph Review field"
            return 1
        fi
    fi

    # Check if Ralph Date field exists
    if grep -q "| Ralph Date |" "$file"; then
        # Update existing field
        sed -i '' "s/| Ralph Date | .* |/| Ralph Date | ${date_val} |/" "$file"
    else
        # Add Ralph Date field after Ralph Review row
        if grep -q "| Ralph Review |" "$file"; then
            sed -i '' "/| Ralph Review |/a\\
| Ralph Date | ${date_val} |" "$file"
            log_warn "Added missing Ralph Date field to Status Header"
        fi
    fi

    # Update Last Updated
    sed -i '' "s/| Last Updated | .* |/| Last Updated | ${ts} |/" "$file"
}

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

# Update execution status in plan's Status Header
update_execution_status() {
    local plan_file="$1"
    local approval_file="$2"
    local ts
    ts=$(timestamp)

    # Get approver from approval file
    local approver
    approver=$(grep '"approved_by"' "$approval_file" | sed 's/.*: *"\([^"]*\)".*/\1/')

    # Update Execution fields
    if grep -q "| Execution Approved |" "$plan_file"; then
        sed -i '' "s/| Execution Approved | .* |/| Execution Approved | yes |/" "$plan_file"
    fi
    if grep -q "| Execution Approved By |" "$plan_file"; then
        sed -i '' "s/| Execution Approved By | .* |/| Execution Approved By | ${approver} |/" "$plan_file"
    fi
    if grep -q "| Execution Started |" "$plan_file"; then
        sed -i '' "s/| Execution Started | .* |/| Execution Started | ${ts} |/" "$plan_file"
    fi

    # Update Last Updated
    sed -i '' "s/| Last Updated | .* |/| Last Updated | ${ts} |/" "$plan_file"
}

# Update the Status Header in a plan file
update_status() {
    local file="$1"
    local stage="$2"
    local event="$3"
    local approver="${4:-}"
    local ts
    ts=$(timestamp)

    # Update Stage field
    sed -i '' "s/| Stage | .* |/| Stage | ${stage} |/" "$file"

    # Update Last Updated field
    sed -i '' "s/| Last Updated | .* |/| Last Updated | ${ts} |/" "$file"

    # Update Approver if provided
    if [[ -n "$approver" ]]; then
        sed -i '' "s/| Approver | .* |/| Approver | ${approver} |/" "$file"
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

cmd_init() {
    log_info "Initializing plan folder structure..."

    mkdir -p "${PLANS_DIR}"/{drafts,active,completed,abandoned}

    # Create .gitkeep files to preserve empty directories
    for dir in drafts active completed abandoned; do
        touch "${PLANS_DIR}/${dir}/.gitkeep"
    done

    log_info "Created plan folders:"
    echo "  ${PLANS_DIR}/drafts/"
    echo "  ${PLANS_DIR}/active/"
    echo "  ${PLANS_DIR}/completed/"
    echo "  ${PLANS_DIR}/abandoned/"

    echo ""
    log_info "NEXT STEP: Import a plan from ~/.claude/plans:"
    echo -e "  ${GREEN}$SCRIPT_PATH import ~/.claude/plans/<plan-name>.md${NC}"
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

    if [[ ! -f "$source" ]]; then
        log_error "Source file not found: $source"
        exit 1
    fi

    # Convert source to absolute path
    source=$(to_absolute "$source")

    # Generate destination filename
    if [[ -z "$name" ]]; then
        name=$(basename "$source" .md)
    fi
    local dest
    dest=$(to_absolute "${PLANS_DIR}/drafts/$(datestamp)-${name}.md")

    # Copy the file
    cp "$source" "$dest"
    log_info "Copied to: $dest"

    # Add status header if missing
    add_status_header "$dest" "Claude"

    # Delete the original
    rm "$source"
    log_info "Deleted original: $source"

    # Cleanup any other files in ~/.claude/plans
    cleanup_claude_plans

    log_info "Import complete: $dest"

    # Show next step based on phase count
    local phase_count
    phase_count=$(count_phases "$dest")
    echo ""
    if [[ "$phase_count" -ge 2 ]]; then
        log_info "NEXT STEP: This is a multi-phase plan. Start Ralph Loop review:"
        echo -e "  ${GREEN}$SCRIPT_PATH ralph $dest${NC}"
    else
        log_info "NEXT STEP: This is a single-phase plan. Promote directly:"
        echo -e "  ${GREEN}$SCRIPT_PATH promote $dest --approver \"Your Name\"${NC}"
    fi
}

cmd_ralph() {
    local plan_file="${1:-}"
    local mark_complete=false

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mark-complete)
                mark_complete=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH ralph <plan-file> [--mark-complete]"
        exit 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    # Convert to absolute path for output messages
    plan_file=$(to_absolute "$plan_file")

    # Verify plan is in drafts
    if [[ "$plan_file" != *"/drafts/"* ]]; then
        log_error "Ralph Loop review only applies to plans in drafts/"
        exit 1
    fi

    local phase_count
    phase_count=$(count_phases "$plan_file")
    local plan_basename
    plan_basename=$(basename "$plan_file")

    if [[ "$mark_complete" == "true" ]]; then
        # Block AI from marking Ralph as complete
        verify_interactive_terminal

        # Mark Ralph Loop as completed
        update_ralph_status "$plan_file" "completed"
        update_status "$plan_file" "draft" "Ralph Loop review completed"
        log_info "Marked Ralph Loop review as completed for: $plan_file"

        echo ""
        log_info "NEXT STEP: Promote the plan to active:"
        echo -e "  ${GREEN}$SCRIPT_PATH promote $plan_file --approver \"Your Name\"${NC}"
    else
        # Show Ralph Loop command to run
        echo ""
        log_info "Plan: $plan_basename"
        log_info "Phases detected: $phase_count"

        if [[ "$phase_count" -lt 2 ]]; then
            log_warn "This is a single-phase plan. Ralph Loop review is NOT required."
            echo ""
            log_info "NEXT STEP: Promote the plan directly:"
            echo -e "  ${GREEN}$SCRIPT_PATH promote $plan_file --approver \"Your Name\"${NC}"
            return 0
        fi

        echo ""
        log_info "Multi-phase plan detected. Ralph Loop review is REQUIRED before promotion."
        echo ""
        log_info "STEP 1: Run this command in Claude Code to start Ralph Loop review:"
        echo ""
        echo -e "${GREEN}/ralph-loop:ralph-loop \"review ${plan_file} and look for areas to improve. iterate multiple times until there are no more improvements possible. <promise>DONEDONE</promise>\" --max-iterations 10 --completion-promise \"DONEDONE\"${NC}"
        echo ""
        log_info "STEP 2: After Ralph Loop completes, mark it done:"
        echo -e "  ${GREEN}$SCRIPT_PATH ralph $plan_file --mark-complete${NC}"
    fi
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
        echo ""
        log_error "Ralph Loop review has NOT been completed for this plan."
        echo ""
        echo "To start Ralph Loop review, run:"
        echo "  $SCRIPT_PATH ralph $plan_file"
        echo ""
        echo "After review completes, mark it done:"
        echo "  $SCRIPT_PATH ralph $plan_file --mark-complete"
        echo ""
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
    local dest
    dest=$(to_absolute "${PLANS_DIR}/active/${basename}")

    # Move file
    mv "$plan_file" "$dest"

    # Update status
    update_status "$dest" "active" "Approved by ${approver}, promoted to active" "$approver"

    # Cleanup claude plans
    cleanup_claude_plans

    log_info "Promoted to active: $dest"

    echo ""
    log_info "NEXT STEP: Mark as AI Developer Ready after reviewing for AI concerns:"
    echo -e "  ${GREEN}$SCRIPT_PATH ai-ready $dest --reviewer \"Your Name\"${NC}"
}

cmd_ai_ready() {
    # Block AI from running this command
    verify_interactive_terminal

    local plan_file="${1:-}"
    local reviewer=""
    local iteration=1

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reviewer) reviewer="$2"; shift 2 ;;
            --iteration) iteration="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Validation
    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH ai-ready <plan-file> --reviewer <name>"
        exit 1
    fi
    if [[ -z "$reviewer" ]]; then
        log_error "Reviewer required: --reviewer <name>"
        exit 1
    fi
    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    # Convert to absolute path for output messages
    plan_file=$(to_absolute "$plan_file")

    # Enforce active/ folder requirement
    if [[ "$plan_file" != *"/active/"* ]]; then
        log_error "Can only mark plans in active/ as AI Developer Ready"
        log_error "This plan is in: $(dirname "$plan_file")"
        echo ""
        log_error "Plans must be promoted to active/ before AI Developer Ready review."
        echo "Run: $SCRIPT_PATH promote <plan> --approver <name>"
        exit 1
    fi

    # Check if already approved
    if has_ai_ready_approval "$plan_file"; then
        log_warn "Plan is already marked AI Developer Ready"
        exit 0
    fi

    # Update Status Header
    update_ai_ready_status "$plan_file" "$reviewer" "$iteration"

    # Add approval stamp
    add_ai_ready_stamp "$plan_file" "$reviewer" "$(datestamp)" "$iteration"

    # Update progress log
    update_status "$plan_file" "active" "AI Developer Ready approved by ${reviewer} (iteration ${iteration})"

    echo ""
    log_info "Marked as AI Developer Ready: $plan_file"
    log_info "Reviewer: $reviewer"
    log_info "Iteration: $iteration (FINAL)"

    echo ""
    log_info "NEXT STEP: Request execution approval (AI runs this, then you approve in separate terminal):"
    echo -e "  ${GREEN}$SCRIPT_PATH execute $plan_file${NC}"
}

cmd_execute() {
    local plan_file="${1:-}"

    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH execute <plan-file>"
        exit 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    # Convert to absolute path for output messages
    plan_file=$(to_absolute "$plan_file")

    # Verify plan is in active/ folder
    if [[ "$plan_file" != *"/active/"* ]]; then
        log_error "Can only execute plans in active/ folder"
        log_error "This plan is not in active/: $plan_file"
        exit 1
    fi

    # Check AI Developer Ready approval (HARD REQUIREMENT)
    if ! has_ai_ready_approval "$plan_file"; then
        log_error "BLOCKED: Plan has not been marked AI Developer Ready."
        echo ""
        log_error "Before execution, a human must review this plan for AI implementation concerns."
        echo ""
        echo "To mark as AI Developer Ready, run:"
        echo -e "  ${GREEN}$SCRIPT_PATH ai-ready $plan_file --reviewer \"Your Name\"${NC}"
        echo ""
        echo "See: standards/enforcement/ai-developer-ready-checklist.md"
        exit 1
    fi

    # Check for existing valid approval
    local approval
    approval=$(find_valid_approval "$plan_file")

    if [[ -z "$approval" ]]; then
        # No approval - create request and block
        local request_id
        request_id=$(create_execution_request "$plan_file")

        log_error "BLOCKED: Execution requires human approval."
        echo ""
        log_info "STEP 1: A human must approve execution in a SEPARATE TERMINAL:"
        echo -e "  ${GREEN}$SCRIPT_PATH approve-execute ${request_id} --approver \"Your Name\"${NC}"
        echo ""
        log_info "STEP 2: Then retry this command:"
        echo -e "  ${GREEN}$SCRIPT_PATH execute $plan_file${NC}"
        echo ""
        log_warn "Approval expires in ${EXECUTION_EXPIRY_MINUTES} minutes."
        exit 1
    fi

    # Valid approval found - output tim-loop command
    update_execution_status "$plan_file" "$approval"
    update_status "$plan_file" "active" "Execution approved, starting tim-loop"

    echo ""
    log_info "Execution APPROVED!"
    echo ""
    log_info "STEP 1: Run this command in Claude Code to start implementation:"
    echo ""
    echo -e "${GREEN}/tim-loop \"implement ${plan_file}. you are not done until all iterations and phases of the plan are complete.\"${NC}"
    echo ""
    log_info "STEP 2: When tim-loop completes successfully, mark the plan as complete:"
    echo -e "  ${GREEN}$SCRIPT_PATH complete $plan_file${NC}"
}

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

    echo ""
    log_info "NEXT STEP: AI can now retry execute to get the tim-loop command:"
    echo -e "  ${GREEN}$SCRIPT_PATH execute $plan_file${NC}"
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
    local dest
    dest=$(to_absolute "${PLANS_DIR}/completed/${basename}")

    # Move file
    mv "$plan_file" "$dest"

    # Update status
    update_status "$dest" "completed" "All phases completed, verification passed"

    log_info "Completed: $dest"

    echo ""
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
    local dest
    dest=$(to_absolute "${PLANS_DIR}/abandoned/${basename}")

    # Move file
    mv "$plan_file" "$dest"

    # Update status
    update_status "$dest" "abandoned" "Abandoned: ${reason}"

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
    read -r -p "Delete these files? [y/N] " response
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

cmd_list() {
    local stage="${1:-all}"

    if [[ "$stage" == "all" ]]; then
        for s in drafts active completed abandoned; do
            echo "=== ${s} ==="
            if [[ -d "${PLANS_DIR}/$s" ]]; then
                local files
                files=$(find "${PLANS_DIR}/$s" -name "*.md" -type f 2>/dev/null | sort)
                if [[ -n "$files" ]]; then
                    echo "$files" | while read -r f; do
                        echo "  $(basename "$f")"
                    done
                else
                    echo "  (none)"
                fi
            else
                echo "  (folder not found)"
            fi
            echo ""
        done
    else
        if [[ -d "${PLANS_DIR}/$stage" ]]; then
            local files
            files=$(find "${PLANS_DIR}/$stage" -name "*.md" -type f 2>/dev/null | sort)
            if [[ -n "$files" ]]; then
                echo "$files" | while read -r f; do
                    echo "$(basename "$f")"
                done
            else
                echo "(none)"
            fi
        else
            log_error "Folder not found: ${PLANS_DIR}/$stage"
            exit 1
        fi
    fi
}

cmd_help() {
    cat << 'EOF'
plan-ops.sh - TIM Plan Lifecycle Management

USAGE:
    ./tools/plan-ops.sh <command> [arguments]

COMMANDS:
    init
        Initialize plan folder structure (drafts/active/completed/abandoned)

    import <source-file> [--name <description>]
        Import plan from ~/.claude/plans to drafts folder
        Automatically deletes original and cleans up ~/.claude/plans

    ralph <plan-file> [--mark-complete]
        Start or complete Ralph Loop review for a draft plan
        - Without flags: Shows the Ralph Loop command to run
        - With --mark-complete: Marks Ralph review as done (required before promote)
        Multi-phase plans (2+ phases) MUST complete Ralph Loop before promotion

    promote <plan-file> --approver <name>
        Move plan from drafts to active (requires human approver)
        BLOCKED for multi-phase plans until Ralph Loop review is completed

    ai-ready <plan-file> --reviewer <name> [--iteration <n>]
        Mark plan as AI Developer Ready after human review
        - Only works on active/ plans (must promote first)
        - Required before execute will succeed
        - Adds approval stamp to plan file
        See: standards/enforcement/ai-developer-ready-checklist.md

    execute <plan-file>
        Request execution approval for an active plan
        First call: Creates approval request, BLOCKS until approved
        After approval: Outputs tim-loop command to run

    approve-execute <request-id> --approver <name>
        Human approval for plan execution (run in SEPARATE TERMINAL)
        Required before execute will output the tim-loop command
        Approval expires after 15 minutes

    complete <plan-file>
        Move plan from active to completed

    abandon <plan-file> [--reason <reason>]
        Move plan to abandoned with optional reason

    cleanup-drafts [--older-than <N>d]
        Find and optionally delete drafts older than N days (default: 30)

    list [drafts|active|completed|abandoned|all]
        List plans by stage (default: all)

    help
        Show this help message

RALPH LOOP WORKFLOW:
    Multi-phase plans require Ralph Loop review before promotion:

    1. ./tools/plan-ops.sh ralph plans/drafts/my-plan.md
       (Shows the Ralph Loop command to run)

    2. Run the displayed /ralph-loop command in Claude Code

    3. ./tools/plan-ops.sh ralph plans/drafts/my-plan.md --mark-complete
       (Marks review as done)

    4. ./tools/plan-ops.sh promote plans/drafts/my-plan.md --approver "Name"
       (Now promotion is allowed)

EXECUTION WORKFLOW (HARD ENFORCED):
    Active plans require human approval before execution:

    1. AI runs: ./tools/plan-ops.sh execute plans/active/my-plan.md
       → BLOCKED, creates approval request, outputs request ID

    2. HUMAN runs in SEPARATE TERMINAL:
       ./tools/plan-ops.sh approve-execute <request-id> --approver "Name"

    3. AI retries: ./tools/plan-ops.sh execute plans/active/my-plan.md
       → Outputs /tim-loop command

    4. Run the /tim-loop command to execute the plan

    5. ./tools/plan-ops.sh complete plans/active/my-plan.md

EXAMPLES:
    ./tools/plan-ops.sh init
    ./tools/plan-ops.sh import ~/.claude/plans/xyz.md --name "feature-auth"
    ./tools/plan-ops.sh ralph plans/drafts/2025-01-16-feature-auth.md
    ./tools/plan-ops.sh ralph plans/drafts/2025-01-16-feature-auth.md --mark-complete
    ./tools/plan-ops.sh promote plans/drafts/2025-01-16-feature-auth.md --approver "Tim"
    ./tools/plan-ops.sh execute plans/active/2025-01-16-feature-auth.md
    ./tools/plan-ops.sh approve-execute abc123 --approver "Tim"
    ./tools/plan-ops.sh complete plans/active/2025-01-16-feature-auth.md
    ./tools/plan-ops.sh abandon plans/drafts/old-plan.md --reason "Requirements changed"
    ./tools/plan-ops.sh list active

ENVIRONMENT:
    PLANS_DIR   Override default plans directory (default: plans)

For full documentation, see: standards/operations/plan-management.md
EOF
}

# Main dispatch
case "${1:-help}" in
    init) cmd_init ;;
    import) cmd_import "${@:2}" ;;
    ralph) cmd_ralph "${@:2}" ;;
    promote) cmd_promote "${@:2}" ;;
    ai-ready) cmd_ai_ready "${@:2}" ;;
    execute) cmd_execute "${@:2}" ;;
    approve-execute) cmd_approve_execute "${@:2}" ;;
    complete) cmd_complete "${@:2}" ;;
    abandon) cmd_abandon "${@:2}" ;;
    cleanup-drafts) cmd_cleanup_drafts "${@:2}" ;;
    list) cmd_list "${@:2}" ;;
    help|--help|-h) cmd_help ;;
    *)
        log_error "Unknown command: $1"
        echo "Run '$SCRIPT_PATH help' for usage."
        exit 1
        ;;
esac
