/**
 * TIM Shared Testing Module
 *
 * Provides test utilities, factories, and assertion helpers for Node.js/Express testing.
 *
 * @example
 * import { createTestApp, assertResponseOk, UserFactory } from "@tim/lib/testing";
 *
 * const app = createTestApp();
 * const response = await request(app).get("/health");
 * assertResponseOk(response);
 */

import type { Application, Request, Response, NextFunction } from "express";
import type { Response as SupertestResponse } from "supertest";

/**
 * Create a test Express application with minimal middleware.
 *
 * @param setupRoutes - Optional function to add routes to the app
 * @returns Configured Express app for testing
 */
export function createTestApp(
  setupRoutes?: (app: Application) => void
): Application {
  const express = require("express") as typeof import("express");
  const app = express();

  app.use(express.json());

  if (setupRoutes !== undefined) {
    setupRoutes(app);
  }

  return app;
}

/**
 * Test configuration override helper.
 *
 * Creates config values suitable for testing without real credentials.
 *
 * @param overrides - Values to override
 * @returns Test configuration object
 */
export function createMockConfig<T extends Record<string, unknown>>(
  overrides: Partial<T> = {}
): T {
  const defaults = {
    DATABASE_URL: "postgresql://test:test@localhost:5432/test_db",
    JWT_SECRET: "test-secret-key-minimum-32-characters-long",
    JWT_EXPIRY_MINUTES: 30,
    ENVIRONMENT: "test",
    LOG_LEVEL: "silent",
    PORT: 0, // Random available port
  };

  return { ...defaults, ...overrides } as unknown as T;
}

/**
 * User factory for creating test user data.
 */
export class UserFactory {
  private static counter = 0;

  /**
   * Create a test user object.
   *
   * @param overrides - Values to override
   * @returns Test user data
   */
  static create(
    overrides: Partial<{
      id: string;
      email: string;
      password: string;
      name: string;
      role: string;
      isActive: boolean;
    }> = {}
  ): {
    id: string;
    email: string;
    password: string;
    name: string;
    role: string;
    isActive: boolean;
  } {
    UserFactory.counter++;
    const n = UserFactory.counter;

    return {
      id: `user-${n}`,
      email: `testuser${n}@example.com`,
      password: `password${n}`,
      name: `Test User ${n}`,
      role: "user",
      isActive: true,
      ...overrides,
    };
  }

  /**
   * Create multiple test users.
   *
   * @param count - Number of users to create
   * @param overrides - Values to override for all users
   * @returns Array of test user data
   */
  static createMany(
    count: number,
    overrides: Partial<{
      role: string;
      isActive: boolean;
    }> = {}
  ): Array<{
    id: string;
    email: string;
    password: string;
    name: string;
    role: string;
    isActive: boolean;
  }> {
    return Array.from({ length: count }, () => UserFactory.create(overrides));
  }

  /**
   * Reset the counter (call in beforeEach/afterEach).
   */
  static reset(): void {
    UserFactory.counter = 0;
  }
}

/**
 * Generic factory for creating test data.
 */
export class TestDataFactory<T extends Record<string, unknown>> {
  private counter = 0;
  private readonly defaultsFactory: (n: number) => T;

  constructor(defaultsFactory: (n: number) => T) {
    this.defaultsFactory = defaultsFactory;
  }

  /**
   * Create a single test object.
   */
  create(overrides: Partial<T> = {}): T {
    this.counter++;
    return { ...this.defaultsFactory(this.counter), ...overrides };
  }

  /**
   * Create multiple test objects.
   */
  createMany(count: number, overrides: Partial<T> = {}): T[] {
    return Array.from({ length: count }, () => this.create(overrides));
  }

  /**
   * Reset the counter.
   */
  reset(): void {
    this.counter = 0;
  }
}

// =============================================================================
// RESPONSE ASSERTIONS
// =============================================================================

/**
 * Assert response is successful (2xx).
 *
 * @param response - Supertest response
 * @param expectedStatus - Expected status code (default 200)
 */
export function assertResponseOk(
  response: SupertestResponse,
  expectedStatus: number = 200
): void {
  if (response.status !== expectedStatus) {
    throw new Error(
      `Expected status ${expectedStatus}, got ${response.status}. ` +
        `Body: ${JSON.stringify(response.body)}`
    );
  }
}

/**
 * Assert response is 201 Created.
 *
 * @param response - Supertest response
 */
export function assertResponseCreated(response: SupertestResponse): void {
  assertResponseOk(response, 201);
}

/**
 * Assert response is an error with expected status and message.
 *
 * @param response - Supertest response
 * @param expectedStatus - Expected error status code
 * @param expectedMessage - Expected error message (optional)
 */
export function assertResponseError(
  response: SupertestResponse,
  expectedStatus: number,
  expectedMessage?: string
): void {
  if (response.status !== expectedStatus) {
    throw new Error(
      `Expected status ${expectedStatus}, got ${response.status}. ` +
        `Body: ${JSON.stringify(response.body)}`
    );
  }

  if (expectedMessage !== undefined) {
    const actualMessage = response.body?.error ?? response.body?.message;
    if (actualMessage !== expectedMessage) {
      throw new Error(
        `Expected error message "${expectedMessage}", got "${actualMessage}"`
      );
    }
  }
}

/**
 * Assert response body contains expected fields.
 *
 * @param response - Supertest response
 * @param fields - Fields that must exist in response body
 */
export function assertResponseContains(
  response: SupertestResponse,
  fields: string[]
): void {
  const body = response.body;
  const missingFields = fields.filter(
    (field) => !(field in body) || body[field] === undefined
  );

  if (missingFields.length > 0) {
    throw new Error(
      `Response missing expected fields: ${missingFields.join(", ")}. ` +
        `Body: ${JSON.stringify(body)}`
    );
  }
}

/**
 * Assert response is paginated with expected structure.
 *
 * @param response - Supertest response
 * @param expectedCount - Expected number of items (optional)
 */
export function assertPaginatedResponse(
  response: SupertestResponse,
  expectedCount?: number
): void {
  assertResponseOk(response);

  const body = response.body;
  const requiredFields = ["items", "total", "page", "pageSize"];
  const missingFields = requiredFields.filter(
    (field) => !(field in body) || body[field] === undefined
  );

  if (missingFields.length > 0) {
    throw new Error(
      `Paginated response missing fields: ${missingFields.join(", ")}. ` +
        `Body: ${JSON.stringify(body)}`
    );
  }

  if (!Array.isArray(body.items)) {
    throw new Error("Paginated response 'items' must be an array");
  }

  if (expectedCount !== undefined && body.items.length !== expectedCount) {
    throw new Error(
      `Expected ${expectedCount} items, got ${body.items.length}`
    );
  }
}

// =============================================================================
// TEST MIDDLEWARE
// =============================================================================

/**
 * Create a mock authentication middleware for testing.
 *
 * @param mockUser - User data to attach to request
 * @returns Express middleware that attaches mock user
 */
export function createMockAuthMiddleware(
  mockUser: Record<string, unknown>
): (req: Request, res: Response, next: NextFunction) => void {
  return (req: Request, _res: Response, next: NextFunction): void => {
    (req as Request & { user: Record<string, unknown> }).user = mockUser;
    next();
  };
}

/**
 * Create a middleware that captures requests for assertion.
 *
 * @returns Object with middleware and captured requests array
 */
export function createRequestCapture(): {
  middleware: (req: Request, res: Response, next: NextFunction) => void;
  requests: Array<{
    method: string;
    path: string;
    body: unknown;
    headers: Record<string, string | string[] | undefined>;
  }>;
  clear: () => void;
} {
  const requests: Array<{
    method: string;
    path: string;
    body: unknown;
    headers: Record<string, string | string[] | undefined>;
  }> = [];

  return {
    middleware: (req: Request, _res: Response, next: NextFunction): void => {
      requests.push({
        method: req.method,
        path: req.path,
        body: req.body,
        headers: req.headers as Record<string, string | string[] | undefined>,
      });
      next();
    },
    requests,
    clear: (): void => {
      requests.length = 0;
    },
  };
}

// =============================================================================
// DATABASE TEST UTILITIES
// =============================================================================

/**
 * Transaction rollback helper for database tests.
 *
 * Wraps test in a transaction that rolls back after completion.
 * Requires Prisma client with $transaction support.
 *
 * @param prisma - Prisma client instance
 * @param testFn - Test function to run within transaction
 */
export async function withRollback<T>(
  prisma: {
    $transaction: <R>(
      fn: (tx: unknown) => Promise<R>,
      options?: { timeout?: number }
    ) => Promise<R>;
  },
  testFn: (tx: unknown) => Promise<T>
): Promise<void> {
  try {
    await prisma.$transaction(
      async (tx) => {
        await testFn(tx);
        throw new Error("ROLLBACK");
      },
      { timeout: 30000 }
    );
  } catch (error) {
    if (error instanceof Error && error.message === "ROLLBACK") {
      return;
    }
    throw error;
  }
}

/**
 * Clean specific tables in test database.
 *
 * @param prisma - Prisma client instance
 * @param tableNames - Tables to truncate
 */
export async function cleanTables(
  prisma: {
    $executeRawUnsafe: (query: string) => Promise<number>;
  },
  tableNames: string[]
): Promise<void> {
  for (const table of tableNames) {
    // Validate table name to prevent SQL injection
    if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(table)) {
      throw new Error(`Invalid table name: ${table}`);
    }
    await prisma.$executeRawUnsafe(
      `TRUNCATE TABLE "${table}" RESTART IDENTITY CASCADE`
    );
  }
}

// =============================================================================
// TIMING UTILITIES
// =============================================================================

/**
 * Wait for a specified duration.
 *
 * @param ms - Milliseconds to wait
 */
export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Wait for a condition to be true.
 *
 * @param condition - Function that returns true when condition is met
 * @param options - Timeout and interval options
 */
export async function waitFor(
  condition: () => boolean | Promise<boolean>,
  options: { timeout?: number; interval?: number } = {}
): Promise<void> {
  const { timeout = 5000, interval = 100 } = options;
  const start = Date.now();

  while (Date.now() - start < timeout) {
    if (await condition()) {
      return;
    }
    await sleep(interval);
  }

  throw new Error(`Condition not met within ${timeout}ms`);
}

// =============================================================================
// MOCK HELPERS
// =============================================================================

/**
 * Create a mock function that tracks calls.
 *
 * @param implementation - Optional implementation
 * @returns Mock function with call tracking
 */
export function createMock<T extends (...args: unknown[]) => unknown>(
  implementation?: T
): T & {
  calls: Array<{ args: Parameters<T>; result: ReturnType<T> }>;
  reset: () => void;
} {
  const calls: Array<{ args: Parameters<T>; result: ReturnType<T> }> = [];

  const mock = ((...args: Parameters<T>): ReturnType<T> => {
    const result = implementation?.(...args) as ReturnType<T>;
    calls.push({ args, result });
    return result;
  }) as T & {
    calls: Array<{ args: Parameters<T>; result: ReturnType<T> }>;
    reset: () => void;
  };

  mock.calls = calls;
  mock.reset = (): void => {
    calls.length = 0;
  };

  return mock;
}

/**
 * Create a mock that resolves/rejects based on call count.
 *
 * @param responses - Array of responses (or Error to reject)
 * @returns Mock function that returns responses in order
 */
export function createSequenceMock<T>(
  responses: Array<T | Error>
): () => Promise<T> {
  let callCount = 0;

  return async (): Promise<T> => {
    const response = responses[callCount % responses.length];
    callCount++;

    if (response instanceof Error) {
      throw response;
    }
    return response as T;
  };
}
