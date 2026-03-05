# End-to-End Testing Reference

E2E testing guidelines for projects that choose to implement them. Tests are not required for deployment — but if they exist, they must pass (no flaky tests, no skipped tests in promotion).

## Core Principles

1. **Critical journeys require e2e tests** - Authentication, payment, core workflows
2. **True e2e testing** - Real browser, real user simulation, real data entry
3. **DevOps mindset** - See a problem, fix it, regardless of who created it
4. **Zero tolerance for flaky tests** - No flaky tests, no skipped tests in promotion

## Three-Layer Testing Model

| Layer | Environment | Test Requirements | Promotion Rule |
|-------|-------------|-------------------|----------------|
| **DEV** | Local or remote | Unit + Integration | Quick deploy allowed |
| **PROD** | Remote | Full e2e + smoke | Human approval required |

### DEV Layer

- Unit tests must pass
- Integration tests must pass
- Quick iteration allowed
- Errors/skips permitted (for active development)
- **Cannot promote to PROD with any failing tests**

### PROD Layer

- Full e2e suite for critical user journeys
- Smoke test validates critical routes
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
└── data/                            # Source of Truth
    ├── users.yaml
    ├── projects.yaml
    ├── billing.yaml
    └── index.ts                     # Exports typed test data
```

## Route Discovery (Recommended)

### Smoke Test: Route Discovery

Route discovery is a useful technique for validating that pages load without errors. It's recommended for projects with many routes but is not a hard gate:

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
      // Log uncovered routes for review — not a hard gate
      console.warn(`No e2e test for route: ${route.path}`);
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

Critical user journeys should have dedicated e2e tests that cover the full flow:

- **New user onboarding** - Registration through first meaningful action
- **Core workflow** - The primary thing users come to do
- **Payment/billing** - If applicable, test the money path end-to-end
- **Error recovery** - Critical error scenarios (payment failure, session expiry)

Organize journey tests separately from feature-level e2e tests:

```text
tests/e2e/
├── suites/          # Feature-level e2e tests
├── user-journeys/   # Full flow tests
└── smoke/           # Quick validation
```

Journey tests are typically longer and slower than feature tests. Run them in CI but prioritize them for pre-deploy gates.

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

      - name: Check route coverage
        run: |
          UNCOVERED=$(node scripts/check-route-coverage.js)
          if [ -n "$UNCOVERED" ]; then
            echo "::warning::Routes without e2e coverage: $UNCOVERED"
          fi

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

  // Log uncovered routes as informational (not a promotion blocker)
  const coverage = await checkRouteCoverage();
  if (coverage.uncovered.length > 0) {
    console.warn(`${coverage.uncovered.length} routes without e2e tests — review recommended`);
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
