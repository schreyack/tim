#!/bin/bash
# Tim Loop Setup Script - v8 (Plugin Version)
# Goal in, working code out: iterative convergence through automated planning and implementation
# - Four-phase workflow: Plan -> Review -> Implement -> Verify
# - Session-based state files for concurrent execution
# - Installed as a Claude Code plugin

set -euo pipefail

# Plugin root is set by Claude Code when running from a plugin
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"

# Path to plan-ops.sh - look in common locations
find_plan_ops() {
    local locations=(
        "${PLAN_OPS_SCRIPT:-}"
        "./tools/plan-ops.sh"
        "../design_standards/tools/plan-ops.sh"
        "/Volumes/External/Git/design_standards/tools/plan-ops.sh"
    )
    for loc in "${locations[@]}"; do
        if [[ -n "$loc" && -f "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    done
    echo ""
}

PLAN_OPS_SCRIPT=$(find_plan_ops)

# Defaults
MAX_ITERATIONS=30
COMPLETION_PROMISE="COMPLETE"
TASK_PARTS=()
DRY_RUN=false
PLAN_ONLY=false
IMPLEMENT_FILE=""
NO_REVIEW=false
NO_VERIFY=false
MAX_VERIFY_CYCLES=999999
REVIEW_ITERATIONS=10
AUTO_APPROVE=false
FORCE_NEW_SESSION=false

# Cleanup: Configurable orphan age threshold (default 24 hours)
TIM_LOOP_ORPHAN_AGE_HOURS="${TIM_LOOP_ORPHAN_AGE_HOURS:-24}"

# Cleanup function: Remove expired approval requests
cleanup_expired_approval_requests() {
    local requests_dir=".tim-execution-requests"
    [ -d "$requests_dir" ] || return 0

    python3 << PYTHON_EOF
import json, os
from datetime import datetime, timezone

requests_dir = "$requests_dir"
for f in os.listdir(requests_dir):
    if not f.endswith('.json'): continue
    filepath = os.path.join(requests_dir, f)
    try:
        with open(filepath) as fp:
            data = json.load(fp)
        expires = data.get('expires_at', '').replace('Z', '+00:00')
        if expires and datetime.now(timezone.utc) > datetime.fromisoformat(expires):
            os.remove(filepath)
    except: pass
PYTHON_EOF
}

# Cleanup function: Remove orphan hooks when no active sessions
cleanup_orphan_hooks() {
    local recent_state_files
    recent_state_files=$(find ~/.claude -maxdepth 1 -name ".tim-loop-state-*" -mmin -60 2>/dev/null | wc -l)
    [ "$recent_state_files" -gt 0 ] && return 0
    [ -f ~/.claude/settings.local.json ] || return 0

    python3 << 'PYTHON_EOF'
import json, os, sys
settings_file = os.path.expanduser("~/.claude/settings.local.json")
try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    sys.exit(0)

modified = False
if 'hooks' in settings:
    for hook_type in ['stop', 'PreToolUse', 'PreCompact']:
        if hook_type in settings['hooks']:
            original = len(settings['hooks'][hook_type])
            settings['hooks'][hook_type] = [h for h in settings['hooks'][hook_type] if 'tim-loop' not in h.get('command', '')]
            if len(settings['hooks'][hook_type]) != original:
                modified = True
            if not settings['hooks'][hook_type]:
                del settings['hooks'][hook_type]
    if not settings['hooks']:
        del settings['hooks']
        modified = True
if modified:
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)
PYTHON_EOF
}

# Cleanup function: Remove orphan state files older than threshold
cleanup_orphan_state_files() {
    local age_minutes=$((TIM_LOOP_ORPHAN_AGE_HOURS * 60))
    find ~/.claude -maxdepth 1 -name ".tim-loop-state-*" -mmin +"$age_minutes" -delete 2>/dev/null || true
    find ~/.claude -maxdepth 1 -name ".tim-loop-prompt-*" -mmin +"$age_minutes" -delete 2>/dev/null || true

    if [ -f ~/.claude/.tim-loop-active ]; then
        local active_state
        active_state=$(cat ~/.claude/.tim-loop-active 2>/dev/null)
        [ -n "$active_state" ] && [ ! -f "$active_state" ] && rm -f ~/.claude/.tim-loop-active
    fi

    if [ -f ~/.claude/.tim-loop-auto-approve ]; then
        local session_id
        session_id=$(cat ~/.claude/.tim-loop-auto-approve 2>/dev/null)
        [ -n "$session_id" ] && [ ! -f ~/.claude/.tim-loop-state-"$session_id" ] && rm -f ~/.claude/.tim-loop-auto-approve
    fi

    cleanup_expired_approval_requests
    cleanup_orphan_hooks
}

# Cleanup function: Remove all tim-loop artifacts
cleanup_all() {
    local force="${1:-}"
    if [ "$force" = "--force" ]; then
        rm -f ~/.claude/.tim-loop-state-* ~/.claude/.tim-loop-prompt-* ~/.claude/.tim-loop-active ~/.claude/.tim-loop-auto-approve 2>/dev/null || true
        [ -d ".tim-execution-requests" ] && rm -f .tim-execution-requests/*.json 2>/dev/null || true
        cleanup_orphan_hooks
        echo "All tim-loop state files and hooks cleaned up" >&2
    else
        cleanup_orphan_state_files
        echo "Orphan tim-loop state files cleaned up" >&2
    fi
}

# Cleanup function: Remove a specific session's files
cleanup_session() {
    local state_file="$1"
    local session_id
    session_id=$(basename "$state_file" | sed 's/\.tim-loop-state-//')

    echo "Cleaning up orphaned session $session_id" >&2

    # Remove session files
    rm -f "$state_file"
    rm -f "${state_file/state/prompt}"
    rm -f ~/.claude/.tim-loop-active
    rm -f ~/.claude/.tim-loop-iteration-count

    cleanup_orphan_hooks
}

# Check if an existing session should be cleaned up
should_cleanup_existing_session() {
    local old_state="$1"
    local current_project="$2"

    # Source the state file to get metadata
    local old_project=""
    local old_plan_file=""
    local created_at=""

    if [[ -f "$old_state" ]]; then
        # shellcheck disable=SC1090
        source "$old_state"
        old_project="${PROJECT_PATH:-}"
        old_plan_file="${PLAN_FILE:-}"
        created_at="${CREATED_AT:-}"
    fi

    # Case 1: Old session's plan file no longer exists
    if [[ -n "$old_plan_file" ]] && [[ ! -f "$old_plan_file" ]]; then
        echo "  Reason: Plan file no longer exists" >&2
        return 0
    fi

    # Case 2: Different project
    if [[ -n "$old_project" ]] && [[ "$old_project" != "$current_project" ]]; then
        echo "  Reason: Different project (was: $old_project)" >&2
        return 0
    fi

    # Case 3: Session is stale (> 4 hours old)
    if [[ -n "$created_at" ]]; then
        local created_epoch now_epoch age_hours
        # Handle both macOS and Linux date commands
        if date -j -f "%Y-%m-%dT%H:%M:%S" "${created_at%Z}" "+%s" &>/dev/null; then
            created_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${created_at%Z}" "+%s")
        elif date -d "${created_at}" "+%s" &>/dev/null; then
            created_epoch=$(date -d "${created_at}" "+%s")
        else
            created_epoch=0
        fi
        now_epoch=$(date "+%s")
        age_hours=$(( (now_epoch - created_epoch) / 3600 ))

        if [[ "$age_hours" -gt 4 ]]; then
            echo "  Reason: Session is $age_hours hours old (stale)" >&2
            return 0
        fi
    fi

    # Should NOT cleanup - might be a legitimate parallel session
    return 1
}

# Detect and handle existing active session
handle_existing_session() {
    local force_flag="$1"
    local current_project="$2"

    if [[ ! -f ~/.claude/.tim-loop-active ]]; then
        return 0  # No existing session
    fi

    local old_state
    old_state=$(cat ~/.claude/.tim-loop-active 2>/dev/null)

    if [[ -z "$old_state" ]] || [[ ! -f "$old_state" ]]; then
        # Stale pointer, just clean it up
        rm -f ~/.claude/.tim-loop-active
        return 0
    fi

    echo "Warning: Active tim-loop session detected" >&2

    if [[ "$force_flag" == true ]]; then
        echo "  --force specified, cleaning up existing session" >&2
        cleanup_session "$old_state"
        return 0
    fi

    if should_cleanup_existing_session "$old_state" "$current_project"; then
        cleanup_session "$old_state"
        return 0
    fi

    # Session is recent and in same project - block unless --force
    echo "" >&2
    echo "An active tim-loop session exists in this project." >&2
    echo "Use --force to override, or complete the existing session first." >&2
    echo "" >&2
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --wizard)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --wizard requires a plan file path" >&2
                exit 1
            fi
            if [[ -z "$PLAN_OPS_SCRIPT" || ! -f "$PLAN_OPS_SCRIPT" ]]; then
                echo "Error: plan-ops.sh not found" >&2
                echo "Set PLAN_OPS_SCRIPT environment variable to the correct path." >&2
                exit 1
            fi
            exec "$PLAN_OPS_SCRIPT" wizard "$2"
            ;;
        -h|--help)
            cat << 'HELP_EOF'
Tim Loop - Goal in, working code out: iterative convergence through automated planning and implementation

USAGE:
  /tim-loop TASK [OPTIONS]
  /tim-loop --implement FILE [OPTIONS]
  /tim-loop --wizard FILE

ARGUMENTS:
  TASK    The task to work on (can be multiple words)

MODES (mutually exclusive):
  Full Workflow (default):  /tim-loop "add feature X"
  Plan Only (--plan):       /tim-loop --plan "design feature X"
  Implement Existing:       /tim-loop --implement plans/active/my-plan.md
  Quick Mode:               /tim-loop --no-review "fix typo"
  Wizard Mode:              /tim-loop --wizard plans/active/my-plan.md

MODIFIER OPTIONS:
  --force, -f               Override existing active session detection
  --no-verify               Skip verification phase (WARNING: can leave incomplete work)
  --auto-approve            Auto-approve all tool permissions
  --max-iterations <n>      Safety limit (default: 30)
  --completion-promise      Phrase signaling completion (default: COMPLETE)
  --dry-run                 Preview prompt without executing

CLEANUP OPTIONS:
  --cleanup                 Remove orphan state files (>24h old)
  --cleanup-all             Remove ALL state files (use if stuck)

For full help: /tim-loop --help
HELP_EOF
            exit 0
            ;;
        --cleanup)
            cleanup_all
            exit 0
            ;;
        --cleanup-all)
            echo "WARNING: This will remove ALL tim-loop state files, including active sessions." >&2
            cleanup_all --force
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --plan)
            PLAN_ONLY=true
            shift
            ;;
        --implement)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --implement requires a file path" >&2
                exit 1
            fi
            if [[ ! -f "$2" ]]; then
                echo "Error: Plan file not found: $2" >&2
                exit 1
            fi
            if [[ "$2" != *"/active/"* ]]; then
                echo "Error: Can only implement plans from active/ folder" >&2
                exit 1
            fi
            if ! grep -q "| AI Developer Ready | yes |" "$2"; then
                echo "Error: Plan is not marked AI Developer Ready" >&2
                exit 1
            fi
            IMPLEMENT_FILE="$2"
            shift 2
            ;;
        --no-review)
            NO_REVIEW=true
            shift
            ;;
        --no-verify)
            NO_VERIFY=true
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --force|-f)
            FORCE_NEW_SESSION=true
            shift
            ;;
        --max-verify-cycles)
            MAX_VERIFY_CYCLES="$2"
            shift 2
            ;;
        --review-iterations)
            REVIEW_ITERATIONS="$2"
            shift 2
            ;;
        --max-iterations)
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        --completion-promise)
            COMPLETION_PROMISE="$2"
            shift 2
            ;;
        *)
            TASK_PARTS+=("$1")
            shift
            ;;
    esac
done

# Clean up orphan state files from crashed sessions (silent)
cleanup_orphan_state_files 2>/dev/null || true

# Check for existing active session (may block or cleanup)
handle_existing_session "$FORCE_NEW_SESSION" "$PWD"

# Join task parts
TASK="${TASK_PARTS[*]:-}"

# Validate task
if [[ -n "$IMPLEMENT_FILE" ]]; then
    if [[ -z "$TASK" ]]; then
        TASK="implement $(basename "$IMPLEMENT_FILE" .md)"
    fi
elif [[ -z "$TASK" ]]; then
    echo "Error: No task provided" >&2
    echo "Usage: /tim-loop \"your task here\"" >&2
    exit 1
fi

# Validate mutually exclusive flags
if [[ "$PLAN_ONLY" == true ]] && [[ -n "$IMPLEMENT_FILE" ]]; then
    echo "Error: --plan and --implement cannot be used together" >&2
    exit 1
fi

if [[ "$NO_REVIEW" == true ]] && [[ -n "$IMPLEMENT_FILE" ]]; then
    echo "Error: --no-review and --implement cannot be used together" >&2
    exit 1
fi

if [[ "$PLAN_ONLY" == true ]] && [[ "$NO_REVIEW" == true ]]; then
    echo "Error: --plan and --no-review cannot be used together" >&2
    exit 1
fi

# Generate plan filename from task description
generate_plan_slug() {
    local task="$1"
    local slug=$(echo "$task" | tr '[:upper:]' '[:lower:]' | \
                 sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | \
                 sed 's/--*/-/g' | cut -c1-50)
    echo "$(date +%Y-%m-%d)-${slug}.md"
}

# Ensure plans directory exists
ensure_plans_dir() {
    local plans_dir="${PWD}/plans/drafts"
    if [[ ! -d "$plans_dir" ]]; then
        mkdir -p "$plans_dir"
        echo "Created plans directory: $plans_dir" >&2
    fi
    echo "$plans_dir"
}

# Context gathering
CURRENT_GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "not a git repo")
CONTEXT_PWD=$(pwd)

# Generate plan filename and path
PLAN_FILENAME=$(generate_plan_slug "$TASK")
PLANS_DIR=$(ensure_plans_dir)
PLAN_FILEPATH="${PLANS_DIR}/${PLAN_FILENAME}"

# Build prompt (simplified - full version in original script)
build_prompt() {
    local prompt=""
    prompt+="## Task
$TASK

## Context
- Working Dir: $CONTEXT_PWD
- Git Branch: $CURRENT_GIT_BRANCH
- Plan File: $PLAN_FILEPATH

"

    if [[ -n "$IMPLEMENT_FILE" ]]; then
        local plan_content
        plan_content=$(cat "$IMPLEMENT_FILE")
        prompt+="## Mode: Implement Existing Plan

### Plan to Implement
\`\`\`markdown
$plan_content
\`\`\`

Implement 100% of this plan. Add <!-- VERIFIED: NO --> when done, then verify.
Output <promise>$COMPLETION_PROMISE</promise> only when VERIFIED: YES.
"
    elif [[ "$PLAN_ONLY" == true ]]; then
        prompt+="## Mode: Plan Only

Create a plan at $PLAN_FILEPATH with Goal, Implementation Steps, Testing Strategy, Completion Criteria.
Output <promise>$COMPLETION_PROMISE</promise> when plan is written.
"
    else
        prompt+="## Mode: Full Workflow

Phase 1: Create plan at $PLAN_FILEPATH (add <!-- REVIEWED: NO -->)
Phase 2: Validate plan (change to <!-- REVIEWED: YES -->)
Phase 3: Implement 100% (add <!-- VERIFIED: NO -->)
Phase 4: Verify 100% complete (change to <!-- VERIFIED: YES -->)

Output <promise>$COMPLETION_PROMISE</promise> only when VERIFIED: YES.
"
    fi

    echo "$prompt"
}

FULL_PROMPT=$(build_prompt)

# State files for the loop
TIM_LOOP_SESSION_ID="$$"
TIM_LOOP_STATE_FILE="$HOME/.claude/.tim-loop-state-${TIM_LOOP_SESSION_ID}"
TIM_LOOP_PROMPT_FILE="$HOME/.claude/.tim-loop-prompt-${TIM_LOOP_SESSION_ID}"
TIM_LOOP_HOOK_SCRIPT="${PLUGIN_ROOT}/scripts/tim-loop-hook.sh"

# Cleanup function for error/interrupt
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        rm -f "$TIM_LOOP_STATE_FILE" "$TIM_LOOP_PROMPT_FILE" "$HOME/.claude/.tim-loop-active" "$HOME/.claude/.tim-loop-auto-approve"
        python3 -c "
import json, os
try:
    with open(os.path.expanduser('~/.claude/settings.local.json'), 'r') as f:
        settings = json.load(f)
    if 'hooks' in settings:
        for ht in ['stop', 'PreToolUse', 'PreCompact']:
            if ht in settings['hooks']:
                settings['hooks'][ht] = [h for h in settings['hooks'][ht] if 'tim-loop' not in h.get('command', '')]
                if not settings['hooks'][ht]: del settings['hooks'][ht]
        if not settings['hooks']: del settings['hooks']
    with open(os.path.expanduser('~/.claude/settings.local.json'), 'w') as f:
        json.dump(settings, f, indent=2)
except: pass
" 2>/dev/null || true
    fi
}
trap cleanup_on_exit EXIT

# Dry run mode
if [ "$DRY_RUN" = true ]; then
    echo "--- DRY RUN: PROMPT START ---"
    echo "$FULL_PROMPT"
    echo "--- DRY RUN: PROMPT END ---"
    exit 0
fi

# Auto-approve marker
if [[ "$AUTO_APPROVE" == true ]]; then
    echo "$TIM_LOOP_SESSION_ID" > "$HOME/.claude/.tim-loop-auto-approve"
    echo "WARNING: Auto-approve enabled" >&2
fi

# Verify hook script exists
if [[ ! -x "$TIM_LOOP_HOOK_SCRIPT" ]]; then
    echo "Error: tim-loop-hook.sh not found at: $TIM_LOOP_HOOK_SCRIPT" >&2
    exit 1
fi

# Create active session marker
echo "$TIM_LOOP_STATE_FILE" > "$HOME/.claude/.tim-loop-active"

# Initialize state file with metadata
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "$TIM_LOOP_STATE_FILE" << EOF
CURRENT_ITERATION=1
MAX_ITERATIONS=$MAX_ITERATIONS
COMPLETION_PROMISE="$COMPLETION_PROMISE"
TIM_LOOP_PROMPT_FILE="$TIM_LOOP_PROMPT_FILE"
PROJECT_PATH="$CONTEXT_PWD"
PLAN_FILE="$PLAN_FILEPATH"
CREATED_AT="$CREATED_AT"
SESSION_ID="$TIM_LOOP_SESSION_ID"
EOF

# Save prompt for re-injection
echo "$FULL_PROMPT" > "$TIM_LOOP_PROMPT_FILE"

# Register hooks (stop, PreToolUse, and PreCompact for context compaction recovery)
python3 << PYTHON_EOF
import json, os

settings_file = os.path.expanduser("~/.claude/settings.local.json")
stop_hook = "${TIM_LOOP_HOOK_SCRIPT}"
permission_hook = "${PLUGIN_ROOT}/scripts/tim-loop-permission-hook.sh"
prompt_manager_hook = "${PLUGIN_ROOT}/scripts/tim-loop-prompt-manager.sh hook"

try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except:
    settings = {}

if 'hooks' not in settings:
    settings['hooks'] = {}

# Stop hook - re-injects prompt when Claude tries to exit before completion
if 'stop' not in settings['hooks']:
    settings['hooks']['stop'] = []
stop_entry = {"command": stop_hook}
if stop_entry not in settings['hooks']['stop']:
    settings['hooks']['stop'].append(stop_entry)

# PreToolUse hook - auto-approve permissions during tim-loop
if 'PreToolUse' not in settings['hooks']:
    settings['hooks']['PreToolUse'] = []
perm_entry = {"command": permission_hook}
if perm_entry not in settings['hooks']['PreToolUse']:
    settings['hooks']['PreToolUse'].append(perm_entry)

# PreCompact hook - re-injects prompt after context compaction
if 'PreCompact' not in settings['hooks']:
    settings['hooks']['PreCompact'] = []
compact_entry = {"command": prompt_manager_hook}
if compact_entry not in settings['hooks']['PreCompact']:
    settings['hooks']['PreCompact'].append(compact_entry)

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)

print("Tim Loop hooks registered (stop, PreToolUse, PreCompact)")
PYTHON_EOF

# Display startup message
echo ""
echo "Tim Loop: Starting iteration 1 of $MAX_ITERATIONS"
echo ""

# Output the prompt
echo "$FULL_PROMPT"
