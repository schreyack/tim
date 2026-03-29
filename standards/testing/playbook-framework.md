# Playbook Framework

Composable E2E test playbooks executed by Claude via Playwright MCP.

## Concepts

**Automations** are small, self-contained markdown playbooks that test one capability (auth, upload, analysis, etc.). They declare pre-conditions, inputs, outputs, and credentials in YAML frontmatter.

**Orchestrations** are markdown files that compose automations into flows (post-deploy smoke, full regression, etc.). They list automations in order with input overrides and failure/cleanup policies.

**Results** are markdown files written after each run with per-automation pass/fail status.

## Execution Model

Claude + Playwright MCP is the execution engine. No runner scripts, no test framework, no ops.sh integration. A human runs `/tim-e2e:tim-e2e` and points Claude at an orchestration or automation file. Claude reads the markdown, executes each step via Playwright MCP tools, and writes a results file.

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
- `outputs` — at least one, or empty list `[]` if no state produced

### Optional Fields

- `pre_conditions` — omit if the automation has no dependencies
- `inputs` — omit if no configurable parameters
- `credentials` — omit if no secrets needed
- `estimated_duration` — recommended but not enforced
- `tags` — recommended for orchestration filtering

### Body

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

## Orchestration Format

File: `plans/playbooks/orchestrations/<name>.md`

### Frontmatter

```yaml
---
name: <string>                # unique identifier
description: <string>         # one-line summary
on_failure: stop | continue   # what to do when an automation fails
cleanup: always | on_failure  # when to run cleanup automation
---
```

### Body

```markdown
# <Title>

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

File: `plans/playbooks/results/<name>-<YYYYMMDD-HHMMSS>.md` (gitignored)

```markdown
# <orchestration-name> — <YYYY-MM-DD HH:MM:SS>

| Automation | Status | Duration | Notes |
|-----------|--------|----------|-------|
| auth      | PASS   | 45s      |       |
| upload    | PASS   | 1m 20s   | stem_id: 12345 |
| analysis  | FAIL   | 2m 10s   | Timeout waiting for DSP |
| cleanup   | PASS   | 30s      | Project deleted |

**Overall: PASS | FAIL** (<N> of <M> automations passed)

## Findings
- <any bugs, issues, or observations>
```

## Credential Handling

- Automations declare Vault paths in frontmatter: `credentials: [{vault: "secret/..."}]`
- Claude retrieves at runtime via `<alias> --env <env> vault get <path>`
- Never hardcoded, never committed
- `results/` is gitignored to prevent credential leakage through result files

## Who Builds What

**TIM (this standard) provides:**
- This convention document
- Template files for automations and orchestrations
- Directory scaffolding via `tim-sync`

**Projects provide:**
- Automation files (the actual test scenarios)
- Orchestration files (how to compose automations)
- Test fixtures (sample data, audio files, etc.)
