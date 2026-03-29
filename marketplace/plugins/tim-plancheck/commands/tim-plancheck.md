---
description: "Plan audit: verify every plan's claims against actual codebase state"
argument-hint: "[--drafts-only | --active-only | --deep]"
---

# Plan Check

You are verifying claims. Every plan is a claim: "this work is done" or "this work is in progress." Your job is to check those claims against the codebase and move plans to the state the evidence supports.

**Do not assume completion.** A plan is complete only when every step has verifiable evidence — files exist, code is implemented, configs are in place. "Probably done" is not done.

**Do not assume abandonment.** A plan whose approach changed is not abandoned if the goal is still relevant. Check git activity before classifying.

---

## Phase 1: Inventory

Scan `plans/drafts/` and `plans/active/` for `.md` files (exclude `MASTER.md` — those are package parents). Respect `--drafts-only` / `--active-only` flags.

Also scan `plans/completed/` and `plans/abandoned/` for the summary table. Do not re-audit those unless `--deep` is passed (see below).

Empty directories → "No plans to audit" → stop.

---

## Phase 2: Verification

For each plan in drafts or active:

### 2a. Read and understand

Read the full plan. Identify every step, deliverable, and acceptance criterion.

### 2b. Check git activity

```bash
# Find files the plan references, check recent activity
git log --oneline --since="30 days ago" -- <referenced-files-or-dirs>
```

Recent commits on plan-related files = evidence of active work. No commits in 60+ days = likely stalled or abandoned.

### 2c. Verify steps

**Use lightweight tools first.** For existence checks (does this file exist? does this function exist?), use Glob and Grep directly. Only spawn Explore agents for complex verifications (does this implementation match the spec? is this config correct?).

For each step, record: DONE (with evidence), PARTIAL (what's done, what's missing), or NOT DONE.

### 2d. Classify

| Classification | Criteria |
|---|---|
| **COMPLETED** | Every step verified. No gaps. |
| **ACTIVE (N/M)** | N of M steps done, recent git activity, remaining steps still relevant |
| **STALLED (N/M)** | N of M steps done, no recent git activity |
| **ABANDONED** | Goals superseded, approach replaced, or no longer relevant to current codebase |
| **BLOCKED** | Cannot proceed: missing dependencies, unresolved decisions, external blockers |
| **DRAFT** | No meaningful progress. Still a proposal. |

The N/M count matters — "ACTIVE 9/10" and "ACTIVE 1/10" are very different situations.

### --deep flag

When `--deep` is passed, also spot-check plans in `plans/completed/`. For each, verify that the key deliverables still exist and haven't regressed. If a completed plan's deliverables are broken by subsequent changes, note it in the report as a regression.

---

## Phase 3: Move Plans

- **COMPLETED** → `mv` to `plans/completed/`
- **ABANDONED** → `mv` to `plans/abandoned/`, append an `## Abandoned` section with date and reason
- **ACTIVE/STALLED** → move to `plans/active/` if currently in drafts. Already in active → leave.
- **BLOCKED / DRAFT** → leave in current location.

Create directories if needed.

---

## Phase 4: Summary

```markdown
## Plan Audit Summary

| Plan | From | To | Status | Progress | Last Activity | Notes |
|------|------|----|--------|----------|---------------|-------|
| plan.md | drafts/ | completed/ | COMPLETED | 5/5 | 2026-03-25 | All steps verified |
| other.md | active/ | active/ | ACTIVE | 3/7 | 2026-03-28 | Auth steps done, UI pending |
| stale.md | active/ | active/ | STALLED | 2/6 | 2026-01-15 | No activity in 73 days |
| old.md | completed/ | completed/ | (completed) | — | — | — |

Audited X plans: Y completed, Z active, W stalled, V abandoned, U blocked, T draft.
```

For `--deep` audits, add a Regressions section if any completed plans have broken deliverables.
