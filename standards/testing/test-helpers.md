# Test Helpers Library

All common testing functionality is centralized in a helpers library. No code duplication. Small, discrete, reusable functions.

## Core Principles

1. **No Duplication** - If two tests need the same logic, it's a helper
2. **Small & Discrete** - Each helper does one thing well
3. **Reusable** - Helpers work across all test types
4. **Documented** - Every helper has JSDoc/docstring
5. **Typed** - Full TypeScript types for all helpers

## Directory Structure

```
tests/
└── helpers/
    ├── index.ts                 # Main export
    │
    ├── actions/                 # UI interaction helpers
    │   ├── index.ts
    │   ├── auth.ts             # Login, logout, register
    │   ├── navigation.ts       # Page navigation
    │   ├── forms.ts            # Form filling
    │   ├── tables.ts           # Table interactions
    │   ├── modals.ts           # Modal handling
    │   └── uploads.ts          # File uploads
    │
    ├── assertions/             # Custom assertions
    │   ├── index.ts
    │   ├── visual.ts           # Visual assertions
    │   ├── data.ts             # Data assertions
    │   ├── api.ts              # API response assertions
    │   └── accessibility.ts    # a11y assertions
    │
    ├── fixtures/               # Data creation helpers
    │   ├── index.ts
    │   ├── user.fixture.ts
    │   ├── project.fixture.ts
    │   ├── order.fixture.ts
    │   └── factory.ts          # Generic factory
    │
    ├── utils/                  # General utilities
    │   ├── index.ts
    │   ├── test-id.ts          # Test ID generation
    │   ├── cleanup.ts          # Data cleanup
    │   ├── wait.ts             # Timing utilities
    │   ├── retry.ts            # Retry logic
    │   └── random.ts           # Random data generation
    │
    ├── api/                    # API interaction helpers
    │   ├── index.ts
    │   ├── client.ts           # API client
    │   ├── auth.ts             # Auth tokens
    │   └── requests.ts         # Common requests
    │
    └── mocks/                  # Mocking utilities
        ├── index.ts
        ├── api.ts              # API mocks
        ├── time.ts             # Time mocks
        └── storage.ts          # Storage mocks
```

## Action Helpers

### Authentication Actions

```typescript
// helpers/actions/auth.ts
import { Page, expect } from '@playwright/test';
import { testData } from '../../data';

/**
 * Log in a user through the UI
 * @param page - Playwright page
 * @param user - User credentials (defaults to standard test user)
 */
export async function login(
  page: Page,
  user: { email: string; password: string } = testData.users.standard
): Promise<void> {
  await page.goto('/login');
  await page.fill('[data-testid="email"]', user.email);
  await page.fill('[data-testid="password"]', user.password);
  await page.click('[data-testid="submit"]');
  await expect(page).toHaveURL(/\/(dashboard|home)/);
}

/**
 * Log out the current user
 * @param page - Playwright page
 */
export async function logout(page: Page): Promise<void> {
  await page.click('[data-testid="user-menu"]');
  await page.click('[data-testid="logout"]');
  await expect(page).toHaveURL('/');
}

/**
 * Register a new user through the UI
 * @param page - Playwright page
 * @param userData - User data to register
 * @returns The registered user's email
 */
export async function register(
  page: Page,
  userData: {
    email: string;
    password: string;
    firstName?: string;
    lastName?: string;
  }
): Promise<string> {
  await page.goto('/register');
  await page.fill('[data-testid="email"]', userData.email);
  await page.fill('[data-testid="password"]', userData.password);
  await page.fill('[data-testid="confirm-password"]', userData.password);

  if (userData.firstName) {
    await page.fill('[data-testid="first-name"]', userData.firstName);
  }
  if (userData.lastName) {
    await page.fill('[data-testid="last-name"]', userData.lastName);
  }

  await page.click('[data-testid="submit"]');
  await expect(page).toHaveURL(/\/(dashboard|onboarding)/);

  return userData.email;
}

/**
 * Login as admin user
 * @param page - Playwright page
 */
export async function loginAsAdmin(page: Page): Promise<void> {
  await login(page, testData.users.admin);
}
```

### Form Actions

```typescript
// helpers/actions/forms.ts
import { Page, Locator } from '@playwright/test';

/**
 * Fill a form with data
 * @param page - Playwright page
 * @param formSelector - Form selector
 * @param data - Key-value pairs of field name to value
 */
export async function fillForm(
  page: Page,
  formSelector: string,
  data: Record<string, string | boolean | number>
): Promise<void> {
  const form = page.locator(formSelector);

  for (const [field, value] of Object.entries(data)) {
    const input = form.locator(`[data-testid="${field}"], [name="${field}"]`);
    const tagName = await input.evaluate(el => el.tagName.toLowerCase());
    const inputType = await input.getAttribute('type');

    if (tagName === 'select') {
      await input.selectOption(String(value));
    } else if (inputType === 'checkbox' || inputType === 'radio') {
      if (value) {
        await input.check();
      } else {
        await input.uncheck();
      }
    } else {
      await input.fill(String(value));
    }
  }
}

/**
 * Submit a form and wait for navigation or response
 * @param page - Playwright page
 * @param submitSelector - Submit button selector
 * @param waitFor - What to wait for after submit
 */
export async function submitForm(
  page: Page,
  submitSelector: string = '[type="submit"]',
  waitFor: 'navigation' | 'networkidle' = 'navigation'
): Promise<void> {
  const submitButton = page.locator(submitSelector);

  if (waitFor === 'navigation') {
    await Promise.all([
      page.waitForNavigation(),
      submitButton.click(),
    ]);
  } else {
    await submitButton.click();
    await page.waitForLoadState('networkidle');
  }
}

/**
 * Fill and submit a form in one action
 * @param page - Playwright page
 * @param formSelector - Form selector
 * @param data - Form data
 */
export async function fillAndSubmitForm(
  page: Page,
  formSelector: string,
  data: Record<string, string | boolean | number>
): Promise<void> {
  await fillForm(page, formSelector, data);
  await submitForm(page, `${formSelector} [type="submit"]`);
}

/**
 * Clear all fields in a form
 * @param page - Playwright page
 * @param formSelector - Form selector
 */
export async function clearForm(page: Page, formSelector: string): Promise<void> {
  const inputs = page.locator(`${formSelector} input, ${formSelector} textarea`);
  const count = await inputs.count();

  for (let i = 0; i < count; i++) {
    await inputs.nth(i).clear();
  }
}
```

### Navigation Actions

```typescript
// helpers/actions/navigation.ts
import { Page, expect } from '@playwright/test';

/**
 * Navigate to a page and wait for it to load
 * @param page - Playwright page
 * @param path - URL path
 * @param options - Navigation options
 */
export async function goTo(
  page: Page,
  path: string,
  options: { waitFor?: 'load' | 'networkidle' | 'domcontentloaded' } = {}
): Promise<void> {
  await page.goto(path);
  await page.waitForLoadState(options.waitFor || 'load');
}

/**
 * Wait for a specific route to be active
 * @param page - Playwright page
 * @param routePattern - URL pattern to match
 * @param timeout - Max time to wait
 */
export async function waitForRoute(
  page: Page,
  routePattern: string | RegExp,
  timeout: number = 10000
): Promise<void> {
  await expect(page).toHaveURL(routePattern, { timeout });
}

/**
 * Navigate using sidebar/menu
 * @param page - Playwright page
 * @param menuItem - Menu item text or data-testid
 */
export async function navigateViaMenu(
  page: Page,
  menuItem: string
): Promise<void> {
  const menuLink = page.locator(
    `[data-testid="nav-${menuItem}"], nav >> text="${menuItem}"`
  );
  await menuLink.click();
  await page.waitForLoadState('networkidle');
}

/**
 * Go back in browser history
 * @param page - Playwright page
 */
export async function goBack(page: Page): Promise<void> {
  await page.goBack();
  await page.waitForLoadState('load');
}

/**
 * Refresh the current page
 * @param page - Playwright page
 */
export async function refresh(page: Page): Promise<void> {
  await page.reload();
  await page.waitForLoadState('load');
}
```

## Fixture Helpers

```typescript
// helpers/fixtures/user.fixture.ts
import { generateTestId } from '../utils/test-id';
import { testData } from '../../data';
import { apiClient } from '../api/client';

export interface CreatedUser {
  id: string;
  email: string;
  testId: string;
  cleanup: () => Promise<void>;
}

/**
 * Create a user via API for testing
 * @param testId - Test ID for traceability
 * @param overrides - Override default user data
 */
export async function createUser(
  testId: string,
  overrides: Partial<typeof testData.users.new_user> = {}
): Promise<CreatedUser> {
  const userData = {
    ...testData.users.new_user,
    ...overrides,
    email: `test_${testId}_${Date.now()}@example.com`,
    firstName: `TestUser_${testId}`,
  };

  const response = await apiClient.post('/api/users', userData);
  const user = response.data;

  return {
    id: user.id,
    email: userData.email,
    testId,
    cleanup: async () => {
      await apiClient.delete(`/api/users/${user.id}`);
    },
  };
}

/**
 * Create multiple users for testing
 * @param testId - Test ID for traceability
 * @param count - Number of users to create
 */
export async function createUsers(
  testId: string,
  count: number
): Promise<CreatedUser[]> {
  const users: CreatedUser[] = [];

  for (let i = 0; i < count; i++) {
    const user = await createUser(testId, {
      email: `test_${testId}_user${i}@example.com`,
    });
    users.push(user);
  }

  return users;
}
```

```typescript
// helpers/fixtures/factory.ts
import { generateTestId } from '../utils/test-id';

/**
 * Generic factory for creating test entities
 */
export class TestFactory<T> {
  private createFn: (testId: string, overrides?: Partial<T>) => Promise<T & { id: string }>;
  private deleteFn: (id: string) => Promise<void>;
  private created: Array<{ id: string; testId: string }> = [];

  constructor(
    createFn: (testId: string, overrides?: Partial<T>) => Promise<T & { id: string }>,
    deleteFn: (id: string) => Promise<void>
  ) {
    this.createFn = createFn;
    this.deleteFn = deleteFn;
  }

  async create(testId: string, overrides?: Partial<T>): Promise<T & { id: string }> {
    const entity = await this.createFn(testId, overrides);
    this.created.push({ id: entity.id, testId });
    return entity;
  }

  async createMany(testId: string, count: number, overrides?: Partial<T>): Promise<Array<T & { id: string }>> {
    const entities: Array<T & { id: string }> = [];
    for (let i = 0; i < count; i++) {
      entities.push(await this.create(testId, overrides));
    }
    return entities;
  }

  async cleanup(testId?: string): Promise<void> {
    const toDelete = testId
      ? this.created.filter(e => e.testId === testId)
      : this.created;

    for (const entity of toDelete.reverse()) {
      try {
        await this.deleteFn(entity.id);
      } catch (error) {
        console.warn(`Failed to delete entity ${entity.id}:`, error);
      }
    }

    this.created = testId
      ? this.created.filter(e => e.testId !== testId)
      : [];
  }
}
```

## Utility Helpers

```typescript
// helpers/utils/test-id.ts
import { randomUUID } from 'crypto';

/**
 * Generate a unique test ID for traceability
 * Format: TEST_<timestamp>_<short-uuid>
 */
export function generateTestId(): string {
  const timestamp = Date.now();
  const uuid = randomUUID().slice(0, 8);
  return `TEST_${timestamp}_${uuid}`;
}

/**
 * Extract timestamp from a test ID
 */
export function getTestIdTimestamp(testId: string): number | null {
  const match = testId.match(/TEST_(\d+)_/);
  return match ? parseInt(match[1], 10) : null;
}

/**
 * Check if a string contains test data markers
 */
export function isTestData(value: string): boolean {
  return /TEST_\d+_[a-f0-9]+/i.test(value) || value.includes('@example.com');
}

/**
 * Generate a test-safe email address
 */
export function generateTestEmail(testId: string): string {
  return `test_${testId}@example.com`;
}
```

```typescript
// helpers/utils/wait.ts
import { Page } from '@playwright/test';

/**
 * Wait for a specific amount of time
 * Note: Prefer page.waitFor* methods when possible
 */
export async function wait(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Wait for an element to be visible and stable
 */
export async function waitForStable(
  page: Page,
  selector: string,
  timeout: number = 5000
): Promise<void> {
  const element = page.locator(selector);
  await element.waitFor({ state: 'visible', timeout });

  // Wait for animations to complete
  await page.waitForFunction(
    (sel) => {
      const el = document.querySelector(sel);
      if (!el) return false;
      const rect = el.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    },
    selector,
    { timeout }
  );
}

/**
 * Wait for network requests to settle
 */
export async function waitForNetworkIdle(
  page: Page,
  timeout: number = 5000
): Promise<void> {
  await page.waitForLoadState('networkidle', { timeout });
}

/**
 * Wait for a toast/notification to appear and optionally dismiss
 */
export async function waitForToast(
  page: Page,
  options: { text?: string; dismiss?: boolean } = {}
): Promise<string> {
  const toast = page.locator('[data-testid="toast"], .toast, [role="alert"]');
  await toast.waitFor({ state: 'visible' });

  const text = await toast.textContent();

  if (options.text) {
    expect(text).toContain(options.text);
  }

  if (options.dismiss) {
    const closeButton = toast.locator('[data-testid="toast-close"], .toast-close');
    if (await closeButton.isVisible()) {
      await closeButton.click();
    }
  }

  return text || '';
}
```

```typescript
// helpers/utils/cleanup.ts
import { apiClient } from '../api/client';

interface CleanupResult {
  testId: string;
  deleted: Array<{ type: string; count: number }>;
  errors: Array<{ message: string }>;
}

export const cleanup = {
  /**
   * Clean up all data created by a specific test
   */
  async byTestId(testId: string): Promise<CleanupResult> {
    const result: CleanupResult = {
      testId,
      deleted: [],
      errors: [],
    };

    // Delete in reverse dependency order
    const entities = ['invoices', 'orders', 'projects', 'users'];

    for (const entity of entities) {
      try {
        const response = await apiClient.delete(`/api/test-cleanup/${entity}`, {
          params: { testId },
        });
        result.deleted.push({ type: entity, count: response.data.deleted });
      } catch (error: any) {
        result.errors.push({ message: `Failed to clean ${entity}: ${error.message}` });
      }
    }

    return result;
  },

  /**
   * Clean up stale test data older than specified hours
   */
  async staleData(maxAgeHours: number = 24): Promise<CleanupResult> {
    const cutoff = Date.now() - (maxAgeHours * 60 * 60 * 1000);

    const response = await apiClient.delete('/api/test-cleanup/stale', {
      params: { before: new Date(cutoff).toISOString() },
    });

    return response.data;
  },

  /**
   * Verify no test data remains in the database
   */
  async verifyClean(): Promise<{ clean: boolean; leaks: Record<string, number> }> {
    const response = await apiClient.get('/api/test-cleanup/verify');
    return response.data;
  },
};
```

## Main Export

```typescript
// helpers/index.ts

// Actions
export * from './actions/auth';
export * from './actions/navigation';
export * from './actions/forms';
export * from './actions/tables';
export * from './actions/modals';
export * from './actions/uploads';

// Assertions
export * from './assertions/visual';
export * from './assertions/data';
export * from './assertions/api';

// Fixtures
export * from './fixtures/user.fixture';
export * from './fixtures/project.fixture';
export * from './fixtures/factory';

// Utils
export * from './utils/test-id';
export * from './utils/cleanup';
export * from './utils/wait';
export * from './utils/retry';
export * from './utils/random';

// API
export * from './api/client';
export * from './api/auth';

// Mocks
export * from './mocks/api';
export * from './mocks/time';
```

## Usage Example

A test using helpers should look like this:

```typescript
// tests/e2e/projects/create-project.spec.ts
import { test, expect } from '@playwright/test';
import { getTestData } from '../../data';
import {
  generateTestId,
  login,
  goTo,
  fillAndSubmitForm,
  waitForToast,
  cleanup,
} from '../../helpers';
import { createUser } from '../../helpers/fixtures/user.fixture';

test.describe('Create Project', () => {
  let testId: string;
  let testData: ReturnType<typeof getTestData>;
  let user: Awaited<ReturnType<typeof createUser>>;

  test.beforeEach(async ({ page }) => {
    // Setup
    testId = generateTestId();
    testData = getTestData(testId);

    // Create test user
    user = await createUser(testId);

    // Login
    await login(page, { email: user.email, password: testData.users.new_user.password });
  });

  test.afterEach(async () => {
    // Cleanup - test owns all its data
    await user.cleanup();
    await cleanup.byTestId(testId);
  });

  test('creates project with valid data', async ({ page }) => {
    // Navigate
    await goTo(page, '/projects/new');

    // Fill form using helper
    await fillAndSubmitForm(page, '[data-testid="create-project-form"]', {
      name: testData.projects.new_project.name,
      description: testData.projects.new_project.description,
    });

    // Verify
    await waitForToast(page, { text: 'Project created' });
    await expect(page).toHaveURL(/\/projects\/\w+/);
  });
});
```

Note how the test:
- Imports everything from helpers
- Uses test data from SOT
- Creates its own data with testId
- Cleans up after itself
- Contains only test-specific logic
