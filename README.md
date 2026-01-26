# TIM Design Standards

Authoritative standards for all TIM projects. Defense in depth. Never trust. Always verify.

**Philosophy**: 100% of TIM development is done by AI developers. These standards are designed to enforce rules automatically - not just document them. If a rule can be bypassed, an AI will bypass it.

## Quick Start

### New Project Setup
1. Copy `CLAUDE.md` to your project root
2. Copy templates from `templates/python/` or `templates/node/`
3. Install shared library: `pip install ./lib/design_standards/libs/python` or `npm install ./lib/design_standards/libs/node`
4. Copy `.tim-patterns.yaml` template and register your patterns
5. Run `pre-commit install`
6. Configure CI pipeline using templates from `templates/ci/`

### Existing Project Migration
1. Run `tools/tim-compliance-check.sh` to assess current state
2. Follow [Legacy Onboarding Playbook](standards/operations/legacy-onboarding.md)
3. Start at enforcement Level 0 (audit only)
4. Use [Graduated Enforcement](standards/enforcement/graduated-enforcement.md) to progressively tighten
5. Migrate tests using [Test Migration Standard](standards/testing/test-migration.md)
6. Reach Level 4 (full enforcement) before production

### Tim Loop Plugin & plan-ops

Tim Loop is a Claude Code plugin for AI-driven development with guaranteed completion. It includes `plan-ops` for plan lifecycle management.

**Install the plugin:**
```bash
# In Claude Code
/plugin marketplace add schreyack/design_standards
/plugin install tim-loop@tim-design-standards
```

**Add plan-ops to your PATH (one-time setup):**
```bash
# 1. Add to your shell config (~/.zshrc or ~/.bashrc)
export PATH="$HOME/.claude/plugins/marketplaces/tim-design-standards/bin:$PATH"

# 2. Reload your shell
source ~/.zshrc   # or: source ~/.bashrc

# 3. Verify it works
plan-ops help
```

**Now you can run plan-ops from any directory:**
```bash
plan-ops init                              # Initialize plans/ folder
plan-ops import ~/.claude/plans/my-plan.md # Import a plan
plan-ops wizard plans/drafts/my-plan.md    # Guided workflow
plan-ops list                              # List all plans
```

See [plugins/tim-loop/README.md](plugins/tim-loop/README.md) for full documentation.

## Repository Structure

```
design_standards/
├── CLAUDE.md                    # Copy to new TIM projects
├── README.md                    # This file
├── standards/
│   ├── enforcement/             # Gate definitions, compliance
│   │   ├── gates.md             # Four-gate model
│   │   ├── graduated-enforcement.md  # Migration levels
│   │   ├── ai-instruction-enforcement.md  # Detect AI ignoring CLAUDE.md
│   │   ├── ai-review-checklist.md
│   │   └── strict-compliance.md # Pattern registry enforcement
│   ├── operations/              # Multi-AI coordination, migration, plans
│   │   ├── ai-coordination.md   # Worktree/branch strategy
│   │   ├── legacy-onboarding.md # Migration playbook
│   │   ├── plan-management.md   # Plan lifecycle & approval
│   │   └── tim-loop-integration.md    # Tim Loop for plan execution
│   ├── architecture/
│   │   └── shared-libraries.md  # Library strategy
│   ├── coding/                  # Language standards
│   ├── testing/                 # Test requirements
│   ├── security/                # Security standards
│   │   ├── owasp-checklist.md
│   │   ├── secrets.md           # Secrets management
│   │   └── authentication.md    # JWT, password hashing
│   ├── database/                # Migration standards
│   ├── deployment/              # CI/CD, ops, observability
│   └── incident/                # Incident response
│       └── response.md          # Procedures, post-mortems
├── libs/                        # Shared libraries (REQUIRED)
│   ├── python/                  # tim-lib Python package
│   └── node/                    # @tim/lib Node.js package
├── templates/                   # Ready-to-copy configs
│   ├── python/
│   ├── node/
│   ├── ci/                      # CI pipeline templates
│   ├── ops/                     # ops.sh templates
│   └── tim-patterns.yaml.template
└── tools/                       # Enforcement tools
    ├── tim-compliance-check.sh  # Compliance verification
    └── tim-ops-approve          # Human approval for ops
```

## Standards Overview

| Area | Document | Summary |
|------|----------|---------|
| **Enforcement** | [gates.md](standards/enforcement/gates.md) | What blocks merges and deploys |
| **Graduated Enforcement** | [graduated-enforcement.md](standards/enforcement/graduated-enforcement.md) | Migration levels (0-4) |
| **AI Instruction Enforcement** | [ai-instruction-enforcement.md](standards/enforcement/ai-instruction-enforcement.md) | Catch when AI ignores CLAUDE.md |
| **Compliance** | [strict-compliance.md](standards/enforcement/strict-compliance.md) | Pattern registry, human approval workflow |
| **AI Review** | [ai-review-checklist.md](standards/enforcement/ai-review-checklist.md) | Human review checklist for AI code |
| **AI Coordination** | [ai-coordination.md](standards/operations/ai-coordination.md) | Multi-AI developer coordination |
| **Legacy Onboarding** | [legacy-onboarding.md](standards/operations/legacy-onboarding.md) | Migration playbook for existing projects |
| **Plan Management** | [plan-management.md](standards/operations/plan-management.md) | Plan lifecycle, Ralph Loop, Tim Loop |
| **Test Migration** | [test-migration.md](standards/testing/test-migration.md) | Convert tests to TIM standards |
| **Shared Libs** | [shared-libraries.md](standards/architecture/shared-libraries.md) | Required library usage |
| **Code Organization** | [code-organization.md](standards/coding/code-organization.md) | File size limits, complexity (AI-critical) |
| **Python** | [python.md](standards/coding/python.md) | mypy strict, ruff, FastAPI patterns |
| **TypeScript** | [typescript.md](standards/coding/typescript.md) | strict mode, ESLint, Prisma |
| **API Versioning** | [api-versioning.md](standards/coding/api-versioning.md) | URL path versioning, deprecation |
| **Testing** | [requirements.md](standards/testing/requirements.md) | 90% coverage, TDD workflow |
| **E2E Testing** | [e2e-requirements.md](standards/testing/e2e-requirements.md) | True e2e, route discovery |
| **Security** | [owasp-checklist.md](standards/security/owasp-checklist.md) | OWASP Top 10 coverage |
| **Secrets** | [secrets.md](standards/security/secrets.md) | Secrets management, rotation |
| **Authentication** | [authentication.md](standards/security/authentication.md) | JWT, password hashing |
| **Database** | [migrations.md](standards/database/migrations.md) | Migration requirements |
| **Incident Response** | [response.md](standards/incident/response.md) | Incident handling, post-mortems |
| **CI/CD** | [ci-integration.md](standards/deployment/ci-integration.md) | Pipeline + ops.sh integration |
| **Feature Flags** | [feature-flags.md](standards/deployment/feature-flags.md) | Ship features safely |
| **Canary** | [canary.md](standards/deployment/canary.md) | 10% rollout, auto-rollback |
| **Observability** | [observability.md](standards/deployment/observability.md) | Logs, metrics, traces, alerts |
| **Ops Script** | [ops-script.md](standards/deployment/ops-script.md) | Deployment operations interface |
| **Ops Security** | [ops-security.md](standards/deployment/ops-security.md) | Ops script security, audit logging |

## Four-Gate Enforcement Model

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
├─────────────────────────────────────────────────────────────┤
│  GATE 4: PATTERN COMPLIANCE                                 │
│  All patterns registered in .tim-patterns.yaml              │
│  CUSTOM patterns require human approval                     │
│  BLOCKS: Deployment if non-compliant                        │
└─────────────────────────────────────────────────────────────┘
```

## Shared Libraries (Required)

Every TIM project MUST use the shared libraries. This ensures:
- Consistent patterns across all projects
- Central maintenance of common code
- Automatic security updates

### Python Projects
```bash
# Install tim-lib
pip install ./lib/design_standards/libs/python
# or add to pyproject.toml dependencies
```

```python
from tim_lib import (
    BaseAppSettings,
    configure_logging, get_logger,
    hash_password, verify_password,
    create_access_token, verify_token,
    AppError, NotFoundError, ValidationError,
)
```

### Node.js Projects
```bash
# Install @tim/lib
npm install ./lib/design_standards/libs/node
```

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

Every project must have a `.tim-patterns.yaml` file registering all design patterns used. If a pattern is not registered or not approved, deployment is blocked.

```yaml
# .tim-patterns.yaml
patterns:
  authentication:
    standard: "jwt-bearer"
    reference: "standards/security/authentication.md"
    implemented: true

  database_access:
    standard: "sqlalchemy-async"  # or "prisma"
    reference: "standards/coding/python.md#sqlalchemy-patterns"
    implemented: true

  # For patterns without TIM standards:
  custom_audio_processing:
    standard: "CUSTOM"
    justification: "No TIM standard exists for audio DSP"
    approved_by: "human@example.com"
    approved_date: "2025-01-15"
    ticket: "STANDARDS-42"
```

## ops.sh Safety Tiers

The ops.sh script has NO bypass flags. Operations are either allowed or require human approval.

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

## AI Development Context

TIM develops exclusively with AI. All standards are designed for this context:

- **Strict rules are appropriate** - AI doesn't fatigue from strict enforcement
- **Hard gates catch AI mistakes** - Plausible bugs need verification
- **No bypass flags** - If AI can bypass, AI will bypass
- **Human approval is the escape hatch** - For undefined or blocked operations
- **Human review is critical** - Use the AI review checklist

## Technology Stacks

### Python Stack
- FastAPI + SQLAlchemy 2.0 (async) + Alembic
- Next.js (TypeScript) frontend
- PostgreSQL + Celery/Redis
- Docker Compose / Kubernetes
- tim-lib shared library

### Node.js Stack
- Express or NestJS (TypeScript strict)
- React (TypeScript) frontend
- PostgreSQL + Prisma
- Docker Compose / Kubernetes
- @tim/lib shared library

## Key Requirements

| Requirement | Threshold | Enforcement |
|-------------|-----------|-------------|
| Type safety | 100% | Pre-commit + CI |
| Test coverage | 90% | CI blocks merge |
| Security vulns | 0 HIGH/CRITICAL | CI blocks merge |
| Secrets in code | 0 | Pre-commit blocks |
| Pattern compliance | 100% | Deploy blocks |
| Shared lib usage | Required | Compliance check |
| **File size** | **400 lines max** | **CI blocks merge** |
| **Function size** | **50 lines max** | **CI blocks merge** |
| **Complexity** | **10 max** | **CI blocks merge** |

## Templates

Ready-to-copy configuration files:

**Python**
- `templates/python/pyproject.toml` - Poetry + ruff + mypy
- `templates/python/.pre-commit-config.yaml` - Python pre-commit hooks

**Node.js**
- `templates/node/package.json` - TypeScript + ESLint
- `templates/node/tsconfig.json` - Strict TypeScript
- `templates/node/.pre-commit-config.yaml` - Node pre-commit hooks

**CI/CD**
- `templates/ci/python-ci.yml` - GitHub Actions for Python
- `templates/ci/node-ci.yml` - GitHub Actions for Node.js

**Ops**
- `templates/ops/tim-ops-lib.sh` - Shared ops library
- `templates/ops/ops-config.yaml.template` - Project config template

**Project Setup**
- `templates/CLAUDE.md.template` - Project CLAUDE.md template (customize per project)

**Compliance**
- `templates/tim-patterns.yaml.template` - Pattern registry template

## Compliance Verification

Run the compliance checker before deployment:

```bash
./tools/tim-compliance-check.sh /path/to/project
```

This verifies:
- Required files exist (CLAUDE.md, .tim-patterns.yaml, etc.)
- Shared library is installed
- Configuration is correct (strict mode, coverage threshold)
- No secrets in code
- All patterns are registered
- CUSTOM patterns have human approval
