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

ops.sh is the **only** way to interact with the k3s cluster. All cluster operations — deployment, debugging, logs, database access — go through ops.sh. Never bypass it with direct SSH, kubectl, or raw SQL.

ops.sh lives in the infra repo, not in projects. Projects have only `ops-config.yaml`. Access via shell alias (e.g., `myapp --env dev ship`).

**Available commands:**
- `status` — pods, services, deployments
- `health` — health check all services
- `logs <svc|job>` — view logs for a service (deployment) or a job (e.g., migration jobs)
- `describe <svc|job|pod>` — describe a service, job, or pod with events (use this to diagnose failures like ImagePullBackOff, CrashLoopBackOff, etc.)
- `restart <svc|all>` / `stop` / `start` — manage services
- `shell <svc>` — interactive shell in a pod
- `exec <svc> <cmd>` — run a command in a pod
- `build <svc|all>` — build images via kaniko
- `deploy` — run migrations + apply manifests
- `ship` — full pipeline: commit, push, build, deploy, health check, commit overlay
- `db backup|restore|migrate|shell|query|status` — database operations
- `cleanup` — remove completed/failed pods
- `disk` — PVC usage

**If ops.sh doesn't support what you need, STOP and ask the human.** Do not work around it with direct kubectl, SSH, or any other cluster access. The human will add the capability to ops.sh.

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
