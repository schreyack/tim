# TIM Design Standards

Authoritative standards for all TIM projects. Defense in depth. Never trust. Always verify.

## Quick Start

### New Project Setup
1. Copy `CLAUDE.md` to your project root
2. Copy templates from `templates/python/` or `templates/node/`
3. Run `pre-commit install`
4. Configure CI pipeline

### Existing Project Compliance
1. Review `standards/enforcement/gates.md` for requirements
2. Add pre-commit hooks (Gate 1)
3. Add CI pipeline (Gate 2)
4. Add deploy gates (Gate 3)

## Standards Overview

| Area | Document | Summary |
|------|----------|---------|
| **Enforcement** | [gates.md](standards/enforcement/gates.md) | What blocks merges and deploys |
| **AI Review** | [ai-review-checklist.md](standards/enforcement/ai-review-checklist.md) | Human review checklist for AI code |
| **Python** | [python.md](standards/coding/python.md) | mypy strict, ruff, FastAPI patterns |
| **TypeScript** | [typescript.md](standards/coding/typescript.md) | strict mode, ESLint, Prisma |
| **Testing** | [requirements.md](standards/testing/requirements.md) | 90% coverage, TDD workflow |
| **E2E Testing** | [e2e-requirements.md](standards/testing/e2e-requirements.md) | True e2e, route discovery, user journeys |
| **Security** | [owasp-checklist.md](standards/security/owasp-checklist.md) | OWASP Top 10 coverage |
| **Database** | [migrations.md](standards/database/migrations.md) | Migration requirements |
| **Feature Flags** | [feature-flags.md](standards/deployment/feature-flags.md) | Ship features safely |
| **Canary** | [canary.md](standards/deployment/canary.md) | 10% rollout, auto-rollback |
| **Observability** | [observability.md](standards/deployment/observability.md) | Logs, metrics, traces, alerts |
| **Ops Script** | [ops-script.md](standards/deployment/ops-script.md) | Deployment operations interface |

## Three-Gate Model

```
┌─────────────────────────────────────────────────────────────┐
│  GATE 1: LOCAL (Pre-commit)                                 │
│  Type check → Lint → Format → Secrets scan                  │
│  BLOCKS: git commit                                         │
├─────────────────────────────────────────────────────────────┤
│  GATE 2: CI (Pull Request)                                  │
│  Gate 1 + Tests + Coverage (90%) + Security scan            │
│  BLOCKS: PR merge                                           │
├─────────────────────────────────────────────────────────────┤
│  GATE 3: DEPLOY (Pre-deployment)                            │
│  Integration + E2E + Canary (10%) + Human approval          │
│  BLOCKS: Production deploy                                  │
└─────────────────────────────────────────────────────────────┘
```

## AI Development Context

TIM develops exclusively with AI. All standards are designed for this context:

- **Strict rules are appropriate** - AI doesn't fatigue
- **Hard gates catch AI mistakes** - Plausible bugs need verification
- **Human review is critical** - Use the AI review checklist

## Technology Stacks

### Python Stack
- FastAPI + SQLAlchemy 2.0 (async) + Alembic
- Next.js (TypeScript) frontend
- PostgreSQL + Celery/Redis
- Docker Compose / Kubernetes

### Node.js Stack
- Express or NestJS (TypeScript strict)
- React (TypeScript) frontend
- PostgreSQL + Prisma
- Docker Compose / Kubernetes

## Key Requirements

| Requirement | Threshold | Enforcement |
|-------------|-----------|-------------|
| Type safety | 100% | Pre-commit + CI |
| Test coverage | 90% | CI blocks merge |
| Security vulns | 0 HIGH/CRITICAL | CI blocks merge |
| Secrets in code | 0 | Pre-commit blocks |

## Templates

Ready-to-copy configuration files:

- `templates/python/pyproject.toml` - Poetry + ruff + mypy
- `templates/python/.pre-commit-config.yaml` - Python pre-commit hooks
- `templates/node/package.json` - TypeScript + ESLint
- `templates/node/tsconfig.json` - Strict TypeScript
- `templates/node/.pre-commit-config.yaml` - Node pre-commit hooks
