# TIM Rule Classification

This document classifies every TIM rule as either a **Principle** (immutable) or **Contextual** (subject to review).

---

## Why This Classification Matters

TIM has two types of rules:

1. **Principles** - Philosophical commitments that define what TIM *is*. These will never change because changing them would make TIM something else entirely.

2. **Contextual Rules** - Calibrations based on current understanding of AI capabilities, tooling, and operational experience. These may change as technology evolves.

Understanding the difference helps teams know:
- Which rules can never have exceptions
- Which rules might be adjusted with evidence
- What would trigger a review of contextual rules

---

## Quick Reference

| Category | Principle Examples | Contextual Examples |
|----------|-------------------|---------------------|
| Philosophy | Trust but verify, Human oversight | - |
| Code Size | Code must be comprehensible | 400 lines max |
| Testing | Must have coverage threshold | 90% coverage |
| Tools | Must use a linter | ruff vs. black |
| Deployment | Human approval for prod | Canary 10% split |

---

# PRINCIPLES (Immutable)

These define what TIM *is*. They will not change.

## Core Philosophy

| Principle | Why It's Immutable |
|-----------|-------------------|
| Trust, but verify | Core identity of TIM |
| Defense in depth | Fundamental architecture - no single point of failure |
| Hard gates that AI cannot bypass | Core enforcement model |
| Human oversight for consequential decisions | Safety principle |
| No bypass flags anywhere | Prevents circumvention - if AI can bypass, AI will |
| If you touched it, you own it (accountability) | Responsibility model |
| Single source of truth | Data integrity - prevents inconsistency |
| Completeness over speed | 100% verification, no "good enough" |
| TDD for new features | Test-first prevents "test what I wrote" thinking |

## Type Safety

| Principle | Why It's Immutable |
|-----------|-------------------|
| 100% type coverage required | Types catch bugs at compile time, AI needs type info |
| No `any` types | Defeats purpose of type system |
| All functions must have type hints | Explicit contracts |
| No vanilla JavaScript | Type safety is non-negotiable |

## Code Quality

| Principle | Why It's Immutable |
|-----------|-------------------|
| Code must be comprehensible | Complexity = bugs (specific numbers are contextual) |
| Zero warnings policy | Warnings exist for reasons; noise gets ignored |
| No print/console.log in committed code | Use logging module; print is debugging noise |
| No commented-out code | Clean code principle |
| No TODO/FIXME placeholders | Implement fully or don't add it |
| No bare except clauses | Catch specific exceptions |
| Must have coverage threshold | Testing is required (specific % is contextual) |
| 100% test pass rate | Non-negotiable quality |
| Bug fixes require failing test first | Verification principle |

## Security

| Principle | Why It's Immutable |
|-----------|-------------------|
| Never hardcode secrets | Security fundamental |
| Never log secrets | Security fundamental |
| Never commit .env files | Security fundamental |
| All external input validated server-side | Security fundamental |
| HIGH/CRITICAL vulnerabilities block merge | Security fundamental |
| Required security headers (CSP, HSTS, X-Frame-Options, etc.) | Security fundamental |
| Parameterized queries only (no string interpolation for SQL) | Security fundamental |

## Database

| Principle | Why It's Immutable |
|-----------|-------------------|
| Migrations only (no sync/create_all/raw DDL) | Data integrity |
| Every migration has tested rollback | Recoverability |
| Migration tested: upgrade → downgrade → upgrade | Verification |

## Enforcement Architecture

| Principle | Why It's Immutable |
|-----------|-------------------|
| Four-gate model exists | Enforcement architecture |
| Gate 1 (pre-commit) exists | Enforcement architecture |
| Gate 2 (CI) exists | Enforcement architecture |
| Gate 3 (deploy) exists | Enforcement architecture |
| Gate 4 (compliance) exists | Enforcement architecture |
| Gates block on failure | Core enforcement model |
| Must use a linter | Code quality |
| Must use a formatter | Consistency |
| Must use shared library (tim-lib / @tim/lib) | Standardization |

## AI Behavioral Enforcement

| Principle | Why It's Immutable |
|-----------|-------------------|
| Excuse pattern detection | Accountability enforcement |
| Code quality validation on edit | Real-time enforcement |
| Block on deflection patterns | Accountability enforcement |

## Plan Lifecycle

| Principle | Why It's Immutable |
|-----------|-------------------|
| Plans require human approval before execution | Human oversight |
| Multi-phase plans require review | Verification |
| AI Developer Ready approval required | Quality gate |
| 100% verification before tim-loop exit | Completeness |
| No escape hatch from verification | Enforcement integrity |
| AI cannot enable local development | Human control |
| --env flag required for all ops.sh commands | Explicit environment awareness |
| Human approval for production deployment | Human oversight |

---

# CONTEXTUAL RULES (Subject to Review)

These are calibrations based on current understanding. They may change as AI capabilities evolve.

## File & Code Size Limits

*Current rationale: AI context window and comprehension limitations (2025)*

| Rule | Current Value | Review Trigger |
|------|---------------|----------------|
| Max lines per source file | 400 | Context windows > 500K with demonstrated comprehension |
| Max lines per test file | 500 | Context windows > 500K with demonstrated comprehension |
| Max lines per config file | 200 | Context windows > 500K with demonstrated comprehension |
| Max lines per type definitions | 300 | Context windows > 500K with demonstrated comprehension |
| Max lines per function | 50 | AI demonstrates comprehension of longer functions |
| Max lines per class | 300 | AI demonstrates comprehension of larger classes |
| Max methods per class | 10 | AI demonstrates comprehension of larger classes |
| Max attributes per class | 10 | AI demonstrates comprehension of larger classes |

## Complexity Thresholds

*Current rationale: Industry standards + AI comprehension limits*

| Rule | Current Value | Review Trigger |
|------|---------------|----------------|
| Max cyclomatic complexity | 10 | Evidence of successful handling of higher complexity |
| Max cognitive complexity | 15 | Evidence of successful handling of higher complexity |
| Max function parameters | 5 | Evidence this causes more harm than good |
| Max nesting depth | 4 | Evidence this causes more harm than good |

## Coverage Thresholds

*Current rationale: Experience-based calibration*

| Rule | Current Value | Review Trigger |
|------|---------------|----------------|
| Minimum line coverage | 90% | Evidence different threshold is more effective |
| Minimum branch coverage | 90% | Evidence different threshold is more effective |
| Minimum function coverage | 90% | Evidence different threshold is more effective |
| New code coverage | 95% | Evidence different threshold is more effective |

## Tool Choices

*Current rationale: Best available tools for TIM stacks (2025)*

| Rule | Current Choice | Review Trigger |
|------|----------------|----------------|
| Python type checker | mypy --strict | Better tool emerges |
| Python linter/formatter | ruff | Better tool emerges |
| TypeScript compiler | tsc --strict | Better tool emerges |
| TypeScript linter | ESLint | Better tool emerges |
| TypeScript formatter | Prettier | Better tool emerges |
| Secrets scanner | detect-secrets / gitleaks | Better tool emerges |

## Stack Choices

*Current rationale: Best available for TIM requirements (2025)*

| Rule | Current Choice | Review Trigger |
|------|----------------|----------------|
| Python backend | FastAPI | Better framework for async APIs emerges |
| Python ORM | SQLAlchemy 2.0 async | Better ORM emerges |
| Python migrations | Alembic | Better migration tool emerges |
| Python validation | Pydantic v2 | Better validation library emerges |
| Node ORM | Prisma | Better ORM emerges |
| Node validation | Zod | Better validation library emerges |
| Database | PostgreSQL | Project requirements change |

## Deployment Parameters

*Current rationale: Operational experience*

| Rule | Current Value | Review Trigger |
|------|---------------|----------------|
| Remote-first deployment | Default | Project type doesn't fit remote model |
| Canary traffic split | 10% minimum | Operational data suggests different % |
| Canary observation window | 5 minutes | Operational data suggests different window |
| Canary min requests | 100 | Operational data suggests different threshold |
| Auto-rollback error threshold | 1% | Operational data suggests different threshold |
| Auto-rollback latency threshold | 2x P99 baseline | Operational data suggests different threshold |
| Secrets rotation (JWT) | Quarterly | Security guidance changes |
| Secrets rotation (API keys) | Annually | Security guidance changes |
| Execution approval expiration | 15 minutes | Operational needs change |

## Style & Formatting

*Current rationale: Readability + tool defaults*

| Rule | Current Value | Review Trigger |
|------|---------------|----------------|
| Python line length | 88 | Team preference / tooling changes |
| TypeScript line length | 100 | Team preference / tooling changes |
| Test naming convention | test_what_when_then | Better convention emerges |
| Commit message format | Conventional Commits | Team preference changes |

## Timing Limits

*Current rationale: CI/CD practicality*

| Rule | Current Value | Review Trigger |
|------|---------------|----------------|
| Unit test max duration | 1 second each | CI infrastructure changes |
| E2E test max (local) | 5 minutes | CI infrastructure changes |
| E2E test max (CI PR) | 10 minutes | CI infrastructure changes |
| E2E test max (pre-deploy) | 15 minutes | CI infrastructure changes |

## AI Behavioral Patterns

*Current rationale: Observed deflection behaviors*

| Rule | Current Value | Review Trigger |
|------|---------------|----------------|
| Excuse patterns | 76 across 15 categories | New patterns observed, false positives identified |

---

# CHANGING CONTEXTUAL RULES

## Requirements

To change a contextual rule, you must provide:

1. **Evidence** - Data or experience justifying the change
2. **Testing** - Validation that the new value works
3. **Documentation** - Updated rationale and review trigger

## Process

1. Propose change with evidence
2. Review with team
3. Test in non-production environment
4. Update this document
5. Update enforcement tools if applicable

## Change Log Template

```markdown
## YYYY-MM-DD: [Rule Name] Change

- **Old value:** X
- **New value:** Y
- **Evidence:** [What data/experience justified this?]
- **Tested in:** [Where was this validated?]
- **Changed by:** [Name]
- **Next review:** [When should we revisit?]
```

---

# CHANGE LOG

*No changes yet. This is the initial classification (2026-01-27).*
