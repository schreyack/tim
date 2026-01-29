#!/usr/bin/env bash
# plan-ops/commands-utility.sh - Utility commands
# Part of plan-ops.sh modular refactor
#
# Dependencies: core.sh
# Exports: cmd_list, cmd_help
#
# This file is sourced by plan-ops.sh, not executed directly.
# shellcheck source=plan-ops/core.sh

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This module must be sourced, not executed directly" >&2
    exit 1
fi

# =============================================================================
# LIST COMMAND
# =============================================================================

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

# =============================================================================
# HELP COMMAND
# =============================================================================

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

    review <plan-file> [--mark-complete]
        Start or complete Plan Review for a draft plan
        - Without flags: Shows the Tim Loop review command to run
        - With --mark-complete: Marks review as done (required before promote)
        Multi-phase plans (2+ phases) MUST complete Plan Review before promotion

    promote <plan-file> --approver <name>
        Move plan from drafts to active (requires human approver)
        BLOCKED for multi-phase plans until Plan Review is completed

    ai-ready <plan-file> --reviewer <name> [--iteration <n>]
        Mark plan as AI Developer Ready after human review
        - Only works on active/ plans (must promote first)
        - Required before execute will succeed
        - Adds approval stamp to plan file
        See: standards/enforcement/ai-developer-ready-checklist.md

    execute <plan-file>
        Output tim-loop command for an active plan
        Requires AI Developer Ready approval before it will succeed

    fast-track <plan-file> --approver <name> [--reason <reason>]
        Skip the normal approval workflow and go directly to implementation
        - Works with plans in ~/.claude/plans/, drafts/, or active/
        - Auto-imports from ~/.claude/plans/ if needed
        - Auto-promotes from drafts/ to active/ if needed
        - Marks Plan Review as completed
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

PLAN REVIEW WORKFLOW:
    Multi-phase plans require Plan Review before promotion:

    1. $SCRIPT_PATH review plans/drafts/my-plan.md
       (Shows the Tim Loop review command to run)

    2. Run the displayed /tim-loop --tech-review command in Claude Code

    3. $SCRIPT_PATH review plans/drafts/my-plan.md --mark-complete
       (Marks review as done)

    4. $SCRIPT_PATH promote plans/drafts/my-plan.md --approver "Name"
       (Now promotion is allowed)

EXECUTION WORKFLOW:
    Active plans with AI Developer Ready approval can be executed:

    1. $SCRIPT_PATH execute plans/active/my-plan.md
       → Outputs /tim-loop:tim-loop command

    2. Run the /tim-loop:tim-loop command to execute the plan

    3. $SCRIPT_PATH complete plans/active/my-plan.md

FAST-TRACK WORKFLOW:
    For well-established plans that have already been reviewed:

    $SCRIPT_PATH fast-track <plan-file> --approver "Name" --reason "reason"

    This single command:
    - Imports from ~/.claude/plans/ if needed
    - Promotes from drafts/ to active/ if needed
    - Marks Plan Review as completed
    - Marks AI Developer Ready as yes
    - Marks execution as approved
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
    1. Detect current state (import, review, promote, etc.)
    2. Show the appropriate command or prompt for input
    3. Wait for external steps (Plan Review, approval, Tim Loop)
    4. Track file moves automatically
    5. Offer optional verification tim-loop before marking complete
    6. Continue until plan reaches completed state

    VERIFICATION TIM-LOOP (optional):
    The wizard offers to run a verification tim-loop that:
    - Reviews the original intent of the plan
    - Audits implementation to ensure it matches intent
    - Verifies TIM Project rules are followed
    - Checks for stubs, TODOs, deferred work, or cheating
    - Creates and executes remediation plans if gaps found
    - Iterates with NO LIMIT until 100% complete

    This is offered:
    - Before marking a plan complete (during normal workflow)
    - When running wizard on an already-completed plan (re-verification)

    Use --status to check state without entering the wizard:
    $SCRIPT_PATH wizard <plan-file> --status

EXAMPLES:
    $SCRIPT_PATH init
    $SCRIPT_PATH import ~/.claude/plans/xyz.md --name "feature-auth"
    $SCRIPT_PATH review plans/drafts/2025-01-16-feature-auth.md
    $SCRIPT_PATH review plans/drafts/2025-01-16-feature-auth.md --mark-complete
    $SCRIPT_PATH promote plans/drafts/2025-01-16-feature-auth.md --approver "Tim"
    $SCRIPT_PATH execute plans/active/2025-01-16-feature-auth.md
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
