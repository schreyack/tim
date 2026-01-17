# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## STOP AND READ: Critical Rules

**Before doing ANYTHING, read and understand these rules. They are not optional.**

### Rule 1: Never Prioritize Speed Over Process

This is the most critical rule. No matter what:
- Follow the rules in this document exactly
- If uncertain about the correct approach, **ASK the user** rather than guessing
- Never take shortcuts that could cause problems later

### Rule 2: Ask Before Assuming

When encountering complicated problems:
- Investigate root causes thoroughly before implementing fixes
- If in doubt about the approach, **pause and ask for instructions**
- Avoid quick workarounds that mask underlying issues

---

## Execution Environment

**This repository (design_standards) is local-only.** All commands execute on your machine.

- This is a documentation/standards repository - no application to deploy
- Tests: Run locally if any test infrastructure exists
- File operations: Standard local editing

---

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

---

## Repository Structure

```
design_standards/
├── CLAUDE.md                    # This file - copy to new TIM projects
├── README.md                    # Quick reference guide
├── standards/
│   ├── enforcement/             # Gate definitions, compliance, AI review
│   │   ├── gates.md             # Four-gate model
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

---

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

---

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

---

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

---

## Remote-Only Deployment (MANDATORY)

**All deployments are remote. No local environments. No exceptions.**

### Three Required Environments

| Environment | Access | Restrictions |
|-------------|--------|--------------|
| **dev** | All developers | Minimal (sandbox only) |
| **uat** | QA team, tech leads | Moderate |
| **prod** | DevOps/SRE only | Maximum |

### The --env Flag is REQUIRED

```bash
# ALWAYS specify environment
./ops.sh --env dev deploy     # Deploy to dev
./ops.sh --env uat deploy     # Deploy to UAT
./ops.sh --env prod deploy --ticket PROJ-123  # Deploy to prod

# This will FAIL
./ops.sh deploy               # ERROR: --env required
```

### Configuration Files

| File | In Git? | Purpose |
|------|---------|---------|
| `environments.yaml` | NO (.gitignore) | Connection details per environment |
| `environments.yaml.example` | YES | Template showing structure |
| `ops-config.yaml` | YES | Project settings (services, database) |

See `standards/deployment/environments.md` for full schema.
See `standards/deployment/command-matrix.md` for per-environment restrictions.

---

## ops.sh Safety Tiers (NO BYPASS FLAGS)

**Safety tiers vary by environment.** Dev is permissive. Prod is restrictive.

| Tier | Behavior | Examples |
|------|----------|----------|
| **SAFE** | Always allowed | status, health, logs, backup |
| **MODERATE** | Allowed with logging | deploy, restart, migrate |
| **HUMAN_REQUIRED** | Requires human approval | rollback, stop, db:rollback |
| **BLOCKED** | Never allowed in ops.sh | destroy, db:restore |

**Example: `shell` command by environment:**
- Dev: SAFE (debug freely)
- UAT: MODERATE (allowed, logged)
- Prod: BLOCKED (data theft risk)

For HUMAN_REQUIRED operations:
1. AI attempts operation → creates approval request
2. Human reviews and runs `tim-ops-approve <request_id>`
3. AI retries operation → succeeds with valid approval

BLOCKED operations MUST be performed manually via SSH.

### Never Do These (in projects using ops.sh)

| DO NOT | WHY |
|--------|-----|
| Run `ssh` commands directly | Bypasses safety controls |
| Run `docker exec` directly | Can execute destructive operations |
| Run SQL directly on database | No validation, no audit trail |
| Run `docker-compose up` locally | No local environments allowed |

**If you need to interact with a remote server, use `./ops.sh --env <env>`. No exceptions.**

---

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

---

## Mandatory: Single Source of Truth

Every piece of data, configuration, or definition must have exactly one authoritative source.

### Why This Matters
- Prevents inconsistency when values change
- Eliminates "which one is correct?" ambiguity
- Makes updates atomic - change once, apply everywhere

### Applying the Principle
1. **Identify the source of truth** - Where should this value be defined?
2. **Define it once** - Add to the authoritative source
3. **Import, don't duplicate** - All consumers reference the source
4. **Update the source** - When changes are needed, change only the source

### Anti-patterns to Avoid
- Hardcoding the same value in multiple files
- Creating "local" versions of shared constants
- Copying test data between test files instead of importing
- Duplicating validation logic instead of sharing utilities

---

## Mandatory: Code Quality Rules

### No TODOs or Placeholders

- **NO `TODO`, `FIXME`, `XXX`, `HACK` comments** - Implement fully or don't add it
- **NO placeholder code** - No `raise NotImplementedError`, no `pass`, no `...`
- **NO print debugging** - Use logging module (`structlog`, `logging`)
- **NO bare except clauses** - Catch specific exceptions

### Type Safety

- **ALL functions must have type hints** (parameters and return types)
- **Use `mypy --strict`** (Python) or **`tsc --strict`** (TypeScript)
- **No `any` types** in TypeScript

### Error Handling

- Catch specific exceptions, not `Exception` or bare `except:`
- Include context in error messages (user ID, relevant IDs)
- Log errors server-side with context for debugging
- Never expose internal details to clients

### Security

- Validate all user input server-side
- Use parameterized queries (never string interpolation for SQL)
- Validate authorization for all operations
- Never commit secrets, credentials, or .env files

---

## Mandatory: Test Requirements

**No changes are complete without testing.**

### Test Naming Convention

Use `test_<what>_<when>_<expected>` format:

```python
def test_login_with_valid_credentials_returns_token():
def test_upload_with_invalid_format_returns_400():
def test_create_user_when_email_exists_raises_error():
```

### Test Coverage

- **Minimum 90% coverage** - All new code must meet this bar
- **Both unit and integration tests** - Test in isolation AND with real dependencies
- **E2E tests for critical paths** - Test full user workflows

### Bug Fix Protocol

When a bug is reported:
1. **Write a test that reproduces the bug FIRST**
2. **Run the test - verify it FAILS**
3. **Fix the bug**
4. **Run the test - verify it PASSES**
5. **Run all tests to ensure no regressions**

### Completion Checklist

A task is NOT complete until:
- [ ] All implementation steps are done (no TODOs, no placeholders)
- [ ] Tests exist and pass (unit, integration, E2E as appropriate)
- [ ] Code is deployed (if applicable)
- [ ] Manual verification confirms the fix/feature works
- [ ] No errors in logs

---

## Using This Repository

### For New TIM Projects
1. Copy this `CLAUDE.md` to the new project root
2. Copy templates from `templates/python/` or `templates/node/`
3. Install shared library: `pip install ./lib/design_standards/libs/python` or `npm install ./lib/design_standards/libs/node`
4. Copy `.tim-patterns.yaml` template and register patterns
5. Configure CI pipeline from `templates/ci/`
6. **Set up remote environments:**
   - Copy `templates/environments.yaml.example` to project root
   - Add `environments.yaml` to `.gitignore`
   - Configure dev/uat/prod remote servers
   - Create `environments.yaml` with real connection details
7. Run `tools/tim-compliance-check.sh` to verify setup

### For Existing Projects
1. Run `tools/tim-compliance-check.sh` to identify gaps
2. Create remediation plan for gaps
3. Install shared library
4. Create `.tim-patterns.yaml` and register all patterns
5. Implement pre-commit hooks (Gate 1)
6. Add CI pipeline (Gate 2)
7. Implement deploy gates (Gate 3 + 4)
8. **Migrate to remote-only deployment:**
   - Remove local docker-compose configurations
   - Set up remote dev environment
   - Update team workflow to use `./ops.sh --env dev`

---

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

---

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

---

## Mandatory: Plan Lifecycle Management

All plans MUST use the project's `plans/` folder with lifecycle subfolders.

### Folder Structure

```
plans/
├── drafts/      # Plans being designed (not yet approved)
├── active/      # Approved plans under implementation
├── completed/   # Successfully executed plans
└── abandoned/   # Cancelled plans (preserves learnings)
```

**Naming convention:** `YYYY-MM-DD-<project>-<description>.md`

### Plan Lifecycle

1. **Draft** - Claude creates plan, imports to `plans/drafts/`
2. **Ralph Review** - Multi-phase plans (2+ phases) MUST complete Ralph Loop review
3. **Active** - Human approves, moves to `plans/active/`
4. **Completed** - All phases done, moves to `plans/completed/`
5. **Abandoned** - Cancelled with reason, moves to `plans/abandoned/`

### Ralph Loop Gate (MANDATORY for Multi-Phase Plans)

Plans with 2+ phases **cannot be promoted** until Ralph Loop review is completed:

```bash
# 1. Show Ralph Loop command
./tools/plan-ops.sh ralph plans/drafts/my-plan.md

# 2. Run the displayed /ralph-loop command in Claude Code

# 3. Mark review complete
./tools/plan-ops.sh ralph plans/drafts/my-plan.md --mark-complete

# 4. Now promotion is allowed
./tools/plan-ops.sh promote plans/drafts/my-plan.md --approver "Name"
```

Single-phase plans can skip Ralph Loop and promote directly.

### Tim Loop Execution Gate (HARD ENFORCED)

Active plans require **human approval** before execution. AI cannot bypass this.

```bash
# 1. AI requests execution (creates approval request, BLOCKS)
./tools/plan-ops.sh execute plans/active/my-plan.md

# 2. HUMAN approves in separate terminal
./tools/plan-ops.sh approve-execute <request-id> --approver "Name"

# 3. AI retries (now outputs tim-loop command)
./tools/plan-ops.sh execute plans/active/my-plan.md

# 4. Run the /tim-loop command
```

**Why AI cannot bypass:**
- No `--approver` flag exists
- Approval requires separate terminal session
- Tokens expire after 15 minutes

### Designing for Parallel Agent Execution

Plans should be designed for parallel agent execution. Include an Execution Strategy table:

| Phase | Task | Dependencies | Agent Type | Parallelizable |
|-------|------|--------------|------------|----------------|
| 1 | Search patterns | none | Explore | Yes |
| 1 | Search models | none | Explore | Yes |
| 2 | Implement | Phase 1 | Bash | No |

**Agent types:** `Explore` (search/research), `Plan` (design), `Bash` (commands)

**Guidelines:**
- Max 3 agents in parallel
- Don't parallelize tasks that modify the same files
- Break large tasks into smaller parallelizable units

See `standards/operations/plan-management.md` for full guidance.

### MANDATORY: Cleanup ~/.claude/plans

When Claude Code creates plans in `~/.claude/plans/`:
1. Copy plan to `plans/drafts/` with proper naming
2. Add Status Header if missing
3. **DELETE the original from `~/.claude/plans/`**
4. Commit the new plan to git

**Never leave orphan plans in `~/.claude/plans/`** - they accumulate indefinitely.

### Status Header (Required)

Every plan MUST start with:

```markdown
## Status

| Field | Value |
|-------|-------|
| Stage | draft / active / completed / abandoned |
| Created | 2025-01-16 14:30 |
| Last Updated | 2025-01-16 16:45 |
| Author | Claude Opus 4.5 |
| Approver | [human name or "-"] |
| Ralph Review | required / completed / not-required |
| Ralph Date | [YYYY-MM-DD or "-"] |
| Execution Approved | yes / no |
| Execution Approved By | [human name or "-"] |
| Execution Started | [YYYY-MM-DD HH:MM or "-"] |

### Progress Log

| Timestamp | Stage | Event |
|-----------|-------|-------|
| 2025-01-16 14:30 | draft | Plan created |
```

**Ralph Review values:**
- `required` - Multi-phase plan, Ralph Loop not yet done
- `completed` - Ralph Loop finished, ready for promotion
- `not-required` - Single-phase plan

### Plan Requirements

Every plan MUST include:
1. **Problem/Goal** - What needs to be done
2. **Implementation Steps** - Technical approach
3. **Testing Strategy** - How to verify changes
4. **Completion Criteria** - What "done" looks like

### Automation

Use `./tools/plan-ops.sh` for lifecycle operations:
- `init` - Create folder structure
- `import` - Import from ~/.claude/plans (auto-deletes original)
- `ralph` - Start/complete Ralph Loop review (multi-phase plans)
- `promote` - Move draft to active (blocked for multi-phase until ralphed)
- `execute` - Request execution approval (requires human approval)
- `approve-execute` - Human approves execution (run in separate terminal)
- `complete` - Move active to completed
- `abandon` - Move to abandoned with reason

See `standards/operations/plan-management.md` for full documentation.

---

## TIM Design Standards Reference

This project defines TIM Design Standards. Key requirements for all TIM projects:

| Requirement | Threshold |
|-------------|-----------|
| Type safety | 100% (mypy --strict / tsc --strict) |
| Test coverage | 90% minimum |
| File size | 400 lines maximum |
| Function size | 50 lines maximum |
| Complexity | 10 maximum (cyclomatic) |

---

## AI Developer Acknowledgment

Before making any changes, confirm you understand:
1. All rules in this CLAUDE.md file
2. The test naming convention (test_what_when_then)
3. The file size limits (400 lines max)
4. The requirement to complete features fully (no TODOs)

**If you are uncertain about any rule, ASK before proceeding.**
