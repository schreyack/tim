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
 *
 * @module testing
 */

// Factories
export { createMockConfig, UserFactory, TestDataFactory } from "./factories.js";

// Assertions
export {
  assertResponseOk,
  assertResponseCreated,
  assertResponseError,
  assertResponseContains,
  assertPaginatedResponse,
} from "./assertions.js";

// Middleware
export {
  createTestApp,
  createMockAuthMiddleware,
  createRequestCapture,
} from "./middleware.js";

// Database utilities
export { withRollback, cleanTables } from "./database.js";

// Utility functions
export { sleep, waitFor, createMock, createSequenceMock } from "./utils.js";
