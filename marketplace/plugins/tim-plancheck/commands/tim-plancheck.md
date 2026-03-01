---
description: "Plan audit: verify every plan's completion against actual codebase state"
argument-hint: "[--drafts-only | --active-only]"
---

# Plan Check

You are a plan auditor. Your job is to review every plan in `plans/drafts/` and `plans/active/`, verify whether each plan's steps are actually complete by checking the codebase, and move plans to their correct lifecycle state. You do not delete plans. Ever.

**Do not assume completion.** A plan is complete only when every required step has verifiable evidence in the codebase — files exist, code is implemented, configs are in place. "Probably done" is not done. If you cannot verify a step, it is not done.

---

## Phase 1: Inventory

Scan `plans/drafts/` and `plans/active/` for all `.md` files (excluding `MASTER.md` files — those are multi-plan parent docs, not individual plans).

If `$ARGUMENTS` contains `--drafts-only`, only scan `plans/drafts/`. If `--active-only`, only scan `plans/active/`.

If both directories are empty or don't exist, report "No plans to audit" and stop.

Also scan `plans/completed/` and `plans/abandoned/` to build a full inventory for the summary table, but do NOT re-audit those — they are included only for completeness in the final report.

---

## Phase 2: Deep Verification

For each plan found in drafts or active:

1. **Read the full plan.** Understand every step, deliverable, and acceptance criterion.

2. **Spawn verification agents.** Use the Agent tool (subagent_type: "Explore", model: "opus") to verify each major step or group of related steps against the actual codebase. Each agent should:
   - Search for the specific files, functions, configs, or changes the step requires
   - Check that implementations match what the plan specifies (not just that a file exists, but that it contains the right code)
   - Report back with evidence: file paths, line numbers, or clear "not found" results

   Spawn agents in parallel where steps are independent. Cap each agent's task to a focused verification — don't send one agent to verify an entire 20-step plan.

3. **Classify the plan** based on verification results:

   | Classification | Criteria |
   |---|---|
   | **COMPLETED** | Every step has verifiable evidence in the codebase. No gaps. |
   | **ACTIVE** | Some steps are done, work is clearly in progress, remaining steps are still relevant. |
   | **ABANDONED** | The plan's goals have been superseded by other work, the approach was replaced, or the plan is no longer relevant to the current codebase state. |
   | **BLOCKED** | Steps cannot proceed due to missing dependencies, unresolved decisions, or external blockers. |
   | **DRAFT** | No meaningful progress has been made. Plan is still a proposal. |

---

## Phase 3: Move Plans

For each plan that needs to move:

- **COMPLETED** → `mv` from current location to `plans/completed/`
- **ABANDONED** → `mv` from current location to `plans/abandoned/`
  - Before moving: append a section to the bottom of the plan file:

    ```markdown

    ---

    ## Abandoned

    **Date:** YYYY-MM-DD
    **Reason:** [Clear explanation of why this plan is no longer needed]
    ```

- **ACTIVE** → if currently in `plans/drafts/`, move to `plans/active/`. If already in `plans/active/`, leave it.
- **BLOCKED** / **DRAFT** → leave in current location.

Create destination directories if they don't exist.

---

## Phase 4: Summary Report

Output a markdown table with ALL plans across all directories (including completed/abandoned that you didn't re-audit). Format:

```markdown
## Plan Audit Summary

| Plan | Previous Location | Current Location | Status | Notes |
|------|-------------------|------------------|--------|-------|
| plan-name.md | drafts/ | completed/ | COMPLETED | All 5 steps verified |
| other-plan.md | active/ | active/ | ACTIVE | 3/7 steps done, remaining work is relevant |
| old-plan.md | completed/ | completed/ | (previously completed) | — |
| ...  | ... | ... | ... | ... |
```

For plans that were NOT moved, still include them with "No change" in the notes.

For plans in completed/abandoned that you didn't re-audit, show their status as "(previously completed)" or "(previously abandoned)" and use "—" for notes.

After the table, provide a one-line summary: "Audited X plans: Y completed, Z active, W abandoned, V blocked, U unchanged."
