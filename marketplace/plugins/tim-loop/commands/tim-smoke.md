---
description: "Smoke test: find broken pages, investigate problems, fix or plan"
argument-hint: "[FLOW] [--base-url URL] [--as PERSONA] [--max-depth N] [--fix] [--personas FILE]"
---

# Smoke Test with Playwright MCP

You are investigating a running web application for problems. Your method is systematic crawling. Your objective is finding everything that's broken — not completing a checklist.

When something looks wrong, stop crawling and investigate. A console error isn't a line item — it's a lead. Try to understand *why* it's happening before recording it and moving on.

Parse `$ARGUMENTS` to determine mode and options.

**Arguments:**

- First positional → `FLOW` (optional). If provided, targeted flow test. If omitted, full smoke test of all reachable pages.
- `--base-url URL` → starting URL
- `--as PERSONA` → persona for flow tests (required for flows)
- `--max-depth N` → max crawl depth (default: 10, smoke test only)
- `--fix` → fix small issues in source code as you find them
- `--personas FILE` → persona config (default: `.tim-smoke.yaml`)

---

## Phase 1: Setup

### 1a: Check for Playwright MCP (MANDATORY — do this first)

You need Playwright MCP tools (`browser_navigate`, `browser_snapshot`, etc.) in your tool list. They are NOT shell commands — just check if you have a tool with `browser_navigate` in its name.

**If NOT available:**

```bash
npx playwright install chromium && claude mcp add playwright -- npx -y @playwright/mcp@latest
```

Then print "Playwright MCP installed. Restart Claude Code and run /tim-smoke again." and **STOP**. MCP tools only load at startup.

### 1b: Detect Base URL

If `--base-url` not provided, check: `playwright.config.ts` baseURL → `TIM_SMOKE_BASE_URL` / `TIM_E2E_BASE_URL` env var → `package.json` dev/start script port → ask user. Verify reachable with `curl`. Do not proceed until reachable.

### 1c: Load Personas

Read `.tim-smoke.yaml`. Expected format:

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
```

If the file doesn't exist, ask: does the app require login? How many user types? Collect credentials interactively. Add a `public` persona (no credentials) if there are public pages. Save to `.tim-smoke.yaml`. **Never commit this file.**

### 1d: State File

Create `.tim-smoke-state.json` tracking: timestamp, base URL, mode, personas tested, visited URLs, queue, issues, fixes. Update after every page visit — this is your resume point if context compacts.

---

## Phase 2: Investigation

### Mode A: Full Smoke Test (no FLOW)

For each persona:

**Login:** Navigate to login URL, fill credentials, click submit, verify success text. If login fails → critical issue, skip persona.

**Crawl:** Breadth-first from post-login page. Prioritize navigation elements (sidebar, nav bar, menus) — these reach the most routes. Extract same-origin links, add unvisited to queue. Skip: `mailto:`, `tel:`, `javascript:`, `#`, external domains, logout links. Normalize URLs. Close browser between personas.

**At every page, check:**

1. `browser_console_messages` — any errors? (Check this on EVERY page, not just suspicious ones)
2. `browser_network_requests` — any 4xx/5xx?
3. `browser_snapshot` — does the page render? Is there meaningful content? Any error messages, stack traces, broken images, empty tables, stuck spinners?

**When something looks wrong — investigate:**

- Console error → is it on this page only or every page? What triggers it? Is it a missing API, a bad import, a race condition?
- Empty content area → is the API returning empty data, or is the component failing to render? Check network requests.
- Slow/hung page → take two snapshots 3 seconds apart. Same state? What's the page waiting for?
- Something that feels off (layout jump, flash of wrong content, element that shouldn't be clickable) → interact with it. Try to reproduce it.

Record findings:

```json
{
  "url": "/admin/reports",
  "persona": "admin",
  "check": "console_errors",
  "severity": "critical|high|medium|low",
  "description": "TypeError: Cannot read property 'map' of undefined",
  "investigation": "Error appears on load. API returns 200 but empty array. Component doesn't handle empty state."
}
```

**Spend more time on pages with:** forms, dynamic data, user interactions, dashboards, data tables. These are where bugs live. Static pages get a quick check.

**Form probing (even in smoke test mode):** You may submit empty forms to check validation behavior. Do NOT submit forms with real data in smoke test mode — that's what flow tests are for. But testing that a form *rejects* empty submission is safe and finds real bugs.

### Mode B: Targeted Flow Test (FLOW argument)

Login as `--as` persona. Navigate the described flow — interact with forms, submit data, create records. At each step run the page checks. Try to complete the flow, then verify the outcome. If it breaks, record exactly where and why.

**After the happy path:** try the flow with wrong inputs, skip steps, go back mid-flow. Find where it breaks.

---

## Phase 3: Triage

### Fix Now (only with `--fix`)

Fix only: typos, missing alt text, obvious null-check bugs, broken internal links, missing error boundaries, CSS hiding content. Use Grep/Glob to find source, Read to understand, Edit to fix.

**Do NOT fix:** architectural issues, API/backend problems, database issues, anything you're not confident about. Those go in the plan.

### Remediation Plan

If unfixed issues remain, create `plans/drafts/YYYY-MM-DD-HH-MM-smoke-test-remediation.md`. Group issues that share a root cause — five pages with the same console error is one issue, not five. Organize by severity (critical → high → medium → low).

---

## Phase 4: Report

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

  Investigated:  <n issues where you dug deeper>
  Fixed Inline:  <n> (list files changed)
  In Plan:       <n>

  Plan: plans/drafts/<filename>.md
```

Remove `.tim-smoke-state.json` when done.

---

## Rules

- **The browser is your source of truth.** Check what renders, not what the code says.
- **Investigate, don't just record.** A console error is a lead. Understand it before logging it.
- **Check console + network on EVERY page.** These are invisible without explicitly checking.
- **Spend time where bugs live.** Interactive pages, forms, dashboards — not static content.
- **Same-origin only.** Don't follow external links.
- **Update state after every page.** Resume from state file if context compacts.
- **One persona at a time.** Close browser between personas.
- **Don't follow logout links.**
