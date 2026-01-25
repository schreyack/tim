#!/usr/bin/env bash
set -euo pipefail

# plan-ops.sh - TIM Plan Lifecycle Management
# Usage: $SCRIPT_PATH <command> [args]
#
# Commands:
#   init              Initialize plan folder structure
#   import            Import plan from ~/.claude/plans to drafts
#   ralph             Start Ralph Loop review for a draft plan
#   promote           Move plan from drafts to active
#   execute           Request execution approval for active plan
#   approve-execute   Human approval for plan execution
#   fast-track        Skip workflow and go directly to implementation
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
# Resolve design_standards root directory (parent of tools/)
DESIGN_STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Global for tracking plan file path (updated by wizard steps after moves)
WIZARD_PLAN_FILE=""

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

# Extract the plans directory from a plan file's absolute path.
# Input:  /path/to/project/plans/active/my-plan.md
# Output: /path/to/project/plans
# Falls back to PLANS_DIR if pattern doesn't match.
get_plans_dir_from_path() {
    local path="$1"
    # Match paths like .../plans/stage/filename.md where stage is drafts/active/completed/abandoned
    if [[ "$path" =~ ^(.*/plans)/(drafts|active|completed|abandoned)/[^/]+$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        # Fallback to local PLANS_DIR
        to_absolute "$PLANS_DIR"
    fi
}

# Find plan files matching a name pattern
# Searches: current project's plans/, ~/.claude/plans/
# Returns: newline-separated list of matching absolute paths
find_plans_by_name() {
    local pattern="$1"
    local results=()

    # Add .md extension if not present
    [[ "$pattern" != *.md ]] && pattern="${pattern}.md"

    # Search in current project's plans directory (all stages)
    if [[ -d "$PLANS_DIR" ]]; then
        local abs_plans_dir
        abs_plans_dir=$(to_absolute "$PLANS_DIR")
        for stage in drafts active completed abandoned; do
            if [[ -d "${abs_plans_dir}/${stage}" ]]; then
                while IFS= read -r -d '' file; do
                    results+=("$file")
                done < <(find "${abs_plans_dir}/${stage}" -maxdepth 1 -name "*${pattern}" -type f -print0 2>/dev/null)
            fi
        done
    fi

    # Search in ~/.claude/plans/
    if [[ -d "$CLAUDE_PLANS_DIR" ]]; then
        while IFS= read -r -d '' file; do
            results+=("$file")
        done < <(find "$CLAUDE_PLANS_DIR" -maxdepth 1 -name "*${pattern}" -type f -print0 2>/dev/null)
    fi

    # Output results
    printf '%s\n' "${results[@]}"
}

# Resolve a plan argument to an absolute path
# If it's a path and exists, use it directly
# If it's a path but doesn't exist, extract filename and search
# If it's just a name, search for it and handle duplicates
resolve_plan_path() {
    local arg="$1"
    local search_name=""

    # If it looks like a path
    if [[ "$arg" == */* ]]; then
        local abs_path
        abs_path=$(to_absolute "$arg")

        # If file exists at this path, use it
        if [[ -f "$abs_path" ]]; then
            echo "$abs_path"
            return 0
        fi

        # File doesn't exist at given path - extract filename and search
        search_name=$(basename "$arg" .md)
        log_warn "File not found at: $arg"
        log_info "Searching for plan by name: $search_name"
    else
        search_name="$arg"
    fi

    # Search for plans matching the name
    local matches
    matches=$(find_plans_by_name "$search_name")

    if [[ -z "$matches" ]]; then
        log_error "No plan found matching: $arg"
        log_info "Searched in: $PLANS_DIR/*, $CLAUDE_PLANS_DIR"
        return 1
    fi

    # Count matches
    local count
    count=$(echo "$matches" | grep -c .)

    if [[ "$count" -eq 1 ]]; then
        echo "$matches"
        return 0
    fi

    # Multiple matches - let user choose
    log_warn "Multiple plans found matching '$arg':"
    echo ""
    local i=1
    local options=()
    while IFS= read -r match; do
        # Show relative path from home or absolute
        local display_path="${match/#$HOME/~}"
        echo "  [$i] $display_path"
        options+=("$match")
        ((i++))
    done <<< "$matches"
    echo ""

    local choice
    while true; do
        echo -n "Select plan [1-$count]: "
        read -r choice </dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$count" ]]; then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        echo "Invalid choice. Enter a number between 1 and $count."
    done
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

# Insert a line after a pattern in a file (more reliable than sed -a on macOS)
# Usage: insert_line_after "pattern" "new line content" "file"
# Note: Uses literal string matching (not regex) to handle pipes in markdown tables
insert_line_after() {
    local pattern="$1"
    local new_line="$2"
    local file="$3"
    awk -v pat="$pattern" -v line="$new_line" '
        { print }
        index($0, pat) && !done { print line; done=1 }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
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
# Adds fields if they don't exist
update_ai_ready_status() {
    local file="$1"
    local reviewer="$2"
    local iteration="${3:-1}"  # Default to iteration 1
    local ts date
    ts=$(timestamp)
    date=$(datestamp)

    # Find the best anchor field (last existing field before AI Developer Ready section)
    local anchor=""
    for candidate in "Execution Started" "Execution Approved By" "Execution Approved" "Ralph Date" "Ralph Review" "Approver"; do
        if grep -q "| ${candidate} |" "$file"; then
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
        if grep -q "| ${field} |" "$file"; then
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

    # Find the best anchor field
    local anchor=""
    for candidate in "AI Developer Ready Iteration" "AI Developer Ready Date" "AI Developer Ready By" "AI Developer Ready" "Execution Started" "Ralph Date" "Approver"; do
        if grep -q "| ${candidate} |" "$file"; then
            anchor="$candidate"
            break
        fi
    done

    if [[ -z "$anchor" ]]; then
        log_error "Cannot find anchor field in Status Header to add Implementation Verification fields"
        return 1
    fi

    # Helper to add or update a field
    _add_or_update_field() {
        local field="$1"
        local value="$2"
        local anchor_field="$3"
        local target_file="$4"
        if grep -q "| ${field} |" "$target_file"; then
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
        # Update existing field (pattern handles variable whitespace)
        sed -i '' "s/| Ralph Review[[:space:]]*|[^|]*|/| Ralph Review | ${status} |/" "$file"
    else
        # Add Ralph Review field after Approver row
        if grep -q "| Approver |" "$file"; then
            insert_line_after "| Approver |" "| Ralph Review | ${status} |" "$file"
            log_warn "Added missing Ralph Review field to Status Header"
        else
            log_error "Cannot find Approver row to insert Ralph Review field"
            return 1
        fi
    fi

    # Check if Ralph Date field exists
    if grep -q "| Ralph Date |" "$file"; then
        # Update existing field (pattern handles variable whitespace)
        sed -i '' "s/| Ralph Date[[:space:]]*|[^|]*|/| Ralph Date | ${date_val} |/" "$file"
    else
        # Add Ralph Date field after Ralph Review row
        if grep -q "| Ralph Review |" "$file"; then
            insert_line_after "| Ralph Review |" "| Ralph Date | ${date_val} |" "$file"
            log_warn "Added missing Ralph Date field to Status Header"
        fi
    fi

    # Update Last Updated
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$file"
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

# Strip ANSI color/formatting codes from string
# Usage: clean_text=$(strip_ansi "$colored_text")
strip_ansi() {
    # Remove color codes (\e[...m), bold, underline, etc.
    echo "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

# Check and configure tim-loop permissions in Claude Code settings
# Ensures the project has the necessary permissions to run /tim-loop
ensure_tim_loop_permissions() {
    local project_dir="${1:-.}"
    local settings_file="${project_dir}/.claude/settings.local.json"
    local required_permission='Bash(~/.claude/commands/scripts/*)'

    # Check if .claude directory exists
    if [[ ! -d "${project_dir}/.claude" ]]; then
        mkdir -p "${project_dir}/.claude"
        log_info "Created ${project_dir}/.claude directory"
    fi

    # Check if settings file exists
    if [[ ! -f "$settings_file" ]]; then
        # Create minimal settings file with tim-loop permissions
        cat > "$settings_file" << 'EOF'
{
  "permissions": {
    "allow": [
      "Skill(tim-loop)",
      "Bash(~/.claude/commands/scripts/*)",
      "Bash(\"$HOME/.claude/commands/scripts/tim-loop-setup.sh\":*)"
    ]
  }
}
EOF
        log_info "Created $settings_file with tim-loop permissions"
        return 0
    fi

    # Check if tim-loop bash permission already exists (check for either pattern)
    if grep -q 'Bash(~/.claude/commands/scripts/\*)' "$settings_file" 2>/dev/null || \
       grep -q 'Bash("\$HOME/.claude/commands/scripts/tim-loop-setup.sh"' "$settings_file" 2>/dev/null; then
        return 0  # Already configured
    fi

    # Permission not found - offer to add it
    echo ""
    log_warn "Tim-loop permissions not found in project settings."
    echo ""
    echo "The /tim-loop command requires this permission in .claude/settings.local.json:"
    echo -e "  ${GREEN}\"Bash(~/.claude/commands/scripts/*)\"${NC}"
    echo ""
    echo -n "Add this permission automatically? [Y/n] "
    read -r response </dev/tty

    if [[ ! "$response" =~ ^[Nn] ]]; then
        # Add permission using python for reliable JSON manipulation
        if command -v python3 &>/dev/null; then
            python3 << PYTHON_EOF
import json
import sys

settings_file = "$settings_file"
try:
    with open(settings_file, 'r') as f:
        data = json.load(f)
except:
    data = {}

# Ensure permissions.allow exists
if 'permissions' not in data:
    data['permissions'] = {}
if 'allow' not in data['permissions']:
    data['permissions']['allow'] = []

# Add required permissions if not present
required = [
    'Skill(tim-loop)',
    'Bash(~/.claude/commands/scripts/*)',
    'Bash("$HOME/.claude/commands/scripts/tim-loop-setup.sh":*)'
]
for perm in required:
    if perm not in data['permissions']['allow']:
        data['permissions']['allow'].insert(0, perm)

with open(settings_file, 'w') as f:
    json.dump(data, f, indent=2)

print("OK")
PYTHON_EOF
            log_info "Added tim-loop permissions to $settings_file"
            echo ""
            log_warn "IMPORTANT: Restart Claude Code for the new permissions to take effect."
            echo -n "Press Enter after restarting Claude Code..."
            read -r </dev/tty
        else
            log_error "python3 not found. Please add the permission manually."
            echo ""
            echo "Add this to .claude/settings.local.json in the permissions.allow array:"
            echo -e "  ${GREEN}\"Bash(~/.claude/commands/scripts/*)\"${NC}"
            echo ""
            echo -n "Press Enter when done..."
            read -r </dev/tty
        fi
    else
        echo ""
        log_warn "Skipped. /tim-loop may fail without this permission."
        echo ""
        echo "To add manually, edit .claude/settings.local.json and add to permissions.allow:"
        echo -e "  ${GREEN}\"Bash(~/.claude/commands/scripts/*)\"${NC}"
        echo ""
        echo -n "Press Enter to continue anyway..."
        read -r </dev/tty
    fi
}

# =============================================================================
# WIZARD COMMAND AND STEP FUNCTIONS
# =============================================================================

cmd_wizard() {
    local plan_file="${1:-}"
    local status_only=false

    # Parse --status flag
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status) status_only=true; shift ;;
            *) shift ;;
        esac
    done

    # Validation
    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH wizard <plan-name-or-path> [--status]"
        log_info "Examples:"
        log_info "  $SCRIPT_PATH wizard new-ui-front-page"
        log_info "  $SCRIPT_PATH wizard ~/.claude/plans/my-plan.md"
        exit 1
    fi

    # Resolve plan name or path to absolute path
    WIZARD_PLAN_FILE=$(resolve_plan_path "$plan_file") || exit 1

    # Get current state
    local state
    state=$(get_plan_state "$WIZARD_PLAN_FILE")

    # Status-only mode - show status and exit without entering interactive wizard
    if [[ "$status_only" == "true" ]]; then
        show_plan_status "$WIZARD_PLAN_FILE" "$state"
        exit 0
    fi

    # Ctrl+C handler for graceful exit
    trap 'echo ""; log_warn "Wizard cancelled. Run again to resume."; exit 1' INT

    # Header
    echo ""
    echo "=== Plan Wizard ==="
    echo "Plan: $WIZARD_PLAN_FILE"

    # Main wizard loop - continues until plan is completed
    while [[ "$state" != "done" ]]; do
        case "$state" in
            import)          wizard_step_import ;;
            ralph)           wizard_step_ralph ;;
            promote)         wizard_step_promote ;;
            ai-ready)        wizard_step_ai_ready ;;
            execute-request) wizard_step_execute_request ;;
            execute-approve) wizard_step_execute_approve ;;
            tim-loop)        wizard_step_tim_loop ;;
            complete)        wizard_step_complete ;;
            not-found)
                log_error "Plan file not found: $WIZARD_PLAN_FILE"
                exit 1
                ;;
            abandoned)
                log_warn "Plan was abandoned. Cannot continue."
                exit 0
                ;;
            unknown)
                # Try to add Status Header for files in plans/ folder
                if [[ "$WIZARD_PLAN_FILE" == *"/plans/"* ]]; then
                    log_info "Adding Status Header to plan..."
                    add_status_header "$WIZARD_PLAN_FILE" "Unknown"
                    ensure_status_header_fields "$WIZARD_PLAN_FILE"
                    local new_state
                    new_state=$(get_plan_state "$WIZARD_PLAN_FILE")
                    if [[ "$new_state" == "unknown" ]]; then
                        log_error "Plan has Status Header but Stage field is invalid or missing."
                        log_error "Please check the Status Header in: $WIZARD_PLAN_FILE"
                        exit 1
                    fi
                    state="$new_state"
                    continue
                else
                    log_error "Plan has no Status Header and is not in plans/ folder"
                    exit 1
                fi
                ;;
        esac

        # Refresh state after each step (path may have changed due to move)
        state=$(get_plan_state "$WIZARD_PLAN_FILE")
    done

    # Success - plan reached completed state
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✓ Plan lifecycle complete!${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

wizard_step_import() {
    print_step_header "import" "Import plan to drafts folder"

    local name
    echo -n "Enter a short name for this plan (press Enter for default): "
    read -r name </dev/tty
    [[ -z "$name" ]] && name=$(basename "$WIZARD_PLAN_FILE" .md)

    echo ""
    echo "Importing plan..."

    # Call existing import command and capture output
    local output
    output=$(cmd_import "$WIZARD_PLAN_FILE" --name "$name" 2>&1) || true
    echo "$output"

    # Extract new path from output (strip ANSI codes first)
    local clean_output new_path
    clean_output=$(strip_ansi "$output")
    new_path=$(echo "$clean_output" | grep "Copied to:" | sed 's/.*Copied to: //' | xargs)
    if [[ -n "$new_path" && -f "$new_path" ]]; then
        WIZARD_PLAN_FILE="$new_path"
        log_info "Updated path: $WIZARD_PLAN_FILE"
    fi
}

wizard_step_ralph() {
    print_step_header "ralph" "Ralph Loop Review (multi-phase plan)"

    # Ensure Ralph Review field exists and is set to "required"
    if ! grep -q "| Ralph Review | required |" "$WIZARD_PLAN_FILE"; then
        update_ralph_status "$WIZARD_PLAN_FILE" "required"
    fi

    echo ""
    echo "Run this command in Claude Code:"
    local cmd="/ralph-loop:ralph-loop \"review $WIZARD_PLAN_FILE and look for areas to improve. iterate multiple times until there are no more improvements possible. <promise>DONEDONE</promise>\" --max-iterations 10 --completion-promise \"DONEDONE\""
    show_command "$cmd"
    echo -n "Press Enter when Ralph Loop completes..."
    read -r </dev/tty

    echo ""
    echo "Marking Ralph Loop complete..."

    # cmd_ralph --mark-complete calls verify_interactive_terminal, which will pass
    # since wizard runs interactively
    cmd_ralph "$WIZARD_PLAN_FILE" --mark-complete
}

wizard_step_promote() {
    print_step_header "promote" "Promote to active"

    local name
    name=$(prompt_for_name "Enter approver name")

    echo ""
    echo "Promoting plan..."

    # cmd_promote calls verify_interactive_terminal, which will pass since wizard runs interactively
    cmd_promote "$WIZARD_PLAN_FILE" --approver "$name"

    # Update path after move (drafts -> active)
    local basename
    basename=$(basename "$WIZARD_PLAN_FILE")
    local plans_dir
    plans_dir=$(get_plans_dir_from_path "$WIZARD_PLAN_FILE")
    local new_path="${plans_dir}/active/${basename}"
    if [[ -f "$new_path" ]]; then
        WIZARD_PLAN_FILE="$new_path"
        log_info "Updated path: $WIZARD_PLAN_FILE"
    fi
}

wizard_step_ai_ready() {
    print_step_header "ai-ready" "AI Developer Ready Review"

    # Check if already approved - skip step if so
    if has_ai_ready_approval "$WIZARD_PLAN_FILE"; then
        log_info "Plan is already marked AI Developer Ready. Continuing..."
        return 0
    fi

    echo ""
    echo "Run this command in Claude Code to review for AI implementation concerns:"
    local checklist="${DESIGN_STANDARDS_DIR}/standards/enforcement/ai-developer-ready-checklist.md"
    local cmd="/ralph-loop:ralph-loop \"review $WIZARD_PLAN_FILE for AI implementation concerns using ${checklist}. Verify: (1) instructions are unambiguous (AI has one interpretation), (2) no hallucination opportunities (referenced APIs/files exist), (3) guard rails are explicit (error handling specified), (4) verification criteria are code-checkable. <promise>AI-READY</promise>\" --max-iterations 5 --completion-promise \"AI-READY\""
    show_command "$cmd"
    echo -n "Press Enter when Ralph Loop completes..."
    read -r </dev/tty

    echo ""
    echo "Marking as AI Developer Ready..."
    local name
    name=$(prompt_for_name "Enter reviewer name")

    # Use helper directly to avoid cmd_ai_ready's exit calls
    if ! update_ai_ready_status "$WIZARD_PLAN_FILE" "$name"; then
        log_error "Failed to update AI Developer Ready status"
        return 1
    fi
    if ! update_status "$WIZARD_PLAN_FILE" "active" "AI Developer Ready approved by ${name}"; then
        log_error "Failed to update progress log"
        return 1
    fi
    log_info "AI Developer Ready approval recorded."
}

wizard_step_execute_request() {
    print_step_header "execute" "Execution Approval"

    echo "Creating execution request..."

    # Use helper function directly (don't call cmd_execute which exits)
    local request_id
    request_id=$(create_execution_request "$WIZARD_PLAN_FILE")

    echo ""
    echo "Request ID: $request_id"
    echo ""
    echo "Run this command in a SEPARATE TERMINAL to approve:"
    local cmd="$SCRIPT_PATH approve-execute $request_id --approver \"Your Name\""
    show_command "$cmd"
    echo -n "Press Enter when approved..."
    read -r </dev/tty

    # Verify approval succeeded before continuing
    local approval
    approval=$(find_valid_approval "$WIZARD_PLAN_FILE")
    if [[ -z "$approval" ]]; then
        log_error "Approval not found or expired. Please approve and try again."
        # Don't exit - let the wizard loop retry (state will still be execute-request or execute-approve)
        return
    fi

    # Update execution status in plan
    if ! update_execution_status "$WIZARD_PLAN_FILE" "$approval"; then
        log_error "Failed to update execution status"
        return
    fi
    if ! update_status "$WIZARD_PLAN_FILE" "active" "Execution approved, starting tim-loop"; then
        log_error "Failed to update progress log"
        return
    fi
    log_info "Execution APPROVED!"
}

wizard_step_execute_approve() {
    print_step_header "execute" "Execution Approval (pending request found)"

    # Find the pending request
    local request_file
    request_file=$(find_pending_request "$WIZARD_PLAN_FILE")
    local request_id
    request_id=$(basename "$request_file" .json)

    echo ""
    echo "Found pending approval request: $request_id"
    echo ""
    echo "Run this command in a SEPARATE TERMINAL to approve:"
    local cmd="$SCRIPT_PATH approve-execute $request_id --approver \"Your Name\""
    show_command "$cmd"
    echo -n "Press Enter when approved..."
    read -r </dev/tty

    # Verify approval
    local approval
    approval=$(find_valid_approval "$WIZARD_PLAN_FILE")
    if [[ -z "$approval" ]]; then
        log_error "Approval not found or expired. Please approve and try again."
        # Don't exit - let the wizard loop retry
        return
    fi

    if ! update_execution_status "$WIZARD_PLAN_FILE" "$approval"; then
        log_error "Failed to update execution status"
        return
    fi
    if ! update_status "$WIZARD_PLAN_FILE" "active" "Execution approved, starting tim-loop"; then
        log_error "Failed to update progress log"
        return
    fi
    log_info "Execution APPROVED!"
}

wizard_step_tim_loop() {
    print_step_header "tim-loop" "Run Tim Loop Implementation"

    # Determine project directory from plan file path
    # Go up from plans/active/ to find project root
    local project_dir
    project_dir=$(dirname "$(dirname "$(dirname "$WIZARD_PLAN_FILE")")")

    # Ensure tim-loop permissions are configured
    ensure_tim_loop_permissions "$project_dir"

    echo ""
    echo "Run this command in Claude Code:"
    local cmd="/tim-loop \"implement $WIZARD_PLAN_FILE.

REQUIREMENTS:
- Complete ALL iterations and phases of the plan
- ALL code MUST be TIM Project compliant:
  * Type safety: mypy --strict (Python) or tsc --strict (TypeScript)
  * Test coverage: 90% minimum with meaningful tests
  * No TODOs, placeholders, or NotImplementedError
  * No secrets in code
  * File size: 400 lines max, function size: 50 lines max
  * Use shared libraries (tim-lib / @tim/lib) for common patterns
  * Follow TIM coding standards (see CLAUDE.md)

You are NOT DONE until all phases complete AND code is TIM-compliant.\""
    show_command "$cmd"
    echo -n "Press Enter when Tim Loop completes..."
    read -r </dev/tty

    echo ""
    echo "Did Tim Loop complete successfully? (y/n)"
    echo -n "> "
    read -r response </dev/tty

    if [[ "$response" =~ ^[Yy] ]]; then
        # Mark implementation as verified so state transitions to 'complete'
        local reviewer
        reviewer=$(prompt_for_name "Enter verifier name")
        if ! update_verification_status "$WIZARD_PLAN_FILE" "$reviewer"; then
            log_error "Failed to update verification status"
            exit 1
        fi
        if ! update_status "$WIZARD_PLAN_FILE" "active" "Implementation verified by ${reviewer}"; then
            log_error "Failed to update progress log"
            exit 1
        fi
        log_info "Implementation marked as verified."
    else
        log_warn "Tim Loop not completed. Run the wizard again when ready."
        exit 0
    fi
}

wizard_step_complete() {
    print_step_header "complete" "Mark plan complete"

    # Optional verification tim-loop step
    echo ""
    echo "Before marking complete, you can optionally run a verification tim-loop."
    echo "This will:"
    echo "  - Review the original intent of the plan"
    echo "  - Check if it was actually implemented"
    echo "  - Verify TIM Project rules were followed"
    echo "  - Create remediation plans if gaps are found"
    echo "  - Iterate until fully complete (no stubs, no deferred work)"
    echo ""
    echo -n "Run verification tim-loop? [y/N] "
    read -r run_verification </dev/tty

    if [[ "$run_verification" =~ ^[Yy] ]]; then
        # Determine project directory from plan file path
        local project_dir
        project_dir=$(dirname "$(dirname "$(dirname "$WIZARD_PLAN_FILE")")")

        # Ensure tim-loop permissions are configured
        ensure_tim_loop_permissions "$project_dir"

        echo ""
        echo "Run this command in Claude Code:"
        local cmd="/tim-loop \"VERIFICATION AUDIT for $WIZARD_PLAN_FILE

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
1. Create a detailed remediation plan
2. Implement the fixes
3. Repeat verification

CRITICAL: You are NOT DONE until:
- 100% of original intent is implemented
- All code is functional (not stubbed)
- All TIM rules pass
- No deferred/TODO items remain

Iterate with NO LIMIT until this is achieved.\""
        show_command "$cmd"
        echo -n "Press Enter when verification tim-loop completes..."
        read -r </dev/tty

        echo ""
        echo "Did the verification tim-loop complete successfully with all checks passing? (y/n)"
        echo -n "> "
        read -r verification_passed </dev/tty

        if [[ ! "$verification_passed" =~ ^[Yy] ]]; then
            log_warn "Verification not passed. Run the wizard again when remediation is complete."
            exit 0
        fi

        log_info "Verification passed!"
    fi

    echo ""
    echo "Marking plan complete..."

    # cmd_complete moves the file and updates status
    cmd_complete "$WIZARD_PLAN_FILE"

    # Update path after move (active -> completed)
    local basename
    basename=$(basename "$WIZARD_PLAN_FILE")
    local plans_dir
    plans_dir=$(get_plans_dir_from_path "$WIZARD_PLAN_FILE")
    local new_path="${plans_dir}/completed/${basename}"
    if [[ -f "$new_path" ]]; then
        WIZARD_PLAN_FILE="$new_path"
    fi
}

# =============================================================================
# END WIZARD FUNCTIONS
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

    # Find the best anchor field
    local anchor=""
    for candidate in "Ralph Date" "Ralph Review" "Approver"; do
        if grep -q "| ${candidate} |" "$plan_file"; then
            anchor="$candidate"
            break
        fi
    done

    if [[ -z "$anchor" ]]; then
        log_error "Cannot find anchor field in Status Header to add Execution fields"
        return 1
    fi

    # Helper to add or update a field
    _add_or_update_exec_field() {
        local field="$1"
        local value="$2"
        local anchor_field="$3"
        local target_file="$4"
        if grep -q "| ${field} |" "$target_file"; then
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

# Update the Status Header in a plan file
# Returns 1 if required fields are missing
update_status() {
    local file="$1"
    local stage="$2"
    local event="$3"
    local approver="${4:-}"
    local ts
    ts=$(timestamp)

    # Verify required fields exist
    if ! grep -q "| Stage |" "$file"; then
        log_error "Status Header missing required 'Stage' field in: $file"
        return 1
    fi
    if ! grep -q "| Last Updated |" "$file"; then
        log_error "Status Header missing required 'Last Updated' field in: $file"
        return 1
    fi

    # Update Stage field (pattern handles variable whitespace in markdown tables)
    sed -i '' "s/| Stage[[:space:]]*|[^|]*|/| Stage | ${stage} |/" "$file"

    # Update Last Updated field
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$file"

    # Update Approver if provided
    if [[ -n "$approver" ]]; then
        if grep -q "| Approver |" "$file"; then
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

        # Check if field exists
        if ! grep -q "| ${field_name} |" "$file"; then
            # Add field after anchor
            if grep -q "| ${anchor_field} |" "$file"; then
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
        if ! update_ralph_status "$plan_file" "completed"; then
            log_error "Failed to update Ralph status"
            exit 1
        fi
        if ! update_status "$plan_file" "draft" "Ralph Loop review completed"; then
            log_error "Failed to update progress log"
            exit 1
        fi
        log_info "Marked Ralph Loop review as completed for: $plan_file"

        log_info "NEXT STEP: Promote the plan to active:"
        show_command "$SCRIPT_PATH promote $plan_file --approver \"Your Name\""
    else
        # Show Ralph Loop command to run
        echo ""
        log_info "Plan: $plan_basename"
        log_info "Phases detected: $phase_count"

        if [[ "$phase_count" -lt 2 ]]; then
            log_warn "This is a single-phase plan. Ralph Loop review is NOT required."
            log_info "NEXT STEP: Promote the plan directly:"
            show_command "$SCRIPT_PATH promote $plan_file --approver \"Your Name\""
            return 0
        fi

        echo ""
        log_info "Multi-phase plan detected. Ralph Loop review is REQUIRED before promotion."
        echo ""
        log_info "STEP 1 of 2: Run this command in Claude Code to start Ralph Loop review:"
        show_command "/ralph-loop:ralph-loop \"review ${plan_file} and look for areas to improve. iterate multiple times until there are no more improvements possible. <promise>DONEDONE</promise>\" --max-iterations 10 --completion-promise \"DONEDONE\""
        log_info "STEP 2 of 2: After Ralph Loop completes, mark it done:"
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
        log_info "NEXT STEP: Continue with the wizard to request execution approval:"
        show_command "$SCRIPT_PATH wizard $plan_file"
        exit 0
    fi

    # Update Status Header
    if ! update_ai_ready_status "$plan_file" "$reviewer" "$iteration"; then
        log_error "Failed to update AI Developer Ready status"
        exit 1
    fi

    # Add approval stamp
    add_ai_ready_stamp "$plan_file" "$reviewer" "$(datestamp)" "$iteration"

    # Update progress log
    if ! update_status "$plan_file" "active" "AI Developer Ready approved by ${reviewer} (iteration ${iteration})"; then
        log_error "Failed to update progress log"
        exit 1
    fi

    echo ""
    log_info "Marked as AI Developer Ready: $plan_file"
    log_info "Reviewer: $reviewer"
    log_info "Iteration: $iteration (FINAL)"

    log_info "NEXT STEP: Continue with the wizard to request execution approval:"
    show_command "$SCRIPT_PATH wizard $plan_file"
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
        log_info "STEP 1 of 2: A human must approve execution in a SEPARATE TERMINAL:"
        echo -e "  ${GREEN}$SCRIPT_PATH approve-execute ${request_id} --approver \"Your Name\"${NC}"
        echo ""
        log_info "STEP 2 of 2: Then retry this command:"
        echo -e "  ${GREEN}$SCRIPT_PATH execute $plan_file${NC}"
        echo ""
        log_warn "Approval expires in ${EXECUTION_EXPIRY_MINUTES} minutes."
        exit 1
    fi

    # Valid approval found - output tim-loop command
    if ! update_execution_status "$plan_file" "$approval"; then
        log_error "Failed to update execution status"
        exit 1
    fi
    if ! update_status "$plan_file" "active" "Execution approved, starting tim-loop"; then
        log_error "Failed to update progress log"
        exit 1
    fi

    echo ""
    log_info "Execution APPROVED!"
    echo ""
    log_info "STEP 1 of 2: Run this command in Claude Code to start implementation:"
    echo ""
    echo -e "${GREEN}/tim-loop \"implement ${plan_file}.

REQUIREMENTS:
- Complete ALL iterations and phases of the plan
- ALL code MUST be TIM Project compliant:
  * Type safety: mypy --strict (Python) or tsc --strict (TypeScript)
  * Test coverage: 90% minimum with meaningful tests
  * No TODOs, placeholders, or NotImplementedError
  * No secrets in code
  * File size: 400 lines max, function size: 50 lines max
  * Use shared libraries (tim-lib / @tim/lib) for common patterns
  * Follow TIM coding standards (see CLAUDE.md)

You are NOT DONE until all phases complete AND code is TIM-compliant.\"${NC}"
    echo ""
    log_info "STEP 2 of 2: When tim-loop completes successfully, mark the plan as complete:"
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

    log_info "NEXT STEP: Continue with the wizard to get the tim-loop command:"
    show_command "$SCRIPT_PATH wizard $plan_file"
}

cmd_fast_track() {
    # Block AI from running this command
    verify_interactive_terminal

    local plan_file="${1:-}"
    local approver=""
    local reason=""

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --approver) approver="$2"; shift 2 ;;
            --reason) reason="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Validation
    if [[ -z "$plan_file" ]]; then
        log_error "Usage: $SCRIPT_PATH fast-track <plan-file> --approver <name> [--reason <reason>]"
        exit 1
    fi
    if [[ -z "$approver" ]]; then
        log_error "Approver required: --approver <name>"
        exit 1
    fi

    # Resolve plan path (handles ~/.claude/plans/, drafts/, active/, names without paths)
    plan_file=$(resolve_plan_path "$plan_file") || exit 1

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        exit 1
    fi

    local ts
    ts=$(timestamp)
    local date_stamp
    date_stamp=$(datestamp)

    echo ""
    log_info "Fast-tracking plan: $(basename "$plan_file")"
    log_info "Approver: $approver"
    [[ -n "$reason" ]] && log_info "Reason: $reason"
    echo ""

    # Step 1: Import from ~/.claude/plans/ if needed
    if [[ "$plan_file" == *"/.claude/plans/"* ]]; then
        log_info "Importing plan from ~/.claude/plans/..."
        local name
        name=$(basename "$plan_file" .md)
        local dest
        if [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}- ]]; then
            dest=$(to_absolute "${PLANS_DIR}/drafts/${name}.md")
        else
            dest=$(to_absolute "${PLANS_DIR}/drafts/${date_stamp}-${name}.md")
        fi
        mkdir -p "${PLANS_DIR}/drafts"
        cp "$plan_file" "$dest"
        rm "$plan_file"
        plan_file="$dest"
        add_status_header "$plan_file" "Claude"
        ensure_status_header_fields "$plan_file"
        log_info "Imported to: $plan_file"
    fi

    # Step 2: Move from drafts/ to active/ if needed
    if [[ "$plan_file" == *"/drafts/"* ]]; then
        log_info "Promoting plan to active/..."
        local basename
        basename=$(basename "$plan_file")
        local plans_dir
        plans_dir=$(get_plans_dir_from_path "$plan_file")
        local dest="${plans_dir}/active/${basename}"
        mkdir -p "${plans_dir}/active"
        mv "$plan_file" "$dest"
        plan_file="$dest"
        log_info "Moved to: $plan_file"
    fi

    # Ensure Status Header exists and has all required fields
    add_status_header "$plan_file" "Claude"
    ensure_status_header_fields "$plan_file"

    # Step 3: Mark Ralph Review as completed (or not-required for single-phase)
    local ralph_status
    if [[ "$(requires_ralph "$plan_file")" == "true" ]]; then
        ralph_status="completed"
    else
        ralph_status="not-required"
    fi
    update_ralph_status "$plan_file" "$ralph_status"
    log_info "Ralph Review: $ralph_status"

    # Step 4: Update Stage and Approver (patterns handle variable whitespace)
    sed -i '' "s/| Stage[[:space:]]*|[^|]*|/| Stage | active |/" "$plan_file"
    sed -i '' "s/| Approver[[:space:]]*|[^|]*|/| Approver | ${approver} |/" "$plan_file"
    sed -i '' "s/| Last Updated[[:space:]]*|[^|]*|/| Last Updated | ${ts} |/" "$plan_file"

    # Step 5: Mark AI Developer Ready
    update_ai_ready_status "$plan_file" "$approver" "1"
    log_info "AI Developer Ready: yes (reviewed by $approver)"

    # Step 6: Create and auto-approve execution request
    local request_id
    request_id=$(create_execution_request "$plan_file")
    local request_file="${EXECUTION_REQUESTS_DIR}/${request_id}.json"
    local approval_ts
    approval_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Approve the request
    sed -i '' 's/"approved": false/"approved": true/' "$request_file"
    sed -i '' "s/\"approved_by\": null/\"approved_by\": \"${approver}\"/" "$request_file"
    sed -i '' "s/\"approved_at\": null/\"approved_at\": \"${approval_ts}\"/" "$request_file"

    # Update execution status in plan
    update_execution_status "$plan_file" "$request_file"
    log_info "Execution Approved: yes (approved by $approver)"

    # Step 7: Add progress log entry
    local event_desc="Fast-tracked by ${approver}"
    [[ -n "$reason" ]] && event_desc="${event_desc}: ${reason}"
    update_status "$plan_file" "active" "$event_desc"

    # Cleanup claude plans
    cleanup_claude_plans

    echo ""
    log_info "Plan fast-tracked successfully!"
    log_info "All approvals granted."
    echo ""
    log_info "NEXT STEP: Run the wizard to continue with implementation:"
    show_command "$SCRIPT_PATH wizard $plan_file"
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
    cat << EOF
plan-ops.sh - TIM Plan Lifecycle Management

USAGE:
    $SCRIPT_PATH <command> [arguments]

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

    fast-track <plan-file> --approver <name> [--reason <reason>]
        Skip the normal approval workflow and go directly to implementation
        - Works with plans in ~/.claude/plans/, drafts/, or active/
        - Auto-imports from ~/.claude/plans/ if needed
        - Auto-promotes from drafts/ to active/ if needed
        - Marks Ralph Review as completed
        - Marks AI Developer Ready as yes
        - Auto-approves execution
        - Outputs the tim-loop command ready to run
        Use for well-established plans that have been reviewed outside the system

    complete <plan-file>
        Move plan from active to completed
        When run via wizard: offers optional verification tim-loop first

    abandon <plan-file> [--reason <reason>]
        Move plan to abandoned with optional reason

    cleanup-drafts [--older-than <N>d]
        Find and optionally delete drafts older than N days (default: 30)

    list [drafts|active|completed|abandoned|all]
        List plans by stage (default: all)

    wizard <plan-file> [--status]
        Interactive wizard to guide through plan lifecycle
        - Automatically detects current state from Status Header
        - Shows commands to run in Claude Code vs terminal
        - Prompts for required inputs (names, approvals)
        - Tracks file path changes after moves
        - Use --status to show current state without entering wizard

    help
        Show this help message

RALPH LOOP WORKFLOW:
    Multi-phase plans require Ralph Loop review before promotion:

    1. $SCRIPT_PATH ralph plans/drafts/my-plan.md
       (Shows the Ralph Loop command to run)

    2. Run the displayed /ralph-loop command in Claude Code

    3. $SCRIPT_PATH ralph plans/drafts/my-plan.md --mark-complete
       (Marks review as done)

    4. $SCRIPT_PATH promote plans/drafts/my-plan.md --approver "Name"
       (Now promotion is allowed)

EXECUTION WORKFLOW (HARD ENFORCED):
    Active plans require human approval before execution:

    1. AI runs: $SCRIPT_PATH execute plans/active/my-plan.md
       → BLOCKED, creates approval request, outputs request ID

    2. HUMAN runs in SEPARATE TERMINAL:
       $SCRIPT_PATH approve-execute <request-id> --approver "Name"

    3. AI retries: $SCRIPT_PATH execute plans/active/my-plan.md
       → Outputs /tim-loop command

    4. Run the /tim-loop command to execute the plan

    5. $SCRIPT_PATH complete plans/active/my-plan.md

FAST-TRACK WORKFLOW:
    For well-established plans that have already been reviewed:

    $SCRIPT_PATH fast-track <plan-file> --approver "Name" --reason "reason"

    This single command:
    - Imports from ~/.claude/plans/ if needed
    - Promotes from drafts/ to active/ if needed
    - Marks Ralph Review as completed
    - Marks AI Developer Ready as yes
    - Auto-approves execution
    - Outputs the wizard command to continue (copied to clipboard)

    Then run the wizard to start implementation via tim-loop.

    Use when:
    - Plan was reviewed in a design meeting
    - Plan is a straightforward, well-understood change
    - Human has manually verified the plan is ready for implementation

WIZARD WORKFLOW:
    The wizard guides you through the entire plan lifecycle:

    $SCRIPT_PATH wizard <plan-file>

    The wizard will:
    1. Detect current state (import, ralph, promote, etc.)
    2. Show the appropriate command or prompt for input
    3. Wait for external steps (Ralph Loop, approval, Tim Loop)
    4. Track file moves automatically
    5. Offer optional verification tim-loop before marking complete
    6. Continue until plan reaches completed state

    VERIFICATION TIM-LOOP (optional, at completion):
    Before marking a plan complete, the wizard offers to run a verification
    tim-loop that:
    - Reviews the original intent of the plan
    - Audits implementation to ensure it matches intent
    - Verifies TIM Project rules are followed
    - Checks for stubs, TODOs, deferred work, or cheating
    - Creates and executes remediation plans if gaps found
    - Iterates with NO LIMIT until 100% complete

    Use --status to check state without entering the wizard:
    $SCRIPT_PATH wizard <plan-file> --status

EXAMPLES:
    $SCRIPT_PATH init
    $SCRIPT_PATH import ~/.claude/plans/xyz.md --name "feature-auth"
    $SCRIPT_PATH ralph plans/drafts/2025-01-16-feature-auth.md
    $SCRIPT_PATH ralph plans/drafts/2025-01-16-feature-auth.md --mark-complete
    $SCRIPT_PATH promote plans/drafts/2025-01-16-feature-auth.md --approver "Tim"
    $SCRIPT_PATH execute plans/active/2025-01-16-feature-auth.md
    $SCRIPT_PATH approve-execute abc123 --approver "Tim"
    $SCRIPT_PATH fast-track my-plan.md --approver "Tim" --reason "Already reviewed in design meeting"
    $SCRIPT_PATH complete plans/active/2025-01-16-feature-auth.md
    $SCRIPT_PATH abandon plans/drafts/old-plan.md --reason "Requirements changed"
    $SCRIPT_PATH list active
    $SCRIPT_PATH wizard ~/.claude/plans/new-plan.md
    $SCRIPT_PATH wizard plans/active/my-plan.md --status

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
    fast-track) cmd_fast_track "${@:2}" ;;
    complete) cmd_complete "${@:2}" ;;
    abandon) cmd_abandon "${@:2}" ;;
    cleanup-drafts) cmd_cleanup_drafts "${@:2}" ;;
    list) cmd_list "${@:2}" ;;
    wizard) cmd_wizard "${@:2}" ;;
    help|--help|-h) cmd_help ;;
    *)
        log_error "Unknown command: $1"
        echo "Run '$SCRIPT_PATH help' for usage."
        exit 1
        ;;
esac
