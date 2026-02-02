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
  Full Review:              /tim-loop --full-review plans/drafts/my-plan.md
  Tech Review:              /tim-loop --tech-review plans/drafts/my-plan.md
  PM Review:                /tim-loop --pm-review plans/drafts/my-plan.md
  AI-Ready Review:          /tim-loop --ai-ready plans/active/my-plan.md
  Verify Implementation:    /tim-loop --verify plans/active/my-plan.md
  Quick Mode:               /tim-loop --no-review "fix typo"
  Wizard Mode:              /tim-loop --wizard plans/active/my-plan.md

MODIFIER OPTIONS:
  --force, -f               Override existing active session detection
  --auto-approve            Auto-approve all tool permissions
  --max-iterations <n>      Safety limit (default: 30)
  --min-review-iterations <n> Minimum review passes before allowing completion (default: 5)
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
PLAN_ONLY=false IMPLEMENT_FILE="" REVIEW_FILE="" REVIEW_MODE="" VERIFY_FILE=""
NO_REVIEW=false
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

# For review/verify mode, PLAN_FILEPATH was already set; otherwise generate it
if [[ -z "$REVIEW_FILE" && -z "$VERIFY_FILE" ]]; then
    PLAN_FILENAME=$(generate_plan_slug "$TASK")
    PLANS_DIR=$(ensure_plans_dir)
    PLAN_FILEPATH="${PLANS_DIR}/${PLAN_FILENAME}"
fi

# Build prompt
build_prompt() {
    local prompt="## Task\n$TASK\n\n## Context\n- Working Dir: $CONTEXT_PWD\n- Git Branch: $CURRENT_GIT_BRANCH\n- Plan File: $PLAN_FILEPATH\n\n"
    if [[ -n "$REVIEW_FILE" && "$REVIEW_MODE" == "tech-review" ]]; then
        prompt+="## Mode: Tech Review\n\n"
        prompt+="You are a skeptical senior engineer reviewing $REVIEW_FILE before it goes to an AI developer for implementation.\n\n"
        prompt+="### Your Persona (Senior Engineer)\n"
        prompt+="Think like a skeptical senior engineer who has seen plans fail in production. You're not hostile - you genuinely want this plan to succeed. But you know that vague plans produce buggy code, missing edge cases cause outages, and untestable criteria lead to \"works on my machine\" outcomes. Your skepticism protects the team.\n\n"
        prompt+="### What You're Evaluating\n\n"
        prompt+="**Technical Accuracy**\n"
        prompt+="- Are referenced files, APIs, libraries, and patterns real and correct? (An AI developer will try to use exactly what's written - wrong references cause hallucinated implementations)\n"
        prompt+="- Are version assumptions correct? Are deprecated APIs being referenced?\n"
        prompt+="- Are the proposed approaches technically feasible given the codebase's architecture?\n\n"
        prompt+="**Feasibility & Edge Cases**\n"
        prompt+="- What happens when things go wrong? (Network failures, invalid input, concurrent access, empty states)\n"
        prompt+="- Are there performance implications at scale?\n"
        prompt+="- Are there security considerations not addressed?\n"
        prompt+="- What are the boundary conditions?\n\n"
        prompt+="**Ordering & Dependencies**\n"
        prompt+="- Can the steps be executed in the order specified?\n"
        prompt+="- Are there hidden dependencies between steps?\n"
        prompt+="- Would a different ordering be more efficient or safer?\n\n"
        prompt+="**Completeness**\n"
        prompt+="- Are there gaps where the plan assumes knowledge it doesn't state?\n"
        prompt+="- Are rollback scenarios covered for risky changes?\n"
        prompt+="- Is the testing strategy thorough enough to catch the likely failure modes?\n\n"
        prompt+="**Testability**\n"
        prompt+="- Can every success criterion be verified with a concrete test?\n"
        prompt+="- Are acceptance criteria specific enough to be unambiguous? (\"Works correctly\" is not testable; \"Returns 200 with JSON body containing user_id\" is)\n"
        prompt+="- Would the tests actually catch the bugs this plan might introduce?\n\n"
        prompt+="### Why Scope Reduction Creates More Work\n"
        prompt+="The human invested time designing this plan because they need specific outcomes. When scope gets reduced during review:\n"
        prompt+="- **Every removed item becomes a follow-up request** — the human still needs it, they'll just have to ask again\n"
        prompt+="- **Simplified plans produce incomplete results** — the human discovers gaps when they try to use the work\n"
        prompt+="- **The human loses time twice** — once waiting for this work, again filing and waiting for the missing pieces\n\n"
        prompt+="Difficulty is expected. If something seems hard to implement, that's the work — not a signal to remove it. If you genuinely believe something is impossible or misguided, raise it as a question. The human may have context that explains why it's there, or they may agree to change it. But that's their decision, not yours.\n\n"
        prompt+="Your role during review:\n"
        prompt+="- **Make the plan clearer**, not smaller\n"
        prompt+="- **Add precision**, not simplification\n"
        prompt+="- **Flag concerns as questions**, not deletions\n\n"
        prompt+="### What Excellent Tech Review Looks Like\n"
        prompt+="- Reading the entire plan before making any changes\n"
        prompt+="- Verifying that referenced files/APIs actually exist in the codebase\n"
        prompt+="- Adding specific edge cases the author likely didn't consider\n"
        prompt+="- Tightening vague criteria into concrete, testable statements\n"
        prompt+="- Raising genuine concerns as questions for the author\n"
        prompt+="- Making the plan MORE specific and MORE robust, not less\n\n"
        prompt+="### Evidence Requirement (MANDATORY)\n\n"
        prompt+="Before signaling completion, you MUST output a Review Evidence Log.\n\n"
        prompt+="\`\`\`\n"
        prompt+="**REVIEW EVIDENCE LOG**\n\n"
        prompt+="Files verified:\n"
        prompt+="- [file_path:line_number] - [what was checked, what was found]\n"
        prompt+="- (list all files referenced in the plan that you actually opened and read)\n\n"
        prompt+="Edge cases added:\n"
        prompt+="- [section] Before: [original text] → After: [improved text]\n"
        prompt+="- (list each edge case you added with before/after)\n\n"
        prompt+="Criteria tightened:\n"
        prompt+="- [criterion] Before: [vague] → After: [specific, testable]\n"
        prompt+="- (list each criterion you made more specific)\n\n"
        prompt+="Questions raised:\n"
        prompt+="- [list any questions for the human, or 'None']\n"
        prompt+="\`\`\`\n\n"
        prompt+="**Validation rules:**\n"
        prompt+="- 'Files verified' MUST list specific file:line numbers, not 'verified all files'\n"
        prompt+="- At least one edge case or criterion improvement is expected (plans are rarely perfect)\n"
        prompt+="- Empty or vague evidence logs will be rejected by the stop hook\n\n"
        prompt+="**To signal completion:** Output exactly \`<promise>$COMPLETION_PROMISE</promise>\` (the tag is \`promise\`, NOT \`prompt\`).\n"
    elif [[ -n "$REVIEW_FILE" && "$REVIEW_MODE" == "ai-ready" ]]; then
        prompt+="## Mode: AI-Ready Review\n\n"
        prompt+="You are a tech lead who manages AI developers, reviewing $REVIEW_FILE to ensure it's ready for AI implementation.\n\n"
        prompt+="### Your Persona\n"
        prompt+="You know how AI developers work - they follow instructions literally, they can hallucinate plausible-sounding implementations, and they work best with unambiguous, explicit instructions. You've seen what happens when a plan says \"handle errors appropriately\" (the AI picks whatever seems reasonable, which may not match what the human wanted). Your job is to make this plan AI-proof.\n\n"
        prompt+="### Phase 1: Technical Double-Check\n"
        prompt+="Before assessing AI-readiness, do a quick technical sanity check. A prior tech review should have caught major issues, but verify:\n"
        prompt+="- Referenced files and APIs still exist\n"
        prompt+="- The approach is still sound given current codebase state\n"
        prompt+="- No obvious technical gaps were missed\n\n"
        prompt+="If you find technical issues, fix them before proceeding to Phase 2.\n\n"
        prompt+="### Phase 2: AI-Readiness Assessment\n\n"
        prompt+="**Unambiguous Instructions** (because AI interprets literally)\n"
        prompt+="- Can each instruction be interpreted in only ONE way? If there are multiple valid interpretations, the AI will pick one - and it might not be the one the human wanted\n"
        prompt+="- Are there implicit assumptions that a human would understand but an AI might miss?\n"
        prompt+="- Are \"obvious\" steps spelled out? (AI doesn't share human intuition about what's obvious)\n\n"
        prompt+="**Hallucination Prevention** (because AI generates plausible-sounding code)\n"
        prompt+="- Are all referenced APIs, functions, and file paths verified to exist?\n"
        prompt+="- Are return types, parameter signatures, and error types specified explicitly?\n"
        prompt+="- Is there anything the AI might \"fill in\" that should be explicitly stated instead?\n\n"
        prompt+="**Guard Rails** (because AI needs clear boundaries)\n"
        prompt+="- Is error handling specified explicitly? (Not \"handle errors\" but \"catch ValueError, log with context, return 400\")\n"
        prompt+="- Are there explicit boundaries for what to change and what to leave alone?\n"
        prompt+="- Are there known gotchas in the codebase that the AI should be warned about?\n\n"
        prompt+="**Verifiable Criteria** (because AI needs concrete completion signals)\n"
        prompt+="- Can every completion criterion be checked with code? (Running a test, checking a file exists, grepping for a pattern)\n"
        prompt+="- Are there criteria that require subjective judgment? (These should be rewritten as objective checks)\n"
        prompt+="- Would an AI know, with certainty, whether it has completed each step?\n\n"
        prompt+="### Phase 3: Goal Alignment Check (The Spirit Test)\n"
        prompt+="Now step back with fresh eyes. This is the final sanity check before implementation begins.\n\n"
        prompt+="**The Question:** Does this plan still achieve what the human ACTUALLY wanted?\n\n"
        prompt+="Through technical review and AI-readiness improvements, plans can drift:\n"
        prompt+="- Edge cases get added, but the core goal gets diluted\n"
        prompt+="- Implementation details become more specific, but miss the original intent\n"
        prompt+="- The plan becomes technically correct but spiritually wrong\n\n"
        prompt+="**How to Check:**\n"
        prompt+="1. Re-read the original Goal section - what did the human ask for?\n"
        prompt+="2. Read through the plan as it now stands - what will actually be delivered?\n"
        prompt+="3. Ask: Would the human look at the result and say 'Yes, this is what I meant'?\n"
        prompt+="4. Check: Did we add so much technical detail that we changed WHAT we're building, not just HOW?\n\n"
        prompt+="**If the answer is NO** - the plan has drifted from the original intent:\n"
        prompt+="- Do NOT mark AI-Ready\n"
        prompt+="- Document specifically how the plan drifted from the original goal\n"
        prompt+="- The plan needs to go back to drafts for redesign around the ACTUAL goal\n"
        prompt+="- This is not a failure - catching drift now saves wasted implementation effort\n\n"
        prompt+="**If the answer is YES** - proceed to mark AI-Ready.\n\n"
        prompt+="### Why Scope Reduction Creates More Work\n"
        prompt+="Making a plan AI-ready means making it clearer and more precise — not simpler or smaller. When scope gets reduced:\n"
        prompt+="- **The human still needs every outcome they specified** — removing items just delays when they get them\n"
        prompt+="- **\"Simplifying\" the plan means the human does extra work later** — filing follow-ups, re-explaining context, waiting again\n"
        prompt+="- **An easier plan to implement ≠ a plan that meets the human's needs** — your goal is their success, not your convenience\n\n"
        prompt+="If something seems too complex or ambiguous to be AI-ready, the answer is to make it clearer — not to remove it. Add more detail, specify exact behavior, break it into smaller explicit steps. The complexity the human asked for reflects what they actually need.\n\n"
        prompt+="Your role during AI-ready review:\n"
        prompt+="- **Add clarity through precision**, not through reduction\n"
        prompt+="- **Make vague items explicit**, don't remove them\n"
        prompt+="- **If an item seems impossible, ask** — the human may have context you don't\n\n"
        prompt+="### What Excellent AI-Ready Review Looks Like\n"
        prompt+="- Replacing every vague instruction with a specific one\n"
        prompt+="- Adding explicit error handling where the plan says \"handle errors\"\n"
        prompt+="- Specifying exact file paths, function signatures, and return types\n"
        prompt+="- Converting subjective criteria to objective, code-checkable ones\n"
        prompt+="- Ensuring an AI developer could complete this plan without asking any questions\n"
        prompt+="- Confirming the plan still delivers what the human originally asked for (the spirit test)\n\n"
        prompt+="### Multi-Pass Review Process (REQUIRED)\n\n"
        prompt+="AI-ready review requires MULTIPLE passes through all three phases. Do not declare completion after one pass.\n\n"
        prompt+="**Pass 1: Initial Review**\n"
        prompt+="1. Complete Phase 1 (Technical Double-Check)\n"
        prompt+="2. Complete Phase 2 (AI-Readiness Assessment)\n"
        prompt+="3. Complete Phase 3 (Goal Alignment Check)\n"
        prompt+="4. Fix all issues found\n\n"
        prompt+="**Pass 2+: Verification Passes** (THIS IS WHERE MOST REVIEWERS STOP TOO EARLY)\n"
        prompt+="After making fixes, you MUST re-read the corrected plan:\n"
        prompt+="1. Read the plan AGAIN from the beginning - as if seeing it for the first time\n"
        prompt+="2. Verify your fixes are correct and internally consistent\n"
        prompt+="3. Check if your changes introduced new ambiguities or issues\n"
        prompt+="4. Look for issues you missed on the first pass (fresh eyes often catch more)\n"
        prompt+="5. If you find ANY issues, fix them and do another pass\n\n"
        prompt+="**The Golden Rule: If you made changes, you must re-read.**\n"
        prompt+="Any edit to the plan - no matter how small - requires a full re-read afterward. This is non-negotiable.\n\n"
        prompt+="**The Confidence Trap**\n"
        prompt+="\`Feeling done\` is not the same as \`being done.\` You will feel confident after one thorough pass. That confidence is false. The issues you missed are invisible to you precisely because you missed them. Only a fresh re-read can catch what your first pass didn't see.\n\n"
        prompt+="**Completion Criteria**\n"
        prompt+="You may ONLY declare completion when a full re-read of the plan finds ZERO new issues.\n"
        prompt+="Expect 2-3 passes minimum. Single-pass reviews are almost always incomplete.\n\n"
        prompt+="**To signal completion:** Output exactly \`<promise>$COMPLETION_PROMISE</promise>\` (the tag is \`promise\`, NOT \`prompt\`).\n"
        prompt+="Only output this when:\n"
        prompt+="1. The plan passes the Goal Alignment Check (still achieves the original intent)\n"
        prompt+="2. The plan is fully AI-ready with no ambiguity\n"
        prompt+="3. A verification pass found ZERO new issues to fix\n"
        prompt+="4. You have no outstanding concerns\n\n"
        prompt+="If the plan has drifted from the original goal, do NOT output the completion tag. Instead, document the drift and recommend the plan be sent back to drafts.\n"
    elif [[ -n "$REVIEW_FILE" && "$REVIEW_MODE" == "full-review" ]]; then
        prompt+="## Mode: Full Review (3-Phase with Per-Phase Iteration Tracking)\n\n"
        prompt+="You will perform a comprehensive review of $REVIEW_FILE through three sequential phases.\n"
        prompt+="Each phase has minimum iteration requirements and its own completion signal.\n\n"
        prompt+="### Three-Phase Overview\n\n"
        prompt+="| Phase | Focus | Min Iterations | Completion Signal |\n"
        prompt+="|-------|-------|----------------|-------------------|\n"
        prompt+="| 1. Tech Review | Technical accuracy, edge cases | 3 | \`<promise>PHASE-1-TECH-DONE</promise>\` |\n"
        prompt+="| 2. AI-Ready Review | Unambiguous instructions | 2 | \`<promise>PHASE-2-AI-READY-DONE</promise>\` |\n"
        prompt+="| 3. Goal Alignment | Spirit test - original intent | 1 | \`<promise>PHASE-3-GOAL-ALIGN-DONE</promise>\` |\n\n"
        prompt+="**After all 3 phases:** Output \`<promise>$COMPLETION_PROMISE</promise>\` to complete the full review.\n\n"
        prompt+="---\n\n"
        prompt+="## Phase 1: Tech Review (Current Phase)\n\n"
        prompt+="### Your Persona\n"
        prompt+="Think like a skeptical senior engineer who has seen plans fail in production. You're not hostile - you genuinely want this plan to succeed. But you know that vague plans produce buggy code, missing edge cases cause outages, and untestable criteria lead to \"works on my machine\" outcomes.\n\n"
        prompt+="### What You're Evaluating\n\n"
        prompt+="**Technical Accuracy**\n"
        prompt+="- Are referenced files, APIs, libraries, and patterns real and correct?\n"
        prompt+="- Are version assumptions correct? Are deprecated APIs being referenced?\n"
        prompt+="- Are the proposed approaches technically feasible given the codebase's architecture?\n\n"
        prompt+="**Feasibility & Edge Cases**\n"
        prompt+="- What happens when things go wrong? (Network failures, invalid input, concurrent access, empty states)\n"
        prompt+="- Are there performance implications at scale?\n"
        prompt+="- Are there security considerations not addressed?\n"
        prompt+="- What are the boundary conditions?\n\n"
        prompt+="**Ordering & Dependencies**\n"
        prompt+="- Can the steps be executed in the order specified?\n"
        prompt+="- Are there hidden dependencies between steps?\n"
        prompt+="- Would a different ordering be more efficient or safer?\n\n"
        prompt+="**Completeness**\n"
        prompt+="- Are there gaps where the plan assumes knowledge it doesn't state?\n"
        prompt+="- Are rollback scenarios covered for risky changes?\n"
        prompt+="- Is the testing strategy thorough enough to catch the likely failure modes?\n\n"
        prompt+="**Testability**\n"
        prompt+="- Can every success criterion be verified with a concrete test?\n"
        prompt+="- Are acceptance criteria specific enough to be unambiguous?\n"
        prompt+="- Would the tests actually catch the bugs this plan might introduce?\n\n"
        prompt+="### Why Scope Reduction Creates More Work\n"
        prompt+="The human designed this plan because they need specific outcomes. Reducing scope during review:\n"
        prompt+="- **Shifts work from you to the human** — every removed item becomes a follow-up they must file and wait for\n"
        prompt+="- **Multiplies total effort** — the human explains context again, you rebuild understanding, everyone waits longer\n\n"
        prompt+="When something seems difficult or complex, that's the work the human is counting on you to do. If you genuinely believe something is impossible, ask — don't remove.\n\n"
        prompt+="Your role during review:\n"
        prompt+="- **Improve through precision**, not reduction\n"
        prompt+="- **Add detail to vague items**, don't delete them\n"
        prompt+="- **Raise concerns as questions**, not unilateral changes\n\n"
        prompt+="### What Excellent Tech Review Looks Like\n"
        prompt+="- Verifying that referenced files/APIs actually exist in the codebase\n"
        prompt+="- Adding specific edge cases the author likely didn't consider\n"
        prompt+="- Tightening vague criteria into concrete, testable statements\n"
        prompt+="- Specifying exact file paths, function signatures, and return types\n\n"
        prompt+="### Multi-Pass Process\n"
        prompt+="Tech Review requires multiple iterations. After each pass:\n"
        prompt+="1. Re-read the plan from the beginning with fresh eyes\n"
        prompt+="2. Look for issues you missed on previous passes\n"
        prompt+="3. Make improvements if you find any\n\n"
        prompt+="**To signal Phase 1 completion:** Output \`<promise>PHASE-1-TECH-DONE</promise>\`\n"
        prompt+="Only output this when you genuinely cannot find any more technical issues to fix.\n"
    elif [[ -n "$REVIEW_FILE" && "$REVIEW_MODE" == "pm-review" ]]; then
        prompt+="## Mode: PM Review (Project Management Organization)\n\n"
        prompt+="The engineering team has completed technical reviews of $REVIEW_FILE. Now you will review as a senior project manager to organize and polish the plan.\n\n"
        prompt+="### Your Persona\n"
        prompt+="Think like a senior project manager who has delivered dozens of successful projects. You understand what the technical team has built, and now your job is to organize it for smooth implementation. You're not changing WHAT we're building - you're organizing HOW we present it.\n\n"
        prompt+="### Your Focus Areas\n\n"
        prompt+="**Logical Flow & Organization**\n"
        prompt+="- Does the plan flow logically from one section to the next?\n"
        prompt+="- Are implementation steps ordered in a sensible sequence?\n"
        prompt+="- Would a developer reading this know where to start and how to proceed?\n"
        prompt+="- Are related items grouped together?\n\n"
        prompt+="**Clerical Quality**\n"
        prompt+="- Fix typos, grammar, and formatting inconsistencies\n"
        prompt+="- Ensure consistent naming (if something is called 'widget' in one place, it shouldn't be 'component' in another)\n"
        prompt+="- Verify numbering and bullet points are correct\n"
        prompt+="- Ensure code blocks are properly formatted\n\n"
        prompt+="**Implementation Practicality**\n"
        prompt+="- Is there a clear starting point?\n"
        prompt+="- Are dependencies between steps clear?\n"
        prompt+="- Would an implementer get stuck or confused anywhere?\n"
        prompt+="- Are there any missing transitions between sections?\n\n"
        prompt+="**Clarity Without Technical Change**\n"
        prompt+="- Make instructions clearer through better wording\n"
        prompt+="- Improve section headers to be more descriptive\n"
        prompt+="- Add transitional sentences where flow is unclear\n"
        prompt+="- Reorganize content for better readability\n\n"
        prompt+="### CRITICAL: Never Reduce Scope\n\n"
        prompt+="**This is an organization pass, NOT a scope change.**\n\n"
        prompt+="You MUST NOT:\n"
        prompt+="- Remove any requirements, tasks, or deliverables\n"
        prompt+="- Simplify technical specifications\n"
        prompt+="- Delete edge cases or error handling\n"
        prompt+="- Combine items in ways that lose detail\n"
        prompt+="- Mark anything as \"out of scope\" or \"future work\"\n\n"
        prompt+="You CAN:\n"
        prompt+="- Reorder items for better flow\n"
        prompt+="- Fix typos and formatting\n"
        prompt+="- Improve wording for clarity\n"
        prompt+="- Add section headers or transitions\n"
        prompt+="- Group related items together\n\n"
        prompt+="If something seems wrong or unclear, improve its presentation - don't remove it. If you believe something should be changed substantively, add a NOTE for the human to review.\n\n"
        prompt+="### What Excellent PM Review Looks Like\n"
        prompt+="- The plan reads smoothly from start to finish\n"
        prompt+="- An implementer could follow it without getting confused\n"
        prompt+="- Typos and formatting issues are fixed\n"
        prompt+="- Related items are grouped logically\n"
        prompt+="- Transitions between sections are clear\n"
        prompt+="- ALL original content is preserved (just better organized)\n\n"
        prompt+="**To signal completion:** Output exactly \`<promise>$COMPLETION_PROMISE</promise>\` (the tag is \`promise\`, NOT \`prompt\`).\n"
        prompt+="Only output this when the plan is well-organized, polished, and flows logically - with NO scope reduction.\n"
    elif [[ -n "$VERIFY_FILE" ]]; then
        prompt+="## Mode: Verification Audit\n\n"
        prompt+="You are auditing whether $VERIFY_FILE was fully and correctly implemented.\n\n"
        prompt+="### Why Thorough Verification Helps the Human\n"
        prompt+="The human invested time designing this plan because they need specific outcomes. Every gap you catch now is a gap they won't discover later — in production, in front of users, or when they try to build on top of this work.\n\n"
        prompt+="If verification finds gaps and marks the work \"complete\" anyway:\n"
        prompt+="- **The human builds on a broken foundation** — their downstream work fails or produces wrong results\n"
        prompt+="- **They debug problems they didn't create** — time spent chasing issues that should have been caught\n"
        prompt+="- **Trust breaks down** — \"verified complete\" stops meaning anything, so they review everything themselves\n\n"
        prompt+="Honest verification — even when it reveals incomplete work — is more valuable than false reassurance.\n\n"
        prompt+="### Phase 1: Intent Review\n"
        prompt+="1. Read the plan file completely\n"
        prompt+="2. Extract the ORIGINAL INTENT - what was this plan supposed to accomplish?\n"
        prompt+="3. List all explicit requirements and deliverables\n\n"
        prompt+="### Phase 2: Implementation Audit\n"
        prompt+="For each requirement/deliverable:\n"
        prompt+="1. Find the actual implementation in the codebase\n"
        prompt+="2. Check: Is the code REAL and FUNCTIONAL, or stubbed/placeholder?\n"
        prompt+="3. Check: Are there any TODO comments, NotImplementedError, 'pass' statements?\n"
        prompt+="4. Check: Is anything marked as 'future work' or 'deferred'?\n\n"
        prompt+="### Phase 3: TIM Rules Verification\n"
        prompt+="1. Verify type safety (mypy --strict / tsc --strict passes)\n"
        prompt+="2. Verify test coverage (90% minimum, tests actually test the functionality)\n"
        prompt+="3. Verify no secrets in code\n"
        prompt+="4. Verify file size limits (400 lines max)\n"
        prompt+="5. Verify no bypass flags or shortcuts\n\n"
        prompt+="### Phase 4: Gap Remediation\n"
        prompt+="If ANY gaps are found:\n"
        prompt+="1. Create a detailed remediation plan in the plans/drafts/ folder with 'remediation' in filename\n"
        prompt+="2. The remediation plan MUST include a proper Status Header (use plan-ops format)\n"
        prompt+="3. Implement the fixes directly - do the work now\n"
        prompt+="4. If fixes require human decisions, raise them as questions\n\n"
        prompt+="### What Excellent Verification Looks Like\n"
        prompt+="- Checking every single requirement, not just the obvious ones\n"
        prompt+="- Running tests to confirm they pass, not just checking they exist\n"
        prompt+="- Tracing code paths to verify they handle the specified edge cases\n"
        prompt+="- Being honest about gaps rather than rationalizing partial completion\n"
        prompt+="- Fixing issues found rather than just documenting them\n\n"
        prompt+="### Why Hedged Language Hurts the Human\n"
        prompt+="These phrases feel accurate but create real problems:\n\n"
        prompt+="- **'Mostly done'** — the remaining part could be what the human needs most; they'll discover this at the worst time\n"
        prompt+="- **'Should work'** — untested code has bugs; the human will find them in production\n"
        prompt+="- **'Partially complete'** — the human will discover gaps when they try to use the work, after they've moved on\n"
        prompt+="- **'Works in most cases'** — the cases where it fails are often the ones that matter most to the human\n\n"
        prompt+="Verification that uses hedged language shifts risk to the human. Be certain or be honest about uncertainty.\n\n"
        prompt+="If ANY item fails verification: Fix it first, then re-verify.\n\n"
        prompt+="**To signal completion:** Output exactly \`<promise>$COMPLETION_PROMISE</promise>\` (the tag is \`promise\`, NOT \`prompt\`).\n"
        prompt+="Only output this when every single requirement is verified as fully implemented.\n"
    elif [[ -n "$IMPLEMENT_FILE" ]]; then
        prompt+="## Mode: Implement Existing Plan\n\n"
        prompt+="### Plan to Implement\n\`\`\`markdown\n$(cat "$IMPLEMENT_FILE")\n\`\`\`\n\n"
        prompt+="### Mindset: Fulfill the Human's Intent\n"
        prompt+="A human carefully designed this plan because they need specific outcomes. Your job is to deliver those outcomes faithfully. When the plan says to do something, it's because the human needs it done — not because they forgot to consider whether it was necessary.\n\n"
        prompt+="Genuine completion is more valuable than technical compliance. The goal is for the plan's author to look at the result and say 'Yes, this is exactly what I meant' — which happens when you focus on the spirit of what they asked for, not just the literal words.\n\n"
        prompt+="### Why Reducing Scope Hurts the Human\n"
        prompt+="When you skip, simplify, or reinterpret parts of the plan:\n"
        prompt+="- **The human still needs those outcomes** — they'll discover the gaps and have to request the work again\n"
        prompt+="- **They lose time twice** — waiting for this round, then waiting for the missing pieces\n"
        prompt+="- **Context gets lost** — you move on, they re-explain, everyone rebuilds understanding that already existed\n"
        prompt+="- **Their downstream work is blocked** — they planned to build on top of this; gaps delay everything that follows\n\n"
        prompt+="Every item in this plan exists because the human decided they need it. If something seems unnecessary, it's more likely you're missing context than that they made a mistake.\n\n"
        prompt+="### Your Responsibility\n"
        prompt+="1. **Implement 100% of this plan as written** — partial delivery means the human does more work, not less\n"
        prompt+="2. **Difficulty is expected** — complex items reflect real needs, not invitations to simplify\n"
        prompt+="3. **Ask when uncertain** — a quick question costs seconds; redoing skipped work costs hours\n"
        prompt+="4. **Complete the goal** — the human is counting on this work being done so they can move forward\n\n"
        prompt+="### Patterns That Feel Efficient But Create Rework\n"
        prompt+="These shortcuts shift work to the human — they'll spend more time dealing with the gaps than you saved:\n\n"
        prompt+="- **'Effectively done'** — if it's not explicitly done, the human can't verify it. Make it visible.\n"
        prompt+="- **'Already working'** — what seems to work may not meet the plan's criteria. Verify against the plan.\n"
        prompt+="- **'Out of scope'** — the plan IS the scope. If something feels out of place, ask rather than skip.\n"
        prompt+="- **'I interpret this as...'** — reinterpretation that reduces work usually misses the human's intent. Ask instead.\n"
        prompt+="- **'Started' / 'attempted'** — the human needs finished work. Progress isn't completion.\n"
        prompt+="- **'Not needed because...'** — each step exists because the human considered it. Ask if you're unsure.\n"
        prompt+="- **'Previous step covers this'** — explicit steps mean the human wants explicit verification of each.\n\n"
        prompt+="### Plan File Management\n"
        prompt+="**DO NOT move plans between folders** (drafts/, active/, completed/, abandoned/). Plan lifecycle management - including promoting, completing, and archiving plans - is a human responsibility, not an AI responsibility. The human uses plan-ops to manage these transitions with proper approvals and audit trails. Your role is to implement the plan's contents, not manage the plan file's location.\n\n"
        prompt+="### When You Encounter Blockers\n"
        prompt+="- Technical blockers: Try to solve them. If truly stuck after genuine effort, ask the human - don't skip the item\n"
        prompt+="- Ambiguity: Ask for clarification - don't interpret in a way that reduces work\n"
        prompt+="- Missing information: Ask - don't assume it means \"skip this\"\n\n"
        prompt+="### What Excellent Implementation Looks Like\n"
        prompt+="- Each step completed with obvious evidence (files created, tests passing, output shown)\n"
        prompt+="- Proactive verification: 'I'll confirm this works by running X'\n"
        prompt+="- Clear progress updates: 'Completed step 3 of 7: Created user authentication module'\n"
        prompt+="- Asking clarifying questions BEFORE making assumptions\n"
        prompt+="- When uncertain, showing your reasoning and asking for confirmation\n"
        prompt+="- Every test from the plan running and passing\n"
        prompt+="- Zero TODO/FIXME comments - every piece is genuinely finished\n\n"
        prompt+="### Before Each Step\n"
        prompt+="Briefly state: (1) what you're about to do, (2) which plan item it addresses. This keeps you aligned with the plan and makes progress visible.\n\n"
        prompt+="### Completion Means\n"
        prompt+="- Every Implementation Step is fully executed (not partially, not \"started\")\n"
        prompt+="- Every test from Testing Strategy exists AND passes\n"
        prompt+="- Every Completion Criterion is verified true\n"
        prompt+="- Zero TODO/FIXME comments in new code\n"
        prompt+="- All created files are imported AND used (orphaned code = not implemented)\n\n"
        prompt+="Add <!-- VERIFIED: NO --> when implementation is complete, then verify each item.\n"
        prompt+="**To signal completion:** Output exactly \`<promise>$COMPLETION_PROMISE</promise>\` (the tag is \`promise\`, NOT \`prompt\`).\n"
        prompt+="Only output this when VERIFIED: YES and you have genuinely completed everything.\n"
    elif [[ "$PLAN_ONLY" == true ]]; then
        prompt+="## Mode: Plan Only\n\n"
        prompt+="Create a comprehensive plan at $PLAN_FILEPATH that fully addresses the task.\n\n"
        prompt+="### Mindset: Capture the Full Intent\n"
        prompt+="Your job is to translate the human's goal into a complete, actionable plan. Capture what they ACTUALLY want, not a simplified version that's easier to describe. If the task is ambitious, the plan should be ambitious. You're designing a blueprint that will be implemented faithfully — make it thorough.\n\n"
        prompt+="### Why Reducing Scope Hurts the Human\n"
        prompt+="When you create a simpler plan than what the human asked for:\n"
        prompt+="- **They get incomplete results** — the work finishes but doesn't solve their actual problem\n"
        prompt+="- **They file follow-up requests** — re-explaining context they already provided, waiting again for work they already requested\n"
        prompt+="- **Their timeline slips** — what could have been done once now takes multiple rounds\n"
        prompt+="- **Trust erodes** — if plans don't capture their intent, they'll need to review and correct more closely\n\n"
        prompt+="The human described what they need. If their request seems complex, that's because their need is complex. A simpler plan doesn't make their need simpler — it just leaves part of it unmet.\n\n"
        prompt+="### Your Responsibility\n"
        prompt+="1. **Capture the full scope** — every aspect the human mentioned matters to them, or they wouldn't have mentioned it\n"
        prompt+="2. **Ask when uncertain** — if you're unsure whether something is needed, ask. Don't assume it's optional.\n"
        prompt+="3. **Ambitious tasks get ambitious plans** — your job is to make the human's vision achievable, not to scale it back\n"
        prompt+="4. **If you believe something is infeasible, say so** — but as a question, not a unilateral scope reduction\n\n"
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
        prompt+="**To signal completion:** Output exactly \`<promise>$COMPLETION_PROMISE</promise>\` (the tag is \`promise\`, NOT \`prompt\`).\n"
        prompt+="Only output this when the plan is written AND you have no outstanding questions about scope or approach.\n"
    else
        prompt+="## Mode: Full Workflow\n\n"
        prompt+="You will complete this task through four phases. Your objective is to fully accomplish the goal - the human is counting on the result.\n\n"
        prompt+="### Mindset: Fulfill the Human's Intent\n"
        prompt+="Throughout all phases, focus on what the human actually wants - the outcome they're investing in. When you're unsure about something, ask. When something is difficult, that's the work. The human designed this task knowing what they need; your job is to deliver it.\n\n"
        prompt+="### Why Reducing Scope Creates More Work for Everyone\n"
        prompt+="When scope gets reduced — whether during planning, review, or implementation:\n"
        prompt+="- **The human still needs what they asked for** — removed items become follow-up requests they must file and wait for\n"
        prompt+="- **Context gets lost and rebuilt** — you forget why things mattered, the human re-explains, everyone loses time\n"
        prompt+="- **Total effort increases** — doing it in pieces takes longer than doing it once completely\n"
        prompt+="- **The human's timeline slips** — they planned based on this work being done; gaps delay everything downstream\n\n"
        prompt+="If something seems difficult, that's the work. If something seems unnecessary, ask — the human may have context you don't.\n\n"
        prompt+="### Guiding Principles\n"
        prompt+="1. **Preserve the scope exactly** — the human designed this task knowing what they need\n"
        prompt+="2. **Difficulty is expected** — complex requests reflect complex needs, not opportunities to simplify\n"
        prompt+="3. **Ask before reducing** — if you genuinely believe something should change, ask; don't decide unilaterally\n"
        prompt+="4. **Solve problems** — blockers are challenges to overcome, not reasons to skip items\n"
        prompt+="5. **Complete means complete** — partial work creates more work for the human later\n\n"
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
        prompt+="Review your plan to ensure it's ready for implementation. Focus on making it clearer and more precise — not smaller.\n\n"
        prompt+="**What to improve:**\n"
        prompt+="- Technical accuracy: Are referenced files, APIs, patterns correct?\n"
        prompt+="- Clarity: Can each instruction only be interpreted ONE way?\n"
        prompt+="- Verifiability: Are success criteria code-checkable (not subjective)?\n"
        prompt+="- Completeness: Are all steps explicit (no assumed knowledge)?\n"
        prompt+="- Error handling: Are failure scenarios addressed?\n\n"
        prompt+="**Scope stays exactly as designed:**\n"
        prompt+="Validation improves HOW items are described, not WHETHER they're included. Every item exists because the human needs it. If you remove items during validation:\n"
        prompt+="- The human still needs those outcomes — they'll just have to request them again\n"
        prompt+="- They'll wait longer and explain context twice\n"
        prompt+="- A \"cleaner\" plan that misses their needs isn't actually better\n\n"
        prompt+="If something seems wrong or impossible, raise it as a question. The human decides what to keep or cut.\n\n"
        prompt+="Change to \`<!-- REVIEWED: YES -->\` when the plan is ready for implementation.\n\n"
        prompt+="---\n\n"
        prompt+="### Phase 3: Implement\n"
        prompt+="Execute 100% of the plan as written. The human designed this plan because they need these specific outcomes.\n\n"
        prompt+="**Why every item matters:**\n"
        prompt+="Skipping or simplifying items doesn't reduce work — it shifts work to the human. They'll discover the gaps, file follow-ups, re-explain context, and wait again. What could have been done once now takes multiple rounds. Implement completely the first time.\n\n"
        prompt+="**Implementation rules:**\n"
        prompt+="- Every step must be fully completed (not \"started\", not \"partially done\")\n"
        prompt+="- Every test must exist AND pass\n"
        prompt+="- If you encounter blockers, solve them or ask — don't skip\n"
        prompt+="- Zero TODO/FIXME comments in new code\n"
        prompt+="- All files created must be imported AND used (orphaned code = not implemented)\n\n"
        prompt+="**Patterns that shift work to the human:**\n"
        prompt+="- **'Effectively done'** — implicit completion can't be verified; make it explicit so they can see it works\n"
        prompt+="- **'Already working'** — what seems to work may not meet the plan's criteria; verify against the plan\n"
        prompt+="- **'Out of scope'** — the plan IS the scope; ask rather than skip\n"
        prompt+="- **'I interpret as...'** — reinterpretation that reduces work usually misses the human's intent; ask instead\n"
        prompt+="- **'This step isn't needed'** — each step exists because the human decided they need it; do it or ask\n\n"
        prompt+="**Plan file management:**\n"
        prompt+="DO NOT move plans between folders (drafts/, active/, completed/, abandoned/). Plan lifecycle is a human responsibility - the human uses plan-ops with proper approvals. Your role is to implement the plan's contents, not manage the plan file's location.\n\n"
        prompt+="**Before each step:** Briefly state what you're about to do and which plan item it addresses.\n\n"
        prompt+="Add \`<!-- VERIFIED: NO -->\` when implementation is complete.\n\n"
        prompt+="---\n\n"
        prompt+="### Phase 4: Verify\n"
        prompt+="Verify that 100% of objectives are met. The human will build on top of this work — gaps discovered later cost far more to fix than gaps caught now.\n\n"
        prompt+="**Verification Process (do each step explicitly):**\n"
        prompt+="1. **List each Goal** from the plan and state whether it's DONE or NOT DONE with evidence\n"
        prompt+="2. **List each Implementation Step** and confirm it was executed (not just started)\n"
        prompt+="3. **Run each Test** from the Testing Strategy and confirm it passes\n"
        prompt+="4. **Check each Completion Criterion** and state whether it's TRUE or FALSE\n\n"
        prompt+="**Why hedged verification hurts the human:**\n"
        prompt+="- **'Mostly done'** — the remaining part could be what they need most; they'll discover this at the worst time\n"
        prompt+="- **'Should work'** — untested code has bugs; they'll find them in production\n"
        prompt+="- **'Partially complete'** — they'll discover gaps when they try to use the work, after they've moved on\n"
        prompt+="- **'Works in most cases'** — the failing cases are often the ones that matter most to them\n\n"
        prompt+="**What Excellent Verification Looks Like:**\n"
        prompt+="- Checking every requirement, not just the ones you're confident about\n"
        prompt+="- Running tests and showing output, not just asserting they pass\n"
        prompt+="- Being honest about gaps - fixing them now is better than having the human discover them\n"
        prompt+="- Treating verification as a genuine quality check, not a formality\n\n"
        prompt+="**If ANY item fails verification:** Fix it first, then re-verify. Do not mark VERIFIED: YES with known gaps.\n\n"
        prompt+="Change to \`<!-- VERIFIED: YES -->\` only when every single item passes verification.\n\n"
        prompt+="---\n\n"
        prompt+="**To signal completion:** Output exactly \`<promise>$COMPLETION_PROMISE</promise>\` (the tag is \`promise\`, NOT \`prompt\`).\n"
        prompt+="Only output this when VERIFIED: YES and you have truly completed all work.\n"
    fi
    echo -e "$prompt"
}
FULL_PROMPT=$(build_prompt)

# State files for the loop
TIM_LOOP_SESSION_ID="$$"
TIM_LOOP_STATE_FILE="$HOME/.claude/.tim-loop-state-${TIM_LOOP_SESSION_ID}"
TIM_LOOP_PROMPT_FILE="$HOME/.claude/.tim-loop-prompt-${TIM_LOOP_SESSION_ID}"
TIM_LOOP_HOOK_SCRIPT="python3 ${PLUGIN_ROOT}/scripts/tim_loop_hook.py"

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
        for ht in ['stop', 'PreToolUse', 'SessionStart']:
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
REVIEW_MODE="$REVIEW_MODE"
MIN_REVIEW_ITERATIONS="$MIN_REVIEW_ITERATIONS"
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
MIN_PHASE_1_ITERATIONS="5"
MIN_PHASE_2_ITERATIONS="2"
MIN_PHASE_3_ITERATIONS="2"
MIN_PHASE_4_ITERATIONS="2"
MIN_PHASE_5_ITERATIONS="1"
MIN_PHASE_6_ITERATIONS="1"
PHASE_1_COMPLETE="false"
PHASE_2_COMPLETE="false"
PHASE_3_COMPLETE="false"
PHASE_4_COMPLETE="false"
PHASE_5_COMPLETE="false"
PHASE_6_COMPLETE="false"
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

try:
    with open(settings_file, 'r') as f:
        settings = json.load(f)
except:
    settings = {}

if 'hooks' not in settings:
    settings['hooks'] = {}

# SessionStart hook for prompt reinjection after context compaction
for hook_type, hook_cmd in [('stop', stop_hook), ('PreToolUse', permission_hook), ('SessionStart', prompt_manager_hook)]:
    if hook_type not in settings['hooks']:
        settings['hooks'][hook_type] = []
    entry = {"command": hook_cmd}
    if entry not in settings['hooks'][hook_type]:
        settings['hooks'][hook_type].append(entry)

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
print("Tim Loop hooks registered (stop, PreToolUse, SessionStart)")
PYTHON_EOF

echo -e "\nTim Loop: Starting iteration 1 of $MAX_ITERATIONS\n"
echo "$FULL_PROMPT"
