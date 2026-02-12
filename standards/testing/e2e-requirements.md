# End-to-End Testing Requirements

All TIM applications require comprehensive e2e testing. No route exists without tests. No code deploys without passing tests. Zero tolerance for flaky tests.

## Core Principles

1. **All code requires tests** - Unit, integration, AND e2e. Always.
2. **True e2e testing** - Real browser, real user simulation, real data entry
3. **Defense in depth** - No route allowed without proper e2e coverage
4. **DevOps mindset** - See a problem, fix it, regardless of who created it
5. **Zero tolerance** - No flaky tests, no skipped tests, no exceptions
6. **Strict enforcement** - System-level blocks, not developer honor system

## Three-Layer Testing Model

| Layer | Environment | Test Requirements | Promotion Rule |
|-------|-------------|-------------------|----------------|
| **DEV** | Local or remote | Unit + Integration | Quick deploy allowed |
| **UAT** | Remote (Docker) | Full e2e required | Auto-promote if all tests pass |
| **PROD** | Remote (Docker/Cloud) | Full e2e + smoke | Human approval required |

### DEV Layer

- Unit tests must pass
- Integration tests must pass
- Quick iteration allowed
- Errors/skips permitted (for active development)
- **Cannot promote to UAT with any failing tests**

### UAT Layer

- ALL unit tests must pass
- ALL integration tests must pass
- ALL e2e tests must pass
- Smoke test discovers and validates route coverage
- **Auto-promotes to prod-ready if all pass**

### PROD Layer

- Full e2e suite across entire application
- Smoke test validates all routes
- Zero bugs allowed
- **Requires human approval after tests pass**

## E2E Test Structure

### What "True E2E" Means

E2E tests must:

- Run in a real browser (Playwright/Puppeteer)
- Simulate actual user behavior
- Enter all data through UI (no API shortcuts)
- Navigate through real UI flows
- Wait for real responses
- Validate visual and functional outcomes

```typescript
// WRONG - This is NOT e2e testing
test("create user", async () => {
  const response = await api.post("/users", userData);
  expect(response.status).toBe(201);
});

// CORRECT - True e2e testing
test("create user through registration form", async ({ page }) => {
  await page.goto("/register");
  await page.fill('[data-testid="email"]', testData.user.email);
  await page.fill('[data-testid="password"]', testData.user.password);
  await page.fill('[data-testid="confirm-password"]', testData.user.password);
  await page.click('[data-testid="submit"]');

  await expect(page).toHaveURL("/dashboard");
  await expect(page.locator('[data-testid="welcome-message"]')).toContainText(testData.user.email);
});
```

### Test Organization: Hierarchical Suites

Tests are organized in a tree structure:

```text
tests/
├── e2e/
│   ├── suites/
│   │   ├── auth/                    # Authentication suite
│   │   │   ├── login.spec.ts
│   │   │   ├── logout.spec.ts
│   │   │   ├── registration.spec.ts
│   │   │   ├── password-reset.spec.ts
│   │   │   └── suite.config.ts      # Suite configuration
│   │   │
│   │   ├── billing/                 # Billing suite
│   │   │   ├── subscription.spec.ts
│   │   │   ├── payment.spec.ts
│   │   │   ├── invoices.spec.ts
│   │   │   └── suite.config.ts
│   │   │
│   │   ├── core-features/           # Core features suite
│   │   │   ├── projects/
│   │   │   │   ├── create.spec.ts
│   │   │   │   ├── edit.spec.ts
│   │   │   │   ├── delete.spec.ts
│   │   │   │   └── suite.config.ts
│   │   │   ├── dashboard/
│   │   │   └── settings/
│   │   │
│   │   └── full-suite.config.ts     # Parent suite: runs all child suites
│   │
│   ├── smoke/
│   │   ├── route-discovery.spec.ts  # Automatic route discovery
│   │   └── coverage-check.spec.ts   # Validates e2e coverage exists
│   │
│   ├── user-journeys/               # Complete user path tests
│   │   ├── new-user-onboarding.spec.ts
│   │   ├── returning-user-workflow.spec.ts
│   │   └── admin-workflow.spec.ts
│   │
│   └── regression/                  # Changed-area rigorous tests
│       └── [generated based on git diff]
│
├── integration/
│   ├── api/
│   └── services/
│
├── unit/
│   ├── components/
│   ├── utils/
│   └── services/
│
├── helpers/                         # Shared test utilities
│   ├── actions/                     # Reusable UI actions
│   │   ├── auth.ts                  # login(), logout(), register()
│   │   ├── navigation.ts            # goTo(), waitForRoute()
│   │   ├── forms.ts                 # fillForm(), submitForm()
│   │   └── index.ts
│   │
│   ├── assertions/                  # Custom assertions
│   │   ├── visual.ts
│   │   ├── data.ts
│   │   └── index.ts
│   │
│   ├── fixtures/                    # Test fixtures
│   │   ├── user.fixture.ts
│   │   ├── project.fixture.ts
│   │   └── index.ts
│   │
│   └── utils/                       # General utilities
│       ├── test-id.ts               # UUID generation
│       ├── cleanup.ts               # Data cleanup
│       ├── wait.ts                  # Timing utilities
│       └── index.ts
│
└── data/                            # Source of Truth (YAML)
    ├── users.yaml
    ├── projects.yaml
    ├── billing.yaml
    └── index.ts                     # Exports typed test data
```

## Automatic Route Discovery

### Smoke Test: Route Discovery

The smoke test automatically discovers all routes and validates e2e coverage:

```typescript
// smoke/route-discovery.spec.ts
import { test, expect } from '@playwright/test';
import { discoverRoutes, validateCoverage } from '../helpers/route-discovery';

test.describe('Route Discovery Smoke Test', () => {
  test('discover and validate all routes', async ({ page }) => {
    // 1. Discover frontend routes (SPA router)
    const frontendRoutes = await discoverRoutes(page, {
      type: 'frontend',
      includeAuthenticated: true,
    });

    // 2. Discover API endpoints
    const apiRoutes = await discoverRoutes(page, {
      type: 'api',
      baseUrl: '/api/v1',
    });

    // 3. Validate each route for console errors
    for (const route of [...frontendRoutes, ...apiRoutes]) {
      await page.goto(route.path);

      const errors = await page.evaluate(() => window.__consoleErrors || []);
      expect(errors, `Console errors on ${route.path}`).toHaveLength(0);
    }

    // 4. Validate e2e coverage exists for all routes
    const coverage = await validateCoverage(frontendRoutes);

    for (const route of coverage.uncovered) {
      // This will FAIL the test - no route without e2e coverage
      expect.fail(`Missing e2e test for route: ${route.path}`);
    }
  });
});
```

### Route Discovery Implementation

```typescript
// helpers/route-discovery.ts
interface Route {
  path: string;
  type: 'frontend' | 'api';
  authenticated: boolean;
  methods?: string[];  // For API routes
}

export async function discoverRoutes(
  page: Page,
  options: { type: 'frontend' | 'api'; includeAuthenticated?: boolean }
): Promise<Route[]> {
  const routes: Route[] = [];

  if (options.type === 'frontend') {
    // Extract routes from React Router / Next.js
    const discovered = await page.evaluate(() => {
      // For React Router
      if (window.__REACT_ROUTER_ROUTES__) {
        return window.__REACT_ROUTER_ROUTES__;
      }

      // For Next.js - check __NEXT_DATA__
      if (window.__NEXT_DATA__?.pages) {
        return Object.keys(window.__NEXT_DATA__.pages);
      }

      // Fallback: crawl the DOM for links
      const links = Array.from(document.querySelectorAll('a[href^="/"]'));
      return [...new Set(links.map(a => a.getAttribute('href')))];
    });

    // Recursively discover nested routes
    for (const path of discovered) {
      await page.goto(path);
      // Look for more links, repeat...
    }
  }

  if (options.type === 'api') {
    // Fetch OpenAPI spec if available
    const spec = await fetch('/api/openapi.json').then(r => r.json());
    // Or discover from route registrations
  }

  return routes;
}

export async function validateCoverage(routes: Route[]): Promise<{
  covered: Route[];
  uncovered: Route[];
}> {
  // Check which routes have corresponding .spec.ts files
  const testFiles = await glob('tests/e2e/**/*.spec.ts');
  const testedRoutes = extractRoutesFromTestFiles(testFiles);

  return {
    covered: routes.filter(r => testedRoutes.includes(r.path)),
    uncovered: routes.filter(r => !testedRoutes.includes(r.path)),
  };
}
```

## User Journey Testing

### Defining User Paths

User paths are defined in YAML and approved by humans:

```yaml
# data/user-journeys/new-user-onboarding.yaml
journey:
  name: "New User Onboarding"
  description: "Complete flow from landing to first project creation"
  approved_by: "tim@example.com"
  approved_date: "2025-01-15"

  preconditions:
    - "No existing user with test email"

  steps:
    - name: "Visit landing page"
      action: "navigate"
      path: "/"
      assertions:
        - "page loads without errors"
        - "CTA button visible"

    - name: "Click sign up"
      action: "click"
      selector: "[data-testid='signup-cta']"
      assertions:
        - "navigates to /register"

    - name: "Fill registration form"
      action: "fill-form"
      form: "registration"
      data_ref: "users.new_user"
      assertions:
        - "form submits successfully"
        - "navigates to /onboarding"

    - name: "Complete onboarding"
      action: "complete-onboarding"
      steps:
        - "select-plan"
        - "add-payment"
        - "create-first-project"
      assertions:
        - "arrives at /dashboard"
        - "project visible in list"

  cleanup:
    - "delete created user"
    - "delete created project"
    - "delete payment method"
```

### AI-Proposed, Human-Approved

When creating new tests, the AI developer:

1. Analyzes the feature/route being tested
2. Proposes testing paths covering:
   - Happy path (successful flow)
   - Validation errors
   - Edge cases
   - Error states
3. Presents proposal to human for review
4. Human approves, modifies, or requests changes
5. Only approved paths are implemented

```yaml
# AI proposal format
proposal:
  feature: "User Registration"
  proposed_by: "Claude"
  date: "2025-01-15"
  status: "pending_approval"  # pending_approval | approved | rejected

  paths:
    - name: "Successful registration"
      type: "happy_path"
      priority: "critical"
      steps: [...]

    - name: "Duplicate email rejection"
      type: "validation_error"
      priority: "high"
      steps: [...]

    - name: "Weak password rejection"
      type: "validation_error"
      priority: "high"
      steps: [...]

    - name: "Network error handling"
      type: "error_state"
      priority: "medium"
      steps: [...]

  # Human fills this out
  approval:
    approved_by: null
    approved_date: null
    notes: null
    modifications: []
```

## Changed-Area Rigorous Testing

When code changes touch specific areas, those areas get rigorous testing:

```typescript
// regression/changed-area-tests.ts
import { getChangedFiles } from '../helpers/git';
import { mapFilesToRoutes } from '../helpers/route-mapping';

async function determineRigorousTestScope(): Promise<TestScope> {
  const changedFiles = await getChangedFiles();
  const affectedRoutes = await mapFilesToRoutes(changedFiles);

  return {
    // Changed areas: run ALL possible paths
    rigorous: affectedRoutes,
    // Unchanged areas: run smoke + happy paths only
    standard: getAllRoutes().filter(r => !affectedRoutes.includes(r)),
  };
}
```

For "rigorous" testing, we run every defined path:

- All happy paths
- All validation error paths
- All edge cases
- All error states
- All user journey variations

For "standard" testing:

- Smoke test (no console errors)
- Happy path only

## Browser Configuration

```typescript
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',

  // Parallel execution
  fullyParallel: true,
  workers: process.env.CI ? 4 : undefined,

  // Zero tolerance - fail fast
  forbidOnly: !!process.env.CI,
  retries: 0,  // No retries - flaky = broken

  // Default: Chrome only
  projects: [
    {
      name: 'chrome',
      use: { ...devices['Desktop Chrome'] },
    },
    // Enabled by flag: --project=firefox --project=safari
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'safari',
      use: { ...devices['Desktop Safari'] },
    },
  ],

  // Reporter
  reporter: [
    ['html'],
    ['json', { outputFile: 'test-results/results.json' }],
  ],
});
```

Run with multi-browser:

```bash
# Default: Chrome only
npm run test:e2e

# Multi-browser (human requested)
npm run test:e2e -- --project=chrome --project=firefox --project=safari
```

## Enforcement: Hard Stops

### No Skipping Allowed (Promotion)

```typescript
// In test setup
test.beforeEach(async () => {
  if (process.env.PROMOTION_MODE === 'true') {
    // Disable skip functionality
    test.skip = () => {
      throw new Error(
        'HARD STOP: Tests cannot be skipped during promotion.\n' +
        'Fix the test or get human approval to proceed.'
      );
    };
  }
});
```

### CI Gate Enforcement

```yaml
# .github/workflows/promotion.yml
name: Promotion Gate

on:
  workflow_dispatch:
    inputs:
      target:
        description: 'Target environment'
        required: true
        type: choice
        options:
          - uat
          - prod

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run full e2e suite
        env:
          PROMOTION_MODE: 'true'
        run: npm run test:e2e:full

      - name: Check for skipped tests
        run: |
          SKIPPED=$(jq '.suites[].specs[] | select(.status == "skipped")' test-results/results.json)
          if [ -n "$SKIPPED" ]; then
            echo "::error::HARD STOP: Skipped tests detected during promotion"
            echo "$SKIPPED"
            exit 1
          fi

      - name: Check coverage
        run: |
          UNCOVERED=$(node scripts/check-route-coverage.js)
          if [ -n "$UNCOVERED" ]; then
            echo "::error::HARD STOP: Routes without e2e coverage detected"
            echo "$UNCOVERED"
            exit 1
          fi

  promote-uat:
    needs: test
    if: inputs.target == 'uat'
    runs-on: ubuntu-latest
    steps:
      - name: Auto-promote to UAT
        run: ./ops.sh deploy --environment uat --confirm

  promote-prod:
    needs: test
    if: inputs.target == 'prod'
    runs-on: ubuntu-latest
    environment: production  # Requires approval
    steps:
      - name: Deploy to production
        run: ./ops.sh deploy --environment prod --confirm
```

### Human Alert on Violations

```typescript
// helpers/enforcement.ts
export async function enforceTestRules(results: TestResults): Promise<void> {
  const violations: string[] = [];

  // Check for skipped tests
  const skipped = results.suites.flatMap(s =>
    s.specs.filter(spec => spec.status === 'skipped')
  );
  if (skipped.length > 0) {
    violations.push(`${skipped.length} tests were skipped`);
  }

  // Check for flaky tests (any test that was retried)
  const flaky = results.suites.flatMap(s =>
    s.specs.filter(spec => spec.retries > 0)
  );
  if (flaky.length > 0) {
    violations.push(`${flaky.length} flaky tests detected`);
  }

  // Check for uncovered routes
  const coverage = await checkRouteCoverage();
  if (coverage.uncovered.length > 0) {
    violations.push(`${coverage.uncovered.length} routes without e2e tests`);
  }

  if (violations.length > 0 && process.env.PROMOTION_MODE === 'true') {
    // Send alert
    await sendAlert({
      channel: '#testing-alerts',
      message: `🛑 PROMOTION BLOCKED\n\nViolations:\n${violations.join('\n')}\n\nHuman review required.`,
      severity: 'critical',
    });

    // Hard stop
    console.error('╔══════════════════════════════════════════════════════════════╗');
    console.error('║                    🛑 HARD STOP                              ║');
    console.error('╠══════════════════════════════════════════════════════════════╣');
    console.error('║ Promotion BLOCKED due to test violations:                    ║');
    for (const v of violations) {
      console.error(`║  • ${v.padEnd(56)}║`);
    }
    console.error('╠══════════════════════════════════════════════════════════════╣');
    console.error('║ Human review required. Contact: #testing-alerts              ║');
    console.error('╚══════════════════════════════════════════════════════════════╝');

    process.exit(1);
  }
}
```

## Next: Test Data SOT & Helpers

See:

- [test-data-sot.md](./test-data-sot.md) - Source of Truth for test data
- [test-helpers.md](./test-helpers.md) - Shared helper library
- [promotion-gates.md](./promotion-gates.md) - Promotion workflow
