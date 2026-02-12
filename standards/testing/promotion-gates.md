# Promotion Gates

Code promotion through environments is controlled by automated testing gates. No code moves without passing tests. Human approval required for production only.

## Promotion Flow

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PROMOTION PIPELINE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  DEV                           UAT                          PROD             │
│  ┌──────────────┐             ┌──────────────┐             ┌──────────────┐ │
│  │ • Unit tests │             │ • Full e2e   │             │ • Full e2e   │ │
│  │ • Integration│   AUTO      │ • Smoke test │   HUMAN     │ • Smoke test │ │
│  │ • Quick      │ ─────────►  │ • Route      │ ─────────►  │ • All routes │ │
│  │   iteration  │  IF PASS    │   coverage   │  APPROVAL   │ • Zero bugs  │ │
│  │ • Errors OK  │             │ • No skips   │  REQUIRED   │ • No errors  │ │
│  └──────────────┘             └──────────────┘             └──────────────┘ │
│                                                                              │
│  Errors/skips                  HARD STOP                    HARD STOP        │
│  allowed here                  on any failure               on any failure   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Gate 1: DEV → UAT

### Trigger

- Developer initiates promotion
- Or: Automatic on merge to `develop` branch

### Requirements

| Check | Requirement | Enforcement |
|-------|-------------|-------------|
| Unit tests | All pass | CI gate |
| Integration tests | All pass | CI gate |
| Linting | Zero errors | CI gate |
| Type checking | Zero errors | CI gate |
| Build | Successful | CI gate |

### What's NOT Required at DEV

- E2E tests (encouraged, not required)
- Full route coverage
- Zero console warnings

### Automation

```yaml
# .github/workflows/dev-to-uat.yml
name: DEV to UAT Promotion

on:
  push:
    branches: [develop]
  workflow_dispatch:

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run unit tests
        run: npm run test:unit
        env:
          CI: true

  integration-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: test
        ports:
          - 5432:5432
    steps:
      - uses: actions/checkout@v4
      - name: Run integration tests
        run: npm run test:integration

  promote:
    needs: [unit-tests, integration-tests]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy to UAT
        run: ./ops.sh deploy --environment uat --confirm
        env:
          SSH_PRIVATE_KEY: ${{ secrets.UAT_SSH_KEY }}

      - name: Notify
        run: |
          curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
            -d '{"text":"✅ Promoted to UAT: ${{ github.sha }}"}'
```

## Gate 2: UAT → PROD

### Trigger

- Manual workflow dispatch only
- Requires passing all UAT tests first

### Requirements (STRICT)

| Check | Requirement | Enforcement |
|-------|-------------|-------------|
| All DEV checks | Pass | CI gate |
| Full e2e suite | All pass | CI gate, HARD STOP |
| Smoke test | All routes clean | CI gate, HARD STOP |
| Route coverage | 100% | CI gate, HARD STOP |
| Skipped tests | Zero | CI gate, HARD STOP |
| Flaky tests | Zero | CI gate, HARD STOP |
| Console errors | Zero | CI gate, HARD STOP |
| Human approval | Required | GitHub environment protection |

### Hard Stop Conditions

Any of these triggers immediate HARD STOP:

1. **Any test failure** - No exceptions
2. **Any skipped test** - Must be fixed or removed
3. **Any flaky test** - Must be fixed (no retries)
4. **Uncovered route** - Must have e2e test
5. **Console errors** - Must be fixed
6. **Bypass attempt** - Alerts security team

### Automation

```yaml
# .github/workflows/uat-to-prod.yml
name: UAT to PROD Promotion

on:
  workflow_dispatch:
    inputs:
      confirmation:
        description: 'Type "PROMOTE TO PRODUCTION" to confirm'
        required: true
      reason:
        description: 'Reason for production deployment'
        required: true

jobs:
  validate-input:
    runs-on: ubuntu-latest
    steps:
      - name: Validate confirmation
        if: inputs.confirmation != 'PROMOTE TO PRODUCTION'
        run: |
          echo "::error::Invalid confirmation. Must type exactly: PROMOTE TO PRODUCTION"
          exit 1

  full-e2e-suite:
    needs: validate-input
    runs-on: ubuntu-latest
    env:
      PROMOTION_MODE: 'true'
      TEST_ENVIRONMENT: 'uat'
    steps:
      - uses: actions/checkout@v4

      - name: Setup
        run: npm ci

      - name: Run full e2e suite
        run: |
          npm run test:e2e:full -- \
            --reporter=json \
            --reporter=html \
            --output=test-results/
        timeout-minutes: 60

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: e2e-results
          path: test-results/

  smoke-test:
    needs: validate-input
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run smoke test
        run: npm run test:smoke
        env:
          PROMOTION_MODE: 'true'

  route-coverage:
    needs: validate-input
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check route coverage
        run: |
          npm run test:coverage-check

          UNCOVERED=$(cat test-results/uncovered-routes.json)
          if [ "$UNCOVERED" != "[]" ]; then
            echo "::error::Routes without e2e coverage: $UNCOVERED"
            exit 1
          fi

  validate-results:
    needs: [full-e2e-suite, smoke-test, route-coverage]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: e2e-results

      - name: Check for skipped tests
        run: |
          SKIPPED=$(jq '[.suites[].specs[] | select(.status == "skipped")] | length' results.json)
          if [ "$SKIPPED" -gt 0 ]; then
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║                    🛑 HARD STOP                              ║"
            echo "╠══════════════════════════════════════════════════════════════╣"
            echo "║  $SKIPPED test(s) were skipped.                              ║"
            echo "║  Promotion BLOCKED.                                          ║"
            echo "║  Fix or remove skipped tests before promoting.              ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            exit 1
          fi

      - name: Check for failures
        run: |
          FAILED=$(jq '[.suites[].specs[] | select(.status == "failed")] | length' results.json)
          if [ "$FAILED" -gt 0 ]; then
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║                    🛑 HARD STOP                              ║"
            echo "╠══════════════════════════════════════════════════════════════╣"
            echo "║  $FAILED test(s) failed.                                     ║"
            echo "║  Promotion BLOCKED.                                          ║"
            echo "║  All tests must pass before promoting.                      ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            exit 1
          fi

      - name: Check for flaky tests
        run: |
          FLAKY=$(jq '[.suites[].specs[] | select(.retries > 0)] | length' results.json)
          if [ "$FLAKY" -gt 0 ]; then
            echo "╔══════════════════════════════════════════════════════════════╗"
            echo "║                    🛑 HARD STOP                              ║"
            echo "╠══════════════════════════════════════════════════════════════╣"
            echo "║  $FLAKY flaky test(s) detected.                              ║"
            echo "║  Promotion BLOCKED.                                          ║"
            echo "║  Flaky tests must be fixed, not retried.                    ║"
            echo "╚══════════════════════════════════════════════════════════════╝"
            exit 1
          fi

  human-approval:
    needs: validate-results
    runs-on: ubuntu-latest
    environment: production  # GitHub environment with required reviewers
    steps:
      - name: Waiting for approval
        run: echo "Deployment approved by ${{ github.actor }}"

  deploy-production:
    needs: human-approval
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy to production
        run: |
          ./ops.sh deploy --environment prod --confirm
        env:
          SSH_PRIVATE_KEY: ${{ secrets.PROD_SSH_KEY }}

      - name: Post-deploy verification
        run: |
          # Run smoke test against production
          npm run test:smoke -- --base-url=$PROD_URL

      - name: Notify success
        run: |
          curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
            -d '{
              "text":"🚀 Deployed to PRODUCTION",
              "attachments":[{
                "fields":[
                  {"title":"Commit","value":"${{ github.sha }}","short":true},
                  {"title":"Approved by","value":"${{ github.actor }}","short":true},
                  {"title":"Reason","value":"${{ inputs.reason }}","short":false}
                ]
              }]
            }'
```

## Human Approval Process

### GitHub Environment Protection

Configure the `production` environment:

1. Go to Repository Settings → Environments
2. Create `production` environment
3. Add required reviewers (minimum 2)
4. Enable "Require approval before deployment"
5. Optional: Add deployment branch rules

### Approval Requirements

- Minimum 2 reviewers for production
- Reviewers must be from `@org/senior-devs` team
- Approval expires after 1 hour
- Cannot self-approve

### Audit Trail

All promotions logged:

```json
{
  "promotion_id": "promo_20250115_abc123",
  "from_environment": "uat",
  "to_environment": "prod",
  "triggered_by": "tim",
  "approved_by": ["alice", "bob"],
  "commit": "abc123def456",
  "reason": "Release 2.1.0 - New billing feature",
  "timestamp": "2025-01-15T14:30:00Z",
  "test_results": {
    "total": 450,
    "passed": 450,
    "failed": 0,
    "skipped": 0,
    "duration_ms": 342000
  }
}
```

## Bypass Prevention

### System-Level Enforcement

Bypasses are prevented at the system level, not relying on developer honor:

1. **Branch protection** - Cannot push directly to main/production
2. **Required checks** - CI must pass before merge
3. **Environment protection** - Human approval required for prod
4. **SSH restrictions** - ops.sh is the only way to deploy
5. **Immutable config** - ops-config.yaml is locked

### Attempted Bypass Handling

If someone attempts to bypass:

```typescript
// In ops.sh or deployment script
async function detectBypassAttempt(): Promise<boolean> {
  // Check if tests were actually run
  const testResults = await fetchTestResults();
  if (!testResults || testResults.total === 0) {
    await alertBypassAttempt('No tests were run');
    return true;
  }

  // Check if running without PROMOTION_MODE
  if (process.env.PROMOTION_MODE !== 'true') {
    await alertBypassAttempt('PROMOTION_MODE not set');
    return true;
  }

  // Check if test results were modified
  const resultsHash = await hashTestResults();
  const expectedHash = await fetchExpectedHash();
  if (resultsHash !== expectedHash) {
    await alertBypassAttempt('Test results appear to be tampered');
    return true;
  }

  return false;
}

async function alertBypassAttempt(reason: string): Promise<void> {
  // Immediate alert to security channel
  await sendAlert({
    channel: '#security-alerts',
    message: `🚨 BYPASS ATTEMPT DETECTED\n\nReason: ${reason}\nUser: ${process.env.USER}\nTime: ${new Date().toISOString()}`,
    severity: 'critical',
    mentions: ['@security-team'],
  });

  // Log for audit
  await auditLog({
    event: 'bypass_attempt',
    reason,
    user: process.env.USER,
    timestamp: new Date(),
  });

  // Hard stop
  console.error('╔══════════════════════════════════════════════════════════════╗');
  console.error('║              🚨 BYPASS ATTEMPT DETECTED                       ║');
  console.error('╠══════════════════════════════════════════════════════════════╣');
  console.error('║  Deployment BLOCKED.                                         ║');
  console.error('║  Security team has been notified.                           ║');
  console.error('║  This incident has been logged.                             ║');
  console.error('╚══════════════════════════════════════════════════════════════╝');

  process.exit(99);  // Special exit code for bypass attempts
}
```

## Changed-Area Testing

When promoting code that touches specific areas:

### Detecting Changed Areas

```typescript
// scripts/detect-changed-areas.ts
import { execSync } from 'child_process';

export async function getChangedAreas(): Promise<TestScope> {
  // Get changed files since last deployment
  const lastDeploy = getLastDeployCommit();
  const changedFiles = execSync(`git diff --name-only ${lastDeploy}..HEAD`)
    .toString()
    .split('\n')
    .filter(Boolean);

  // Map files to test suites
  const changedSuites = new Set<string>();

  for (const file of changedFiles) {
    if (file.startsWith('src/auth/')) changedSuites.add('auth');
    if (file.startsWith('src/billing/')) changedSuites.add('billing');
    if (file.startsWith('src/projects/')) changedSuites.add('projects');
    // ... etc
  }

  return {
    // Changed areas get rigorous testing (all paths)
    rigorous: Array.from(changedSuites),
    // Unchanged areas get standard testing (smoke + happy path)
    standard: getAllSuites().filter(s => !changedSuites.has(s)),
  };
}
```

### Running Appropriate Tests

```typescript
// In test runner
async function runPromotionTests(): Promise<TestResults> {
  const scope = await getChangedAreas();

  // Always run smoke test first
  await runSuite('smoke');

  // Run rigorous tests on changed areas
  for (const suite of scope.rigorous) {
    await runSuite(suite, { mode: 'rigorous' });  // All paths
  }

  // Run standard tests on unchanged areas
  for (const suite of scope.standard) {
    await runSuite(suite, { mode: 'standard' });  // Happy path only
  }

  // Before prod: run FULL suite regardless
  if (process.env.TARGET_ENV === 'prod') {
    await runSuite('full', { mode: 'rigorous' });
  }
}
```

## Exception Handling

### Only Humans Can Approve Exceptions

```yaml
# .github/workflows/test-exception.yml
name: Request Test Exception

on:
  issues:
    types: [labeled]

jobs:
  process-exception:
    if: contains(github.event.label.name, 'test-exception')
    runs-on: ubuntu-latest
    steps:
      - name: Validate requester
        run: |
          if [[ ! " @org/senior-devs " =~ " ${{ github.actor }} " ]]; then
            echo "::error::Only senior devs can request test exceptions"
            exit 1
          fi

      - name: Require approval
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              body: `## Test Exception Request

              **Requester:** ${{ github.actor }}
              **Date:** ${new Date().toISOString()}

              ⚠️ This exception requires approval from 2 members of @org/tech-leads

              To approve, comment: \`/approve-exception\`
              To reject, comment: \`/reject-exception\`
              `
            })
```

### Tracking Exceptions

```yaml
# tests/exceptions/EXCEPTIONS.yaml
# All active test exceptions - human reviewed and approved

exceptions:
  - id: "EXC-2025-001"
    test: "tests/e2e/legacy/old-feature.spec.ts"
    reason: "Feature deprecated, will be removed in v3.0"
    approved_by: "alice@example.com"
    approved_date: "2025-01-15"
    expires: "2025-03-01"
    ticket: "JIRA-1234"

  - id: "EXC-2025-002"
    test: "tests/e2e/third-party/flaky-api.spec.ts"
    reason: "Third-party API unreliable, monitoring separately"
    approved_by: "bob@example.com"
    approved_date: "2025-01-10"
    expires: "2025-02-10"
    ticket: "JIRA-1235"
    # Must have alternative monitoring
    alternative_monitoring: "https://status.thirdparty.com"
```

Exceptions are:

- Human-approved only
- Time-limited (must expire)
- Tracked in version control
- Reviewed monthly
- Removed when resolved or expired
