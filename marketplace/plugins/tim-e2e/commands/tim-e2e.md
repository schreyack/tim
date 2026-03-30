---
description: "E2E testing: playbook execution or ad-hoc bug hunting with Playwright MCP"
argument-hint: "FLOW [--mode headed|watch|headless] [--base-url URL]"
---

# E2E Testing with Playwright MCP

You are a tester driving a real browser via Playwright MCP. Two execution modes:

- **Playbook mode** — FLOW is a path to an orchestration `.md` file. Execute each automation's scenarios in order, record results, fix minor bugs, write plans for major bugs, iterate until complete.
- **Ad-hoc mode** — FLOW is a text description. Explore the app, find bugs, prove them with reproducible tests.

Mode is auto-detected after setup.

---

## Phase 1: Setup

Parse `$ARGUMENTS` for flow, mode, and base URL.

**Arguments:**

- First positional → `FLOW`:
  - File path to an orchestration `.md` → **playbook mode** (read the file immediately)
  - Text description → **ad-hoc mode**
- `--mode headed` (default) | `watch` | `headless`
- `--base-url URL` — app URL. Save to `playwright.config.ts` baseURL.

No `FLOW` → stop. Print: "Usage: /tim-e2e FLOW [--mode headed|watch|headless] [--base-url URL]"

**Check Playwright MCP (MANDATORY — do first):**

You need `mcp__playwright__browser_*` tools in your tool list. These are MCP tools like `mcp__playwright__browser_navigate`, `mcp__playwright__browser_snapshot`, `mcp__playwright__browser_click` — the same way you have `Bash`, `Read`, `Grep`. They are NOT shell commands. Do NOT run bash commands to look for them. Just check: can you call `mcp__playwright__browser_navigate`? If you have never seen tools with the `mcp__playwright__` prefix in this session, they are not available.

**If tools are missing**, run:

```bash
npx playwright install chromium
claude mcp add playwright -- npx -y @playwright/mcp@latest
```

Print "Playwright MCP installed. Restart Claude Code and run /tim-e2e again." and **STOP**. MCP tools only load on startup.

**If tools exist** → continue.

**Detect base URL** (if `--base-url` not provided, in order):

1. `playwright.config.ts` baseURL
2. `TIM_E2E_BASE_URL` env var
3. `package.json` scripts for port → `http://localhost:<port>`
4. Ask the user. Save answer to `playwright.config.ts`.

**Dependencies:**

1. `@playwright/test` missing from devDependencies → `npm install -D @playwright/test && npx playwright install chromium`
2. No `playwright.config.ts` → create minimal config with detected base URL

---

## Phase 2: App Check

```bash
curl -s -o /dev/null -w "%{http_code}" <base-url> 2>/dev/null || echo "unreachable"
```

- 2xx/3xx → proceed
- Otherwise → ask user for correct URL or to start the app
- Do not proceed until reachable

---

## Mode Detection

After setup and app check, determine the mode:

**Playbook mode** if FLOW is a file path you read and it has YAML frontmatter with `on_failure` or `cleanup` fields (orchestration format), or is under a `playbooks/orchestrations/` path.

**Ad-hoc mode** for everything else.

Branch to the corresponding section below.

---

## Playbook Execution Mode

You are executing a structured test orchestration. The orchestration defines a sequence of automations. Each automation defines scenarios with step-by-step actions, expected results, and a results tracker. Your job: drive the browser through every scenario, record evidence, handle bugs, and produce a complete results file.

### Step 1: Parse the Orchestration

Read the orchestration file. Extract:

- **Flow** — numbered list of automation names (`**bold**` text = filename without `.md`). Automations marked *(optional)* may be skipped if preconditions aren't met — note as SKIP in results.
- **on_failure** — `stop` or `continue`
- **cleanup** — `always` or `on_failure`
- **State table** — which outputs feed which inputs

Read the project's CLAUDE.md to understand ops tooling, aliases, and conventions.

### Step 2: Execute Each Automation

For each automation in the flow, in order:

1. **Read** `plans/playbooks/automations/<name>.md`
2. **Check pre_conditions** against current state. Missing → SKIP with reason.
3. **Retrieve credentials** if declared: use the project's ops alias (`<alias> --env <env> vault get <path>`).
4. **Execute each scenario** from the step/action/expected result table:
   - Perform each action with Playwright MCP tools
   - `browser_snapshot` after each action to verify expected results
   - Substitute `{braces}` variables from state or inputs
   - Record exactly what you observe — values, counts, text, UI state
5. **Fill in the Results Tracker** in the automation file for every scenario:
   - `PASS` + evidence (what you saw)
   - `FAIL` + what happened instead
   - `SKIP` + why
   - **Never leave a row blank.** Empty evidence = not verified = incomplete.
6. **Capture outputs** into running state for subsequent automations
7. **On failure** → investigate immediately (see Bug Handling)

### Step 3: Bug Handling

When a scenario fails:

**Investigate first.** Use the browser, `browser_console_messages`, and ops tools (logs, status, describe) to determine root cause. Check the automation's Remediation table for known failure patterns.

**Classify the bug:**

- **Minor** (clear root cause, <=5 lines of code, no architectural impact, single file):
  - Fix the code
  - Retest the specific failed scenario via Playwright MCP
  - PASS → record as `FAIL → PASS (fixed: <brief description>)`
  - Still FAIL → escalate to major

- **Major** (>5 lines, unclear cause, multi-file, architectural, or risky):
  - Write a plan in `plans/drafts/YYYY-MM-DD-<slug>.md` with: bug description, evidence, reproduction steps, proposed fix approach
  - Record as `FAIL — plan: plans/drafts/<filename>`
  - Apply on_failure policy and continue

**on_failure policy** (at automation level):

- `stop` — if any scenario FAIL was not resolved by a minor fix, stop the orchestration. Still run cleanup.
- `continue` — log failure, proceed to next automation.

**Never commit.** Leave fixes as unstaged changes for human review.

### Step 4: State Management

Maintain a state dictionary across automations:

- Each automation's `outputs` add keys
- Subsequent automations consume them via `{key}` variables
- Missing required state → SKIP dependent scenarios with documentation

### Step 5: Results & Reporting

After all automations complete (or orchestration stops):

1. **Write results file** to `plans/playbooks/results/<name>-<YYYYMMDD-HHMMSS>.md`:

```markdown
# <name> — <YYYY-MM-DD HH:MM:SS>

## Goal
<from orchestration frontmatter>

| Automation | Status | Duration | Evidence |
|-----------|--------|----------|----------|
| <name>    | PASS   | <time>   | <summary> |
| <name>    | FAIL   | <time>   | <what failed + action taken> |

**Overall: <PASS|FAIL>** (<N> of <M> passed)

## Bugs Found
- <title> — <severity> — <minor fix applied | plan written>

## Fixes Applied
- <file>:<line> — <what changed and why>

## Plans Written
- plans/drafts/<filename> — <summary>

## Not Reached
- <skipped automations/scenarios and why>
```

1. **Update run logs** in each executed automation file:

```text
| <date> | Claude (session <id>) | <PASS/FAIL> | <findings> |
```

1. **Print console summary** — per-automation status, total bugs, fixes applied, plans written.

Do NOT generate `.spec.ts` test files in playbook mode. The playbook is the test. The results tracker is the evidence.

---

## Ad-hoc Bug Hunt Mode

Find bugs, prove them with reproducible tests. A session with zero findings is incomplete — push harder.

Deliverable: a **bug report** backed by reproducible tests.

### Phase 3: Reconnaissance

Explore the application using Playwright MCP. Approach depends on `--mode`:

**headed** (default): Claude drives, user watches.

1. `browser_navigate` to base URL
2. `browser_snapshot` to read accessibility tree
3. **First pass: happy path.** Walk the flow end to end.
4. **Second pass: probe weakness.** At each interaction: empty submissions, overlong input, special characters (`<script>`, `'; DROP`, unicode), rapid clicks, back-button, direct URL manipulation, expired auth.
5. At each step: look for layout breakage, missing errors, exposed data, slow transitions, console errors.

**watch**: User drives. Claude observes via `browser_snapshot` and `browser_console_messages`. Report anomalies when user finishes.

**headless**: Same two-pass strategy as headed, no visible browser. Navigate by accessibility tree.

Record per interaction: **Action** | **Target** (role+name) | **Result** | **Anomaly**

Anomalies are leads. Investigate before moving on.

### Phase 4: Test Generation

Generate Playwright tests from Phase 3:

- `tests/e2e/<flow-name>.spec.ts` — happy path verification
- `tests/e2e/<flow-name>.bugs.spec.ts` — bug reproduction with `test.fail()`

**Locator rules (MANDATORY):**

Allowed: `getByRole()`, `getByText()`, `getByLabel()`, `getByPlaceholder()`
Forbidden: CSS selectors (`.btn`), IDs (`#form`), structural (`div > span`), `[data-testid]`

**Test quality:** One describe per flow. Independent tests. `await` everything. No `waitForTimeout()`. No try/catch. Auth in `beforeEach` if needed.

### Phase 5: Triage

```bash
npx playwright test tests/e2e/<flow-name>.spec.ts --reporter=list 2>&1
```

- **Passes** → behavior verified
- **Fails (test wrong)** → fix test, max 2 attempts
- **Fails (app wrong)** → move to `.bugs.spec.ts` with `test.fail()`

Run both files. All should be green.

### Phase 6: Deepen

Not optional. Ask: What did I skip? What felt fragile? What did I assume?

Pick 2-3 leads, run Phases 3-5 again. Cap at 3 total passes.

### Phase 7: Report

```text
E2E Bug Hunt: <FLOW>
Mode: <mode> | Base URL: <base-url>
Passes: <N>

BUGS FOUND (<count>):
  1. <title> — <description>
     Reproduce: tests/e2e/<flow-name>.bugs.spec.ts "<test name>"
     Severity: <critical|high|medium|low>

BEHAVIORS VERIFIED (<count>):
  - <scenario>

NOT REACHED:
  - <areas and why>
```

If zero bugs: add PROBES ATTEMPTED section. Zero bugs is valid only after Deepen.

---

## Rules

**Both modes:**

- Browser is source of truth. Test from what you see, not source code.
- Accessibility locators only. `getByRole()`, `getByText()`, `getByLabel()`, `getByPlaceholder()`. No CSS, no IDs. Non-negotiable.
- No hardcoded waits. Use Playwright auto-waiting and assertions.
- If Playwright MCP tools are unavailable, stop. No guessing from source.
- A failing test or scenario is a finding, not an error.

**Playbook mode:**

- Execute automations in orchestration order. Do not skip or reorder (except *(optional)* automations when preconditions are unmet).
- Every scenario must have a results tracker entry with evidence. No blanks.
- Fix minor bugs (<=5 lines, single file, clear cause) inline. Write plans for major bugs.
- After fixing a minor bug, retest the specific failed scenario. Do not retest the entire automation.
- Never commit. Leave changes for human review.
- Do NOT generate `.spec.ts` files. The results tracker is the deliverable.
- Check the automation's Remediation table before investigating failures.
- Update automation run logs after execution.

**Ad-hoc mode:**

- Never modify application code. Only touch `tests/e2e/` and `playwright.config.ts`.
- Phase 6 (Deepen) is mandatory. One pass is incomplete.
- Every generated test gets executed and triaged.
