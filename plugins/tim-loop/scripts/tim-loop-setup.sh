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
  Review Mode:              /tim-loop --review plans/drafts/my-plan.md
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
PLAN_ONLY=false IMPLEMENT_FILE="" REVIEW_FILE="" NO_REVIEW=false NO_VERIFY=false
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
        --review)
            [[ -z "${2:-}" ]] && echo "Error: --review requires a file path" >&2 && exit 1
            [[ ! -f "$2" ]] && echo "Error: Review file not found: $2" >&2 && exit 1
            REVIEW_FILE="$2"; shift 2 ;;
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

# Fix for /clear race condition: delete heartbeat before session check.
# Live parallel sessions recreate it immediately via PreToolUse hook;
# dead sessions (after /clear) won't recreate it.
rm -f "$HOME/.claude/.tim-loop-heartbeat" 2>/dev/null || true

handle_existing_session "$FORCE_NEW_SESSION" "$PWD"
init_plans_folders

# Join task and validate
TASK="${TASK_PARTS[*]:-}"
if [[ -n "$REVIEW_FILE" ]]; then
    # Review mode: task derived from filename
    [[ -z "$TASK" ]] && TASK="review $(basename "$REVIEW_FILE" .md)"
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
[[ -n "$REVIEW_FILE" && "$PLAN_ONLY" == true ]] && echo "Error: --review and --plan cannot be used together" >&2 && exit 1
[[ -n "$REVIEW_FILE" && -n "$IMPLEMENT_FILE" ]] && echo "Error: --review and --implement cannot be used together" >&2 && exit 1
[[ -n "$REVIEW_FILE" && "$NO_REVIEW" == true ]] && echo "Error: --review and --no-review cannot be used together" >&2 && exit 1

# Override default completion promise for review mode
if [[ -n "$REVIEW_FILE" && "$COMPLETION_PROMISE" == "COMPLETE" ]]; then
    COMPLETION_PROMISE="DONEDONE"
fi

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

# For review mode, PLAN_FILEPATH was already set; otherwise generate it
if [[ -z "$REVIEW_FILE" ]]; then
    PLAN_FILENAME=$(generate_plan_slug "$TASK")
    PLANS_DIR=$(ensure_plans_dir)
    PLAN_FILEPATH="${PLANS_DIR}/${PLAN_FILENAME}"
fi

# Build prompt
build_prompt() {
    local prompt="## Task\n$TASK\n\n## Context\n- Working Dir: $CONTEXT_PWD\n- Git Branch: $CURRENT_GIT_BRANCH\n- Plan File: $PLAN_FILEPATH\n\n"
    if [[ -n "$REVIEW_FILE" ]]; then
        prompt+="## Mode: Review\n\n"
        prompt+="You are reviewing $REVIEW_FILE to validate it is ready for AI implementation.\n\n"
        prompt+="### Mindset: Collaborative Improvement\n"
        prompt+="You are helping make this plan the best version of itself - not changing what it is. Think of yourself as an editor, not an author. The human wrote this plan with specific intentions; your job is to make those intentions crystal clear and achievable, not to substitute your own judgment about what should be built.\n\n"
        prompt+="### What Review IS For (Technical & AI-Readiness Improvements)\n"
        prompt+="- **Technical accuracy**: Are referenced files, APIs, libraries, and patterns correct and existing?\n"
        prompt+="- **AI clarity**: Can each instruction only be interpreted ONE way? (No ambiguity)\n"
        prompt+="- **Verifiability**: Are success criteria code-checkable? (Not subjective like 'works well')\n"
        prompt+="- **Completeness**: Are all steps explicit? (No assumed knowledge or implied steps)\n"
        prompt+="- **Error handling**: Are failure scenarios and edge cases addressed?\n"
        prompt+="- **Dependencies**: Are prerequisites and execution order clear?\n\n"
        prompt+="### What Review is NOT For (Scope Changes - PROHIBITED)\n"
        prompt+="- **DO NOT change the goal** - The human defined what they want\n"
        prompt+="- **DO NOT remove items** - If something seems hard, that's the work\n"
        prompt+="- **DO NOT simplify scope** - Complex tasks need complex plans\n"
        prompt+="- **DO NOT redesign the approach** - Improve clarity, don't change direction\n"
        prompt+="- **DO NOT add new features** - Stay within the stated goal\n\n"
        prompt+="### Critical Rules\n"
        prompt+="1. **Scope is LOCKED** - Your job is to make the existing plan implementable by an AI agent, not to change what it accomplishes\n"
        prompt+="2. **If you want ANY scope change, STOP and ask the human** - This includes additions, removals, or approach changes\n"
        prompt+="3. **If you are less than 98% confident on any decision, ask the human**\n"
        prompt+="4. **Improve, don't delete** - If something is unclear, clarify it. If something is wrong, fix it. Never remove it.\n\n"
        prompt+="### What Excellent Review Looks Like\n"
        prompt+="- Reading the entire plan before making any changes\n"
        prompt+="- Improving unclear language while preserving meaning\n"
        prompt+="- Adding missing details the human likely assumed\n"
        prompt+="- Flagging genuine concerns as questions, not deletions\n"
        prompt+="- Making the plan MORE specific, not less\n\n"
        prompt+="Iterate until the plan is ready for AI implementation. Do not declare completion if you have unresolved concerns - raise them instead.\n\n"
        prompt+="Output <promise>$COMPLETION_PROMISE</promise> only when the plan is genuinely ready AND you have no outstanding questions.\n"
    elif [[ -n "$IMPLEMENT_FILE" ]]; then
        prompt+="## Mode: Implement Existing Plan\n\n"
        prompt+="### Plan to Implement\n\`\`\`markdown\n$(cat "$IMPLEMENT_FILE")\n\`\`\`\n\n"
        prompt+="### Mindset: Spirit Over Letter\n"
        prompt+="Follow the SPIRIT of this plan, not just the letter. A human carefully designed this plan with specific intentions. Your job is to fulfill those intentions, not to find the shortest path that technically satisfies the words while missing the point.\n\n"
        prompt+="When you're tempted to take a shortcut, ask yourself: 'Is this what the human actually wanted, or am I just finding a clever way to do less work?' If you're being clever, you're probably being unhelpful.\n\n"
        prompt+="The goal is genuine completion that would make the plan's author say 'Yes, this is exactly what I meant' - not technical compliance that requires explanation or defense.\n\n"
        prompt+="### Critical Rules\n"
        prompt+="1. **Implement 100% of this plan exactly as written** - Every goal, every step, every test, every criterion\n"
        prompt+="2. **DO NOT reduce, skip, or defer any part of the plan** - If something seems difficult, that's the work. Do it.\n"
        prompt+="3. **DO NOT change the plan's scope without human approval** - If you believe something should change, STOP and ask\n"
        prompt+="4. **Your objective is to accomplish the goal** - Not to find reasons why items can't be done\n"
        prompt+="5. **If you are less than 98% confident on any implementation decision, ask the human**\n\n"
        prompt+="### What Implementation is NOT (Anti-Rationalization)\n"
        prompt+="- **'Effectively done' is not done** - If the plan says do it, do it explicitly\n"
        prompt+="- **'Already working' is not an excuse** - Verify it meets the specific criteria in the plan\n"
        prompt+="- **'Out of scope' is not your call** - The plan defines scope, not you\n"
        prompt+="- **'I interpret this as...' means you're reducing work** - Ask for clarification instead\n"
        prompt+="- **'Started' or 'attempted' is not complete** - Finish it or ask for help\n"
        prompt+="- **'This step isn't needed because...' is rationalization** - Do what the plan says\n"
        prompt+="- **'The previous step covers this' is an excuse** - Each step is explicit for a reason\n\n"
        prompt+="### When You Encounter Blockers\n"
        prompt+="- Technical blockers: Try to solve them. If truly stuck after genuine effort, ask the human - don't skip the item\n"
        prompt+="- Ambiguity: Ask for clarification - don't interpret in a way that reduces work\n"
        prompt+="- Missing information: Ask - don't assume it means \"skip this\"\n\n"
        prompt+="### What Excellent Implementation Looks Like\n"
        prompt+="- Each step completed with obvious evidence (files created, tests passing, output shown)\n"
        prompt+="- Proactive verification: 'I'll confirm this works by running X'\n"
        prompt+="- Clear progress updates: 'Completed step 3 of 7: Created user authentication module'\n"
        prompt+="- Asking clarifying questions BEFORE making assumptions\n"
        prompt+="- When uncertain, showing your reasoning and asking for confirmation\n\n"
        prompt+="### Before Each Step\n"
        prompt+="Briefly state: (1) what you're about to do, (2) which plan item it addresses. This keeps you aligned with the plan and makes progress visible.\n\n"
        prompt+="### Completion Means\n"
        prompt+="- Every Implementation Step is fully executed (not partially, not \"started\")\n"
        prompt+="- Every test from Testing Strategy exists AND passes\n"
        prompt+="- Every Completion Criterion is verified true\n"
        prompt+="- Zero TODO/FIXME comments in new code\n"
        prompt+="- All created files are imported AND used (orphaned code = not implemented)\n\n"
        prompt+="Add <!-- VERIFIED: NO --> when implementation is complete, then verify each item.\n"
        prompt+="Output <promise>$COMPLETION_PROMISE</promise> only when VERIFIED: YES and you have genuinely completed everything.\n"
    elif [[ "$PLAN_ONLY" == true ]]; then
        prompt+="## Mode: Plan Only\n\n"
        prompt+="Create a comprehensive plan at $PLAN_FILEPATH that fully addresses the task.\n\n"
        prompt+="### Mindset: Capture the Full Intent\n"
        prompt+="Your job is to translate the human's goal into a complete, actionable plan. Capture what they ACTUALLY want, not a simplified version that's easier to describe. If the task is ambitious, the plan should be ambitious. You're not here to manage expectations or reduce scope - you're here to figure out how to accomplish the goal.\n\n"
        prompt+="### Critical Rules\n"
        prompt+="1. **The plan must fully accomplish the stated goal** - Not a subset, not a \"minimal viable\" version, not \"phase 1 of many\"\n"
        prompt+="2. **DO NOT reduce scope to make the task easier** - If the task is complex, the plan should be complex\n"
        prompt+="3. **If you're uncertain about requirements or approach, ask the human** - Don't guess in ways that reduce work\n"
        prompt+="4. **If you are less than 98% confident on any design decision, ask the human**\n"
        prompt+="5. **Your objective is to create a plan that accomplishes the goal** - Not to find reasons why parts can't or shouldn't be done\n\n"
        prompt+="### Required Sections\n"
        prompt+="- **Goal**: What success looks like (must match the original task, not a reduced version)\n"
        prompt+="- **Implementation Steps**: Specific, actionable steps (not vague bullets that leave room for shortcuts)\n"
        prompt+="- **Testing Strategy**: How each part will be verified (tests that would catch incomplete work)\n"
        prompt+="- **Completion Criteria**: Unambiguous checkboxes (if any criterion is skipped, the task failed)\n\n"
        prompt+="### What Excellent Plans Look Like\n"
        prompt+="- Steps are specific enough that there's only ONE way to interpret them\n"
        prompt+="- No weasel words: avoid 'consider', 'optionally', 'if needed', 'as appropriate'\n"
        prompt+="- Each step has clear done/not-done criteria\n"
        prompt+="- Testing strategy would catch incomplete or incorrect work\n"
        prompt+="- An AI implementing this plan would have no ambiguity about what to do\n\n"
        prompt+="### Before Writing the Plan\n"
        prompt+="First, make sure you understand the full scope. If anything is unclear about what the human wants, ask BEFORE creating the plan. It's better to clarify upfront than to plan the wrong thing.\n\n"
        prompt+="Output <promise>$COMPLETION_PROMISE</promise> when the plan is written AND you have no outstanding questions about scope or approach.\n"
    else
        prompt+="## Mode: Full Workflow\n\n"
        prompt+="You will complete this task through four phases. Your objective is to fully accomplish the goal - not to find ways to reduce, defer, or avoid work.\n\n"
        prompt+="### Mindset: Spirit Over Letter\n"
        prompt+="Throughout all phases, follow the SPIRIT of the task - what the human actually wants - not just the literal words. When you're tempted to take shortcuts, ask: 'Is this what the human intended, or am I being clever?' If you're being clever, you're probably being unhelpful.\n\n"
        prompt+="### Critical Rules (Apply to ALL Phases)\n"
        prompt+="1. **DO NOT change, reduce, or shift the scope** - The task defines the work. Do that work.\n"
        prompt+="2. **If you want to change scope, STOP and ask the human** - Scope changes require explicit approval\n"
        prompt+="3. **Your objective is to accomplish the goal** - Not to find reasons why parts can't be done\n"
        prompt+="4. **If you are less than 98% confident on any decision, ask the human**\n"
        prompt+="5. **Blockers are problems to solve, not excuses to skip items** - If stuck, ask for help\n\n"
        prompt+="---\n\n"
        prompt+="### Phase 1: Create Plan\n"
        prompt+="Create a comprehensive plan at $PLAN_FILEPATH that fully addresses the task.\n\n"
        prompt+="**Include:**\n"
        prompt+="- Goal (must match the original task - not a reduced version)\n"
        prompt+="- Implementation Steps (specific and actionable - no vague bullets)\n"
        prompt+="- Testing Strategy (tests that would catch incomplete work)\n"
        prompt+="- Completion Criteria (unambiguous - if any is skipped, the task failed)\n\n"
        prompt+="Add \`<!-- REVIEWED: NO -->\` when complete.\n\n"
        prompt+="---\n\n"
        prompt+="### Phase 2: Validate Plan\n"
        prompt+="Review your plan to ensure it's ready for AI implementation. Focus on technical accuracy and AI-readiness, NOT scope changes.\n\n"
        prompt+="**What to improve (Technical & AI-Readiness):**\n"
        prompt+="- Technical accuracy: Are referenced files, APIs, patterns correct?\n"
        prompt+="- AI clarity: Can each instruction only be interpreted ONE way?\n"
        prompt+="- Verifiability: Are success criteria code-checkable (not subjective)?\n"
        prompt+="- Completeness: Are all steps explicit (no assumed knowledge)?\n"
        prompt+="- Error handling: Are failure scenarios addressed?\n\n"
        prompt+="**What NOT to change (Scope is LOCKED):**\n"
        prompt+="- DO NOT remove items to make the plan \"simpler\"\n"
        prompt+="- DO NOT weaken criteria to make them easier to pass\n"
        prompt+="- DO NOT change the goal or approach\n"
        prompt+="- If you find issues, fix them or ask the human - don't delete\n\n"
        prompt+="Change to \`<!-- REVIEWED: YES -->\` when the plan is ready for implementation.\n\n"
        prompt+="---\n\n"
        prompt+="### Phase 3: Implement\n"
        prompt+="Execute 100% of the plan exactly as written. Follow the SPIRIT of the plan - what the human actually intended - not just the letter. If you're tempted to take shortcuts, ask yourself: 'Is this what I actually meant when I wrote this plan, or am I finding clever ways to do less?'\n\n"
        prompt+="**Implementation rules:**\n"
        prompt+="- Every step must be fully completed (not \"started\", not \"partially done\")\n"
        prompt+="- Every test must exist AND pass\n"
        prompt+="- If you encounter blockers, solve them or ask - don't skip\n"
        prompt+="- Zero TODO/FIXME comments in new code\n"
        prompt+="- All files created must be imported AND used (orphaned code = not implemented)\n\n"
        prompt+="**Anti-rationalization (these are NOT acceptable):**\n"
        prompt+="- 'Effectively done' - do it explicitly\n"
        prompt+="- 'Already working' - verify against the plan's criteria\n"
        prompt+="- 'Out of scope' - the plan defines scope\n"
        prompt+="- 'I interpret as...' - ask instead of reducing\n"
        prompt+="- 'This step isn't needed' - do what the plan says\n\n"
        prompt+="**Before each step:** Briefly state what you're about to do and which plan item it addresses.\n\n"
        prompt+="Add \`<!-- VERIFIED: NO -->\` when implementation is complete.\n\n"
        prompt+="---\n\n"
        prompt+="### Phase 4: Verify\n"
        prompt+="Verify that 100% of objectives are met. This is not a formality - it's a genuine check.\n\n"
        prompt+="**Verification Process (do each step explicitly):**\n"
        prompt+="1. **List each Goal** from the plan and state whether it's DONE or NOT DONE with evidence\n"
        prompt+="2. **List each Implementation Step** and confirm it was executed (not just started)\n"
        prompt+="3. **Run each Test** from the Testing Strategy and confirm it passes\n"
        prompt+="4. **Check each Completion Criterion** and state whether it's TRUE or FALSE\n\n"
        prompt+="**Verification standards:**\n"
        prompt+="- 'Mostly done' = NOT DONE\n"
        prompt+="- 'Should work' = NOT VERIFIED (run it and confirm)\n"
        prompt+="- 'Partially complete' = NOT DONE\n"
        prompt+="- 'Works in most cases' = NOT DONE (handle all cases)\n\n"
        prompt+="**If ANY item fails verification:** Fix it first, then re-verify. Do not mark VERIFIED: YES with known gaps.\n\n"
        prompt+="Change to \`<!-- VERIFIED: YES -->\` only when every single item passes verification.\n\n"
        prompt+="---\n\n"
        prompt+="Output <promise>$COMPLETION_PROMISE</promise> only when VERIFIED: YES and you have truly completed all work.\n"
    fi
    echo -e "$prompt"
}
FULL_PROMPT=$(build_prompt)

# State files for the loop
TIM_LOOP_SESSION_ID="$$"
TIM_LOOP_STATE_FILE="$HOME/.claude/.tim-loop-state-${TIM_LOOP_SESSION_ID}"
TIM_LOOP_PROMPT_FILE="$HOME/.claude/.tim-loop-prompt-${TIM_LOOP_SESSION_ID}"
TIM_LOOP_HOOK_SCRIPT="python3 ${PLUGIN_ROOT}/scripts/tim-loop-hook.py"

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
[[ ! -f "${PLUGIN_ROOT}/scripts/tim-loop-hook.py" ]] && echo "Error: tim-loop-hook.py not found at: ${PLUGIN_ROOT}/scripts/tim-loop-hook.py" >&2 && exit 1

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
