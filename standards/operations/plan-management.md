# Plan Lifecycle Management Standard

This document defines how plans are created, managed, and archived across TIM projects.

---

## Folder Structure

Every TIM project MUST use this folder structure for plans:

```
project/
└── plans/
    ├── drafts/          # Plans being designed (not yet approved)
    ├── active/          # Approved plans under implementation
    ├── completed/       # Successfully executed plans
    └── abandoned/       # Plans that were cancelled (preserves learnings)
```

### Folder Purposes

| Folder | Purpose | Typical Duration |
|--------|---------|------------------|
| `drafts/` | Plans being designed, not yet approved for implementation | Hours to days |
| `active/` | Approved plans currently being implemented | Days to weeks |
| `completed/` | Successfully executed plans (historical record) | Permanent |
| `abandoned/` | Cancelled or superseded plans (institutional knowledge) | Permanent |

---

## Plan Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                         PLAN LIFECYCLE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ~/.claude/plans/       plans/drafts/       plans/active/       │
│  ┌─────────────┐       ┌─────────────┐     ┌─────────────┐     │
│  │   Claude    │ ───── │    Draft    │ ─── │   Active    │     │
│  │  Workspace  │ copy  │   Review    │ ✓   │ Implement   │     │
│  └─────────────┘  +    └─────────────┘     └─────────────┘     │
│        │        delete        │                   │             │
│        │          ↑           │                   │             │
│        └──────────┘           │                   ▼             │
│      (cleanup on              │          ┌─────────────┐       │
│       promotion)              │          │ Completed/  │       │
│                               │          │ Abandoned   │       │
│                               ▼          └─────────────┘       │
│                        (if rejected,                            │
│                         stays in drafts                         │
│                         or delete)                              │
└─────────────────────────────────────────────────────────────────┘
```

### Lifecycle Stages

**1. Draft Creation**
- Claude creates plans in `~/.claude/plans/` during plan mode
- On approval, copy to `plans/drafts/` with proper naming
- Delete the original from `~/.claude/plans/` (MANDATORY)
- Add Status Header if not present

**2. Draft → Active (Human Approval + Ralph Loop Gate)**
- **Multi-phase plans (2+ phases) MUST complete Ralph Loop review first**
- Human reviews and approves the plan
- Move to `plans/active/`
- Update Status Header: Stage = active, Approver = [human]
- Add log entry: "Approved by [human], moved to active/"

See [Ralph Loop Gate](#ralph-loop-gate-for-multi-phase-plans) section below.

**3. Active → Completed**
- All implementation phases completed
- Move to `plans/completed/`
- Update Status Header: Stage = completed
- Add log entry: "All phases completed, verification passed"

**4. Any → Abandoned**
- Plan is cancelled, superseded, or blocked
- Move to `plans/abandoned/`
- Update Status Header: Stage = abandoned
- Add log entry: "Abandoned: [reason]"

---

## Plan File Format

### Naming Convention

**Format:** `YYYY-MM-DD-<project>-<brief-description>.md`

Examples:
- `2025-01-16-micasa-compliance-migration.md`
- `2025-01-16-standards-plan-lifecycle.md`

The date is when the plan was created. The project prefix helps when viewing plans across multiple repos.

### Required Status Header

Every plan MUST include a Status Header at the top:

```markdown
# Plan: [Title]

## Status

| Field | Value |
|-------|-------|
| Stage | draft / active / completed / abandoned |
| Created | 2025-01-16 14:30 |
| Last Updated | 2025-01-16 16:45 |
| Author | Claude Opus 4.5 |
| Approver | [human who approved, or "-" if draft] |
| Ralph Review | required / completed / not-required |
| Ralph Date | [YYYY-MM-DD or "-" if not applicable] |

### Progress Log

| Timestamp | Stage | Event |
|-----------|-------|-------|
| 2025-01-16 14:30 | draft | Plan created |
| 2025-01-16 15:00 | draft | Added testing strategy |
| 2025-01-16 15:30 | draft | Ralph Loop review completed |
| 2025-01-16 16:00 | active | Approved by Tim, moved to active/ |
| 2025-01-16 18:30 | active | Phase 1 completed |
| 2025-01-17 10:00 | completed | All phases done, verification passed |

---

[Rest of plan content...]
```

### Ralph Review Field Values

| Value | Meaning |
|-------|---------|
| `required` | Multi-phase plan, Ralph Loop not yet completed |
| `completed` | Ralph Loop review finished, ready for promotion |
| `not-required` | Single-phase plan, can skip Ralph Loop |

### Required Plan Sections

Every plan MUST include:

1. **Problem/Goal** - What needs to be done and why
2. **Implementation Steps** - Technical approach with phases
3. **Testing Strategy** - How to verify each phase
4. **Completion Criteria** - Checklist of deliverables

---

## Cleanup Rules

### ~/.claude/plans/ (MANDATORY CLEANUP)

When promoting a plan from `~/.claude/plans/` to the project:

1. Copy plan to `plans/drafts/` with proper naming
2. Add Status Header if missing
3. **DELETE the original from `~/.claude/plans/`**
4. Commit the new plan to git

This is MANDATORY - never leave orphan plans in `~/.claude/plans/`.

### plans/drafts/

- Review monthly
- Abandon or delete stale drafts (>30 days without activity)
- If a draft is rejected, either delete or move to abandoned/ with reason

### plans/active/

- Should not accumulate
- If >5 active plans, review prioritization
- Consider whether plans should be completed or abandoned

### plans/completed/

- Archive annually (zip plans older than 1 year, keep in repo)
- These are permanent historical records

### plans/abandoned/

- Keep indefinitely
- Valuable institutional knowledge about what was tried and why it failed

---

## Git Integration

| Plan Stage | Git Action |
|------------|------------|
| draft | Commit to branch (not main) |
| active (approved) | Can merge to main |
| completed | Already on main |
| abandoned | Commit with reason |

Plans should be committed as they progress - this provides:
- Version history of plan evolution
- Reviewable changes in PRs
- Blame/history for decisions

---

## Plan Size Guidelines

| Plan Type | Recommended Size | Max Phases |
|-----------|------------------|------------|
| Bug fix | 50-100 lines | 1-2 |
| Small feature | 100-200 lines | 2-3 |
| Large feature | 200-400 lines | 4-6 |
| Architecture change | 400-600 lines | 6-10 |

If a plan exceeds 600 lines, consider splitting into multiple coordinated plans.

---

## Review Checklist

Before promoting draft → active:

- [ ] Problem/Goal clearly stated
- [ ] All affected files identified
- [ ] Testing strategy defined
- [ ] Completion criteria are verifiable
- [ ] No TODO/TBD placeholders in plan
- [ ] Estimated scope is reasonable
- [ ] Risks identified

---

## Ralph Loop Gate for Multi-Phase Plans

Multi-phase plans (2+ phases) **MUST** complete Ralph Loop review before promotion to active. This is a hard gate enforced by `plan-ops.sh`.

### Why Ralph Loop?

Ralph Loop provides iterative AI-driven improvement:
- Catches gaps, inconsistencies, and missing details
- Improves plan quality through multiple review passes
- Reduces implementation failures from poor planning
- Builds on previous iterations (AI sees its own work in files)

### Detection

A plan requires Ralph Loop if it contains 2+ phases, detected by patterns:
- `## Phase`, `### Phase`
- `Phase 1:`, `Phase 2:`, etc.

Single-phase plans can be promoted directly without Ralph Loop.

### Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    RALPH LOOP GATE WORKFLOW                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Create multi-phase plan in drafts/                          │
│           │                                                     │
│           ▼                                                     │
│  2. ./tools/plan-ops.sh ralph plans/drafts/my-plan.md           │
│     (Outputs the Ralph Loop command to run)                     │
│           │                                                     │
│           ▼                                                     │
│  3. Run /ralph-loop command in Claude Code                      │
│     (Iterates until DONEDONE or max iterations)                 │
│           │                                                     │
│           ▼                                                     │
│  4. ./tools/plan-ops.sh ralph plans/drafts/my-plan.md           │
│        --mark-complete                                          │
│     (Updates Ralph Review: completed)                           │
│           │                                                     │
│           ▼                                                     │
│  5. ./tools/plan-ops.sh promote plans/drafts/my-plan.md         │
│        --approver "Name"                                        │
│     (Promotion now allowed)                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Ralph Loop Command Format

```bash
/ralph-loop:ralph-loop "review plans/drafts/[plan-name] and look for areas to improve. iterate multiple times until there are no more improvements possible. <promise>DONEDONE</promise>" --max-iterations 10 --completion-promise "DONEDONE"
```

### What Happens on Promote Attempt

| Plan Type | Ralph Review Status | Result |
|-----------|---------------------|--------|
| Single-phase | any | Allowed |
| Multi-phase | not-required | Allowed (auto-detected) |
| Multi-phase | required | **BLOCKED** |
| Multi-phase | completed | Allowed |

If blocked, the error message shows exact commands to run.

---

## Tim Loop Execution Gate (HARD ENFORCED)

Active plans **MUST** be executed via `/tim-loop` with human approval. This is a hard gate that AI cannot bypass.

### Why Hard Enforcement?

- AI cannot add an `--approver` flag to bypass (no such flag exists)
- Approval requires human action in a **separate terminal**
- Approval tokens expire after 15 minutes
- Request IDs are unique per attempt

### Execution Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│              PLAN EXECUTION WORKFLOW (HARD ENFORCED)             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. AI: ./tools/plan-ops.sh execute plans/active/my-plan.md     │
│     → Creates approval request, outputs request ID              │
│     → BLOCKED - no tim-loop command yet                         │
│           │                                                     │
│           ▼                                                     │
│  2. HUMAN (separate terminal):                                  │
│     ./tools/plan-ops.sh approve-execute <request-id>            │
│        --approver "Name"                                        │
│     → Validates and approves request                            │
│           │                                                     │
│           ▼                                                     │
│  3. AI: ./tools/plan-ops.sh execute plans/active/my-plan.md     │
│     → Finds valid approval                                      │
│     → Outputs tim-loop command                                  │
│           │                                                     │
│           ▼                                                     │
│  4. Run the /tim-loop command to execute the plan               │
│           │                                                     │
│           ▼                                                     │
│  5. ./tools/plan-ops.sh complete plans/active/my-plan.md        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Tim Loop Command Format

When `execute` succeeds, it outputs:

```bash
/tim-loop "implement plans/active/[plan-name]. you are not done until all iterations and phases of the plan are complete."
```

### Status Header Execution Fields

| Field | Value |
|-------|-------|
| Execution Approved | yes / no |
| Execution Approved By | [human name or "-"] |
| Execution Started | [YYYY-MM-DD HH:MM or "-"] |

---

## Automation: plan-ops.sh

Use `tools/plan-ops.sh` for lifecycle operations:

```bash
# Initialize folder structure
./tools/plan-ops.sh init

# Import from ~/.claude/plans (copies + deletes original)
./tools/plan-ops.sh import ~/.claude/plans/xxx.md --name "project-feature"

# Start Ralph Loop review (shows command to run)
./tools/plan-ops.sh ralph plans/drafts/my-plan.md

# Mark Ralph Loop as complete (after running /ralph-loop)
./tools/plan-ops.sh ralph plans/drafts/my-plan.md --mark-complete

# Promote draft to active (blocked for multi-phase without ralph)
./tools/plan-ops.sh promote plans/drafts/my-plan.md --approver "Tim"

# Request execution approval (first call creates request, blocks)
./tools/plan-ops.sh execute plans/active/my-plan.md

# Human approves execution in separate terminal
./tools/plan-ops.sh approve-execute <request-id> --approver "Tim"

# Retry execute after approval (outputs tim-loop command)
./tools/plan-ops.sh execute plans/active/my-plan.md

# Complete an active plan
./tools/plan-ops.sh complete plans/active/my-plan.md

# Abandon a plan
./tools/plan-ops.sh abandon plans/drafts/my-plan.md --reason "Requirements changed"

# Cleanup stale drafts
./tools/plan-ops.sh cleanup-drafts --older-than 30d

# List plans by stage
./tools/plan-ops.sh list [drafts|active|completed|abandoned|all]
```

---

## Quick Reference

| Action | Command |
|--------|---------|
| Start new project | `./tools/plan-ops.sh init` |
| Import Claude's plan | `./tools/plan-ops.sh import ~/.claude/plans/xxx.md --name "desc"` |
| Start Ralph review | `./tools/plan-ops.sh ralph plans/drafts/plan.md` |
| Complete Ralph review | `./tools/plan-ops.sh ralph plans/drafts/plan.md --mark-complete` |
| Approve plan | `./tools/plan-ops.sh promote plans/drafts/plan.md --approver "Name"` |
| Request execution | `./tools/plan-ops.sh execute plans/active/plan.md` |
| Approve execution (human) | `./tools/plan-ops.sh approve-execute <id> --approver "Name"` |
| Finish plan | `./tools/plan-ops.sh complete plans/active/plan.md` |
| Cancel plan | `./tools/plan-ops.sh abandon plans/*/plan.md --reason "why"` |
| View all plans | `./tools/plan-ops.sh list all` |
