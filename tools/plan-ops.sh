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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

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

# Update Ralph Review fields in Status Header
update_ralph_status() {
    local file="$1"
    local status="$2"  # required / completed / not-required
    local ts
    ts=$(timestamp)

    # Update Ralph Review field
    if grep -q "| Ralph Review |" "$file"; then
        sed -i '' "s/| Ralph Review | .* |/| Ralph Review | ${status} |/" "$file"
    fi

    # Update Ralph Date field
    if grep -q "| Ralph Date |" "$file"; then
        if [[ "$status" == "completed" ]]; then
            sed -i '' "s/| Ralph Date | .* |/| Ralph Date | $(datestamp) |/" "$file"
        else
            sed -i '' "s/| Ralph Date | .* |/| Ralph Date | - |/" "$file"
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
        log_error "Usage: plan-ops.sh import <source-file> [--name <description>]"
        exit 1
    fi

    if [[ ! -f "$source" ]]; then
        log_error "Source file not found: $source"
        exit 1
    fi

    # Generate destination filename
    if [[ -z "$name" ]]; then
        name=$(basename "$source" .md)
    fi
    local dest="${PLANS_DIR}/drafts/$(datestamp)-${name}.md"

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
        log_error "Usage: plan-ops.sh ralph <plan-file> [--mark-complete]"
        exit 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

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
        # Mark Ralph Loop as completed
        update_ralph_status "$plan_file" "completed"
        update_status "$plan_file" "draft" "Ralph Loop review completed"
        log_info "Marked Ralph Loop review as completed for: $plan_file"
        log_info "Plan can now be promoted with: ./tools/plan-ops.sh promote $plan_file --approver <name>"
    else
        # Show Ralph Loop command to run
        echo ""
        log_info "Plan: $plan_basename"
        log_info "Phases detected: $phase_count"

        if [[ "$phase_count" -lt 2 ]]; then
            log_warn "This is a single-phase plan. Ralph Loop review is NOT required."
            log_info "You can promote directly with: ./tools/plan-ops.sh promote $plan_file --approver <name>"
            return 0
        fi

        echo ""
        log_info "Multi-phase plan detected. Ralph Loop review is REQUIRED before promotion."
        echo ""
        echo "Run this command to start Ralph Loop review:"
        echo ""
        echo -e "${GREEN}/ralph-loop:ralph-loop \"review ${plan_file} and look for areas to improve. iterate multiple times until there are no more improvements possible. <promise>DONEDONE</promise>\" --max-iterations 10 --completion-promise \"DONEDONE\"${NC}"
        echo ""
        log_info "After Ralph Loop completes, mark it done with:"
        echo "  ./tools/plan-ops.sh ralph $plan_file --mark-complete"
    fi
}

cmd_promote() {
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
        log_error "Usage: plan-ops.sh promote <plan-file> --approver <name>"
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
        echo "  ./tools/plan-ops.sh ralph $plan_file"
        echo ""
        echo "After review completes, mark it done:"
        echo "  ./tools/plan-ops.sh ralph $plan_file --mark-complete"
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
    local dest="${PLANS_DIR}/active/${basename}"

    # Move file
    mv "$plan_file" "$dest"

    # Update status
    update_status "$dest" "active" "Approved by ${approver}, promoted to active" "$approver"

    # Cleanup claude plans
    cleanup_claude_plans

    log_info "Promoted to active: $dest"
}

cmd_execute() {
    local plan_file="${1:-}"

    if [[ -z "$plan_file" ]]; then
        log_error "Usage: plan-ops.sh execute <plan-file>"
        exit 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    # Verify plan is in active/ folder
    if [[ "$plan_file" != *"/active/"* ]]; then
        log_error "Can only execute plans in active/ folder"
        log_error "This plan is not in active/: $plan_file"
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
        echo "A human must approve execution in a SEPARATE TERMINAL:"
        echo ""
        echo -e "  ${GREEN}./tools/plan-ops.sh approve-execute ${request_id} --approver \"Your Name\"${NC}"
        echo ""
        echo "Then retry this command:"
        echo "  ./tools/plan-ops.sh execute $plan_file"
        echo ""
        log_warn "Approval expires in ${EXECUTION_EXPIRY_MINUTES} minutes."
        exit 1
    fi

    # Valid approval found - output tim-loop command
    update_execution_status "$plan_file" "$approval"
    update_status "$plan_file" "active" "Execution approved, starting tim-loop"

    echo ""
    log_info "Execution APPROVED. Run this command to start:"
    echo ""
    echo -e "${GREEN}/tim-loop \"implement ${plan_file}. you are not done until all iterations and phases of the plan are complete.\"${NC}"
    echo ""
    log_info "When complete, run: ./tools/plan-ops.sh complete $plan_file"
}

cmd_approve_execute() {
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
        log_error "Usage: plan-ops.sh approve-execute <request-id> --approver <name>"
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
        log_error "AI must create a new request with: ./tools/plan-ops.sh execute <plan>"
        exit 1
    fi

    # Get plan file for display
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
    log_info "AI can now retry: ./tools/plan-ops.sh execute $plan_file"
}

cmd_complete() {
    local plan_file="${1:-}"

    if [[ -z "$plan_file" ]]; then
        log_error "Usage: plan-ops.sh complete <plan-file>"
        exit 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    local basename
    basename=$(basename "$plan_file")
    local dest="${PLANS_DIR}/completed/${basename}"

    # Move file
    mv "$plan_file" "$dest"

    # Update status
    update_status "$dest" "completed" "All phases completed, verification passed"

    log_info "Completed: $dest"
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
        log_error "Usage: plan-ops.sh abandon <plan-file> [--reason <reason>]"
        exit 1
    fi

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    local basename
    basename=$(basename "$plan_file")
    local dest="${PLANS_DIR}/abandoned/${basename}"

    # Move file
    mv "$plan_file" "$dest"

    # Update status
    update_status "$dest" "abandoned" "Abandoned: ${reason}"

    log_info "Abandoned: $dest"
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
    execute) cmd_execute "${@:2}" ;;
    approve-execute) cmd_approve_execute "${@:2}" ;;
    complete) cmd_complete "${@:2}" ;;
    abandon) cmd_abandon "${@:2}" ;;
    cleanup-drafts) cmd_cleanup_drafts "${@:2}" ;;
    list) cmd_list "${@:2}" ;;
    help|--help|-h) cmd_help ;;
    *)
        log_error "Unknown command: $1"
        echo "Run './tools/plan-ops.sh help' for usage."
        exit 1
        ;;
esac
