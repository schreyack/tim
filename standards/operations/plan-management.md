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

**2. Draft → Active (Human Approval)**
- Human reviews and approves the plan
- Move to `plans/active/`
- Update Status Header: Stage = active, Approver = [human]
- Add log entry: "Approved by [human], moved to active/"

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

### Progress Log

| Timestamp | Stage | Event |
|-----------|-------|-------|
| 2025-01-16 14:30 | draft | Plan created |
| 2025-01-16 15:00 | draft | Added testing strategy |
| 2025-01-16 16:00 | active | Approved by Tim, moved to active/ |
| 2025-01-16 18:30 | active | Phase 1 completed |
| 2025-01-17 10:00 | completed | All phases done, verification passed |

---

[Rest of plan content...]
```

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

## Automation: plan-ops.sh

Use `tools/plan-ops.sh` for lifecycle operations:

```bash
# Initialize folder structure
./tools/plan-ops.sh init

# Import from ~/.claude/plans (copies + deletes original)
./tools/plan-ops.sh import ~/.claude/plans/xxx.md --name "project-feature"

# Promote draft to active
./tools/plan-ops.sh promote plans/drafts/my-plan.md --approver "Tim"

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
| Approve plan | `./tools/plan-ops.sh promote plans/drafts/plan.md --approver "Name"` |
| Finish plan | `./tools/plan-ops.sh complete plans/active/plan.md` |
| Cancel plan | `./tools/plan-ops.sh abandon plans/*/plan.md --reason "why"` |
| View all plans | `./tools/plan-ops.sh list all` |
