# CLAUDE.md

Guidance for Claude Code when working with TIM projects.

## Critical Rules

- **Help the Human** — If asked to resolve an issue, they need it resolved, not deflection about who caused it.
- **Follow requests exactly** — If uncertain, ASK.
- **Investigate root causes** — No workarounds that mask issues. Goal is functioning code, not quickest resolution.
- **Complete features fully** — No TODOs, placeholders, or partial implementations.

<!-- TIM-ONLY-START -->
## Execution Environment

**Local-only repo.** Documentation/standards — no application to deploy. All commands run on your machine.

## Repository Purpose

**TIM Standards** — authoritative source for coding, testing, security, and deployment standards across all TIM projects. Philosophy: Defense in depth. Never trust. Always verify. Build systems that ENFORCE rules, not just document them.
<!-- TIM-ONLY-END -->

## AI Development Context

TIM develops exclusively with AI. Strict enforcement works because AI doesn't fatigue — when code fails checks, the agent tries again.

- Hard gates catch plausible-sounding bugs — verification required
- NO bypass flags anywhere — if AI can bypass, AI will bypass
- Human approval is the escape hatch for blocked operations
- If you touched a file with violations, fix them (no "it was already broken")
- **AI Behavioral Gates:** File >400 lines or function >50 lines → BLOCKED. Deflection patterns → BLOCKED.

<!-- TIM-ONLY-START -->
## Repository Structure

```text
tim/
├── standards/          # All TIM standards (enforcement, coding, testing, security, database, deployment)
├── libs/               # Shared libraries (REQUIRED)
├── templates/          # Ready-to-copy configs
├── tools/              # Enforcement tools
├── marketplace/plugins/tim-loop/  # tim-loop plugin (NOT for submodule use)
└── .claude-plugin/     # Marketplace definition (NOT for submodule use)
```

When using tim as a submodule, exclude `.claude-plugin/` and `marketplace/` via sparse-checkout. Plugins come from marketplace, not submodule.

## Four-Gate Enforcement Model

All gates block on failure:

1. **Local (Pre-commit):** Type checking, linting, formatting, secrets detection
2. **CI (Pull Request):** Gate 1 + tests (100% pass), coverage (90%), security scan
3. **Deploy (Pre-deployment):** Integration/E2E, migration dry-run, canary (10%)
4. **Pattern Compliance:** All patterns in `.tim-patterns.yaml`, shared library installed
<!-- TIM-ONLY-END -->

## Shared Libraries (REQUIRED)

Every project MUST use `tim-lib` (Python) or `@tim/lib` (Node.js) for: settings, logging, auth, errors, exception handlers, database pooling.

## Pattern Registry

Every project MUST have `.tim-patterns.yaml`. Custom patterns require human approval with ticket reference. Unregistered patterns block deployment.

## Remote-First Deployment

Use `./ops.sh --env <env>` for all operations (`--env` REQUIRED). Environments: local (human-approved only), dev (all devs), uat (QA/leads), prod (DevOps/SRE). Local dev disabled by default — human must run `tim-local-dev-enable`.

**Safety tiers:** SAFE (status/health/logs/backup) → MODERATE logged (deploy/restart/migrate) → HUMAN_REQUIRED (rollback/stop/db:rollback) → BLOCKED (destroy/db:restore)

**Never bypass ops.sh** — no direct SSH, docker exec, raw SQL, or docker-compose up.

## Hard Rules (No Exceptions)

**Code Quality:** `mypy --strict` / `tsc strict`, `eslint --max-warnings 0`, coverage 90% min (95% new code), shared library required.

**Security:** Secrets never committed (pre-commit blocks), all input validated (Pydantic/Zod), required headers (CSP, HSTS, X-Content-Type-Options, X-Frame-Options), HIGH/CRITICAL vulns block merge.

**Database:** Migrations only — no sync(), create_all(), manual DDL. Every migration has tested rollback.

**Code Style:** No TODO/FIXME/XXX, no placeholders, no print debugging (use logging), no bare except, all functions typed. Test naming: `test_<what>_<when>_<then>`. TDD for new features.

## Single Source of Truth

Every value defined once, imported everywhere, updated only at the source.

## Tests

**Tests are diagnostic tools, not goals.** The objective is a functioning application, not passing tests.

## Plan Lifecycle

Plans use `plans/` folder: `drafts/` → `active/` → `completed/` or `abandoned/`. No optional work — everything in a plan is required.

**Plan mode:** Write both the system plan file AND a copy to `plans/drafts/YYYY-MM-DD-HH-MM-short-description.md`.

<!-- TIM-ONLY-START -->
## Using This Repository

**New projects:** Add tim as submodule → sparse-checkout (exclude plugin dirs) → `sync-pre-commit` → create `CLAUDE-PROJECT.md` → `sync-claude-md` → create `.tim-patterns.yaml` → install tim-loop from marketplace → `pre-commit install` → `tim-compliance-check.sh`

**Existing projects:** Run `tim-compliance-check.sh` → add submodule → install plugin → implement four gates → migrate to remote-first.

**Updating:** `cd lib/tim && git pull origin main && cd ../.. && sync-pre-commit && sync-claude-md && git commit`
<!-- TIM-ONLY-END -->

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

## Commits

Conventional Commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`

<!-- TIM-ONLY-START -->
## Plugin Versioning

Update BOTH `.claude-plugin/marketplace.json` and `marketplace/plugins/tim-loop/.claude-plugin/plugin.json`. Semver: Major (breaking), Minor (features), Patch (fixes).

## Standards Thresholds

Type safety 100% (strict) · Coverage 90% min · Files 400 lines max · Functions 50 lines max · Complexity 10 max (cyclomatic)
<!-- TIM-ONLY-END -->

## Context Efficiency

### Subagent Discipline

- Prefer inline work for tasks under ~5 tool calls. Subagents have overhead — don't delegate trivially.
- Cap subagent output: "Final response MUST be under 2000 characters. List files modified and test results. No code snippets or stack traces." Without this, subagents dump entire transcripts into your context.
- One TaskOutput call per subagent. Period. If it times out, increase the timeout — don't re-read. Double-reads double context consumption.
- Don't paste file contents into subagent prompts. Give them the file path and let them read it. Pasting duplicates content in both contexts.
- Put quality rules in subagent prompts, not just the orchestrator. Tell implementers what good code looks like; tell reviewers what to check. Let them enforce quality in their own context instead of the orchestrator re-reading their output to verify.

### File Reading

- Read files with purpose. Before reading a file, know what you're looking for.
- Use Grep to locate relevant sections before reading entire large files.
- Never re-read a file you've already read in this session.
- For files over 500 lines, use offset/limit to read only the relevant section.

### Responses

- Don't echo back file contents you just read — the user can see them.
- Don't narrate tool calls ("Let me read the file..." / "Now I'll edit..."). Just do it.
- Keep explanations proportional to complexity. Simple changes need one sentence, not three paragraphs.

## AI Developer Acknowledgment

Before making changes, confirm you understand all rules here, test naming (`test_what_when_then`), file limits (400 lines), and the requirement to fully complete features. **If uncertain, ASK.**
