# AFK Coding Patterns

Guidelines for autonomous AI development when human oversight is reduced or delayed.

## Overview

"AFK coding" refers to development sessions where AI operates with minimal human intervention - the human may be away from keyboard, asleep, or otherwise unavailable for immediate feedback. TIM's strict enforcement model makes this safe when done correctly.

## When AFK Coding is Appropriate

### Good Candidates

| Scenario | Why It Works |
|----------|--------------|
| Well-defined bug fixes | Clear success criteria, existing tests |
| Feature with existing patterns | Following established architecture |
| Test coverage expansion | Low risk, high verification |
| Refactoring with tests | Tests catch regressions |
| Documentation updates | Non-breaking, easily reviewed |

### Pre-Conditions Required

Before starting AFK development:

1. **Tests exist and pass** - AI needs a working baseline
2. **Clear acceptance criteria** - Unambiguous "done" definition
3. **Patterns documented** - AI knows which approaches to use
4. **Gates enabled** - Pre-commit hooks, CI pipeline active
5. **Plan approved** - Human reviewed the approach before AI executes

## When AFK Coding is NOT Appropriate

### High-Risk Scenarios

| Scenario | Why It's Risky |
|----------|----------------|
| Security-sensitive changes | Requires expert review |
| Database schema changes | Irreversible in production |
| New architectural patterns | Needs design discussion |
| Vague requirements | AI will make assumptions |
| Production deployments | Requires human approval |
| Third-party integrations | External dependencies unpredictable |

### Red Flags That Require Human Input

Stop and wait for human if:

- Requirements are ambiguous
- Multiple valid approaches exist without clear preference
- Security implications are uncertain
- Changes affect production data
- New patterns not covered by existing standards
- External API behavior is undocumented

## Pre-AFK Checklist

Before stepping away, human should verify:

```markdown
## Pre-AFK Checklist

- [ ] Plan approved and in `plans/active/`
- [ ] AI Developer Ready review completed
- [ ] Acceptance criteria are unambiguous
- [ ] All referenced files/APIs exist
- [ ] Tests exist for affected code
- [ ] Pre-commit hooks enabled
- [ ] CI pipeline configured
- [ ] Recovery path defined (what to do if stuck)
```

## Integration with Tim-Loop

Tim-loop is designed for AFK development. It provides:

1. **Plan execution** - Works through approved plan phases
2. **Verification gates** - Must pass 100% verification to complete
3. **Automatic iteration** - Retries on check failures
4. **No silent failures** - Must succeed or clearly report blockers

### Typical AFK Session

```bash
# Human runs execute to get the tim-loop command, then steps away
plan-ops execute plans/active/my-plan.md

# AI runs tim-loop (can take hours for complex plans)
/tim-loop --implement plans/active/my-plan.md

# Tim-loop iterates until:
# - All objectives verified (success)
# - Hits a blocker requiring human input (pauses)
```

## Post-AFK Human Review

When human returns, review:

1. **Plan status** - Did tim-loop complete or block?
2. **Git history** - What commits were made?
3. **Test results** - All passing?
4. **Coverage report** - Did coverage decrease?
5. **Changed files** - Quick sanity check on diff

### Review Commands

```bash
# Check plan status
plan-ops status plans/active/my-plan.md

# Review commits
git log --oneline -20

# Check test status
npm run check  # or poe check

# Review diff since AFK started
git diff HEAD~10..HEAD --stat
```

## Anti-Patterns to Avoid

### DO NOT

| Anti-Pattern | Why It's Bad |
|--------------|--------------|
| Disable pre-commit for speed | Removes safety net |
| Skip plan approval | AI may implement wrong thing |
| Vague "make it work" instructions | Unlimited interpretation |
| AFK for security changes | Needs expert review |
| AFK for database migrations | High risk, needs human |
| Trust without verification | Always review on return |

### DO

| Pattern | Why It Works |
|---------|--------------|
| Clear acceptance criteria | AI knows when done |
| Enable all gates | Catch issues early |
| Use tim-loop for execution | Built-in verification |
| Review on return | Human validates AI work |
| Start small | Build confidence incrementally |

## Feedback Loop Architecture

The reason AFK coding works with TIM:

```text
┌─────────────────────────────────────────────────────┐
│                    AI AGENT                          │
│  ┌─────────┐    ┌─────────┐    ┌─────────────────┐ │
│  │  Write  │───▶│  Check  │───▶│  Pass? Continue │ │
│  │  Code   │    │ Command │    │  Fail? Fix/Retry│ │
│  └─────────┘    └─────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────┘
         │              ▲
         ▼              │
┌─────────────────────────────────────────────────────┐
│                 ENFORCEMENT GATES                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ Type     │  │ Lint     │  │ Test Suite       │  │
│  │ Checking │  │ Rules    │  │ (coverage report) │  │
│  └──────────┘  └──────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────┘
```

Each gate provides immediate feedback. AI iterates until all pass. Human isn't needed in the loop - the gates ARE the quality control.

## Escalation Patterns

When AI should pause and wait for human:

### Immediate Escalation

- Security vulnerability detected
- Production data at risk
- Tests reveal unexpected behavior
- Requirements unclear after investigation

### Soft Escalation (Continue But Note)

- Minor ambiguity resolved with reasonable assumption
- Performance trade-off made
- Alternative approach chosen from valid options

### Logging for Review

AI should document decisions for human review:

```markdown
<!-- DECISION: Chose approach A over B because X -->
<!-- ASSUMPTION: Interpreted "fast" as <100ms response time -->
<!-- BLOCKER: Need clarification on authentication flow -->
```

## See Also

- [Tim-Loop Integration](./tim-loop-integration.md) - Execution engine details
- [Plan Management](./plan-management.md) - Plan lifecycle
- [AI Developer Ready Checklist](../enforcement/ai-developer-ready-checklist.md) - Pre-execution review
- [AI Review Checklist](../enforcement/ai-review-checklist.md) - Human review requirements
