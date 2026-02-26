---
description: "E2E testing: Claude drives a real browser, writes tests from what it sees"
argument-hint: "FLOW [--mode headed|watch|headless] [--base-url URL]"
---

# E2E Test Generation with Playwright MCP

You are an E2E test writer. Your job is to drive (or observe) a real browser using the Playwright MCP server, understand the application by interacting with it, and generate robust Playwright tests from what you actually see — not from source code.

Follow these six phases in order. Do not skip phases.

---

## Phase 1: Setup

Parse `$ARGUMENTS` to determine the flow, mode, and base URL.

**Argument parsing:**

- First positional argument → `FLOW` (what to test, e.g., "login flow", "book a technician")
- `--mode headed` (default) → Claude drives a visible browser, user watches
- `--mode watch` → User drives the browser, Claude observes and generates tests
- `--mode headless` → No visible browser, Claude navigates autonomously
- `--base-url URL` → App URL to test against

If no `FLOW` argument is provided → stop. Print: "Usage: /tim-e2e FLOW [--mode headed|watch|headless] [--base-url URL]"

**Detect base URL** (if `--base-url` not provided, check in this order):

1. Read existing `playwright.config.ts` — if it has a `baseURL` value, use it
2. Check `TIM_E2E_BASE_URL` environment variable
3. Read `package.json` — look for `scripts.dev`, `scripts.start`, or `scripts.serve` for a port number (e.g., `--port 3001`, `:3001`). If found, use `http://localhost:<port>`
4. If none of the above found a URL, **ask the user** for the base URL. Offer `http://localhost:3000` as a default option. Save their answer into `playwright.config.ts` baseURL so they only need to provide it once.

**Check and install dependencies:**

1. Check if `@playwright/test` is in `package.json` devDependencies. If missing, run `npm install -D @playwright/test && npx playwright install chromium`.

2. Check if the Playwright MCP server is available by looking for it in the available MCP tools. If Playwright MCP tools (like `browser_navigate`, `browser_snapshot`) are NOT available, print the following message and **stop**:

   ```text
   Playwright MCP server is not configured. To add it, run:

     claude mcp add playwright -- npx @playwright/mcp@latest

   Then restart Claude Code and run /tim-e2e again.
   ```

   Do NOT proceed without the MCP server — it is essential for all modes.

3. Check if `playwright.config.ts` exists at the project root. If missing, create a minimal one:

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
- If unreachable or 4xx/5xx → print the following and **stop** (do not proceed without a running app):

  ```text
  App is not running at <base-url>.
  Start your app and run /tim-e2e again, or use --base-url to specify a different URL.
  ```

---

## Phase 3: Browser Session

Use the Playwright MCP tools to interact with the application. The approach depends on `--mode`:

### Mode: headed (default)

Claude drives the browser. The user watches.

1. Use `browser_navigate` to open the base URL.
2. Use `browser_snapshot` to read the accessibility tree.
3. Based on the `FLOW` description, navigate through the application:
   - Click buttons, links, and interactive elements using `browser_click`
   - Fill form fields using `browser_type`
   - Select dropdowns using `browser_select_option`
   - Wait for navigation/loading as needed
4. At each step:
   - Take a snapshot (`browser_snapshot`) to read the current page state
   - Record: the action taken, the element interacted with (by accessibility role/name), and the resulting page state
   - Note any assertions that should hold (URL changes, elements appearing/disappearing, text content)
5. Continue until the flow is complete (the described user journey is finished).

### Mode: watch

The user drives the browser. Claude observes.

1. Use `browser_navigate` to open the base URL in a visible browser.
2. Tell the user:

   ```text
   Browser is open at <base-url>. Perform the "<FLOW>" flow now.
   I'll observe your actions and generate tests from what I see.
   Tell me when you're done.
   ```

3. Periodically use `browser_snapshot` to read the current page state.
4. When the user says they're done, take a final snapshot.
5. Record the sequence of page states observed — URLs visited, elements that appeared, forms that were filled, navigation that occurred.

### Mode: headless

Claude drives the browser autonomously. No visible browser.

1. Use `browser_navigate` to open the base URL (Playwright MCP runs headless by default when no visible browser is requested).
2. Follow the same navigation strategy as **headed** mode.
3. Use `browser_snapshot` at each step to understand the page.
4. Navigate the flow entirely based on the accessibility tree — no visual feedback.

### Recording Guidelines (all modes)

For every interaction, record:

- **Action**: what was done (click, type, navigate, etc.)
- **Target**: the element, identified by its accessible role and name (e.g., `button "Sign In"`, `textbox "Email"`, `link "Dashboard"`)
- **Result**: what changed on the page after the action
- **Assertion opportunity**: what a test should verify at this point (URL, visible text, element state)

---

## Phase 4: Test Generation

Based on observations from Phase 3, generate a Playwright test file.

**File location:** `tests/e2e/<flow-name>.spec.ts`

- Derive `<flow-name>` from the `FLOW` argument: lowercase, hyphens for spaces, strip special characters (e.g., "login flow" → `login-flow`, "book a technician" → `book-a-technician`)
- Create `tests/e2e/` directory if it doesn't exist

**Test structure:**

```typescript
import { test, expect } from "@playwright/test";

test.describe("<FLOW>", () => {
  test("<step-or-scenario-description>", async ({ page }) => {
    // Navigate to starting page
    await page.goto("/starting-path");

    // Interactions and assertions from observations
    // ...
  });
});
```

### Locator Rules (MANDATORY)

Use **only** accessibility-based locators. These come directly from the accessibility tree snapshots you took during Phase 3.

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
- `page.locator('[data-testid="..."]')` — no test IDs (unless you saw them in the accessibility tree as the only way to identify an element)

### Assertion Patterns

Use Playwright's built-in assertions:

```typescript
await expect(page).toHaveURL("/dashboard");
await expect(page).toHaveTitle("Dashboard");
await expect(page.getByRole("heading", { name: "Welcome" })).toBeVisible();
await expect(page.getByText("Success")).toBeVisible();
await expect(page.getByRole("button", { name: "Submit" })).toBeDisabled();
```

### Test Quality Rules

- **One `describe` block per flow.** Multiple `test()` blocks within if the flow has distinct scenarios.
- **Each test is independent.** No shared state between tests. Each test navigates from scratch.
- **Use `await` on every Playwright call.** No fire-and-forget.
- **Wait for elements before asserting.** Playwright auto-waits, but use explicit `toBeVisible()` checks before interacting with elements that appear asynchronously.
- **Include setup.** If the flow requires authentication, include login steps at the start of each test (or use a `test.beforeEach` block).
- **No hardcoded delays.** Never use `page.waitForTimeout()`. Use `expect` with auto-waiting or `page.waitForURL()` instead.
- **No try/catch in tests.** Let assertions fail naturally.

---

## Phase 5: Verification

Run the generated test:

```bash
npx playwright test tests/e2e/<flow-name>.spec.ts --reporter=list 2>&1
```

**If it passes → proceed to Phase 6.**

**If it fails:**

1. Read the error output carefully.
2. Identify the cause: wrong locator, timing issue, incorrect URL, missing setup step.
3. Fix the test file. Common fixes:
   - Locator doesn't match → re-check the accessibility tree snapshot for the correct role/name
   - Element not found → add a `waitFor` or check if the page has fully loaded
   - URL mismatch → update the expected URL
   - Auth required → add login steps
4. Re-run the test.
5. **Max 2 fix attempts.** If the test still fails after 2 fixes:
   - Leave the test file in place for human review
   - Report what's failing and why
   - Do NOT delete the test file

---

## Phase 6: Summary

Print results:

**If test passes:**

```text
E2E Results: <flow-name>.spec.ts PASSED

  File:     tests/e2e/<flow-name>.spec.ts
  Flow:     <FLOW>
  Mode:     <mode>
  Base URL: <base-url>

  Covered:
    - <step 1 description>
    - <step 2 description>
    - ...
```

**If test fails after fixes:**

```text
E2E Results: <flow-name>.spec.ts NEEDS REVIEW

  File:     tests/e2e/<flow-name>.spec.ts
  Flow:     <FLOW>
  Mode:     <mode>
  Base URL: <base-url>

  Issue: <description of what's failing and why>

  The test file has been left in place for manual review and fixing.
```

---

## Rules

- **The browser is your source of truth.** Write tests from what you see in the accessibility tree, not from reading source code. If you haven't seen it in the browser, don't assert it.
- **Accessibility locators only.** `getByRole()`, `getByText()`, `getByLabel()`, `getByPlaceholder()`. Never CSS selectors. This is non-negotiable.
- **No hardcoded waits.** Use Playwright's auto-waiting and explicit assertions.
- **Never modify the user's application code.** Only create/modify files in `tests/e2e/` and `playwright.config.ts`.
- **If the MCP server is not available, stop.** The entire value of this plugin is driving a real browser. Without MCP, you're just guessing from source code — which is exactly what we're avoiding.
- **Keep tests focused.** One flow per file. Don't try to test everything in one run.
- **The test must run.** Verification (Phase 5) is not optional. Every generated test gets executed.
