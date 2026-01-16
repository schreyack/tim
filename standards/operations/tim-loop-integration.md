# Tim Loop Integration Standard

This document defines how Tim Loop execution is integrated into TIM plan workflows.

---

## Overview

Tim Loop is a structured execution methodology that wraps Ralph Loop with a 6-step workflow. It provides:

1. **Understand & Clarify** - State goal, rate confidence
2. **Analyze** - Break into discrete testable tasks
3. **Research** - Gather codebase context
4. **Plan** - Recursive convergence until DELTA=0
5. **Validate** - Devil's advocate check
6. **Execute** - Implement to 100% completion

**Purpose in TIM:** Ensure all active plans are executed with the structured Tim Loop methodology, with mandatory human approval before execution begins.

---

## Hard Enforcement

### Why Hard Enforcement?

AI developers can produce plausible-looking work while bypassing safeguards. The execution gate prevents:

- AI executing plans without human oversight
- Plans being implemented incorrectly or incompletely
- Bypassing the approval process via flags or workarounds

### Attack Vectors Blocked

| Attack Vector | Defense |
|---------------|---------|
| AI adds `--approver` flag | No such flag - approval is separate command |
| AI runs approve-execute | Can't - requires separate terminal session |
| AI guesses request ID | Random UUID, time-limited |
| AI waits indefinitely | Tokens expire (15 min default) |
| AI modifies approval files | Files are validated on read |

---

## Execution Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│              PLAN EXECUTION WORKFLOW (HARD ENFORCED)             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Plan promoted to active/ (existing workflow)                │
│           │                                                     │
│           ▼                                                     │
│  2. AI: ./tools/plan-ops.sh execute plans/active/my-plan.md     │
│     → Creates approval request, outputs request ID              │
│     → BLOCKED - no tim-loop command yet                         │
│           │                                                     │
│           ▼                                                     │
│  3. HUMAN (separate terminal):                                  │
│     ./tools/plan-ops.sh approve-execute <request-id>            │
│        --approver "Name"                                        │
│     → Validates and approves request                            │
│           │                                                     │
│           ▼                                                     │
│  4. AI: ./tools/plan-ops.sh execute plans/active/my-plan.md     │
│     → Finds valid approval                                      │
│     → Outputs tim-loop command                                  │
│           │                                                     │
│           ▼                                                     │
│  5. Run the /tim-loop command to execute the plan               │
│     (Tim Loop runs with structured 6-step methodology)          │
│           │                                                     │
│           ▼                                                     │
│  6. ./tools/plan-ops.sh complete plans/active/my-plan.md        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Commands

### Request Execution

```bash
./tools/plan-ops.sh execute plans/active/my-plan.md
```

**First call (no approval):**
- Creates approval request file: `.tim-execution-requests/<request-id>.json`
- Outputs request ID and approval command
- Exits with error (BLOCKED)

**After approval:**
- Finds valid approval for this plan
- Updates Status Header with execution approval
- Outputs the tim-loop command to run

### Approve Execution (Human Only)

```bash
./tools/plan-ops.sh approve-execute <request-id> --approver "Name"
```

- **Must be run in a separate terminal by a human**
- Validates request exists and is not expired
- Marks approval in request file
- Updates plan Status Header

### Tim Loop Command Format

When `execute` succeeds, it outputs:

```bash
/tim-loop "implement plans/active/[plan-name]. you are not done until all iterations and phases of the plan are complete."
```

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

## Status Header Fields

| Field | Value |
|-------|-------|
| Execution Approved | yes / no |
| Execution Approved By | [human name or "-"] |
| Execution Started | [YYYY-MM-DD HH:MM or "-"] |

These fields are updated when execution is approved and started.

---

## Configuration

| Setting | Value | Description |
|---------|-------|-------------|
| `EXECUTION_EXPIRY_MINUTES` | 15 | Time before approval request expires |
| `EXECUTION_REQUESTS_DIR` | `.tim-execution-requests` | Directory for request files |

---

## Integration with Plan Lifecycle

```
Draft → Ralph Review → Active → Execution Approval → Tim Loop → Completed
                  ↓
        (multi-phase only)
```

### Full Lifecycle

1. **Draft** - Plan created in `plans/drafts/`
2. **Ralph Review** - Multi-phase plans reviewed via Ralph Loop
3. **Promote** - Human approves, plan moves to `plans/active/`
4. **Execute Request** - AI requests execution approval
5. **Human Approval** - Human approves in separate terminal
6. **Tim Loop** - Plan executed via structured methodology
7. **Complete** - Plan moves to `plans/completed/`

---

## Troubleshooting

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
- `standards/operations/ralph-loop-integration.md` - Ralph Loop for plan review
- `CLAUDE.md` - Project instructions including execution requirements
