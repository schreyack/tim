# Test Data Source of Truth (SOT)

All test data is defined in a central location. No hardcoding. No duplication. Single source of truth.

## Core Principles

1. **Single Source** - All test data in `tests/data/` directory
2. **YAML Recommended** - YAML is preferred for human readability and reviewability. Factories, builders, and inline data are also fine where they make more sense (e.g., complex object graphs, programmatic generation)
3. **No Hardcoding** - Tests import data, never define it inline (credentials especially)
4. **Type Safety** - Test data exported as typed objects
5. **Environment Aware** - Data can vary by environment
6. **Traceable** - All test data tagged with test UUID

## Directory Structure

```text
tests/
└── data/
    ├── index.ts                    # Main export (typed)
    ├── schema.ts                   # TypeScript interfaces
    │
    ├── users/
    │   ├── users.yaml              # User test data
    │   ├── roles.yaml              # Role definitions
    │   └── permissions.yaml        # Permission sets
    │
    ├── entities/                   # Domain entities
    │   ├── projects.yaml
    │   ├── items.yaml
    │   ├── orders.yaml
    │   └── invoices.yaml
    │
    ├── forms/                      # Form input data
    │   ├── registration.yaml
    │   ├── checkout.yaml
    │   └── settings.yaml
    │
    ├── api/                        # API test payloads
    │   ├── requests.yaml
    │   └── responses.yaml
    │
    ├── journeys/                   # User journey definitions
    │   ├── new-user-onboarding.yaml
    │   └── admin-workflow.yaml
    │
    └── environments/               # Environment-specific overrides
        ├── dev.yaml
        └── prod.yaml
```

## YAML Data Format

### User Data Example

```yaml
# tests/data/users/users.yaml
users:
  # Standard test user
  standard:
    email: "test.user@example.com"
    password: "TestPassword123!"
    firstName: "Test"
    lastName: "User"
    role: "user"

  # Admin user
  admin:
    email: "admin@example.com"
    password: "AdminPassword123!"
    firstName: "Admin"
    lastName: "User"
    role: "admin"

  # User for registration tests (will be created)
  new_user:
    email: "new.user.{{uuid}}@example.com"  # UUID placeholder
    password: "NewUserPassword123!"
    firstName: "New"
    lastName: "User"
    role: "user"

  # Invalid data for validation tests
  invalid:
    empty_email:
      email: ""
      password: "ValidPassword123!"

    weak_password:
      email: "test@example.com"
      password: "123"  # Too weak

    invalid_email:
      email: "not-an-email"
      password: "ValidPassword123!"
```

### Entity Data Example

```yaml
# tests/data/entities/projects.yaml
projects:
  # Project that exists in seeded data
  existing:
    id: "proj_test_001"
    name: "Test Project"
    description: "A project for testing"
    status: "active"

  # Project to be created by tests
  new_project:
    name: "New Project {{uuid}}"
    description: "Created by test {{testId}}"
    status: "draft"

  # Project for edge case testing
  edge_cases:
    max_length_name:
      name: "A" * 255  # Maximum length
      description: "Testing max length"

    unicode_name:
      name: "项目テスト 🚀"
      description: "Unicode characters"

    special_chars:
      name: "Project <script>alert('xss')</script>"
      description: "XSS attempt"
```

### Form Input Data

```yaml
# tests/data/forms/registration.yaml
registration:
  valid:
    email: "{{uuid}}@example.com"
    password: "ValidPassword123!"
    confirmPassword: "ValidPassword123!"
    firstName: "Test"
    lastName: "User"
    agreeToTerms: true

  validation_errors:
    password_mismatch:
      email: "test@example.com"
      password: "Password123!"
      confirmPassword: "DifferentPassword123!"
      expectedError: "Passwords do not match"

    terms_not_accepted:
      email: "test@example.com"
      password: "Password123!"
      confirmPassword: "Password123!"
      agreeToTerms: false
      expectedError: "You must accept the terms"
```

## TypeScript Export

### Schema Definition

```typescript
// tests/data/schema.ts

export interface TestUser {
  email: string;
  password: string;
  firstName: string;
  lastName: string;
  role: 'user' | 'admin' | 'moderator';
}

export interface TestProject {
  id?: string;
  name: string;
  description: string;
  status: 'draft' | 'active' | 'archived';
}

export interface FormData<T> {
  valid: T;
  validation_errors: Record<string, T & { expectedError: string }>;
}

export interface TestData {
  users: {
    standard: TestUser;
    admin: TestUser;
    new_user: TestUser;
    invalid: Record<string, Partial<TestUser>>;
  };
  projects: {
    existing: TestProject;
    new_project: TestProject;
    edge_cases: Record<string, TestProject>;
  };
  forms: {
    registration: FormData<RegistrationForm>;
    checkout: FormData<CheckoutForm>;
  };
}
```

### Main Export

```typescript
// tests/data/index.ts
import { load } from 'js-yaml';
import { readFileSync } from 'fs';
import { join } from 'path';
import { TestData } from './schema';
import { generateTestId, interpolateUuid } from '../helpers/utils/test-id';

const DATA_DIR = __dirname;

function loadYaml<T>(path: string): T {
  const content = readFileSync(join(DATA_DIR, path), 'utf-8');
  return load(content) as T;
}

// Generate a unique test ID for this test run
const testRunId = generateTestId();

function processData<T>(data: T, testId: string): T {
  const str = JSON.stringify(data);
  const processed = str
    .replace(/\{\{uuid\}\}/g, () => crypto.randomUUID())
    .replace(/\{\{testId\}\}/g, testId)
    .replace(/\{\{timestamp\}\}/g, Date.now().toString());
  return JSON.parse(processed);
}

// Load all YAML files
const rawData = {
  users: loadYaml('users/users.yaml'),
  projects: loadYaml('entities/projects.yaml'),
  forms: {
    registration: loadYaml('forms/registration.yaml'),
  },
};

// Export processed data with unique IDs per test run
export function getTestData(testId?: string): TestData {
  const id = testId || testRunId;
  return processData(rawData, id) as TestData;
}

// Convenience exports
export const testData = getTestData();
export { testRunId };
```

### Usage in Tests

```typescript
// tests/e2e/auth/registration.spec.ts
import { test, expect } from '@playwright/test';
import { getTestData } from '../../data';
import { generateTestId } from '../../helpers/utils/test-id';
import { registerUser, deleteUser } from '../../helpers/actions/auth';
import { cleanup } from '../../helpers/utils/cleanup';

test.describe('User Registration', () => {
  let testId: string;
  let testData: ReturnType<typeof getTestData>;

  test.beforeEach(() => {
    testId = generateTestId();
    testData = getTestData(testId);
  });

  test.afterEach(async () => {
    // Cleanup all data created by this test
    await cleanup.byTestId(testId);
  });

  test('successful registration with valid data', async ({ page }) => {
    const userData = testData.users.new_user;

    await registerUser(page, userData);

    await expect(page).toHaveURL('/dashboard');
    await expect(page.locator('[data-testid="welcome"]')).toContainText(userData.firstName);
  });

  test('shows error for password mismatch', async ({ page }) => {
    const formData = testData.forms.registration.validation_errors.password_mismatch;

    await page.goto('/register');
    await page.fill('[data-testid="email"]', formData.email);
    await page.fill('[data-testid="password"]', formData.password);
    await page.fill('[data-testid="confirm-password"]', formData.confirmPassword);
    await page.click('[data-testid="submit"]');

    await expect(page.locator('.error-message')).toContainText(formData.expectedError);
  });
});
```

## Test ID and Traceability

### Test ID Generation

Every test gets a unique UUID that marks all data it creates:

```typescript
// tests/helpers/utils/test-id.ts
import { randomUUID } from 'crypto';

// Format: TEST_<timestamp>_<uuid>
export function generateTestId(): string {
  const timestamp = Date.now();
  const uuid = randomUUID().slice(0, 8);
  return `TEST_${timestamp}_${uuid}`;
}

// Extract timestamp from test ID
export function getTestIdTimestamp(testId: string): number {
  const match = testId.match(/TEST_(\d+)_/);
  return match ? parseInt(match[1], 10) : 0;
}

// Check if a value looks like test data
export function isTestData(value: string): boolean {
  return value.includes('TEST_') || value.includes('@example.com');
}
```

### Marking Created Data

When tests create data, they embed the test ID:

```typescript
// Creating a user
const user = await createUser({
  email: `test_${testId}@example.com`,
  firstName: `TestUser_${testId}`,
  // or use metadata if available
  metadata: { testId },
});

// Creating a project
const project = await createProject({
  name: `Test Project ${testId}`,
  description: `Created by test ${testId} at ${new Date().toISOString()}`,
});
```

### Cleanup by Test ID

```typescript
// tests/helpers/utils/cleanup.ts
import { db } from './database';

export const cleanup = {
  // Clean up all data created by a specific test
  async byTestId(testId: string): Promise<CleanupResult> {
    const result: CleanupResult = {
      testId,
      deleted: [],
      errors: [],
    };

    try {
      // Order matters: delete in reverse dependency order

      // 1. Delete invoices with test ID in metadata
      const invoices = await db.invoice.deleteMany({
        where: { OR: [
          { metadata: { path: ['testId'], equals: testId } },
          { description: { contains: testId } },
        ]},
      });
      result.deleted.push({ type: 'invoices', count: invoices.count });

      // 2. Delete orders
      const orders = await db.order.deleteMany({
        where: { description: { contains: testId } },
      });
      result.deleted.push({ type: 'orders', count: orders.count });

      // 3. Delete projects
      const projects = await db.project.deleteMany({
        where: { OR: [
          { name: { contains: testId } },
          { description: { contains: testId } },
        ]},
      });
      result.deleted.push({ type: 'projects', count: projects.count });

      // 4. Delete users
      const users = await db.user.deleteMany({
        where: { OR: [
          { email: { contains: testId } },
          { firstName: { contains: testId } },
        ]},
      });
      result.deleted.push({ type: 'users', count: users.count });

    } catch (error) {
      result.errors.push({
        message: error.message,
        stack: error.stack,
      });
    }

    return result;
  },

  // Clean up stale test data (older than X hours)
  async staleData(maxAgeHours: number = 24): Promise<CleanupResult> {
    const cutoff = Date.now() - (maxAgeHours * 60 * 60 * 1000);

    // Find all test IDs older than cutoff
    const staleIds = await db.user.findMany({
      where: {
        email: { contains: 'TEST_' },
        createdAt: { lt: new Date(cutoff) },
      },
      select: { email: true },
    });

    // Extract test IDs and clean up
    for (const { email } of staleIds) {
      const testId = email.match(/TEST_\d+_[a-f0-9]+/)?.[0];
      if (testId) {
        await this.byTestId(testId);
      }
    }

    return { /* results */ };
  },

  // Verify no test data leaked
  async verifyClean(): Promise<VerifyResult> {
    const leaks = {
      users: await db.user.count({ where: { email: { contains: 'TEST_' } } }),
      projects: await db.project.count({ where: { name: { contains: 'TEST_' } } }),
      // ... etc
    };

    const hasLeaks = Object.values(leaks).some(count => count > 0);

    if (hasLeaks) {
      console.warn('⚠️  Test data leak detected:', leaks);
    }

    return { clean: !hasLeaks, leaks };
  },
};
```

## Idempotency Requirements

### Every Test Must Be Idempotent

```typescript
test.describe('Idempotent Test', () => {
  let testId: string;

  test.beforeEach(async () => {
    testId = generateTestId();

    // NEVER assume data exists
    // ALWAYS create what you need
  });

  test.afterEach(async () => {
    // ALWAYS clean up what you created
    await cleanup.byTestId(testId);
  });

  test('can run multiple times without interference', async ({ page }) => {
    // Create fresh data for this run
    const user = await createUser({ testId });
    const project = await createProject({ testId, ownerId: user.id });

    // Run test logic
    await page.goto(`/projects/${project.id}`);
    // ...assertions...

    // Cleanup happens in afterEach
  });
});
```

### Pre-flight Check

Before each test run, verify clean state:

```typescript
// tests/setup.ts
import { cleanup } from './helpers/utils/cleanup';

async function globalSetup() {
  // Verify no leaked test data from previous runs
  const result = await cleanup.verifyClean();

  if (!result.clean) {
    console.warn('Cleaning up stale test data...');
    await cleanup.staleData(24);  // Clean data older than 24 hours
  }
}

export default globalSetup;
```

## Environment-Specific Data

```yaml
# tests/data/environments/prod.yaml
overrides:
  api_base_url: "https://prod.example.com/api"
  timeout_ms: 30000

  users:
    admin:
      email: "prod-admin@example.com"
      # Password from secrets manager, not in YAML
```

```typescript
// tests/data/index.ts
const environment = process.env.TEST_ENVIRONMENT || 'dev';

function loadEnvironmentOverrides(): Partial<TestData> {
  try {
    return loadYaml(`environments/${environment}.yaml`);
  } catch {
    return {};
  }
}

export function getTestData(testId?: string): TestData {
  const base = processData(rawData, testId || testRunId);
  const overrides = loadEnvironmentOverrides();
  return deepMerge(base, overrides);
}
```

## Enforcement

### No Hardcoding Rule

Linter rule to catch hardcoded test data:

```javascript
// eslint-plugin-tim/no-hardcoded-test-data.js
module.exports = {
  create(context) {
    return {
      Literal(node) {
        if (context.getFilename().includes('/tests/')) {
          const value = node.value;

          // Check for hardcoded emails
          if (typeof value === 'string' && value.match(/@.*\.(com|org|net)/)) {
            if (!value.includes('example.com') && !value.includes('{{')) {
              context.report({
                node,
                message: 'Hardcoded email in test. Use test data from SOT.',
              });
            }
          }

          // Check for hardcoded passwords
          if (typeof value === 'string' && value.match(/password/i)) {
            context.report({
              node,
              message: 'Hardcoded password in test. Use test data from SOT.',
            });
          }
        }
      },
    };
  },
};
```

### CI Check

```yaml
# In CI pipeline
- name: Check for hardcoded test data
  run: |
    # Find any test files with hardcoded credentials
    grep -r "email.*@" tests/ --include="*.spec.ts" | grep -v "example.com" | grep -v "{{" && exit 1 || true
    grep -r "password.*=" tests/ --include="*.spec.ts" | grep -v "testData\." | grep -v "import" && exit 1 || true
```

## Hard Requirements Summary

| Requirement | Enforcement | Gate |
|-------------|-------------|------|
| No hardcoded credentials | ESLint rule + CI grep check | Gate 1 + Gate 2 |
| Test ID traceability | Required in all created data | Code review |
| Cleanup after tests | afterEach hook required | Code review |
