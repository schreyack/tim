# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is the **TIM Design Standards** repository - the authoritative source for coding, testing, security, and deployment standards used across all TIM projects.

**Philosophy**: Defense in depth. Never trust. Always verify. Build systems that ENFORCE rules, not just document them.

**Stakes**: $20K+/minute downtime costs, millions in data breach liability. These aren't guidelines - they're requirements.

## Approved Technology Stacks

### Stack 1: Python
- **Backend**: FastAPI + SQLAlchemy 2.0 (async) + Alembic migrations
- **Frontend**: Next.js 16+ with TypeScript
- **Database**: PostgreSQL
- **Queue**: Celery + Redis
- **Deployment**: Docker Compose / Kubernetes

### Stack 2: Node.js (TypeScript-First)
- **Backend**: Express.js or NestJS with TypeScript (strict mode)
- **Frontend**: React 18+ with TypeScript
- **ORM**: Prisma (recommended) or Sequelize with CLI migrations
- **Database**: PostgreSQL
- **Deployment**: Docker Compose / Kubernetes

**Non-Negotiable**: Both stacks require strict type checking. No vanilla JavaScript. No `any` types.

## Repository Structure

```
design_standards/
├── CLAUDE.md                    # This file - copy to new TIM projects
├── README.md                    # Quick reference guide
├── standards/
│   ├── enforcement/             # Gate definitions, AI review checklist
│   ├── coding/                  # Language-specific standards
│   ├── testing/                 # Test requirements and patterns
│   ├── security/                # Security requirements
│   ├── database/                # Migration and backup requirements
│   ├── deployment/              # Containers, feature flags, canary, observability
│   └── incident/                # Incident response procedures
├── templates/                   # Ready-to-copy configuration files
│   ├── python/                  # Python project templates
│   └── node/                    # Node.js project templates
└── examples/                    # Working reference implementations
```

## Three-Gate Enforcement Model

All TIM projects must implement three enforcement gates:

### Gate 1: Local (Pre-commit)
Runs on every commit attempt. Blocks commit on failure.
- Type checking (mypy/tsc)
- Linting (ruff/ESLint)
- Formatting (ruff/Prettier)
- Secrets detection

### Gate 2: CI (Pull Request)
Runs on every PR. Blocks merge on failure.
- All Gate 1 checks (server-side enforcement)
- Test suite (100% pass required)
- Coverage threshold (90% minimum)
- Security scanning (HIGH/CRITICAL = blocked)
- Container scanning

### Gate 3: Deploy (Pre-deployment)
Runs before production deployment. Blocks deploy on failure.
- Integration tests
- E2E tests (critical paths, max 15 min)
- Database migration dry-run
- Health check validation
- Security header verification
- Canary deployment (10% traffic)
- Manual approval with AI-specific checklist

## AI Development Context

TIM develops exclusively with AI developers. This context informs all standards:

- **Strict rules are appropriate** - AI doesn't fatigue from strict enforcement
- **Hard gates catch AI mistakes** - Plausible-sounding bugs need verification
- **Fast iteration is expected** - Quick failure, quick fix, quick retry
- **Human review is critical** - See `standards/enforcement/ai-review-checklist.md`

## Hard Rules (No Exceptions)

### Code Quality
- **Python**: `mypy --strict` must pass. `ruff` with security rules enabled.
- **TypeScript**: `strict: true` in tsconfig. `eslint --max-warnings 0`.
- **Coverage**: 90% minimum (line, branch, function). New code requires 95%.

### Security
- **Secrets**: NEVER committed. Pre-commit hook blocks. No default values.
- **Input validation**: All external input validated (Pydantic/Zod).
- **Headers**: CSP, HSTS, X-Content-Type-Options, X-Frame-Options required.
- **Dependencies**: HIGH/CRITICAL vulnerabilities block merge.

### Database
- **Migrations only**: No `sequelize.sync()`, no `db.create_all()`, no manual DDL.
- **Rollback required**: Every migration must have a tested rollback.

### Testing
- **Naming**: `test_<what>_<when>_<then>` format required.
- **TDD**: Red-green-refactor workflow for new features.

## Using This Repository

### For New TIM Projects
1. Copy this `CLAUDE.md` to the new project root
2. Copy templates from `templates/python/` or `templates/node/`
3. Configure CI pipeline using templates
4. Reference `standards/` documents for detailed requirements

### For Existing Projects
1. Run compliance check against current standards
2. Create remediation plan for gaps
3. Implement pre-commit hooks first (Gate 1)
4. Add CI pipeline checks (Gate 2)
5. Implement deploy gates (Gate 3)

## Quick Reference

| Standard | Python | Node.js |
|----------|--------|---------|
| Type checking | mypy --strict | tsc strict mode |
| Linting | ruff | ESLint |
| Formatting | ruff format | Prettier |
| Testing | pytest | Jest/Vitest |
| Coverage | pytest-cov (90%) | coverage (90%) |
| ORM | SQLAlchemy + Alembic | Prisma |
| Validation | Pydantic | Zod |
| Secrets scan | detect-secrets | gitleaks |
| Security scan | bandit + safety | npm audit + Snyk |
| Container scan | trivy | trivy |

## Commit Message Format

Use Conventional Commits:
```
feat: add user authentication
fix: resolve token expiration bug
refactor: simplify database queries
test: add coverage for billing service
docs: update API documentation
```

Always include co-author line:
```
Co-Authored-By: Claude <model>/<version> <noreply@anthropic.com>
```
