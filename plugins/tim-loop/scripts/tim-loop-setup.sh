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
  Tech Review:              /tim-loop --tech-review plans/drafts/my-plan.md
  AI-Ready Review:          /tim-loop --ai-ready plans/active/my-plan.md
  Verify Implementation:    /tim-loop --verify plans/active/my-plan.md
  Quick Mode:               /tim-loop --no-review "fix typo"
  Wizard Mode:              /tim-loop --wizard plans/active/my-plan.md

MODIFIER OPTIONS:
  --force, -f               Override existing active session detection
  --no-verify               Skip verification phase (WARNING: incomplete work)
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
NO_REVIEW=false NO_VERIFY=false
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
            [[ -n "$REVIEW_MODE" ]] && echo "Error: --tech-review and --ai-ready cannot be used together" >&2 && exit 1
            REVIEW_FILE="$2"; REVIEW_MODE="ai-ready"; shift 2 ;;
        --verify)
            [[ -z "${2:-}" ]] && echo "Error: --verify requires a file path" >&2 && exit 1
            [[ ! -f "$2" ]] && echo "Error: Plan file not found: $2" >&2 && exit 1
            VERIFY_FILE="$2"; shift 2 ;;
        --no-review) NO_REVIEW=true; shift ;;
        --no-verify) NO_VERIFY=true; shift ;;
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
        prompt+="### Your Persona\n"
        prompt+="Think like a senior engineer who has seen plans fail in production. You're not hostile - you genuinely want this plan to succeed. But you know that vague plans produce buggy code, missing edge cases cause outages, and untestable criteria lead to \"works on my machine\" outcomes. Your skepticism protects the team.\n\n"
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
        prompt+="### Scope is Locked\n"
        prompt+="The human designed this plan with specific intentions. Your role:\n"
        prompt+="- **Preserve the goal** as the human defined it\n"
        prompt+="- **Keep all items** - difficulty is expected, not a reason to remove\n"
        prompt+="- **Improve clarity and correctness** - make the plan more precise, not different\n"
        prompt+="- **Flag genuine risks** as questions, not deletions\n\n"
        prompt+="### What Excellent Tech Review Looks Like\n"
        prompt+="- Reading the entire plan before making any changes\n"
        prompt+="- Verifying that referenced files/APIs actually exist in the codebase\n"
        prompt+="- Adding specific edge cases the author likely didn't consider\n"
        prompt+="- Tightening vague criteria into concrete, testable statements\n"
        prompt+="- Raising genuine concerns as questions for the author\n"
        prompt+="- Making the plan MORE specific and MORE robust, not less\n\n"
        prompt+="Iterate until the plan is technically sound. Raise concerns rather than declaring completion with doubts.\n\n"
        prompt+="Output <promise>$COMPLETION_PROMISE</promise> only when the plan is technically solid AND you have no outstanding concerns.\n"
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
        prompt+="### Scope is Locked\n"
        prompt+="The human designed this plan with specific intentions. Your role:\n"
        prompt+="- **Preserve the goal** as the human defined it\n"
        prompt+="- **Make instructions AI-proof** - remove ambiguity, add explicit details\n"
        prompt+="- **Clarify, don't redesign** - improve clarity while keeping direction\n\n"
        prompt+="### What Excellent AI-Ready Review Looks Like\n"
        prompt+="- Replacing every vague instruction with a specific one\n"
        prompt+="- Adding explicit error handling where the plan says \"handle errors\"\n"
        prompt+="- Specifying exact file paths, function signatures, and return types\n"
        prompt+="- Converting subjective criteria to objective, code-checkable ones\n"
        prompt+="- Ensuring an AI developer could complete this plan without asking any questions\n\n"
        prompt+="Iterate until the plan is AI-implementation-ready. If you have doubts about how an AI would interpret something, clarify it.\n\n"
        prompt+="Output <promise>$COMPLETION_PROMISE</promise> only when the plan is fully AI-ready AND you have no concerns about ambiguity.\n"
    elif [[ -n "$VERIFY_FILE" ]]; then
        prompt+="## Mode: Verification Audit\n\n"
        prompt+="You are auditing whether $VERIFY_FILE was fully and correctly implemented.\n\n"
        prompt+="### Why Verification Matters\n"
        prompt+="The human invested time designing this plan because they need specific outcomes. Partial implementation means they'll discover gaps in production or have to file another request. Thorough verification now saves everyone time and builds trust that completed work is genuinely complete.\n\n"
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
        prompt+="### Verification Means Certainty\n"
        prompt+="These common phrases signal incomplete verification - here's why each matters:\n\n"
        prompt+="- **'Mostly done'** means the remaining part could be the part the human cares about most\n"
        prompt+="- **'Should work'** means it hasn't been tested - and untested code has bugs\n"
        prompt+="- **'Partially complete'** means the human will discover the missing parts later, at a worse time\n"
        prompt+="- **'Works in most cases'** means there are known cases where it fails, which need fixing\n\n"
        prompt+="If ANY item fails verification: Fix it first, then re-verify.\n\n"
        prompt+="Output <promise>$COMPLETION_PROMISE</promise> only when every single requirement is verified as fully implemented.\n"
    elif [[ -n "$IMPLEMENT_FILE" ]]; then
        prompt+="## Mode: Implement Existing Plan\n\n"
        prompt+="### Plan to Implement\n\`\`\`markdown\n$(cat "$IMPLEMENT_FILE")\n\`\`\`\n\n"
        prompt+="### Mindset: Fulfill the Human's Intent\n"
        prompt+="A human carefully designed this plan because they need specific outcomes. Your job is to deliver those outcomes faithfully. When the plan says to do something, it's because the human needs it done - not because they forgot to consider whether it was necessary.\n\n"
        prompt+="Genuine completion is more valuable than technical compliance. The goal is for the plan's author to look at the result and say 'Yes, this is exactly what I meant' - which happens when you focus on the spirit of what they asked for, not just the literal words.\n\n"
        prompt+="### Why These Rules Matter\n"
        prompt+="1. **Implement 100% of this plan exactly as written** - because the human designed each part knowing what they need. Partial implementation means they'll need to do more work later or file another request.\n"
        prompt+="2. **Keep the plan's scope intact** - because the human scoped this task knowing what they need. If you believe something should change, ask - they may have context you don't.\n"
        prompt+="3. **Ask when uncertain** - because assumptions that reduce work often miss the human's actual intent. A quick question saves hours of rework.\n"
        prompt+="4. **Your objective is to accomplish the goal** - because the human is counting on this being done. They'll build on top of this work.\n\n"
        prompt+="### Patterns That Cause Problems\n"
        prompt+="These patterns feel efficient but create real issues:\n\n"
        prompt+="- **'Effectively done'** - The human can't verify implicit completion. Making it explicit means they can see it works and trust the result.\n"
        prompt+="- **'Already working'** - What seems to work may not meet the plan's specific criteria. Verifying against the plan catches subtle mismatches.\n"
        prompt+="- **'Out of scope'** - The plan defines the scope. If something feels out of place, it's worth asking about rather than skipping.\n"
        prompt+="- **'I interpret this as...'** - Reinterpretation that reduces work often misses the human's intent. Asking takes seconds; redoing takes hours.\n"
        prompt+="- **'Started' / 'attempted'** - The human needs finished work, not progress updates. Completion means the outcome exists and works.\n"
        prompt+="- **'Not needed because...'** - Each step exists because the human thought about it. If it truly isn't needed, they'll confirm when asked.\n"
        prompt+="- **'Previous step covers this'** - Steps are explicit because the human wants each outcome verified individually.\n\n"
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
        prompt+="Output <promise>$COMPLETION_PROMISE</promise> only when VERIFIED: YES and you have genuinely completed everything.\n"
    elif [[ "$PLAN_ONLY" == true ]]; then
        prompt+="## Mode: Plan Only\n\n"
        prompt+="Create a comprehensive plan at $PLAN_FILEPATH that fully addresses the task.\n\n"
        prompt+="### Mindset: Capture the Full Intent\n"
        prompt+="Your job is to translate the human's goal into a complete, actionable plan. Capture what they ACTUALLY want, not a simplified version that's easier to describe. If the task is ambitious, the plan should be ambitious. You're designing a blueprint that will be implemented faithfully - make it thorough.\n\n"
        prompt+="### Why These Rules Matter\n"
        prompt+="1. **The plan must fully accomplish the stated goal** - because the human will implement exactly what you write. A partial plan produces a partial result, and they'll need to come back for the rest.\n"
        prompt+="2. **Preserve the full scope** - because the human designed this task knowing what they need. A reduced version means they'll need to do more work later or file another request.\n"
        prompt+="3. **If you're uncertain about requirements or approach, ask the human** - because guessing wrong means the plan will be wrong, and implementation will be wasted effort.\n"
        prompt+="4. **Ask when uncertain** - Multiple valid approaches? Unclear requirements? Ask.\n"
        prompt+="5. **Your objective is to create a plan that accomplishes the goal** - because the human is counting on this plan to guide implementation of exactly what they need.\n\n"
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
        prompt+="You will complete this task through four phases. Your objective is to fully accomplish the goal - the human is counting on the result.\n\n"
        prompt+="### Mindset: Fulfill the Human's Intent\n"
        prompt+="Throughout all phases, focus on what the human actually wants - the outcome they're investing in. When you're unsure about something, ask. When something is difficult, that's the work. The human designed this task knowing what they need; your job is to deliver it.\n\n"
        prompt+="### Guiding Principles\n"
        prompt+="1. **Preserve the scope exactly** - The task defines the work, and each part matters to the human\n"
        prompt+="2. **Ask before changing scope** - The human may have context you don't; a quick question prevents misaligned work\n"
        prompt+="3. **Your goal is completion** - Solve problems rather than documenting why they can't be solved\n"
        prompt+="4. **Ask when uncertain** - Multiple valid approaches? Unclear requirements? Ask.\n"
        prompt+="5. **Blockers are problems to solve** - If stuck, ask for help rather than skipping\n\n"
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
        prompt+="Review your plan to ensure it's ready for implementation. Focus on technical accuracy and clarity, not scope changes.\n\n"
        prompt+="**What to improve (Technical & Clarity):**\n"
        prompt+="- Technical accuracy: Are referenced files, APIs, patterns correct?\n"
        prompt+="- Clarity: Can each instruction only be interpreted ONE way?\n"
        prompt+="- Verifiability: Are success criteria code-checkable (not subjective)?\n"
        prompt+="- Completeness: Are all steps explicit (no assumed knowledge)?\n"
        prompt+="- Error handling: Are failure scenarios addressed?\n\n"
        prompt+="**Why scope stays locked:**\n"
        prompt+="Review improves clarity and correctness, not direction. The human designed the scope knowing what they need. If you find something that seems wrong about the scope itself, raise it as a question - the human may have context that explains why it's there.\n\n"
        prompt+="Change to \`<!-- REVIEWED: YES -->\` when the plan is ready for implementation.\n\n"
        prompt+="---\n\n"
        prompt+="### Phase 3: Implement\n"
        prompt+="Execute 100% of the plan as written. Focus on delivering the outcomes the human designed this plan to achieve.\n\n"
        prompt+="**Implementation rules:**\n"
        prompt+="- Every step must be fully completed (not \"started\", not \"partially done\")\n"
        prompt+="- Every test must exist AND pass\n"
        prompt+="- If you encounter blockers, solve them or ask - don't skip\n"
        prompt+="- Zero TODO/FIXME comments in new code\n"
        prompt+="- All files created must be imported AND used (orphaned code = not implemented)\n\n"
        prompt+="**Patterns that feel efficient but cause rework:**\n"
        prompt+="- **'Effectively done'** - The human can't verify implicit completion; making it explicit lets them see it works and trust the result\n"
        prompt+="- **'Already working'** - What seems to work may not meet the plan's specific criteria; verify against the plan\n"
        prompt+="- **'Out of scope'** - The plan defines scope; if something feels out of place, ask rather than skip\n"
        prompt+="- **'I interpret as...'** - Reinterpretation that reduces work often misses the human's intent; ask instead\n"
        prompt+="- **'This step isn't needed'** - Each step exists because the human considered it; do it or ask why it's there\n\n"
        prompt+="**Plan file management:**\n"
        prompt+="DO NOT move plans between folders (drafts/, active/, completed/, abandoned/). Plan lifecycle is a human responsibility - the human uses plan-ops with proper approvals. Your role is to implement the plan's contents, not manage the plan file's location.\n\n"
        prompt+="**Before each step:** Briefly state what you're about to do and which plan item it addresses.\n\n"
        prompt+="Add \`<!-- VERIFIED: NO -->\` when implementation is complete.\n\n"
        prompt+="---\n\n"
        prompt+="### Phase 4: Verify\n"
        prompt+="Verify that 100% of objectives are met. This matters because the human will build on top of this work - gaps discovered later are far more costly to fix.\n\n"
        prompt+="**Verification Process (do each step explicitly):**\n"
        prompt+="1. **List each Goal** from the plan and state whether it's DONE or NOT DONE with evidence\n"
        prompt+="2. **List each Implementation Step** and confirm it was executed (not just started)\n"
        prompt+="3. **Run each Test** from the Testing Strategy and confirm it passes\n"
        prompt+="4. **Check each Completion Criterion** and state whether it's TRUE or FALSE\n\n"
        prompt+="**Verification means certainty:**\n"
        prompt+="- **'Mostly done'** means the remaining part could be the part the human cares about most\n"
        prompt+="- **'Should work'** means it hasn't been tested - and untested code has bugs\n"
        prompt+="- **'Partially complete'** means the human will discover the missing parts later, at a worse time\n"
        prompt+="- **'Works in most cases'** means there are known cases where it fails, which need fixing\n\n"
        prompt+="**What Excellent Verification Looks Like:**\n"
        prompt+="- Checking every requirement, not just the ones you're confident about\n"
        prompt+="- Running tests and showing output, not just asserting they pass\n"
        prompt+="- Being honest about gaps - fixing them now is better than having the human discover them\n"
        prompt+="- Treating verification as a genuine quality check, not a formality\n\n"
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
REVIEW_MODE="$REVIEW_MODE"
MIN_REVIEW_ITERATIONS="$MIN_REVIEW_ITERATIONS"
EOF

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
