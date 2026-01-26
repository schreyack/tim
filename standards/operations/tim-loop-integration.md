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

### Review Mode (`--review`)
An iterative review methodology for improving plans:
- Feeds the same prompt to Claude repeatedly while work persists in files
- Each iteration sees previous work, enabling incremental improvement
- Continues until completion criteria are met (DONEDONE by default)

**Purpose in TIM:** Ensure all active plans are executed with structured methodology, with mandatory review for multi-phase plans and human approval before execution begins.

---

## Review Mode (`--review`)

### When Review is Required

#### Mandatory: Multi-Phase Plans

Plans with **2 or more phases** MUST complete Plan Review before promotion from `drafts/` to `active/`.

**Detection:** Auto-detected by counting phase headers:
- `## Phase`, `### Phase`
- `Phase 1:`, `Phase 2:`, etc.

#### Exempt: Single-Phase Plans

Plans with 0-1 phases can be promoted directly without Plan Review.

### Review Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                   PLAN REVIEW GATE WORKFLOW                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Create plan in plans/drafts/                                │
│     (auto-detects phase count, sets Plan Review status)         │
│           │                                                     │
│           ▼                                                     │
│  2. plan-ops.sh review plans/drafts/my-plan.md                  │
│     → If single-phase: "Not required, can promote directly"     │
│     → If multi-phase: Shows Tim Loop review command to run      │
│           │                                                     │
│           ▼                                                     │
│  3. Run /tim-loop --review command in Claude Code               │
│     (Iterates until DONEDONE promise or max iterations)         │
│           │                                                     │
│           ▼                                                     │
│  4. plan-ops.sh review plans/drafts/my-plan.md --mark-complete  │
│     (Updates Status Header: Plan Review = completed)            │
│           │                                                     │
│           ▼                                                     │
│  5. plan-ops.sh promote plans/drafts/my-plan.md --approver "N"  │
│     (Promotion now allowed)                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Review Commands

#### Start Plan Review

```bash
plan-ops.sh review plans/drafts/my-plan.md
```

**Output for multi-phase plans:**
- Shows phase count
- Outputs the exact `/tim-loop --review` command to run
- Instructions for marking complete

**Output for single-phase plans:**
- Indicates Plan Review is not required
- Shows promote command

#### Mark Review Complete

```bash
plan-ops.sh review plans/drafts/my-plan.md --mark-complete
```

Updates the plan's Status Header:
- `Plan Review: completed`
- `Review Date: [current date]`
- Progress Log entry: "Plan Review completed"

### Tim Loop Review Command Format

The standard command for plan review:

```bash
/tim-loop:tim-loop --review plans/drafts/[plan-name].md --max-iterations 10 --completion-promise "DONEDONE"
```

#### Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `--review FILE` | Plan file path | Directs Tim Loop to review and improve the file |
| `--max-iterations` | `10` | Safety limit to prevent infinite loops |
| `--completion-promise` | `DONEDONE` | Signal phrase when no more improvements possible |

#### What Review Mode Does

1. Reads the plan file
2. Analyzes for gaps, inconsistencies, missing details
3. Makes improvements directly to the plan file
4. Checks if more improvements are possible
5. Repeats until satisfied or max iterations reached
6. Outputs `<promise>DONEDONE</promise>` when complete

---

## Implementation Mode Execution

### Hard Enforcement

#### Why Hard Enforcement?

AI developers can produce plausible-looking work while bypassing safeguards. The execution gate prevents:

- AI executing plans without human oversight
- Plans being implemented incorrectly or incompletely
- Bypassing the approval process via flags or workarounds

#### Attack Vectors Blocked

| Attack Vector | Defense |
|---------------|---------|
| AI adds `--approver` flag | No such flag - approval is separate command |
| AI runs approve-execute | Can't - requires separate terminal session |
| AI guesses request ID | Random UUID, time-limited |
| AI waits indefinitely | Tokens expire (15 min default) |
| AI modifies approval files | Files are validated on read |

### Execution Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│              PLAN EXECUTION WORKFLOW (HARD ENFORCED)            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Plan promoted to active/ (existing workflow)                │
│           │                                                     │
│           ▼                                                     │
│  2. AI: plan-ops.sh execute plans/active/my-plan.md             │
│     → Creates approval request, outputs request ID              │
│     → BLOCKED - no tim-loop command yet                         │
│           │                                                     │
│           ▼                                                     │
│  3. HUMAN (separate terminal):                                  │
│     plan-ops.sh approve-execute <request-id> --approver "Name"  │
│     → Validates and approves request                            │
│           │                                                     │
│           ▼                                                     │
│  4. AI: plan-ops.sh execute plans/active/my-plan.md             │
│     → Finds valid approval                                      │
│     → Outputs tim-loop command                                  │
│           │                                                     │
│           ▼                                                     │
│  5. Run the /tim-loop command to execute the plan               │
│     (Tim Loop runs with structured methodology)                 │
│           │                                                     │
│           ▼                                                     │
│  6. plan-ops.sh complete plans/active/my-plan.md                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Execution Commands

#### Request Execution

```bash
plan-ops.sh execute plans/active/my-plan.md
```

**First call (no approval):**
- Creates approval request file: `.tim-execution-requests/<request-id>.json`
- Outputs request ID and approval command
- Exits with error (BLOCKED)

**After approval:**
- Finds valid approval for this plan
- Updates Status Header with execution approval
- Outputs the tim-loop command to run

#### Approve Execution (Human Only)

```bash
plan-ops.sh approve-execute <request-id> --approver "Name"
```

- **Must be run in a separate terminal by a human**
- Validates request exists and is not expired
- Marks approval in request file
- Updates plan Status Header

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

Note: For backward compatibility, `Ralph Review` and `Ralph Date` field names are also recognized.

### Execution Fields

| Field | Value |
|-------|-------|
| Execution Approved | yes / no |
| Execution Approved By | [human name or "-"] |
| Execution Started | [YYYY-MM-DD HH:MM or "-"] |

---

## Approval Request Files

### Location

`.tim-execution-requests/<request-id>.json`

### Format

```json
{
  "request_id": "abc12345",
  "plan_file": "plans/active/my-plan.md",
  "created_at": "2026-01-16T12:00:00Z",
  "expires_at": "2026-01-16T12:15:00Z",
  "approved": false,
  "approved_by": null,
  "approved_at": null
}
```

### After Approval

```json
{
  "request_id": "abc12345",
  "plan_file": "plans/active/my-plan.md",
  "created_at": "2026-01-16T12:00:00Z",
  "expires_at": "2026-01-16T12:15:00Z",
  "approved": true,
  "approved_by": "Tim",
  "approved_at": "2026-01-16T12:05:00Z"
}
```

---

## Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| `EXECUTION_EXPIRY_MINUTES` | 15 | Time before approval request expires |
| `EXECUTION_REQUESTS_DIR` | `.tim-execution-requests` | Directory for request files |

---

## Integration with Plan Lifecycle

```
Draft → Plan Review → Active → Execution Approval → Tim Loop → Completed
              ↓
    (multi-phase only)
```

### Full Lifecycle

1. **Draft** - Plan created in `plans/drafts/`
2. **Plan Review** - Multi-phase plans reviewed via Tim Loop `--review` mode
3. **Promote** - Human approves, plan moves to `plans/active/`
4. **Execute Request** - AI requests execution approval
5. **Human Approval** - Human approves in separate terminal
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
plan-ops.sh review plans/drafts/my-plan.md
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

### "BLOCKED: Execution requires human approval"

This is expected. A human must run the approve-execute command in a separate terminal.

### "Request not found"

The request ID may be incorrect, or the request may have expired. Have AI create a new request with `execute`.

### "Request has EXPIRED"

Approval requests expire after 15 minutes. Create a new request by running `execute` again.

### Execution started but tim-loop not running

After `execute` succeeds, you must manually run the `/tim-loop` command it outputs.

---

## Related Documentation

- `standards/operations/plan-management.md` - Full plan lifecycle documentation
- `CLAUDE.md` - Project instructions including execution requirements
