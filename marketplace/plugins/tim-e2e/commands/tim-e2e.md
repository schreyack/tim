---
description: "E2E bug hunting: Claude drives a real browser, finds bugs, proves them with tests"
argument-hint: "FLOW [--mode headed|watch|headless] [--base-url URL]"
---

# E2E Bug Hunting with Playwright MCP

You are a bug hunter. Your job is to drive (or observe) a real browser using the Playwright MCP server, probe the application for defects, and deliver evidence: failing tests that prove bugs exist, passing tests that prove behaviors work. A session with zero findings is incomplete — push harder before concluding.

Your deliverable is not test files. It is a **bug report** backed by reproducible tests.

Follow these seven phases in order. Do not skip phases.

---

## Phase 1: Setup

Parse `$ARGUMENTS` to determine the flow, mode, and base URL.

**Argument parsing:**

- First positional argument → `FLOW`. This can be:
  - A text description of what to test (e.g., "login flow", "book a technician")
  - A path to a playbook/orchestration `.md` file — if so, **read the file** and use its Flow section as your test plan. Each step in the flow references an automation by name. The orchestration defines the order and state dependencies.
- `--mode headed` (default) → Claude drives a visible browser, user watches
- `--mode watch` → User drives the browser, Claude observes and generates tests
- `--mode headless` → No visible browser, Claude navigates autonomously
- `--base-url URL` → App URL to test against. **Save this URL** to `playwright.config.ts` baseURL so future runs use it automatically.

If no `FLOW` argument is provided → stop. Print: "Usage: /tim-e2e FLOW [--mode headed|watch|headless] [--base-url URL]"

**FIRST — Check for Playwright MCP (MANDATORY, do this before anything else):**

You need Playwright MCP tools to drive the browser. These are tools like `mcp__playwright__browser_navigate`, `mcp__playwright__browser_snapshot`, `mcp__playwright__browser_click` that appear in your available tool list — the same way you have `Bash`, `Read`, `Grep`, etc. They are NOT shell commands. Do NOT run bash commands to look for them. Just check: can you call a tool named `mcp__playwright__browser_navigate`? If you have never seen tools with the `mcp__playwright__` prefix in this session, they are not available.

**If you do NOT have `mcp__playwright__*` tools**, run these commands immediately:

```bash
npx playwright install chromium
claude mcp add playwright -- npx -y @playwright/mcp@latest
```

Then print this message and **STOP** (do not continue to any other phase):

```text
Playwright MCP server has been installed. Restart Claude Code and run /tim-e2e again.
```

MCP tools only load on startup — there is no way to use them in the current session after adding them.

**If you DO have `mcp__playwright__*` tools** → continue with setup below.

**Detect base URL** (if `--base-url` not provided, check in this order):

1. Read existing `playwright.config.ts` — if it has a `baseURL` value, use it
2. Check `TIM_E2E_BASE_URL` environment variable
3. Read `package.json` — look for `scripts.dev`, `scripts.start`, or `scripts.serve` for a port number (e.g., `--port 3001`, `:3001`). If found, use `http://localhost:<port>`
4. If none of the above found a URL, **ask the user** for the base URL. Offer `http://localhost:3000` as a default option. Save their answer into `playwright.config.ts` baseURL so they only need to provide it once.

**Check and install dependencies:**

1. Check if `@playwright/test` is in `package.json` devDependencies. If missing, run `npm install -D @playwright/test && npx playwright install chromium`.

2. Check if `playwright.config.ts` exists at the project root. If missing, create a minimal one:

   ```typescript
   import { defineConfig } from "@playwright/test";

   export default defineConfig({
     testDir: "./tests/e2e",
     timeout: 30000,
     retries: 0,
     use: {
       baseURL: "<detected-or-default-base-url>",
       trace: "on-first-retry",
     },
     projects: [
       {
         name: "chromium",
         use: { browserName: "chromium" },
       },
     ],
   });
   ```

   Replace `<detected-or-default-base-url>` with the actual base URL.

---

## Phase 2: App Check

Verify the app is running at the base URL:

```bash
curl -s -o /dev/null -w "%{http_code}" <base-url> 2>/dev/null || echo "unreachable"
```

- If the response is a 2xx or 3xx status → proceed.
- If unreachable or 4xx/5xx → **ask the user** what to do. Present these options:
  1. A different URL (let them type it, then re-check that URL)
  2. They'll start the app and tell you when it's ready (wait for them, then re-check)
- If the base URL was auto-detected (not from `--base-url` flag or `playwright.config.ts`), mention what was detected and that it may be wrong.
- After getting a working URL from the user, save it to `playwright.config.ts` baseURL so future runs use it automatically.
- Do not proceed until you have a reachable URL.

---

## Phase 3: Reconnaissance

Use the Playwright MCP tools to explore the application. The approach depends on `--mode`:

### Mode: headed (default)

Claude drives the browser. The user watches.

1. Use `browser_navigate` to open the base URL.
2. Use `browser_snapshot` to read the accessibility tree.
3. Based on the `FLOW` description (or orchestration file), navigate through the application.
4. **First pass: the happy path.** Walk the intended flow end to end. Record what works.
5. **Second pass: probe for weakness.** At each interaction point, try what a user shouldn't do:
   - Empty submissions, overlong input, special characters (`<script>`, `'; DROP`, unicode)
   - Rapid repeated clicks on submit buttons
   - Back-button after form submission
   - Direct URL manipulation (skip steps, access pages out of order)
   - Actions with expired/missing auth state
6. At each step, take a snapshot (`browser_snapshot`) and **look for things that feel wrong**: layout breakage, missing error messages, exposed data, flash of wrong content, slow or hung transitions, console errors.

### Mode: watch

The user drives the browser. Claude observes.

1. Use `browser_navigate` to open the base URL in a visible browser.
2. Tell the user:

   ```text
   Browser is open at <base-url>. Perform the "<FLOW>" flow now.
   I'll observe your actions and look for issues.
   Tell me when you're done.
   ```

3. Periodically use `browser_snapshot` to read the current page state.
4. Use `browser_console_messages` to watch for errors, warnings, and failed network requests.
5. When the user says they're done, take a final snapshot.
6. Report anything that looked wrong during observation — don't wait for test generation.

### Mode: headless

Claude drives the browser autonomously. No visible browser.

1. Use `browser_navigate` to open the base URL.
2. Follow the same two-pass strategy as **headed** mode.
3. Use `browser_snapshot` at each step to understand the page.
4. Navigate entirely based on the accessibility tree.

### What to record (all modes)

For every interaction, record:

- **Action**: what was done (click, type, navigate, etc.)
- **Target**: the element, by accessible role and name (e.g., `button "Sign In"`, `textbox "Email"`)
- **Result**: what changed on the page
- **Anomaly**: anything unexpected — missing validation, wrong redirect, stale data, console error, element that should be disabled but isn't

Anomalies are leads. Do not move on from an anomaly without investigating it.

---

## Phase 4: Test Generation

Based on findings from Phase 3, generate Playwright test files. Separate bug-proving tests from verification tests.

**File locations:**

- `tests/e2e/<flow-name>.spec.ts` — happy path verification tests
- `tests/e2e/<flow-name>.bugs.spec.ts` — tests that reproduce found bugs (expected to fail)

Derive `<flow-name>` from the `FLOW` argument: lowercase, hyphens for spaces, strip special characters. Create `tests/e2e/` if it doesn't exist.

**Test structure:**

```typescript
import { test, expect } from "@playwright/test";

test.describe("<FLOW>", () => {
  test("<step-or-scenario-description>", async ({ page }) => {
    await page.goto("/starting-path");
    // Interactions and assertions from observations
  });
});
```

**Bug tests** use `test.fail()` to mark expected failures:

```typescript
test.describe("<FLOW> — known bugs", () => {
  test("BUG: <description of the defect>", async ({ page }) => {
    test.fail(); // This test proves a bug — it SHOULD fail
    await page.goto("/path");
    // Steps that reproduce the bug
    // Assertion that would pass if the bug were fixed
  });
});
```

A `test.fail()` test that fails is **correct** — it proves the bug exists. If it starts passing, the bug was fixed.

### Locator Rules (MANDATORY)

Use **only** accessibility-based locators from the snapshots you took.

**Allowed:**

- `page.getByRole("button", { name: "Sign In" })`
- `page.getByRole("textbox", { name: "Email" })`
- `page.getByRole("link", { name: "Dashboard" })`
- `page.getByLabel("Password")`
- `page.getByText("Welcome back")`
- `page.getByPlaceholder("Enter your email")`

**Forbidden:**

- `page.locator(".btn-primary")` — no CSS selectors
- `page.locator("#login-form")` — no ID selectors
- `page.locator("div > span")` — no structural selectors
- `page.locator('[data-testid="..."]')` — no test IDs (unless the accessibility tree offers no alternative)

### Assertion Patterns

```typescript
await expect(page).toHaveURL("/dashboard");
await expect(page).toHaveTitle("Dashboard");
await expect(page.getByRole("heading", { name: "Welcome" })).toBeVisible();
await expect(page.getByText("Success")).toBeVisible();
await expect(page.getByRole("button", { name: "Submit" })).toBeDisabled();
```

### Test Quality Rules

- **One `describe` per flow.** Multiple `test()` blocks for distinct scenarios.
- **Each test is independent.** No shared state. Each test navigates from scratch.
- **`await` on every Playwright call.** No fire-and-forget.
- **Wait for elements before asserting.** Use `toBeVisible()` before interacting with async elements.
- **Include setup.** If auth is needed, include login steps or use `test.beforeEach`.
- **No hardcoded delays.** Never `page.waitForTimeout()`. Use assertions or `page.waitForURL()`.
- **No try/catch in tests.** Let assertions fail naturally.

---

## Phase 5: Triage

Run the generated tests and classify the results.

```bash
npx playwright test tests/e2e/<flow-name>.spec.ts --reporter=list 2>&1
```

For each test result, determine the cause:

### Test passes → behavior verified

The app does what it should. Keep the test.

### Test fails — test is wrong

Bad locator, timing issue, incorrect URL, missing setup step. **Fix the test**, re-run. Max 2 fix attempts per test. This is a test defect, not an app defect.

### Test fails — app is wrong

The test correctly reproduced a bug. **Do not fix the test.** Move it to the `.bugs.spec.ts` file, add `test.fail()`, and document the bug in the findings.

If a `.bugs.spec.ts` test passes (the `test.fail()` expectation is violated), it means the bug doesn't reproduce — re-examine your steps.

After triaging all results, run both files:

```bash
npx playwright test tests/e2e/<flow-name>.spec.ts tests/e2e/<flow-name>.bugs.spec.ts --reporter=list 2>&1
```

All tests should be green: verification tests pass because the app works, bug tests "pass" because `test.fail()` correctly expects the failure.

---

## Phase 6: Deepen

You've completed one pass. Now push further. This phase is not optional.

Review what you've tested and ask:

1. **What did I skip?** Were there branches in the flow I didn't take? Form fields I didn't try to break? Error states I didn't trigger?
2. **What felt fragile?** Slow loads, transitions that flickered, elements that appeared briefly then vanished — go back and stress those.
3. **What assumptions did I make?** Did I assume auth would always work? That data would always be present? That the page would always load in time? Test those assumptions.
4. **What would a hostile user do?** Not malicious — just impatient, confused, or creative. Double-clicks, back-button, refresh mid-flow, opening the same page in two tabs.

Pick the 2-3 most promising leads and run them through Phases 3-5 again. Add findings to the existing test files.

If this second pass finds nothing new, you're done. If it finds bugs, consider whether a third pass is warranted — but cap at 3 total passes to avoid diminishing returns.

---

## Phase 7: Report

Print the final bug report. This is the deliverable.

```text
E2E Bug Hunt: <FLOW>
Mode: <mode> | Base URL: <base-url>
Passes: <N total passes>

BUGS FOUND (<count>):
  1. <title> — <one-line description>
     Reproduce: tests/e2e/<flow-name>.bugs.spec.ts "<test name>"
     Severity: <critical|high|medium|low>

  2. ...

BEHAVIORS VERIFIED (<count>):
  - <step/scenario that passed>
  - ...

NOT REACHED:
  - <areas you couldn't test and why — auth wall, missing data, feature flag, etc.>
```

**If zero bugs found:**

```text
E2E Bug Hunt: <FLOW>
Mode: <mode> | Base URL: <base-url>
Passes: <N total passes>

NO BUGS FOUND

BEHAVIORS VERIFIED (<count>):
  - <step/scenario that passed>
  - ...

PROBES ATTEMPTED:
  - <edge case / negative test that passed>
  - ...

NOT REACHED:
  - <areas you couldn't test and why>
```

Zero bugs is a valid outcome — but only after the Deepen phase. If you didn't probe edge cases, you didn't look hard enough.

---

## Rules

- **The browser is your source of truth.** Write tests from what you see in the accessibility tree, not from reading source code. If you haven't seen it in the browser, don't assert it.
- **A failing test is a finding, not an error.** Only fix tests that fail due to test defects (wrong locator, timing). If the app is broken, the test is correct.
- **Accessibility locators only.** `getByRole()`, `getByText()`, `getByLabel()`, `getByPlaceholder()`. Never CSS selectors. Non-negotiable.
- **No hardcoded waits.** Use Playwright's auto-waiting and explicit assertions.
- **Never modify the user's application code.** Only create/modify files in `tests/e2e/` and `playwright.config.ts`.
- **If the MCP server is not available, stop.** The entire value of this tool is driving a real browser. Without MCP, you're guessing from source code — which is what we're avoiding.
- **Keep tests focused.** One flow per file pair (`.spec.ts` + `.bugs.spec.ts`).
- **Every generated test gets executed.** Verification is not optional.
- **Your session is incomplete until you've deepened.** Phase 6 is mandatory. Don't declare done after one pass.
