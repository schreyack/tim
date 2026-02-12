# Plan Lifecycle Management Standard

This document defines how plans are created, managed, and archived across TIM projects.

---

## Folder Structure

Every TIM project MUST use this folder structure for plans:

```text
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

## Plan Content Principles

### No Optional Work

**Plans contain only required work. There are no optional steps, phases, or tasks.**

This is a core TIM principle. If something is worth including in a plan, it's required. If it's truly optional, it doesn't belong in the plan.

| Include in Plan | Exclude from Plan |
|-----------------|-------------------|
| Required steps | "Nice to have" items |
| Must-complete phases | Optional enhancements |
| Blocking tasks | Future considerations |

**Why this matters for AI development:**

- AI cannot cherry-pick easy tasks while skipping "optional" harder ones
- Verification is binary: all tasks done = complete, anything missing = incomplete
- No room for interpretation about what was required
- Implementation Verification Gate enforces 100% completion

**Anti-patterns to avoid:**

- "Optional: add error handling" → Either require it or remove it from the plan
- "Phase 3 (if time permits)" → Either commit to Phase 3 or exclude it entirely
- "Nice to have: tests for edge cases" → Either require the tests or don't mention them
- "Stretch goal: performance optimization" → Either it's a required phase or exclude it

**What to do with truly optional ideas:**

- Document them separately (not in the plan)
- Create a separate future plan if they become important
- Add to project backlog or roadmap documents

---

## Plan Lifecycle

```text
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

**2. Draft → Active (Human Approval + Plan Review Gate)**

- **Multi-phase plans (2+ phases) MUST complete Plan Review first**
- Human reviews and approves the plan
- Move to `plans/active/`
- Update Status Header: Stage = active, Approver = [human]
- Add log entry: "Approved by [human], moved to active/"

See [Plan Review Gate](#plan-review-gate-for-multi-phase-plans) section below.

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

## Plan Formats

TIM supports two plan formats:

1. **Standalone plans** - Single `.md` files for simple plans
2. **Package plans** - Folders containing related plans with a MASTER.md

### When to Use Each Format

| Format | Use When |
|--------|----------|
| **Standalone** | Simple plans, single iteration, clear scope |
| **Package** | Multiple related plans, research iterations, PM reviews |

---

## Standalone Plan Format

### Naming Convention

**Format:** `YYYY-MM-DD-<project>-<brief-description>.md`

Examples:

- `2025-01-16-myapp-compliance-migration.md`
- `2025-01-16-standards-plan-lifecycle.md`

The date is when the plan was created. The project prefix helps when viewing plans across multiple repos.

---

## Package Plan Format

Packages group related plans that were created during iterative development. When a plan involves multiple research iterations, PM reviews, or evolved through multiple sessions, package them together.

### Package Structure

```text
plans/drafts/
├── 2026-02-01-feature-auth/              # Package folder
│   ├── MASTER.md                          # THE implementation plan
│   ├── original-plan.md                   # Initial plan (optional)
│   ├── research-iteration-1.md            # Research findings
│   ├── research-iteration-2.md            # More research
│   └── pm-review-notes.md                 # PM review artifacts
└── 2026-02-01-simple-bugfix.md           # Standalone plan
```

### Package Rules

1. **MASTER.md** is ALWAYS the implementation plan - this is what wizard/tim-loop uses
2. **Package folders** move as a unit through lifecycle stages
3. **Folder name** follows the same convention as standalone: `YYYY-MM-DD-<topic>`
4. **Supporting files** get descriptive names (not auto-generated Claude plan names)

### Creating Packages

Use `plan-ops package` to organize existing related plans:

```bash
# Interactive mode - prompts for grouping
plan-ops package

# Explicit mode - specify what to package
plan-ops package 2026-02-01-feature-auth \
    --master plans/drafts/2026-02-01-pm-review-plan.md \
    --include "plans/drafts/2026-02-01-*auth*"
```

### Package Lifecycle

Packages move through lifecycle stages exactly like standalone plans:

```text
plans/drafts/2026-02-01-my-feature/      → promote →
plans/active/2026-02-01-my-feature/      → complete →
plans/completed/2026-02-01-my-feature/
```

The entire folder moves, preserving all supporting files.

### Working with Packages

```bash
# Wizard automatically detects packages
plan-ops wizard plans/drafts/2026-02-01-my-feature/

# Or specify the MASTER.md directly
plan-ops wizard plans/drafts/2026-02-01-my-feature/MASTER.md

# List shows packages with [P] marker
plan-ops list drafts
# Output:
#   PACKAGES:
#     [P] 2026-02-01-my-feature/ (4 files)
#   STANDALONE:
#     2026-02-01-simple-fix.md
```

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
| Plan Review | required / completed / not-required |
| Review Date | [YYYY-MM-DD or "-" if not applicable] |

### Progress Log

| Timestamp | Stage | Event |
|-----------|-------|-------|
| 2025-01-16 14:30 | draft | Plan created |
| 2025-01-16 15:00 | draft | Added testing strategy |
| 2025-01-16 15:30 | draft | Plan Review completed |
| 2025-01-16 16:00 | active | Approved by Tim, moved to active/ |
| 2025-01-16 18:30 | active | Phase 1 completed |
| 2025-01-17 10:00 | completed | All phases done, verification passed |

---

[Rest of plan content...]
```

### Plan Review Field Values

| Value | Meaning |
|-------|---------|
| `required` | Multi-phase plan, review not yet completed |
| `completed` | Plan Review finished, ready for promotion |
| `not-required` | Single-phase plan, can skip Plan Review |

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

## Plan Review Gate for Multi-Phase Plans

Multi-phase plans (2+ phases) **MUST** complete Plan Review before promotion to active. This is a hard gate enforced by `plan-ops.sh`.

### Why Plan Review?

Plan Review provides iterative AI-driven improvement:

- Catches gaps, inconsistencies, and missing details
- Improves plan quality through multiple review passes
- Reduces implementation failures from poor planning
- Builds on previous iterations (AI sees its own work in files)

### Detection

A plan requires Plan Review if it contains 2+ phases, detected by patterns:

- `## Phase`, `### Phase`
- `Phase 1:`, `Phase 2:`, etc.

Single-phase plans can be promoted directly without Plan Review.

### Workflow

```text
┌─────────────────────────────────────────────────────────────────┐
│                   PLAN REVIEW GATE WORKFLOW                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Create multi-phase plan in drafts/                          │
│           │                                                     │
│           ▼                                                     │
│  2. plan-ops review plans/drafts/my-plan.md                     │
│     (Outputs the Tim Loop review command to run)                │
│           │                                                     │
│           ▼                                                     │
│  3. Run /tim-loop --tech-review command in Claude Code           │
│     (Iterates until DONEDONE or max iterations)                 │
│           │                                                     │
│           ▼                                                     │
│  4. plan-ops review plans/drafts/my-plan.md                     │
│        --mark-complete                                          │
│     (Updates Plan Review: completed)                            │
│           │                                                     │
│           ▼                                                     │
│  5. plan-ops promote plans/drafts/my-plan.md                    │
│        --approver "Name"                                        │
│     (Promotion now allowed)                                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Tim Loop Review Command Format

```bash
/tim-loop:tim-loop --tech-review plans/drafts/[plan-name].md --max-iterations 10
```

### What Happens on Promote Attempt

| Plan Type | Plan Review Status | Result |
|-----------|---------------------|--------|
| Single-phase | any | Allowed |
| Multi-phase | not-required | Allowed (auto-detected) |
| Multi-phase | required | **BLOCKED** |
| Multi-phase | completed | Allowed |

If blocked, the error message shows exact commands to run.

---

## Tim Loop Execution

Active plans are executed via `/tim-loop` after AI Developer Ready approval.

### Execution Workflow

```text
┌─────────────────────────────────────────────────────────────────┐
│                    PLAN EXECUTION WORKFLOW                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. plan-ops execute plans/active/my-plan.md                    │
│     → Outputs tim-loop command                                  │
│           │                                                     │
│           ▼                                                     │
│  2. Run the /tim-loop command to execute the plan               │
│           │                                                     │
│           ▼                                                     │
│  3. plan-ops complete plans/active/my-plan.md                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Tim Loop Command Format

When `execute` succeeds, it outputs:

```bash
/tim-loop:tim-loop --implement plans/active/[plan-name].md
```

### Status Header Execution Fields

| Field | Value |
|-------|-------|
| Execution Approved | yes / no |
| Execution Approved By | [name or "-"] |
| Execution Started | [YYYY-MM-DD HH:MM or "-"] |

---

## AI Developer Ready Gate (MANDATORY)

Before execution, ALL plans require AI Developer Ready approval. This ensures plans are reviewed with the specific mindset that an AI developer will implement them.

### Why This Gate?

AI developers make different mistakes than humans:

- Misinterpret ambiguous instructions
- Hallucinate APIs or methods that don't exist
- Over-engineer simple solutions
- Leave placeholder code when instructions are vague
- Miss implicit context that humans would understand

### Workflow

```bash
# After promoting to active/, human reviews for AI concerns:
plan-ops ai-ready plans/active/my-plan.md --reviewer "Name"
```

This is a **HARD REQUIREMENT**. Both `execute` and `tim-loop --implement` will fail without this approval.

### Checklist Reference

See `standards/enforcement/ai-developer-ready-checklist.md` for the full review checklist.

### Approval Stamp Format

When approved, this stamp is added to the plan:

```markdown
### AI Developer Ready Approval

**Reviewer**: [Name]
**Date**: YYYY-MM-DD
**Iteration**: N (FINAL)
**Status**: APPROVED
```

### Status Header AI Developer Ready Fields

| Field | Value |
|-------|-------|
| AI Developer Ready | yes / no |
| AI Developer Ready By | [reviewer name or "-"] |
| AI Developer Ready Date | [YYYY-MM-DD or "-"] |
| AI Developer Ready Iteration | [N or "-"] |

---

## Implementation Verification Gate (MANDATORY)

After implementation, tim-loop verifies that 100% of plan objectives are met. There is no escape hatch.

### Why This Gate?

- AI implementations may miss objectives
- Partial completion is not acceptable
- Forces complete implementations, not "good enough"

### Verification Flow

1. **Implementation completes** - Tim-loop adds `<!-- VERIFIED: NO -->` marker
2. **Verification phase** - Each completion criterion is checked
3. **If 100% met** - `<!-- VERIFIED: YES -->`, tim-loop exits
4. **If gaps found** - Creates remediation plan, tim-loop continues

### Remediation Flow

When verification fails:

1. Original plan marked `<!-- VERIFIED: FAILED -->`
2. New remediation plan created in `plans/drafts/`
3. Remediation plan goes through FULL lifecycle (Review → Promote → AI-Ready → Execute)
4. When remediation succeeds, original plan updated to `<!-- VERIFIED: YES -->`

### Status Header Verification Fields

| Field | Value |
|-------|-------|
| Implementation Verified | yes / no |
| Implementation Verified By | [reviewer or "-"] |
| Implementation Verified Date | [YYYY-MM-DD or "-"] |
| Remediation Plan | [path or "-"] |

---

## AI Bypass Prevention

Multiple layers prevent AI from approving its own work:

### Layer 1: PreToolUse Hook

A Claude Code hook intercepts Bash commands and blocks approval patterns:

```bash
# ~/.claude/hooks/block-ai-approvals.sh blocks:
# - plan-ops.sh promote --approver
# - plan-ops.sh ai-ready --reviewer
# - plan-ops.sh review --mark-complete
```

### Layer 2: TTY Verification

Approval commands verify they're running from an interactive terminal:

- Checks if stdin is a terminal
- Checks for Claude Code session environment variables
- Blocks piped or scripted execution

### Layer 3: Process Lineage Check

Approval commands check process ancestry:

- Walks up the process tree
- Blocks if any ancestor is a Claude process

### Hook Registration

To enable AI bypass prevention, register the hook in `~/.claude/settings.local.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {"command": "~/.claude/hooks/block-ai-approvals.sh"}
    ]
  }
}
```

---

## Designing Plans for Agent Execution

Plans should be designed for parallel agent execution where possible. Claude Code can launch multiple agents simultaneously, and well-designed plans take advantage of this.

### Parallelization Principles

1. **Identify independent tasks** - Tasks with no shared dependencies can run simultaneously
2. **Map dependencies explicitly** - Know which tasks must wait for others
3. **Prefer smaller parallelizable tasks** - Break large tasks into smaller parallel-capable units
4. **Think across phases** - Some Phase 2 tasks may start before Phase 1 fully completes

### Agent Type Selection

| Agent Type | Use For | Examples |
|------------|---------|----------|
| `Explore` | Codebase search, pattern finding, research | Finding all usages, understanding architecture |
| `Plan` | Architecture design, approach comparison | Designing new features, evaluating tradeoffs |
| `Bash` | Independent commands, git operations | Running tests, building, migrations |

### Execution Strategy Table

Every plan should include an Execution Strategy table:

```markdown
| Phase | Task | Dependencies | Agent Type | Parallelizable |
|-------|------|--------------|------------|----------------|
| 1 | Search for auth patterns | none | Explore | Yes |
| 1 | Search for user models | none | Explore | Yes |
| 1 | Design auth approach | tasks above | Plan | No |
| 2 | Implement auth | Phase 1 | Bash | No |
| 2 | Write tests | Phase 1 | Bash | Yes (with impl) |
```

### Good vs Bad Plan Design

**Bad: Monolithic, no parallelization**

```text
Phase 1: Implement the authentication feature
  1. Research existing auth
  2. Design the approach
  3. Write the code
  4. Write tests
  5. Deploy
```

**Good: Parallelizable with clear dependencies**

```text
Phase 1: Research (parallel)
  1a. [Explore] Search for existing auth patterns
  1b. [Explore] Search for user model structure
  1c. [Explore] Search for middleware patterns

Phase 2: Design (depends on Phase 1)
  2. [Plan] Design auth approach based on findings

Phase 3: Implement (parallel where possible)
  3a. [Bash] Implement auth middleware
  3b. [Bash] Write unit tests (can parallel with 3a)
  3c. [Bash] Write integration tests (depends on 3a)
```

### Guidelines

- **Max 3 agents in parallel** - System limit, more isn't better
- **Don't parallelize shared state** - If tasks modify the same files, sequence them
- **Document sequential reasoning** - If tasks must be sequential, note why
- **Consider failure modes** - If parallel task A fails, does task B still make sense?

---

## Automation: plan-ops

To run `plan-ops` from anywhere, add the tim `bin/` directory to your PATH:

```bash
# Add to ~/.bashrc or ~/.zshrc:
export PATH="/path/to/tim/bin:$PATH"
source ~/.bashrc  # or source ~/.zshrc
```

Use `plan-ops` for lifecycle operations:

```bash
# Initialize folder structure
plan-ops init

# Import from ~/.claude/plans (copies + deletes original)
plan-ops import ~/.claude/plans/xxx.md --name "project-feature"

# Start Plan Review (shows command to run)
plan-ops review plans/drafts/my-plan.md

# Mark Plan Review as complete (after running /tim-loop --tech-review)
plan-ops review plans/drafts/my-plan.md --mark-complete

# Promote draft to active (blocked for multi-phase without review)
plan-ops promote plans/drafts/my-plan.md --approver "Tim"

# Execute (outputs tim-loop command)
plan-ops execute plans/active/my-plan.md

# Complete an active plan
plan-ops complete plans/active/my-plan.md

# Abandon a plan
plan-ops abandon plans/drafts/my-plan.md --reason "Requirements changed"

# Cleanup stale drafts
plan-ops cleanup-drafts --older-than 30d

# List plans by stage
plan-ops list [drafts|active|completed|abandoned|all]
```

---

## Quick Reference

| Action | Command |
|--------|---------|
| Start new project | `plan-ops init` |
| Import Claude's plan | `plan-ops import ~/.claude/plans/xxx.md --name "desc"` |
| Start Plan Review | `plan-ops review plans/drafts/plan.md` |
| Complete Plan Review | `plan-ops review plans/drafts/plan.md --mark-complete` |
| Approve plan | `plan-ops promote plans/drafts/plan.md --approver "Name"` |
| Execute plan | `plan-ops execute plans/active/plan.md` |
| Finish plan | `plan-ops complete plans/active/plan.md` |
| Cancel plan | `plan-ops abandon plans/*/plan.md --reason "why"` |
| View all plans | `plan-ops list all` |
