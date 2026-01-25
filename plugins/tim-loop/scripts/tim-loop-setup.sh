#!/bin/bash
# Tim Loop Setup Script - v9 (Plugin Version, Refactored)
# Goal in, working code out: iterative convergence through automated planning
# - Four-phase workflow: Plan -> Review -> Implement -> Verify
# - Session-based state files for concurrent execution

set -euo pipefail

# Plugin root is set by Claude Code when running from a plugin
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
SCRIPT_DIR="${PLUGIN_ROOT}/scripts"

# Source helper modules
source "${SCRIPT_DIR}/tim-loop-cleanup.sh"
source "${SCRIPT_DIR}/tim-loop-session.sh"

# Path to bundled plan-ops (in plugin's scripts folder)
PLAN_OPS_SCRIPT="${PLUGIN_ROOT}/scripts/plan-ops.sh"

# Initialize plans folder structure if not present
init_plans_folders() {
    for stage in drafts active completed abandoned; do
        if [[ ! -d "./plans/${stage}" ]]; then
            mkdir -p "./plans/${stage}"
            touch "./plans/${stage}/.gitkeep"
            echo "Created: ./plans/${stage}/" >&2
        fi
    done
}

# Show help
show_help() {
    cat << 'HELP_EOF'
Tim Loop - Goal in, working code out: iterative convergence

USAGE:
  /tim-loop TASK [OPTIONS]
  /tim-loop --implement FILE [OPTIONS]
  /tim-loop --wizard FILE

MODES (mutually exclusive):
  Full Workflow (default):  /tim-loop "add feature X"
  Plan Only (--plan):       /tim-loop --plan "design feature X"
  Implement Existing:       /tim-loop --implement plans/active/my-plan.md
  Quick Mode:               /tim-loop --no-review "fix typo"
  Wizard Mode:              /tim-loop --wizard plans/active/my-plan.md

MODIFIER OPTIONS:
  --force, -f               Override existing active session detection
  --no-verify               Skip verification phase (WARNING: incomplete work)
  --auto-approve            Auto-approve all tool permissions
  --max-iterations <n>      Safety limit (default: 30)
  --completion-promise      Phrase signaling completion (default: COMPLETE)
  --dry-run                 Preview prompt without executing

CLEANUP OPTIONS:
  --cleanup                 Remove orphan state files (>24h old)
  --cleanup-all             Remove ALL state files (use if stuck)

PLAN-OPS:
    Tim Loop uses plan-ops.sh bundled in the plugin for plan lifecycle
    management. Run plan-ops commands directly from the plugin:

    $PLUGIN_ROOT/scripts/plan-ops.sh wizard <plan-file>
    $PLUGIN_ROOT/scripts/plan-ops.sh help

BEST PRACTICE:
    Always clear context before starting. Copy-paste this block:

      /clear
      /tim-loop "your task"
HELP_EOF
}

# Defaults
MAX_ITERATIONS=30 COMPLETION_PROMISE="COMPLETE" TASK_PARTS=() DRY_RUN=false
PLAN_ONLY=false IMPLEMENT_FILE="" NO_REVIEW=false NO_VERIFY=false
MAX_VERIFY_CYCLES=999999 REVIEW_ITERATIONS=10 AUTO_APPROVE=false
FORCE_NEW_SESSION=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --wizard)
            [[ -z "${2:-}" ]] && echo "Error: --wizard requires a plan file path" >&2 && exit 1
            [[ -z "$PLAN_OPS_SCRIPT" || ! -f "$PLAN_OPS_SCRIPT" ]] && echo "Error: plan-ops.sh not found" >&2 && exit 1
            exec "$PLAN_OPS_SCRIPT" wizard "$2"
            ;;
        -h|--help) show_help; exit 0 ;;
        --cleanup) cleanup_all; exit 0 ;;
        --cleanup-all) echo "WARNING: Removing ALL tim-loop state files." >&2; cleanup_all --force; exit 0 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --plan) PLAN_ONLY=true; shift ;;
        --implement)
            [[ -z "${2:-}" ]] && echo "Error: --implement requires a file path" >&2 && exit 1
            [[ ! -f "$2" ]] && echo "Error: Plan file not found: $2" >&2 && exit 1
            [[ "$2" != *"/active/"* ]] && echo "Error: Can only implement plans from active/ folder" >&2 && exit 1
            ! grep -q "| AI Developer Ready | yes |" "$2" && echo "Error: Plan not AI Developer Ready" >&2 && exit 1
            IMPLEMENT_FILE="$2"; shift 2 ;;
        --no-review) NO_REVIEW=true; shift ;;
        --no-verify) NO_VERIFY=true; shift ;;
        --auto-approve) AUTO_APPROVE=true; shift ;;
        --force|-f) FORCE_NEW_SESSION=true; shift ;;
        --max-verify-cycles) MAX_VERIFY_CYCLES="$2"; shift 2 ;;
        --review-iterations) REVIEW_ITERATIONS="$2"; shift 2 ;;
        --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
        --completion-promise) COMPLETION_PROMISE="$2"; shift 2 ;;
        *) TASK_PARTS+=("$1"); shift ;;
    esac
done

# Cleanup and session handling
cleanup_orphan_state_files 2>/dev/null || true
handle_existing_session "$FORCE_NEW_SESSION" "$PWD"
init_plans_folders

# Join task and validate
TASK="${TASK_PARTS[*]:-}"
if [[ -n "$IMPLEMENT_FILE" ]]; then
    [[ -z "$TASK" ]] && TASK="implement $(basename "$IMPLEMENT_FILE" .md)"
elif [[ -z "$TASK" ]]; then
    echo "Error: No task provided. Usage: /tim-loop \"your task here\"" >&2 && exit 1
fi

# Validate mutually exclusive flags
[[ "$PLAN_ONLY" == true && -n "$IMPLEMENT_FILE" ]] && echo "Error: --plan and --implement cannot be used together" >&2 && exit 1
[[ "$NO_REVIEW" == true && -n "$IMPLEMENT_FILE" ]] && echo "Error: --no-review and --implement cannot be used together" >&2 && exit 1
[[ "$PLAN_ONLY" == true && "$NO_REVIEW" == true ]] && echo "Error: --plan and --no-review cannot be used together" >&2 && exit 1

# Generate plan filename and path
generate_plan_slug() {
    local task="$1"
    local slug=$(echo "$task" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g' | tr ' ' '-' | sed 's/--*/-/g' | cut -c1-50)
    echo "$(date +%Y-%m-%d)-${slug}.md"
}

ensure_plans_dir() {
    local plans_dir="${PWD}/plans/drafts"
    [[ ! -d "$plans_dir" ]] && mkdir -p "$plans_dir" && echo "Created plans directory: $plans_dir" >&2
    echo "$plans_dir"
}

CURRENT_GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "not a git repo")
CONTEXT_PWD=$(pwd)
PLAN_FILENAME=$(generate_plan_slug "$TASK")
PLANS_DIR=$(ensure_plans_dir)
PLAN_FILEPATH="${PLANS_DIR}/${PLAN_FILENAME}"

# Build prompt
build_prompt() {
    local prompt="## Task\n$TASK\n\n## Context\n- Working Dir: $CONTEXT_PWD\n- Git Branch: $CURRENT_GIT_BRANCH\n- Plan File: $PLAN_FILEPATH\n\n"
    if [[ -n "$IMPLEMENT_FILE" ]]; then
        prompt+="## Mode: Implement Existing Plan\n\n### Plan to Implement\n\`\`\`markdown\n$(cat "$IMPLEMENT_FILE")\n\`\`\`\n\nImplement 100% of this plan. Add <!-- VERIFIED: NO --> when done, then verify.\nOutput <promise>$COMPLETION_PROMISE</promise> only when VERIFIED: YES.\n"
    elif [[ "$PLAN_ONLY" == true ]]; then
        prompt+="## Mode: Plan Only\n\nCreate a plan at $PLAN_FILEPATH with Goal, Implementation Steps, Testing Strategy, Completion Criteria.\nOutput <promise>$COMPLETION_PROMISE</promise> when plan is written.\n"
    else
        prompt+="## Mode: Full Workflow\n\nPhase 1: Create plan at $PLAN_FILEPATH (add <!-- REVIEWED: NO -->)\nPhase 2: Validate plan (change to <!-- REVIEWED: YES -->)\nPhase 3: Implement 100% (add <!-- VERIFIED: NO -->)\nPhase 4: Verify 100% complete (change to <!-- VERIFIED: YES -->)\n\nOutput <promise>$COMPLETION_PROMISE</promise> only when VERIFIED: YES.\n"
    fi
    echo -e "$prompt"
}
FULL_PROMPT=$(build_prompt)

# State files for the loop
TIM_LOOP_SESSION_ID="$$"
TIM_LOOP_STATE_FILE="$HOME/.claude/.tim-loop-state-${TIM_LOOP_SESSION_ID}"
TIM_LOOP_PROMPT_FILE="$HOME/.claude/.tim-loop-prompt-${TIM_LOOP_SESSION_ID}"
TIM_LOOP_HOOK_SCRIPT="${PLUGIN_ROOT}/scripts/tim-loop-hook.sh"

# Cleanup on error/interrupt
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

# Setup session
[[ "$AUTO_APPROVE" == true ]] && echo "$TIM_LOOP_SESSION_ID" > "$HOME/.claude/.tim-loop-auto-approve" && echo "WARNING: Auto-approve enabled" >&2
[[ ! -x "$TIM_LOOP_HOOK_SCRIPT" ]] && echo "Error: tim-loop-hook.sh not found at: $TIM_LOOP_HOOK_SCRIPT" >&2 && exit 1

echo "$TIM_LOOP_STATE_FILE" > "$HOME/.claude/.tim-loop-active"
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
echo "$FULL_PROMPT" > "$TIM_LOOP_PROMPT_FILE"

# Register hooks
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

for hook_type, hook_cmd in [('stop', stop_hook), ('PreToolUse', permission_hook), ('PreCompact', prompt_manager_hook)]:
    if hook_type not in settings['hooks']:
        settings['hooks'][hook_type] = []
    entry = {"command": hook_cmd}
    if entry not in settings['hooks'][hook_type]:
        settings['hooks'][hook_type].append(entry)

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
print("Tim Loop hooks registered (stop, PreToolUse, PreCompact)")
PYTHON_EOF

echo -e "\nTim Loop: Starting iteration 1 of $MAX_ITERATIONS\n"
echo "$FULL_PROMPT"
