# CLAUDE.md

## How to Work

- Best technical solution, not easiest. Quality and correctness over speed. Don't offer easy vs best — just do best.
- Follow requests exactly. If uncertain, ASK.
- Investigate root causes. No workarounds that mask issues.
- Complete features fully. No TODOs, placeholders, or partial implementations.
- If you touched a file with violations, fix them.

## AI Behavioral Gates

- File >400 lines → BLOCKED. Function >50 lines → BLOCKED.
- No bypass flags. Human approval is the only escape hatch.

## Tests

**AI must not write tests unless explicitly asked.** AI-generated tests optimize for metrics, not for finding bugs. They create false confidence. Tests are human territory — humans write them when they choose to.

If a human asks you to write tests, write tests that would catch real bugs. Do not write tests to hit coverage numbers.

## Code Quality

- `mypy --strict` (Python) / `tsc strict` (Node). Zero warnings.
- Secrets never committed. All input validated (Pydantic/Zod).
- Migrations only — no sync(), create_all(), manual DDL.
- No TODO/FIXME/XXX, no print debugging, no bare except.
- Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`

## Deployment

Deployments use `ops.sh ship` — the standard single-command deploy pipeline. `ship` validates the current branch matches the target env, commits and pushes code changes, builds all services via kaniko, deploys (migrations + manifests + rollout), runs health checks, then commits and pushes the overlay update. Use `<alias> --env <env> ship` to deploy. `build` and `deploy` are available as individual commands but `ship` is preferred.

## ops.sh (MANDATORY)

ops.sh handles both operations (logs, status, shell, db) and deployment (ship, build, deploy). ops.sh lives in the infra repo, not in projects. Projects have only `ops-config.yaml`. Access via shell alias (e.g., `myapp --env dev ship`). Never bypass — no direct SSH, kubectl exec, or raw SQL.

## Shared Libraries (REQUIRED)

Every project uses `tim-lib` (Python) or `@tim/lib` (Node) for: settings, logging, auth, errors, exception handlers, database pooling.

## Pattern Registry

Every project has `.tim-patterns.yaml`. Unregistered patterns block deployment. Custom patterns require human approval.

## Context Efficiency

### Subagent Discipline

- Prefer inline work for tasks under ~5 tool calls. Don't delegate trivially.
- Cap subagent output: "Final response MUST be under 2000 characters. List files modified and test results. No code snippets or stack traces."
- One TaskOutput call per subagent. If it times out, increase the timeout — don't re-read.
- Don't paste file contents into subagent prompts. Give file paths, let them read.
- Put quality rules in subagent prompts, not just the orchestrator. Let them enforce quality in their own context.

### File Reading

- Read files with purpose. Know what you're looking for before reading.
- Grep to locate relevant sections before reading large files.
- Never re-read a file already read this session.
- Files over 500 lines: use offset/limit for the relevant section only.

### Responses

- Don't echo back file contents you just read.
- Don't narrate tool calls. Just do it.
- Keep explanations proportional to complexity.

## Plans

Plans use `plans/` folder: `drafts/` → `active/` → `completed/` or `abandoned/`. Everything in a plan is required — no optional work.
