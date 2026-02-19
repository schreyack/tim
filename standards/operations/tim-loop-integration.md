# Tim Loop Integration Standard

This document defines how Tim Loop execution and review is integrated into TIM plan workflows.

---

## Overview

Tim Loop is a structured execution methodology with multiple modes:

### Implementation Mode (default)

A 6-step workflow for plan execution:

1. **Understand & Clarify** - State goal, rate confidence
2. **Analyze** - Break into discrete testable tasks
3. **Research** - Gather codebase context
4. **Plan** - Recursive convergence until DELTA=0
5. **Validate** - Devil's advocate check
6. **Execute** - Implement to 100% completion

### Review Modes (`--tech-review`, `--ai-ready`)

Two distinct review modes for improving plans:

- **Tech Review** (`--tech-review`): Skeptical senior engineer persona evaluating technical accuracy, feasibility, edge cases, and testability
- **AI-Ready Review** (`--ai-ready`): Tech lead persona ensuring instructions are unambiguous for AI implementation
- Each feeds the same prompt to Claude repeatedly while work persists in files
- Continues until completion criteria are met

### Verify Mode (`--verify`)

Post-implementation verification audit:

- Four phases: intent review, implementation audit, TIM rules check, gap remediation
- Creates remediation plans if gaps are found

**Purpose in TIM:** Ensure all active plans are executed with structured methodology, with mandatory review for multi-phase plans and human approval before execution begins.

---

## Review Modes (`--tech-review`, `--ai-ready`)

### When Review is Required

#### Mandatory: Multi-Phase Plans

Plans with **2 or more phases** MUST complete Plan Review before promotion from `drafts/` to `active/`.

**Detection:** Auto-detected by counting phase headers:

- `## Phase`, `### Phase`
- `Phase 1:`, `Phase 2:`, etc.

#### Exempt: Single-Phase Plans

Plans with 0-1 phases can be promoted directly without Plan Review.

### Review Workflow

```text
┌─────────────────────────────────────────────────────────────────┐
│                   PLAN REVIEW GATE WORKFLOW                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Create plan in plans/drafts/                                │
│     (auto-detects phase count, sets Plan Review status)         │
│           │                                                     │
│           ▼                                                     │
│  2. plan-ops review plans/drafts/my-plan.md                  │
│     → If single-phase: "Not required, can promote directly"     │
│     → If multi-phase: Shows Tim Loop review command to run      │
│           │                                                     │
│           ▼                                                     │
│  3. Run /tim-loop --tech-review command in Claude Code           │
│     (Iterates until TECH-REVIEW-DONE or max iterations)         │
│           │                                                     │
│           ▼                                                     │
│  4. plan-ops review plans/drafts/my-plan.md --mark-complete  │
│     (Updates Status Header: Plan Review = completed)            │
│           │                                                     │
│           ▼                                                     │
│  5. plan-ops promote plans/drafts/my-plan.md --approver "N"  │
│     (Promotion now allowed)                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Review Commands

#### Start Plan Review

```bash
plan-ops review plans/drafts/my-plan.md
```

**Output for multi-phase plans:**

- Shows phase count
- Outputs the exact `/tim-loop --tech-review` command to run
- Instructions for marking complete

**Output for single-phase plans:**

- Indicates Plan Review is not required
- Shows promote command

#### Mark Review Complete

```bash
plan-ops review plans/drafts/my-plan.md --mark-complete
```

Updates the plan's Status Header:

- `Plan Review: completed`
- `Review Date: [current date]`
- Progress Log entry: "Plan Review completed"

### Tim Loop Review Command Format

The standard command for plan review:

```bash
/tim-loop:tim-loop --tech-review plans/drafts/[plan-name].md --max-iterations 10
```

#### Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `--tech-review FILE` | Plan file path | Directs Tim Loop to perform technical review of the file |
| `--ai-ready FILE` | Plan file path | Directs Tim Loop to perform AI-readiness review of the file |
| `--verify FILE` | Plan file path | Directs Tim Loop to verify implementation of the plan |
| `--max-iterations` | `10` | Safety limit to prevent infinite loops |

#### What Review Mode Does

1. Reads the plan file
2. Analyzes for gaps, inconsistencies, missing details
3. Makes improvements directly to the plan file
4. Checks if more improvements are possible
5. Repeats until satisfied or max iterations reached
6. Outputs `<promise>DONEDONE</promise>` when complete

---

## Implementation Mode Execution

### Execution Workflow

```text
┌─────────────────────────────────────────────────────────────────┐
│                    PLAN EXECUTION WORKFLOW                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Plan promoted to active/ and marked AI Developer Ready      │
│           │                                                     │
│           ▼                                                     │
│  2. plan-ops execute plans/active/my-plan.md                 │
│     → Outputs tim-loop command                                  │
│           │                                                     │
│           ▼                                                     │
│  3. Run the /tim-loop command to execute the plan               │
│     (Tim Loop runs with structured methodology)                 │
│           │                                                     │
│           ▼                                                     │
│  4. plan-ops complete plans/active/my-plan.md                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Execution Commands

#### Execute Plan

```bash
plan-ops execute plans/active/my-plan.md
```

- Checks AI Developer Ready approval (required)
- Updates Status Header with execution fields
- Outputs the tim-loop command to run

#### Tim Loop Implement Command

When `execute` succeeds, it outputs:

```bash
/tim-loop:tim-loop --implement plans/active/[plan-name].md
```

---

## Status Header Fields

### Plan Review Fields

| Field | Value | Meaning | Promotion Allowed? |
|-------|-------|---------|-------------------|
| Plan Review | `required` | Multi-phase plan, review not done | NO |
| Plan Review | `completed` | Review finished | YES |
| Plan Review | `not-required` | Single-phase plan | YES |
| Review Date | `-` | Not applicable or not yet completed | - |
| Review Date | `YYYY-MM-DD` | When review was completed | - |

### Execution Fields

| Field | Value |
|-------|-------|
| Execution Approved | yes / no |
| Execution Approved By | [human name or "-"] |
| Execution Started | [YYYY-MM-DD HH:MM or "-"] |

---

## Integration with Plan Lifecycle

```text
Draft → Plan Review → Active → AI Developer Ready → Execute → Tim Loop → Completed
              ↓
    (multi-phase only)
```

### Full Lifecycle

1. **Draft** - Plan created in `plans/drafts/`
2. **Plan Review** - Multi-phase plans reviewed via Tim Loop `--tech-review` mode
3. **Promote** - Human approves, plan moves to `plans/active/`
4. **AI Developer Ready** - Human reviews plan for AI implementation concerns
5. **Execute** - Outputs the tim-loop command
6. **Tim Loop** - Plan executed via `--implement` mode
7. **Complete** - Plan moves to `plans/completed/`

---

## Best Practices

### When Creating Plans

1. Use meaningful phase names
2. Include clear completion criteria per phase
3. Add testing strategy for each phase
4. Consider dependencies between phases

### During Plan Review

1. Let the loop run to completion (or max iterations)
2. Review the changes made by each iteration
3. If the plan is significantly restructured, consider re-running
4. Trust the completion promise - if DONEDONE is output, review is thorough

### After Plan Review

1. Do a final human review before promotion
2. Ensure Plan Review shows "completed"
3. Proceed with confidence - the plan has been stress-tested

---

## Troubleshooting

### "BLOCKED: Multi-phase plan requires Plan Review"

Run the Plan Review workflow:

```bash
plan-ops review plans/drafts/my-plan.md
# Follow the displayed instructions
```

### Review Not Detecting Phases

Ensure phases are formatted correctly:

- `## Phase 1: Name` ✓
- `### Phase 2` ✓
- `Phase 3: Description` ✓
- `Step 1` ✗ (not detected as phase)

### Review Runs Forever

The `--max-iterations 10` parameter prevents infinite loops. If hitting max iterations without completion:

1. The task may be too complex
2. Consider breaking into smaller plans
3. Manually mark complete after reviewing iterations

### Execution started but tim-loop not running

After `execute` succeeds, you must manually run the `/tim-loop` command it outputs.

---

## Related Documentation

- `standards/operations/plan-management.md` - Full plan lifecycle documentation
- `CLAUDE.md` - Project instructions including execution requirements
