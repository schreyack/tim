# Playbook Framework

Composable E2E test playbooks executed by Claude via Playwright MCP.

## Concepts

**Automations** are small, self-contained markdown playbooks that test one capability (auth, upload, analysis, etc.). Each automation declares its goal, success criteria, pre-conditions, inputs, outputs, and credentials. It contains scenarios with steps, and a results tracker that enforces verification.

**Orchestrations** are markdown files that compose automations into flows (post-deploy smoke, full regression, etc.). They list automations in order with input overrides and failure/cleanup policies.

## Execution Model

Claude + Playwright MCP is the execution engine. No runner scripts, no test framework, no ops.sh integration. A human runs `/tim-e2e:tim-e2e` and points Claude at an orchestration or automation file. Claude reads the markdown, executes each step via Playwright MCP tools, records evidence in the results tracker, and writes a results file.

## Directory Structure

```
plans/playbooks/
├── automations/       # One file per capability
├── orchestrations/    # Compose automations into flows
├── results/           # Run outputs (gitignored)
└── fixtures/          # Shared test data (audio files, configs, etc.)
```

`tim-sync` scaffolds this structure during project setup and appends `plans/playbooks/results/` to `.gitignore`.

## Automation Format

File: `plans/playbooks/automations/<name>.md`

### Frontmatter

```yaml
---
name: <string>                    # unique identifier, matches filename
description: <string>             # one-line summary
goal: <string>                    # WHY this test exists — what are we trying to prove?
success_criteria:                 # measurable conditions for PASS
  - "All stems appear in project list after upload"
  - "Stem type detection matches expected type for each format"
pre_conditions:                   # state keys that must be truthy or exist
  - authenticated
  - project_id
inputs:                           # configurable parameters with defaults
  stem_count: 3
  file_types: ["wav", "mp3"]
outputs:                          # state keys this automation produces
  - stem_ids
  - project_id
estimated_duration: <string>      # human-readable estimate (e.g., "5m", "20m")
tags: [<string>, ...]             # for filtering/categorization
credentials:                      # Vault paths retrieved at runtime
  - vault: secret/<project>/test-accounts/local
---
```

### Required Fields

- `name` — must match the filename (without `.md`)
- `description` — one line
- `goal` — why this test matters (not just what it does)
- `success_criteria` — list of measurable conditions that define PASS
- `outputs` — at least one, or empty list `[]` if no state produced

### Optional Fields

- `pre_conditions` — omit if the automation has no dependencies
- `inputs` — omit if no configurable parameters
- `credentials` — omit if no secrets needed
- `estimated_duration` — recommended but not enforced
- `tags` — recommended for orchestration filtering

### Body

#### Scenarios

Standard scenario format with numbered steps in tables:

```markdown
## Scenario 1: <Title>

| Step | Action | Expected Result |
|------|--------|----------------|
| 1    | <what to do>  | <what should happen> |
| 2    | ...           | ...                  |

**Output:** Capture `<key>` from <where>.
```

Variables in `{braces}` reference state from previous automations or inputs defined in frontmatter (e.g., `{project_id}`, `{stem_count}`).

#### Results Tracker

Every automation ends with a results tracker table. This is the enforcement mechanism — a scenario is not complete until its row has a status AND evidence in the Notes column.

```markdown
## Results Tracker

| Scenario | Status | Evidence |
|----------|--------|----------|
| 1. Upload WAV stem | - | - |
| 2. Upload MP3 stem | - | - |
| 3. Verify type detection | - | - |
```

**Rules:**
- One row per scenario
- Status is `PASS`, `FAIL`, or `SKIP` — never left blank
- Evidence column records what was observed (a value, a count, a quoted string, a description of what the UI showed). Empty evidence = scenario not verified = automation incomplete.
- The executor cannot mark a scenario PASS without recording what they observed

#### Remediation

Each automation should include remediation guidance for common failures:

```markdown
## Remediation

| Failure | Likely Cause | Action |
|---------|-------------|--------|
| Upload hangs at progress bar | Backend not processing, check worker logs | `<alias> --env dev logs backend` |
| Type detection shows "unknown" | Missing stem type mapping | Check `stem_types` table in DB |
```

### Run Log

Each automation maintains a run log that creates an audit trail across executions:

```markdown
## Run Log

| Date | Executor | Result | Findings |
|------|----------|--------|----------|
| 2026-03-29 | Claude (session 12345) | PASS | All 3 stems uploaded, types correct |
| 2026-03-28 | Claude (session 11234) | FAIL | MP3 upload timeout — BUG-12 filed |
```

The run log stays in the automation file (not gitignored) so the history is visible across sessions.

## Orchestration Format

File: `plans/playbooks/orchestrations/<name>.md`

### Frontmatter

```yaml
---
name: <string>                # unique identifier
description: <string>         # one-line summary
goal: <string>                # what this flow validates end-to-end
on_failure: stop | continue   # what to do when an automation fails
cleanup: always | on_failure  # when to run cleanup automation
---
```

### Body

```markdown
# <Title>

## Goal

<Why this orchestration exists — what end-to-end flow is being validated?>

## Flow

1. **<automation-name>** — <description>
2. **<automation-name>** `input_key: value` — <description with override>
3. **<automation-name>** — <description>

## State

Each automation's `outputs` carry forward as state for subsequent automations.

## On Failure

<describe failure behavior>
```

The `**bold**` name in the flow list matches the automation filename (without `.md`). Inline backtick parameters override the automation's default inputs.

## Results Format

After each orchestration run, a results file is written:

File: `plans/playbooks/results/<name>-<YYYYMMDD-HHMMSS>.md` (gitignored)

```markdown
# <orchestration-name> — <YYYY-MM-DD HH:MM:SS>

## Goal

<orchestration goal from frontmatter>

| Automation | Status | Duration | Evidence |
|-----------|--------|----------|----------|
| auth      | PASS   | 45s      | Login successful, session cookie set |
| upload    | PASS   | 1m 20s   | stem_id: 12345, type: vocal_lead |
| analysis  | FAIL   | 2m 10s   | Timeout after 120s, no DSP results |
| cleanup   | PASS   | 30s      | Project deleted, confirmed empty list |

**Overall: FAIL** (2 of 3 automations passed, 1 failed)

## Findings

- BUG: Overall analysis timed out after 2 minutes on single stem
- Root cause: Worker not picking up task from queue (check KEDA scaling)

## Remediation Taken

- Restarted worker-analysis pod
- Re-ran analysis — completed in 45s
- Filed as BUG-15 for investigation
```

## Credential Handling

- Automations declare Vault paths in frontmatter: `credentials: [{vault: "secret/..."}]`
- Claude retrieves at runtime via `<alias> --env <env> vault get <path>`
- Never hardcoded, never committed
- `results/` is gitignored to prevent credential leakage through result files

## Enforcement

`plan-ops` enforces playbook structure. When run against a file in `plans/playbooks/automations/`, it checks for required sections and adds any that are missing — same auto-fix pattern it uses for plan frontmatter. If a playbook is missing the Results Tracker, Remediation table, Run Log, or required frontmatter fields, plan-ops adds them from the template.

No pre-commit hooks or manual checks — plan-ops is the single enforcement point.

## Who Builds What

**TIM (this standard) provides:**
- This convention document
- Template files for automations and orchestrations
- Directory scaffolding via `tim-sync`
- Structure enforcement via `plan-ops`

**Projects provide:**
- Automation files (the actual test scenarios)
- Orchestration files (how to compose automations)
- Test fixtures (sample data, audio files, etc.)
