# Ralph Loop Integration Standard

This document defines how Ralph Loop is integrated into TIM plan workflows.

---

## Overview

Ralph Loop is an iterative AI review methodology that feeds the same prompt to Claude repeatedly while work persists in files. Each iteration sees previous work, enabling incremental improvement until completion criteria are met.

**Purpose in TIM:** Enforce iterative review of multi-phase plans before promotion, catching gaps and improving quality before execution begins.

---

## When Ralph Loop is Required

### Mandatory: Multi-Phase Plans

Plans with **2 or more phases** MUST complete Ralph Loop review before promotion from `drafts/` to `active/`.

**Detection:** Auto-detected by counting phase headers:
- `## Phase`, `### Phase`
- `Phase 1:`, `Phase 2:`, etc.

### Exempt: Single-Phase Plans

Plans with 0-1 phases can be promoted directly without Ralph Loop review.

---

## Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    RALPH LOOP GATE WORKFLOW                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Create plan in plans/drafts/                                │
│     (auto-detects phase count, sets Ralph Review status)        │
│           │                                                     │
│           ▼                                                     │
│  2. ./plugins/tim-loop/scripts/plan-ops.sh ralph plans/drafts/my-plan.md           │
│     → If single-phase: "Not required, can promote directly"     │
│     → If multi-phase: Shows Ralph Loop command to run           │
│           │                                                     │
│           ▼                                                     │
│  3. Run /ralph-loop command in Claude Code                      │
│     (Iterates until DONEDONE promise or max iterations)         │
│           │                                                     │
│           ▼                                                     │
│  4. ./plugins/tim-loop/scripts/plan-ops.sh ralph plans/drafts/my-plan.md           │
│        --mark-complete                                          │
│     (Updates Status Header: Ralph Review = completed)           │
│           │                                                     │
│           ▼                                                     │
│  5. ./plugins/tim-loop/scripts/plan-ops.sh promote plans/drafts/my-plan.md         │
│        --approver "Name"                                        │
│     (Promotion now allowed)                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Commands

### Start Ralph Loop Review

```bash
./plugins/tim-loop/scripts/plan-ops.sh ralph plans/drafts/my-plan.md
```

**Output for multi-phase plans:**
- Shows phase count
- Outputs the exact `/ralph-loop` command to run
- Instructions for marking complete

**Output for single-phase plans:**
- Indicates Ralph Loop is not required
- Shows promote command

### Mark Ralph Loop Complete

```bash
./plugins/tim-loop/scripts/plan-ops.sh ralph plans/drafts/my-plan.md --mark-complete
```

Updates the plan's Status Header:
- `Ralph Review: completed`
- `Ralph Date: [current date]`
- Progress Log entry: "Ralph Loop review completed"

### Attempt Promotion

```bash
./plugins/tim-loop/scripts/plan-ops.sh promote plans/drafts/my-plan.md --approver "Name"
```

**If multi-phase and Ralph not completed:**
- BLOCKED with error message
- Shows commands to run Ralph Loop

**If single-phase OR Ralph completed:**
- Promotion proceeds normally

---

## Ralph Loop Command Format

The standard Ralph Loop command for plan review:

```bash
/ralph-loop:ralph-loop "review plans/drafts/[plan-name] and look for areas to improve. iterate multiple times until there are no more improvements possible. <promise>DONEDONE</promise>" --max-iterations 10 --completion-promise "DONEDONE"
```

### Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| Prompt | `review plans/drafts/[plan-name]...` | Directs Claude to review and improve the plan |
| `--max-iterations` | `10` | Safety limit to prevent infinite loops |
| `--completion-promise` | `DONEDONE` | Signal phrase when no more improvements possible |

### What Ralph Loop Does

1. Reads the plan file
2. Analyzes for gaps, inconsistencies, missing details
3. Makes improvements directly to the plan file
4. Checks if more improvements are possible
5. Repeats until satisfied or max iterations reached
6. Outputs `<promise>DONEDONE</promise>` when complete

---

## Status Header Fields

### Ralph Review

| Value | Meaning | Promotion Allowed? |
|-------|---------|-------------------|
| `required` | Multi-phase plan, Ralph not done | NO |
| `completed` | Ralph Loop finished | YES |
| `not-required` | Single-phase plan | YES |

### Ralph Date

- `-` if not applicable or not yet completed
- `YYYY-MM-DD` when Ralph Loop was completed

---

## Why This Matters

### Defense Against AI Planning Errors

AI can produce plausible-sounding plans with subtle issues:
- Missing edge cases
- Incomplete testing strategies
- Unrealistic scope estimates
- Inconsistent approach across phases

Ralph Loop catches these through iterative self-review.

### Quality Threshold Before Execution

A plan that survives 10 iterations of Ralph Loop review is more likely to:
- Have complete coverage of requirements
- Include realistic implementation steps
- Have coherent testing strategy
- Be ready for execution without major rework

### Audit Trail

The Ralph Review fields in Status Header provide:
- Evidence that review occurred
- Date of review completion
- Clear gate enforcement

---

## Integration with Plan Lifecycle

```
Draft Creation
    │
    ▼
[Multi-phase?] ──NO──▶ Promote directly
    │
   YES
    │
    ▼
Ralph Loop Review (MANDATORY)
    │
    ▼
Mark Complete
    │
    ▼
Human Approval + Promotion
    │
    ▼
Active Implementation
```

---

## Enforcement

### plan-ops.sh Enforces the Gate

The `promote` command in `plan-ops.sh`:
1. Counts phases in the plan
2. Checks Ralph Review status in Status Header
3. Blocks promotion if multi-phase AND not completed
4. Displays helpful error with commands to run

### No Bypass for Multi-Phase Plans

The `--skip-ralph` flag only works for single-phase plans. Multi-phase plans have no bypass mechanism - Ralph Loop is mandatory.

---

## Best Practices

### When Creating Plans

1. Use meaningful phase names
2. Include clear completion criteria per phase
3. Add testing strategy for each phase
4. Consider dependencies between phases

### During Ralph Loop Review

1. Let the loop run to completion (or max iterations)
2. Review the changes made by each iteration
3. If the plan is significantly restructured, consider re-running
4. Trust the completion promise - if Claude says DONEDONE, review is thorough

### After Ralph Loop

1. Do a final human review before promotion
2. Ensure Ralph Review shows "completed"
3. Proceed with confidence - the plan has been stress-tested

---

## Troubleshooting

### "BLOCKED: Multi-phase plan requires Ralph Loop review"

Run the Ralph Loop workflow:
```bash
./plugins/tim-loop/scripts/plan-ops.sh ralph plans/drafts/my-plan.md
# Follow the displayed instructions
```

### Ralph Loop Not Detecting Phases

Ensure phases are formatted correctly:
- `## Phase 1: Name` ✓
- `### Phase 2` ✓
- `Phase 3: Description` ✓
- `Step 1` ✗ (not detected as phase)

### Ralph Loop Runs Forever

The `--max-iterations 10` parameter prevents infinite loops. If hitting max iterations without completion:
1. The task may be too complex
2. Consider breaking into smaller plans
3. Manually mark complete after reviewing iterations

---

## Related Documentation

- `standards/operations/plan-management.md` - Full plan lifecycle documentation
- `CLAUDE.md` - Project instructions including plan requirements
- `templates/plan.md.template` - Plan template with Ralph Review fields
