/**
 * Response assertions for testing HTTP responses.
 *
 * @module testing/assertions
 */

import type { Response as SupertestResponse } from "supertest";

/**
 * Assert response is successful (2xx).
 *
 * @param response - Supertest response
 * @param expectedStatus - Expected status code (default 200)
 */
export function assertResponseOk(response: SupertestResponse, expectedStatus = 200): void {
  if (response.status !== expectedStatus) {
    throw new Error(
      `Expected status ${expectedStatus.toString()}, got ${response.status.toString()}. ` +
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
      `Expected status ${expectedStatus.toString()}, got ${response.status.toString()}. ` +
        `Body: ${JSON.stringify(response.body)}`
    );
  }

  if (expectedMessage !== undefined) {
    const body = response.body as Record<string, unknown>;
    const actualMessage = body.error ?? body.message;
    if (actualMessage !== expectedMessage) {
      throw new Error(
        `Expected error message "${expectedMessage}", got "${String(actualMessage)}"`
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
export function assertResponseContains(response: SupertestResponse, fields: string[]): void {
  const body = response.body as Record<string, unknown>;
  const missingFields = fields.filter(
    (field) => !Object.hasOwn(body, field) || body[field] === undefined // eslint-disable-line security/detect-object-injection -- field comes from trusted test code
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
export function assertPaginatedResponse(response: SupertestResponse, expectedCount?: number): void {
  assertResponseOk(response);

  const body = response.body as Record<string, unknown>;
  const requiredFields = ["items", "total", "page", "pageSize"];
  const missingFields = requiredFields.filter(
    (field) => !Object.hasOwn(body, field) || body[field] === undefined // eslint-disable-line security/detect-object-injection -- field comes from hardcoded list
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
      `Expected ${expectedCount.toString()} items, got ${body.items.length.toString()}`
    );
  }
}
