---
description: "Smoke test: crawl every route, check every page, fix or plan issues"
argument-hint: "[FLOW] [--base-url URL] [--as PERSONA] [--max-depth N] [--fix] [--personas FILE]"
---

# Smoke Test with Playwright MCP

You are a QA engineer performing an exhaustive smoke test of a web application. Your job is to visit every reachable page, check for issues, fix small problems inline, and write a remediation plan for larger ones.

Parse `$ARGUMENTS` to determine mode and options.

**Arguments:**

- First positional → `FLOW` (optional). If provided, this is a targeted flow test (e.g., "schedule an appointment", "create a new user"). If omitted, perform a full smoke test of all reachable pages.
- `--base-url URL` → starting URL
- `--as PERSONA` → which persona to use for a targeted flow (e.g., `--as admin`). Required for flow tests. For smoke tests, all personas are tested.
- `--max-depth N` → max crawl depth (default: 10, smoke test only)
- `--fix` → fix small issues in source code as you find them. Without this flag, report only.
- `--personas FILE` → persona config file path (default: `.tim-smoke.yaml`)

Follow these phases in order. Do not skip phases.

---

## Phase 1: Setup

### 1a: Check for Playwright MCP (MANDATORY — do this first)

You need Playwright MCP tools to drive the browser. These are tools like `mcp__playwright__browser_navigate`, `mcp__plugin_playwright_playwright__browser_navigate`, or similar — the prefix varies by installation. They appear in your available tool list the same way `Bash`, `Read`, `Grep` do. They are NOT shell commands. Do NOT run bash commands to look for them. Just check: can you call a tool with `browser_navigate` in its name?

**If you do NOT have any `browser_navigate` tool**, install it automatically — no user interaction needed:

```bash
npx playwright install chromium && claude mcp add playwright -- npx -y @playwright/mcp@latest && echo "Playwright MCP installed successfully"
```

Then print this message and **STOP**:

```text
Playwright MCP installed automatically. Restart Claude Code and run /tim-smoke again.
(MCP tools only load at startup — this is a one-time requirement.)
```

Do not continue to Phase 1b. MCP tools cannot be loaded mid-session.

**If you DO have browser tools** → continue.

### 1b: Detect Base URL

If `--base-url` not provided, check in this order:

1. `playwright.config.ts` — look for `baseURL`
2. `TIM_SMOKE_BASE_URL` or `TIM_E2E_BASE_URL` environment variable
3. `package.json` — look for dev/start/serve scripts with a port number → `http://localhost:<port>`
4. **Ask the user.** Offer `http://localhost:3000` as default.

Verify the app is running:

```bash
curl -s -o /dev/null -w "%{http_code}" <base-url> 2>/dev/null || echo "unreachable"
```

If unreachable, ask the user to start the app or provide a different URL. Do not proceed until reachable.

### 1c: Load Personas

Read the personas file (default: `.tim-smoke.yaml`). Expected format:

```yaml
personas:
  - name: admin
    login_url: /login
    credentials:
      - field: Email
        value: admin@example.com
      - field: Password
        value: admin123
    submit: Sign In
    verify: Dashboard
  - name: user
    login_url: /login
    credentials:
      - field: Email
        value: user@example.com
      - field: Password
        value: user123
    submit: Sign In
    verify: Welcome
```

Fields:

- `name` — persona identifier (used with `--as`)
- `login_url` — path to login page (relative to base URL)
- `credentials` — list of `{field, value}` pairs. `field` is the accessible name of the input (label text).
- `submit` — accessible name of the submit button
- `verify` — text or element visible after successful login

If the file doesn't exist, ask the user interactively:

1. Does the app require login? If no → create a single persona with `name: public` and no credentials. Skip login for this persona.
2. If yes: how many user types does the app have?
3. For each type: name, login URL, credential fields + values, submit button text, verification text
4. Are there also public (no-login) pages? If yes, add a `public` persona with no credentials — this gets crawled first without login.

Save answers to `.tim-smoke.yaml` for future runs. **Do NOT commit this file** — it contains credentials.

**Public persona example** (no login needed):

```yaml
personas:
  - name: public
    # no login_url, credentials, submit, or verify = skip login
```

### 1d: Create State File

Create `.tim-smoke-state.json` in the project root:

```json
{
  "started_at": "<ISO timestamp>",
  "base_url": "<url>",
  "mode": "<smoke|flow>",
  "flow": "<flow description or null>",
  "personas_tested": [],
  "current_persona": null,
  "visited": [],
  "queue": [],
  "issues": [],
  "fixes": []
}
```

Update this file after every page visit. This is your source of truth if context compacts — always read it first to see what's already been done.

---

## Phase 2: Test Execution

### Mode A: Full Smoke Test (no FLOW argument)

For **each** persona in the config:

#### 2a: Login

If the persona has no `login_url` (e.g., `public` persona) → skip login, navigate directly to the base URL, and start crawling.

Otherwise:

1. Navigate to `<base_url><login_url>`
2. Take a snapshot to find the form fields
3. Fill each credential using `browser_type` (click the field first, then type)
4. Click the submit button
5. Take a snapshot — verify the `verify` text/element is visible
6. If login fails → record as a critical issue, skip this persona

#### 2b: Crawl

Starting from the post-login page, use breadth-first crawling:

1. Take a snapshot → extract all same-origin links (hrefs starting with `/` or the base URL domain)
2. Add unvisited links to the queue
3. **Prioritize navigation elements first** — sidebar links, nav bar items, menu dropdowns. These lead to the most routes.
4. Visit the next unvisited URL from the queue
5. Perform page inspection (2c) at each page
6. Extract new links from the page, add unvisited ones to queue
7. Repeat until queue is empty or max depth reached

**Skip:** `mailto:`, `tel:`, `javascript:`, `#`-only anchors, file download links, external domains, logout/signout links.

**Deduplicate:** Normalize URLs — strip trailing slashes, treat `/page` and `/page/` as the same. Track query parameters only if they change the page content.

**Between personas:** Close the browser (`browser_close`), then reopen for the next persona. Clean session each time.

#### 2c: Page Inspection (EVERY page)

At each page, perform ALL of these checks:

| # | Check | Tool | Issue if... |
|---|-------|------|-------------|
| 1 | Console errors | `browser_console_messages` | Any `error`-level messages |
| 2 | Failed network requests | `browser_network_requests` | Any 4xx or 5xx responses |
| 3 | Page loads at all | `browser_snapshot` | Blank page, only a spinner, or error boundary |
| 4 | Has meaningful content | `browser_snapshot` | Main content area is empty or shows only a loading skeleton |
| 5 | Charts/graphs render | `browser_snapshot` | Canvas/SVG elements with "No data", "Error", or zero dimensions |
| 6 | Images load | `browser_snapshot` | Alt text visible (means image failed to load) or broken image indicators |
| 7 | Error messages visible | `browser_snapshot` | User-facing error messages, stack traces, "Something went wrong" |
| 8 | Tables have data | `browser_snapshot` | Tables with zero rows when data is expected |
| 9 | Navigation works | `browser_snapshot` | Current page URL doesn't match where you navigated to (redirect to error page) |
| 10 | Stuck loading | Two snapshots 3s apart | Same loading/spinner state in both snapshots |

**For checks 1-2:** Call these tools on EVERY page, not just when something looks wrong. Console errors and failed network requests are invisible without explicitly checking.

Record each finding:

```json
{
  "url": "/admin/reports",
  "persona": "admin",
  "check": "console_errors",
  "severity": "high",
  "description": "TypeError: Cannot read property 'map' of undefined",
  "details": "Error appears when reports page loads, likely missing API data"
}
```

Severity guide:

- **critical** — page doesn't load, login broken, app crashes
- **high** — console errors, failed API calls, blank content areas, broken core functionality
- **medium** — missing images, empty charts with "no data", minor UI broken states
- **low** — console warnings, minor visual issues, non-blocking UX problems

### Mode B: Targeted Flow Test (FLOW argument provided)

Use the persona specified by `--as` (required for flow tests).

1. **Login** as the specified persona (same as 2a above)
2. **Navigate the flow** described in the FLOW argument:
   - Read the current page snapshot
   - Find the link, button, or menu item that corresponds to the next step in the flow
   - Click it, fill forms, select options, interact with the page as a real user would
   - **You MAY submit forms and create data** — this is the point of flow testing
   - At each step, perform the page inspection checklist (2c)
   - Continue until the flow is complete (the described journey is finished)
3. **Verify the outcome** — did the flow succeed? Check for confirmation messages, created records, navigation to success pages.
4. If the flow breaks at any point, record exactly where and why.

**Flow navigation tips:**

- Use `browser_snapshot` to read the accessibility tree before each action
- Look for buttons, links, and form fields by their accessible names (role + name)
- If you can't find the next step, take a screenshot and describe what you see
- Don't guess — if the flow path is ambiguous, describe the options you see and pick the most likely one
- Record every step you take so the finding report is reproducible

---

## Phase 3: Triage

After completing all crawling/flows, review all issues found.

### Fix Now (only if `--fix` flag is set)

Fix these types of issues inline by editing source code:

- Typos in user-visible text
- Missing alt text on images
- Console errors from obvious bugs (undefined variables, missing null checks, wrong imports)
- Broken internal links (wrong href path)
- Missing error boundary causing blank screens
- CSS issues causing content to not display

For each fix:

1. Use Grep/Glob to locate the source file
2. Read the relevant code
3. Make the fix with Edit
4. Record what was fixed in the state file

**Do NOT fix:** anything requiring architectural changes, API/backend fixes, database issues, or changes you're not confident about. Those go in the plan.

### Create Remediation Plan

If any unfixed issues remain, create a plan file:

`plans/drafts/YYYY-MM-DD-HH-MM-smoke-test-remediation.md`

```markdown
# Smoke Test Remediation Plan

**Tested:** <date>
**Base URL:** <url>
**Personas tested:** <list>
**Pages visited:** <count>
**Issues found:** <total> (<fixed> fixed inline, <remaining> need remediation)

## Critical Issues

### 1. <title>
- **URL:** <url>
- **Persona:** <persona>
- **What happens:** <description>
- **Expected:** <what should happen>
- **Console/Network:** <any relevant errors>

## High Priority Issues

### 1. ...

## Medium Priority Issues

### 1. ...

## Low Priority Issues

### 1. ...
```

Group issues that share a root cause. If five pages all have the same console error, that's one issue with multiple affected pages, not five issues.

---

## Phase 4: Report

Print a summary:

```text
Smoke Test Complete

  Base URL:    <url>
  Mode:        <smoke test | flow: "description">
  Personas:    <list>
  Pages:       <total visited>

  Issues Found:  <total>
    Critical:    <n>
    High:        <n>
    Medium:      <n>
    Low:         <n>

  Fixed Inline:  <n> (list files changed)
  In Plan:       <n>

  Plan: plans/drafts/<filename>.md
```

Remove `.tim-smoke-state.json` when done.

---

## Rules

- **The browser is your source of truth.** Check what actually renders, not what the code says should render.
- **Visit EVERY link in smoke test mode.** Don't skip pages because they "probably work." Exhaustive coverage is the point.
- **Check console + network on EVERY page.** These are invisible issues — the page might look fine but have errors.
- **Same-origin only.** Don't follow links to external sites.
- **Don't submit forms in smoke test mode.** View-only navigation. Flow test mode is for interaction.
- **Fix only what you're sure about.** When in doubt, put it in the plan.
- **Update the state file after every page.** If context compacts, read the state file first to resume where you left off.
- **One persona at a time.** Complete all pages for one persona before moving to the next. Close browser between personas.
- **Never skip the login verification.** If login fails, you're testing the wrong thing.
- **Don't follow logout links.** Skip any link containing "logout", "signout", "sign-out", or similar.
