# CLAUDE.md

This file provides guidance to Claude Code when working with TIM projects.

---

## Critical Rules

- **Help the Human** - Deflecting requests because you didn't cause a problem is not helpful.  If the human asks you to resolve an issue, they are not blaming you, they need the problem resolved.
- **Follow requests exactly** - If uncertain, ASK rather than guess
- **Investigate root causes** - No quick workarounds that mask issues, the objective is functioning code, not quickest resolution
- **Complete features fully** - No TODOs, placeholders, or partial implementations

<!-- TIM-ONLY-START -->
---

## Execution Environment

**This repository (tim) is local-only.** All commands execute on your machine.

- Documentation/standards repository - no application to deploy
- Tests: Run locally if any test infrastructure exists
- File operations: Standard local editing

---

## Repository Purpose

This is the **TIM Standards** repository - the authoritative source for coding, testing, security, and deployment standards used across all TIM projects.

**Philosophy**: Defense in depth. Never trust. Always verify. Build systems that ENFORCE rules, not just document them.
<!-- TIM-ONLY-END -->

---

## AI Development Context

TIM develops exclusively with AI. Strict enforcement works because AI doesn't fatigue from iteration - when code fails checks, the agent simply tries again. This makes feedback loops incredibly powerful.

**Key behaviors:**

- Hard gates catch AI mistakes - plausible-sounding bugs need verification
- NO bypass flags anywhere - if AI can bypass, AI will bypass
- Human approval is the escape hatch for blocked operations
- If you touched a file with violations, you must fix them (no "it was already broken")

**AI Behavioral Gates** enforce rules in real-time:

- Code Quality Validator: File >400 lines, function >50 lines → BLOCKED
- Excuse Pattern Detector: Deflection like "was already broken" → BLOCKED

<!-- TIM-ONLY-START -->
---

## Repository Structure

```text
tim/
├── CLAUDE.md                    # This file
├── .claude-plugin/              # Marketplace definition (NOT for submodule use)
├── marketplace/                 # Plugin source (NOT for submodule use)
│   └── plugins/tim-loop/        # tim-loop plugin
├── standards/                   # All TIM standards
│   ├── enforcement/             # Gate definitions, AI review
│   ├── coding/                  # Language-specific standards
│   ├── testing/                 # Test requirements
│   ├── security/                # Security requirements
│   ├── database/                # Migration requirements
│   └── deployment/              # CI/CD, ops requirements
├── libs/                        # Shared libraries (REQUIRED)
├── templates/                   # Ready-to-copy configs
└── tools/                       # Enforcement tools
```

**Note:** When using tim as a git submodule, exclude `.claude-plugin/` and `marketplace/` via sparse-checkout. Plugins should come from the marketplace, not the submodule.

---

## Four-Gate Enforcement Model

All TIM projects implement four gates. Each blocks on failure.

1. **Local (Pre-commit)**: Type checking, linting, formatting, secrets detection
2. **CI (Pull Request)**: All Gate 1 + tests (100% pass), coverage (90%), security scan
3. **Deploy (Pre-deployment)**: Integration/E2E tests, migration dry-run, canary (10%)
4. **Pattern Compliance**: All patterns in `.tim-patterns.yaml`, shared library installed

<!-- TIM-ONLY-END -->
---

## Shared Libraries (REQUIRED)

Every TIM project MUST use `tim-lib` (Python) or `@tim/lib` (Node.js) for: settings, logging, auth (hash/verify password, JWT), errors, exception handlers, database pooling.

---

## Pattern Registry

Every project MUST have `.tim-patterns.yaml`. CUSTOM patterns require human approval with ticket reference. Unregistered patterns block deployment.

---

## Remote-First Deployment

**Remote by default.** Use `./ops.sh --env <env>` for all operations. The `--env` flag is REQUIRED.

| Environment | Access |
|-------------|--------|
| local | Human-approved only |
| dev | All developers |
| uat | QA team, tech leads |
| prod | DevOps/SRE only |

Local development is disabled by default. A human must run `tim-local-dev-enable`.

---

## ops.sh Safety Tiers

| Tier | Behavior | Examples |
|------|----------|----------|
| SAFE | Always allowed | status, health, logs, backup |
| MODERATE | Logged | deploy, restart, migrate |
| HUMAN_REQUIRED | Needs approval | rollback, stop, db:rollback |
| BLOCKED | Never in ops.sh | destroy, db:restore |

**Never bypass ops.sh** - No direct SSH, docker exec, raw SQL, or docker-compose up.

---

## Hard Rules (No Exceptions)

**Code Quality:**

- Python: `mypy --strict`, ruff with security rules
- TypeScript: `strict: true`, `eslint --max-warnings 0`
- Coverage: 90% minimum, 95% for new code
- Shared library MUST be used

**Security:**

- Secrets NEVER committed (pre-commit blocks)
- All external input validated (Pydantic/Zod)
- Required headers: CSP, HSTS, X-Content-Type-Options, X-Frame-Options
- HIGH/CRITICAL vulnerabilities block merge

**Database:**

- Migrations only - no sync(), create_all(), or manual DDL
- Every migration must have tested rollback

**Testing:**

- Naming: `test_<what>_<when>_<then>`
- TDD for new features

**Code Style:**

- No TODO/FIXME/XXX comments
- No placeholder code (NotImplementedError, pass, ...)
- No print debugging - use logging
- No bare except clauses
- All functions have type hints

---

## Single Source of Truth

Every piece of data must have exactly one authoritative source. Define once, import everywhere, update only the source.

---

## Test Requirements

**Tests are diagnostic tools, not goals.** The objective is a functioning application, not passing tests.

---

## Plan Lifecycle Management

Plans use `plans/` folder with lifecycle subfolders: `drafts/`, `active/`, `completed/`, `abandoned/`.

**No optional work** - Everything in a plan is required. No "nice to have" items.

<!-- TIM-ONLY-START -->
---

## Using This Repository

### For New TIM Projects

1. Add tim as git submodule: `git submodule add /path/to/tim lib/tim`
2. Configure sparse-checkout to exclude plugin directories (plugins come from marketplace):

   ```bash
   git -C lib/tim config core.sparseCheckout true
   cat > .git/modules/lib/tim/info/sparse-checkout << 'EOF'
   /*
   !.claude-plugin/
   !marketplace/
   EOF
   git -C lib/tim read-tree -mu HEAD

   ```

3. Generate pre-commit config: `lib/tim/bin/sync-pre-commit <project>`
4. Optionally create `.pre-commit-overrides.yaml` for project-specific hooks
5. Create `CLAUDE-PROJECT.md` with project-specific content
6. Run `lib/tim/bin/sync-claude-md` to generate CLAUDE.md
7. Create `.tim-patterns.yaml` from template
8. Install tim-loop plugin from marketplace (not from submodule)
9. Run `pre-commit install`
10. Run `tools/tim-compliance-check.sh`

### For Existing Projects

1. Run `tools/tim-compliance-check.sh` to identify gaps
2. Add tim submodule and symlink configs (see above)
3. Install tim-loop plugin
4. Implement all four gates
5. Migrate to remote-first deployment

### Updating Tim Standards in Projects

When tim is updated, run in each project:

```bash
cd lib/tim && git pull origin main
cd ../..
lib/tim/bin/sync-pre-commit   # Regenerate pre-commit configs
lib/tim/bin/sync-claude-md     # Regenerate CLAUDE.md
git add lib/tim .pre-commit-config.yaml CLAUDE.md && git commit -m "chore: update tim submodule"
```
<!-- TIM-ONLY-END -->

---

## Quick Reference

| Standard | Python | Node.js |
|----------|--------|---------|
| Type checking | mypy --strict | tsc strict |
| Linting | ruff | ESLint |
| Testing | pytest | Jest/Vitest |
| Coverage | 90% | 90% |
| ORM | SQLAlchemy + Alembic | Prisma |
| Validation | Pydantic | Zod |
| Shared lib | tim-lib | @tim/lib |

---

## Commit Message Format

Use Conventional Commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`

<!-- TIM-ONLY-START -->
---

## Plugin Version Management

When updating tim-loop version, update BOTH:

- `.claude-plugin/marketplace.json`
- `marketplace/plugins/tim-loop/.claude-plugin/plugin.json`

Use semantic versioning: Major (breaking), Minor (features), Patch (fixes).

---

## TIM Standards Reference

| Requirement | Threshold |
|-------------|-----------|
| Type safety | 100% (mypy --strict / tsc --strict) |
| Test coverage | 90% minimum |
| File size | 400 lines maximum |
| Function size | 50 lines maximum |
| Complexity | 10 maximum (cyclomatic) |
<!-- TIM-ONLY-END -->

---

## AI Developer Acknowledgment

Before making changes, confirm you understand:

1. All rules in this CLAUDE.md
2. Test naming: `test_what_when_then`
3. File size limits: 400 lines max
4. Complete features fully - no TODOs

**If uncertain about any rule, ASK before proceeding.**
