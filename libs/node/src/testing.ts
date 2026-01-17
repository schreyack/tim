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

// Re-export everything from submodules
export * from "./testing/index.js";
