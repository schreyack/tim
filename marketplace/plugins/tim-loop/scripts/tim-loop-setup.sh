#!/bin/bash
# Tim Loop Setup Script - v10 (Split Review Modes, Carrot-First Tone)
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
source "${SCRIPT_DIR}/setup-core.sh"
source "${SCRIPT_DIR}/setup-hooks.sh"
source "${SCRIPT_DIR}/setup-prompts.sh"
source "${SCRIPT_DIR}/setup-help.sh"

# Path to bundled plan-ops (in plugin's scripts folder)
PLAN_OPS_SCRIPT="${PLUGIN_ROOT}/scripts/plan-ops.sh"

# Defaults
MAX_ITERATIONS=30 COMPLETION_PROMISE="COMPLETE" TASK_PARTS=() DRY_RUN=false
PLAN_ONLY=false IMPLEMENT_FILE="" REVIEW_FILE="" REVIEW_MODE="" VERIFY_FILE=""
NO_REVIEW=false USE_TEAM=false
MAX_VERIFY_CYCLES=999999 REVIEW_ITERATIONS=10 MIN_REVIEW_ITERATIONS=5 AUTO_APPROVE=false
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
        --health) exec "${SCRIPT_DIR}/hook-health-check.sh" ;;
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
        --tech-review)
            [[ -z "${2:-}" ]] && echo "Error: --tech-review requires a file path" >&2 && exit 1
            [[ ! -f "$2" ]] && echo "Error: Review file not found: $2" >&2 && exit 1
            [[ -n "$REVIEW_MODE" ]] && echo "Error: --tech-review and --ai-ready cannot be used together" >&2 && exit 1
            REVIEW_FILE="$2"; REVIEW_MODE="tech-review"; shift 2 ;;
        --ai-ready)
            [[ -z "${2:-}" ]] && echo "Error: --ai-ready requires a file path" >&2 && exit 1
            [[ ! -f "$2" ]] && echo "Error: Review file not found: $2" >&2 && exit 1
            [[ -n "$REVIEW_MODE" ]] && echo "Error: Cannot combine review modes" >&2 && exit 1
            REVIEW_FILE="$2"; REVIEW_MODE="ai-ready"; shift 2 ;;
        --full-review)
            [[ -z "${2:-}" ]] && echo "Error: --full-review requires a file path" >&2 && exit 1
            [[ ! -f "$2" ]] && echo "Error: Review file not found: $2" >&2 && exit 1
            [[ -n "$REVIEW_MODE" ]] && echo "Error: Cannot combine review modes" >&2 && exit 1
            REVIEW_FILE="$2"; REVIEW_MODE="full-review"; shift 2 ;;
        --pm-review)
            [[ -z "${2:-}" ]] && echo "Error: --pm-review requires a file path" >&2 && exit 1
            [[ ! -f "$2" ]] && echo "Error: Review file not found: $2" >&2 && exit 1
            [[ -n "$REVIEW_MODE" ]] && echo "Error: Cannot combine review modes" >&2 && exit 1
            REVIEW_FILE="$2"; REVIEW_MODE="pm-review"; shift 2 ;;
        --verify)
            [[ -z "${2:-}" ]] && echo "Error: --verify requires a file path" >&2 && exit 1
            [[ ! -f "$2" ]] && echo "Error: Plan file not found: $2" >&2 && exit 1
            VERIFY_FILE="$2"; shift 2 ;;
        --no-review) NO_REVIEW=true; shift ;;
        --auto-approve) AUTO_APPROVE=true; shift ;;
        --force|-f) FORCE_NEW_SESSION=true; shift ;;
        --team) USE_TEAM=true; shift ;;
        --max-verify-cycles) MAX_VERIFY_CYCLES="$2"; shift 2 ;;
        --review-iterations) REVIEW_ITERATIONS="$2"; shift 2 ;;
        --min-review-iterations) MIN_REVIEW_ITERATIONS="$2"; shift 2 ;;
        --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
        --completion-promise) COMPLETION_PROMISE="$2"; shift 2 ;;
        *) TASK_PARTS+=("$1"); shift ;;
    esac
done

# Cleanup and session handling
cleanup_orphan_state_files 2>/dev/null || true

# Fix for /clear race condition: delete heartbeat before session check.
# Live parallel sessions recreate it immediately via PreToolUse hook;
# dead sessions (after /clear) won't recreate it.
rm -f "$HOME/.claude/.tim-loop-heartbeat" 2>/dev/null || true

handle_existing_session "$FORCE_NEW_SESSION" "$PWD"
init_plans_folders

# Join task and validate
TASK="${TASK_PARTS[*]:-}"
if [[ -n "$VERIFY_FILE" ]]; then
    # Verify mode: task derived from filename
    [[ -z "$TASK" ]] && TASK="verify $(basename "$VERIFY_FILE" .md)"
    PLAN_FILEPATH="$VERIFY_FILE"
elif [[ -n "$REVIEW_FILE" ]]; then
    # Review mode: task derived from filename
    [[ -z "$TASK" ]] && TASK="${REVIEW_MODE} $(basename "$REVIEW_FILE" .md)"
    # Skip plan path generation for review mode
    PLAN_FILEPATH="$REVIEW_FILE"
elif [[ -n "$IMPLEMENT_FILE" ]]; then
    [[ -z "$TASK" ]] && TASK="implement $(basename "$IMPLEMENT_FILE" .md)"
elif [[ -z "$TASK" ]]; then
    echo "Error: No task provided. Usage: /tim-loop \"your task here\"" >&2 && exit 1
fi

# Validate mutually exclusive flags
[[ "$PLAN_ONLY" == true && -n "$IMPLEMENT_FILE" ]] && echo "Error: --plan and --implement cannot be used together" >&2 && exit 1
[[ "$NO_REVIEW" == true && -n "$IMPLEMENT_FILE" ]] && echo "Error: --no-review and --implement cannot be used together" >&2 && exit 1
[[ "$PLAN_ONLY" == true && "$NO_REVIEW" == true ]] && echo "Error: --plan and --no-review cannot be used together" >&2 && exit 1
[[ -n "$REVIEW_FILE" && "$PLAN_ONLY" == true ]] && echo "Error: --tech-review/--ai-ready and --plan cannot be used together" >&2 && exit 1
[[ -n "$REVIEW_FILE" && -n "$IMPLEMENT_FILE" ]] && echo "Error: --tech-review/--ai-ready and --implement cannot be used together" >&2 && exit 1
[[ -n "$REVIEW_FILE" && "$NO_REVIEW" == true ]] && echo "Error: --tech-review/--ai-ready and --no-review cannot be used together" >&2 && exit 1
[[ -n "$VERIFY_FILE" && -n "$IMPLEMENT_FILE" ]] && echo "Error: --verify and --implement cannot be used together" >&2 && exit 1
[[ -n "$VERIFY_FILE" && -n "$REVIEW_FILE" ]] && echo "Error: --verify and --tech-review/--ai-ready cannot be used together" >&2 && exit 1
[[ -n "$VERIFY_FILE" && "$PLAN_ONLY" == true ]] && echo "Error: --verify and --plan cannot be used together" >&2 && exit 1
[[ -n "$VERIFY_FILE" && "$NO_REVIEW" == true ]] && echo "Error: --verify and --no-review cannot be used together" >&2 && exit 1
[[ "$USE_TEAM" == true && "$PLAN_ONLY" == true ]] && echo "Error: --team and --plan cannot be used together (teams are for implementation)" >&2 && exit 1
[[ "$USE_TEAM" == true && -n "$REVIEW_FILE" ]] && echo "Error: --team and review modes cannot be used together (teams are for implementation)" >&2 && exit 1
[[ "$USE_TEAM" == true && -n "$VERIFY_FILE" ]] && echo "Error: --team and --verify cannot be used together (teams are for implementation)" >&2 && exit 1

# Override default completion promise based on mode
if [[ -n "$REVIEW_FILE" && "$COMPLETION_PROMISE" == "COMPLETE" ]]; then
    if [[ "$REVIEW_MODE" == "tech-review" ]]; then
        COMPLETION_PROMISE="TECH-REVIEW-DONE"
    elif [[ "$REVIEW_MODE" == "ai-ready" ]]; then
        COMPLETION_PROMISE="AI-READY-DONE"
    elif [[ "$REVIEW_MODE" == "full-review" ]]; then
        COMPLETION_PROMISE="FULL-REVIEW-DONE"
    elif [[ "$REVIEW_MODE" == "pm-review" ]]; then
        COMPLETION_PROMISE="PM-REVIEW-DONE"
    fi
fi
if [[ -n "$VERIFY_FILE" && "$COMPLETION_PROMISE" == "COMPLETE" ]]; then
    COMPLETION_PROMISE="VERIFY-DONE"
fi

CURRENT_GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "not a git repo")
CONTEXT_PWD=$(pwd)

# For review/verify mode, PLAN_FILEPATH was already set; otherwise generate it
if [[ -z "$REVIEW_FILE" && -z "$VERIFY_FILE" ]]; then
    PLAN_FILENAME=$(generate_plan_slug "$TASK")
    PLANS_DIR=$(ensure_plans_dir)
    PLAN_FILEPATH="${PLANS_DIR}/${PLAN_FILENAME}"
fi

# Build prompt
FULL_PROMPT=$(build_prompt)

# State files for the loop
TIM_LOOP_SESSION_ID="$$"
TIM_LOOP_CLAUDE_PID=$(find_claude_pid)
TIM_LOOP_STATE_FILE="$HOME/.claude/.tim-loop-state-${TIM_LOOP_SESSION_ID}"
TIM_LOOP_PROMPT_FILE="$HOME/.claude/.tim-loop-prompt-${TIM_LOOP_SESSION_ID}"
TIM_LOOP_HOOK_SCRIPT="python3 ${PLUGIN_ROOT}/scripts/tim_loop_hook.py"

# Register cleanup trap
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
[[ ! -f "${PLUGIN_ROOT}/scripts/tim_loop_hook.py" ]] && echo "Error: tim_loop_hook.py not found at: ${PLUGIN_ROOT}/scripts/tim_loop_hook.py" >&2 && exit 1

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
CLAUDE_PID="$TIM_LOOP_CLAUDE_PID"
REVIEW_MODE="$REVIEW_MODE"
MIN_REVIEW_ITERATIONS="$MIN_REVIEW_ITERATIONS"
IMPLEMENT_MODE="$( [[ -n "$IMPLEMENT_FILE" ]] && echo "true" || echo "false" )"
USE_TEAM="$USE_TEAM"
EOF

# For full-review mode, add phase tracking to state file
if [[ "$REVIEW_MODE" == "full-review" ]]; then
    cat >> "$TIM_LOOP_STATE_FILE" << EOF
CURRENT_PHASE="1"
PHASE_1_ITERATIONS="0"
PHASE_2_ITERATIONS="0"
PHASE_3_ITERATIONS="0"
PHASE_4_ITERATIONS="0"
PHASE_5_ITERATIONS="0"
PHASE_6_ITERATIONS="0"
PHASE_7_ITERATIONS="0"
MIN_PHASE_1_ITERATIONS="5"
MIN_PHASE_2_ITERATIONS="2"
MIN_PHASE_3_ITERATIONS="2"
MIN_PHASE_4_ITERATIONS="2"
MIN_PHASE_5_ITERATIONS="1"
MIN_PHASE_6_ITERATIONS="1"
MIN_PHASE_7_ITERATIONS="1"
PHASE_1_COMPLETE="false"
PHASE_2_COMPLETE="false"
PHASE_3_COMPLETE="false"
PHASE_4_COMPLETE="false"
PHASE_5_COMPLETE="false"
PHASE_6_COMPLETE="false"
PHASE_7_COMPLETE="false"
EOF
fi

# Save prompt using prompt manager with required environment variables
# This enables security validation on reinjection
PROMPT_MANAGER="${PLUGIN_ROOT}/scripts/tim-loop-prompt-manager.sh"
if [[ -x "$PROMPT_MANAGER" ]]; then
    TIM_LOOP_SESSION_ID="$TIM_LOOP_SESSION_ID" \
    PWD="$CONTEXT_PWD" \
    "$PROMPT_MANAGER" save "$FULL_PROMPT" 2>/dev/null || {
        # Fallback to direct write if prompt manager fails
        echo "WARNING: Prompt manager failed, using direct save" >&2
        echo "$FULL_PROMPT" > "$TIM_LOOP_PROMPT_FILE"
    }
else
    # Direct write if prompt manager not available
    echo "$FULL_PROMPT" > "$TIM_LOOP_PROMPT_FILE"
fi

# Register hooks
python3 << PYTHON_EOF
import json, os
settings_file = os.path.expanduser("~/.claude/settings.local.json")
stop_hook = "${TIM_LOOP_HOOK_SCRIPT}"
permission_hook = "${PLUGIN_ROOT}/scripts/tim-loop-permission-hook.sh"
prompt_manager_hook = "${PLUGIN_ROOT}/scripts/tim-loop-prompt-manager.sh hook"
option_expander_hook = "python3 ${PLUGIN_ROOT}/scripts/option_expander.py"

try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except:
    settings = {}

if 'hooks' not in settings:
    settings['hooks'] = {}

# Clean existing tim-loop hooks before registering (prevents version accumulation)
for ht in ['stop', 'PreToolUse', 'SessionStart', 'UserPromptSubmit']:
    if ht in settings['hooks']:
        settings['hooks'][ht] = [h for h in settings['hooks'][ht] if 'tim-loop' not in h.get('command', '')]
        if not settings['hooks'][ht]:
            del settings['hooks'][ht]

# Register current version's hooks
for hook_type, hook_cmd in [('stop', stop_hook), ('PreToolUse', permission_hook), ('SessionStart', prompt_manager_hook), ('UserPromptSubmit', option_expander_hook)]:
    if hook_type not in settings['hooks']:
        settings['hooks'][hook_type] = []
    settings['hooks'][hook_type].append({"command": hook_cmd})

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
print("Tim Loop hooks registered (stop, PreToolUse, SessionStart, UserPromptSubmit)")
PYTHON_EOF

echo -e "\nTim Loop: Starting iteration 1 of $MAX_ITERATIONS\n"
echo "$FULL_PROMPT"
