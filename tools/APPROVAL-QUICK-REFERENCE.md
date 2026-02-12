# Plan Approval Quick Reference

Quick reference for human approval commands in `plan-ops.sh`.

**Key principle:** AI cannot bypass these commands. They require an interactive terminal and block execution from within Claude Code sessions.

---

## Approval Workflow Overview

```text
Draft → [Plan Review] → Promote → AI Ready → Execute → Tim Loop
```

| Step | Command | Who Runs |
|------|---------|----------|
| Plan Review | `review --mark-complete` | Human |
| Promotion | `promote --approver` | Human |
| AI Developer Ready | `ai-ready --reviewer` | Human |

---

## 1. Plan Review (Multi-Phase Plans Only)

Plans with 2+ phases require Plan Review before promotion.

```bash
# Step 1: See the Tim Loop review command to run
./plugins/tim-loop/scripts/plan-ops.sh review plans/drafts/my-plan.md

# Step 2: Run the displayed /tim-loop --tech-review command in Claude Code

# Step 3: Mark review complete (human only)
./plugins/tim-loop/scripts/plan-ops.sh review plans/drafts/my-plan.md --mark-complete
```

**Single-phase plans skip this step.**

---

## 2. Promote Draft to Active

Move an approved plan from `drafts/` to `active/`.

```bash
./plugins/tim-loop/scripts/plan-ops.sh promote plans/drafts/my-plan.md --approver "Your Name"
```

**Blocked if:** Multi-phase plan hasn't completed Plan Review.

---

## 3. AI Developer Ready Approval

Human reviews plan for AI implementation concerns before execution.

```bash
./plugins/tim-loop/scripts/plan-ops.sh ai-ready plans/active/my-plan.md --reviewer "Your Name"
```

**Review checklist:** `standards/enforcement/ai-developer-ready-checklist.md`

**What to verify:**

- Instructions are unambiguous (AI has one interpretation)
- No hallucination opportunities (referenced APIs/files exist)
- Guard rails are explicit (error handling specified)
- Verification criteria are code-checkable

---

## 4. Execute Plan

After AI Developer Ready approval, run execute to get the tim-loop command:

```bash
./plugins/tim-loop/scripts/plan-ops.sh execute plans/active/my-plan.md
```

This outputs the `/tim-loop --implement` command to paste into Claude Code.

---

## 5. Complete or Abandon

```bash
# Mark as completed
./plugins/tim-loop/scripts/plan-ops.sh complete plans/active/my-plan.md

# Or abandon with reason
./plugins/tim-loop/scripts/plan-ops.sh abandon plans/active/my-plan.md --reason "Requirements changed"
```

---

## Full Example Workflow

```bash
# 1. Import plan from Claude's default location
./plugins/tim-loop/scripts/plan-ops.sh import ~/.claude/plans/xyz.md --name "feature-auth"

# 2. For multi-phase plans: Start Plan Review
./plugins/tim-loop/scripts/plan-ops.sh review plans/drafts/2025-01-16-feature-auth.md
# (Run the displayed /tim-loop --tech-review command in Claude Code)
./plugins/tim-loop/scripts/plan-ops.sh review plans/drafts/2025-01-16-feature-auth.md --mark-complete

# 3. Promote to active
./plugins/tim-loop/scripts/plan-ops.sh promote plans/drafts/2025-01-16-feature-auth.md --approver "Tim"

# 4. Mark AI Developer Ready
./plugins/tim-loop/scripts/plan-ops.sh ai-ready plans/active/2025-01-16-feature-auth.md --reviewer "Tim"

# 5. Execute (outputs tim-loop command)
./plugins/tim-loop/scripts/plan-ops.sh execute plans/active/2025-01-16-feature-auth.md

# 6. After /tim-loop completes: Mark complete
./plugins/tim-loop/scripts/plan-ops.sh complete plans/active/2025-01-16-feature-auth.md
```

---

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| "BLOCKED: This command must be run interactively" | Running from script/AI | Open terminal manually |
| "Cannot approve from within Claude Code session" | Running in Claude terminal | Use separate terminal |
| "Multi-phase plan requires Plan Review" | Trying to promote without review | Complete Plan Review first |
| "Plan has not been marked AI Developer Ready" | Missing ai-ready approval | Run ai-ready command |

---

## See Also

- `./plugins/tim-loop/scripts/plan-ops.sh help` - Full command documentation
- `standards/operations/plan-management.md` - Complete plan lifecycle docs
- `standards/enforcement/ai-developer-ready-checklist.md` - AI review checklist
