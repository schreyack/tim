# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is the **TIM Design Standards** repository - the authoritative source for coding, testing, security, and deployment standards used across all TIM projects.

**Philosophy**: Defense in depth. Never trust. Always verify. Build systems that ENFORCE rules, not just document them. If a rule can be bypassed, an AI will bypass it.

**Stakes**: $20K+/minute downtime costs, millions in data breach liability. These aren't guidelines - they're requirements.

## Critical: AI Development Context

TIM develops exclusively with AI developers. This context informs EVERYTHING:

- **Strict rules are appropriate** - AI doesn't fatigue from strict enforcement
- **Hard gates catch AI mistakes** - Plausible-sounding bugs need verification
- **NO bypass flags anywhere** - If AI can bypass, AI will bypass
- **Human approval is the escape hatch** - For undefined or blocked operations
- **Fast iteration is expected** - Quick failure, quick fix, quick retry
- **Human review is critical** - See `standards/enforcement/ai-review-checklist.md`

## Approved Technology Stacks

### Stack 1: Python
- **Backend**: FastAPI + SQLAlchemy 2.0 (async) + Alembic migrations
- **Frontend**: Next.js 16+ with TypeScript
- **Database**: PostgreSQL
- **Queue**: Celery + Redis
- **Shared Library**: tim-lib (REQUIRED)
- **Deployment**: Docker Compose / Kubernetes

### Stack 2: Node.js (TypeScript-First)
- **Backend**: Express.js or NestJS with TypeScript (strict mode)
- **Frontend**: React 18+ with TypeScript
- **ORM**: Prisma (recommended) or Sequelize with CLI migrations
- **Database**: PostgreSQL
- **Shared Library**: @tim/lib (REQUIRED)
- **Deployment**: Docker Compose / Kubernetes

**Non-Negotiable**: Both stacks require strict type checking. No vanilla JavaScript. No `any` types.

## Repository Structure

```
design_standards/
├── CLAUDE.md                    # This file - copy to new TIM projects
├── README.md                    # Quick reference guide
├── standards/
│   ├── enforcement/             # Gate definitions, compliance, AI review
│   │   ├── gates.md             # Three-gate model
│   │   ├── ai-review-checklist.md
│   │   └── strict-compliance.md # Pattern registry enforcement
│   ├── architecture/
│   │   └── shared-libraries.md  # Required library usage
│   ├── coding/                  # Language-specific standards
│   ├── testing/                 # Test requirements and patterns
│   ├── security/                # Security requirements + secrets.md
│   ├── database/                # Migration and backup requirements
│   └── deployment/              # CI/CD, ops, feature flags, canary, observability
├── libs/                        # Shared libraries (REQUIRED in all projects)
│   ├── python/                  # tim-lib Python package
│   └── node/                    # @tim/lib Node.js package
├── templates/                   # Ready-to-copy configuration files
│   ├── python/                  # Python project templates
│   ├── node/                    # Node.js project templates
│   ├── ci/                      # CI pipeline templates
│   ├── ops/                     # ops.sh templates
│   └── tim-patterns.yaml.template
└── tools/                       # Enforcement tools
    ├── tim-compliance-check.sh  # Compliance verification
    └── tim-ops-approve          # Human approval for ops
```

## Four-Gate Enforcement Model

All TIM projects must implement four enforcement gates:

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

### Gate 4: Pattern Compliance
Runs at deploy time. Blocks deploy if non-compliant.
- All patterns registered in `.tim-patterns.yaml`
- CUSTOM patterns have human approval
- Shared library is installed
- No secrets in code

## Shared Libraries (REQUIRED)

Every TIM project MUST use the shared libraries:

### Python
```python
from tim_lib import (
    BaseAppSettings,           # Pydantic settings with validation
    configure_logging, get_logger,
    hash_password, verify_password,
    create_access_token, verify_token,
    AppError, NotFoundError, ValidationError,
    setup_exception_handlers,
    create_async_engine_with_pool, get_session_factory,
)
```

### Node.js
```typescript
import {
  createConfig, baseEnvSchema,
  createLogger, LogContextMiddleware,
  hashPassword, verifyPassword,
  createAccessToken, verifyToken,
  AppError, NotFoundError, ValidationError,
  setupErrorHandlers, securityHeadersMiddleware,
} from "@tim/lib";
```

## Pattern Registry

Every project MUST have `.tim-patterns.yaml` in the root:

```yaml
patterns:
  authentication:
    standard: "jwt-bearer"
    reference: "standards/security/authentication.md"
    implemented: true

  # For patterns without TIM standards:
  custom_audio_processing:
    standard: "CUSTOM"
    justification: "No TIM standard exists for audio DSP"
    approved_by: "human@example.com"  # REQUIRED
    approved_date: "2025-01-15"
    ticket: "STANDARDS-42"            # REQUIRED
```

If code uses an unregistered or unapproved pattern, deployment is BLOCKED.

## ops.sh Safety Tiers (NO BYPASS FLAGS)

| Tier | Behavior | Examples |
|------|----------|----------|
| **SAFE** | Always allowed | status, health, logs, backup |
| **MODERATE** | Allowed with logging | deploy, restart, migrate |
| **HUMAN_REQUIRED** | Requires human approval | rollback, stop, db:rollback |
| **BLOCKED** | Never allowed in ops.sh | destroy, db:restore |

For HUMAN_REQUIRED operations:
1. AI attempts operation → creates approval request
2. Human reviews and runs `tim-ops-approve <request_id>`
3. AI retries operation → succeeds with valid approval

BLOCKED operations MUST be performed manually via SSH.

## Hard Rules (No Exceptions)

### Code Quality
- **Python**: `mypy --strict` must pass. `ruff` with security rules enabled.
- **TypeScript**: `strict: true` in tsconfig. `eslint --max-warnings 0`.
- **Coverage**: 90% minimum (line, branch, function). New code requires 95%.
- **Shared Library**: tim-lib/@tim/lib MUST be used for common patterns.

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

### Patterns
- **Registry required**: Every design pattern must be in `.tim-patterns.yaml`
- **CUSTOM requires approval**: Human must approve with ticket reference
- **Standards first**: Check for existing standard before creating CUSTOM

## Using This Repository

### For New TIM Projects
1. Copy this `CLAUDE.md` to the new project root
2. Copy templates from `templates/python/` or `templates/node/`
3. Install shared library: `pip install ./lib/design_standards/libs/python` or `npm install ./lib/design_standards/libs/node`
4. Copy `.tim-patterns.yaml` template and register patterns
5. Configure CI pipeline from `templates/ci/`
6. Run `tools/tim-compliance-check.sh` to verify setup

### For Existing Projects
1. Run `tools/tim-compliance-check.sh` to identify gaps
2. Create remediation plan for gaps
3. Install shared library
4. Create `.tim-patterns.yaml` and register all patterns
5. Implement pre-commit hooks (Gate 1)
6. Add CI pipeline (Gate 2)
7. Implement deploy gates (Gate 3 + 4)

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
| Shared lib | tim-lib | @tim/lib |

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
