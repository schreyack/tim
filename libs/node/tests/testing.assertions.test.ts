import { describe, it, expect } from "vitest";
import {
  assertResponseOk,
  assertResponseCreated,
  assertResponseError,
  assertResponseContains,
  assertPaginatedResponse,
} from "../src/testing.js";
import type { Response as SupertestResponse } from "supertest";

describe("assertResponseOk", () => {
  it("should pass when response status is 200", () => {
    const response = { status: 200, body: {} } as SupertestResponse;

    expect(() => assertResponseOk(response)).not.toThrow();
  });

  it("should pass when response matches custom expected status", () => {
    const response = { status: 204, body: {} } as SupertestResponse;

    expect(() => assertResponseOk(response, 204)).not.toThrow();
  });

  it("should throw when response has unexpected status", () => {
    const response = { status: 400, body: { error: "Bad" } } as SupertestResponse;

    expect(() => assertResponseOk(response)).toThrow("Expected status 200, got 400");
  });
});

describe("assertResponseCreated", () => {
  it("should pass when response status is 201", () => {
    const response = { status: 201, body: {} } as SupertestResponse;

    expect(() => assertResponseCreated(response)).not.toThrow();
  });

  it("should throw when response status is not 201", () => {
    const response = { status: 200, body: {} } as SupertestResponse;

    expect(() => assertResponseCreated(response)).toThrow("Expected status 201");
  });
});

describe("assertResponseError", () => {
  it("should pass when response matches expected error status", () => {
    const response = { status: 404, body: {} } as SupertestResponse;

    expect(() => assertResponseError(response, 404)).not.toThrow();
  });

  it("should pass when error message matches expected", () => {
    const response = {
      status: 400,
      body: { error: "Validation failed" },
    } as SupertestResponse;

    expect(() => assertResponseError(response, 400, "Validation failed")).not.toThrow();
  });

  it("should throw when error message does not match", () => {
    const response = {
      status: 400,
      body: { error: "Wrong message" },
    } as SupertestResponse;

    expect(() => assertResponseError(response, 400, "Expected message")).toThrow(
      'Expected error message "Expected message"'
    );
  });

  it("should check message field when error field is missing", () => {
    const response = {
      status: 400,
      body: { message: "Validation failed" },
    } as SupertestResponse;

    expect(() => assertResponseError(response, 400, "Validation failed")).not.toThrow();
  });
});

describe("assertResponseContains", () => {
  it("should pass when all expected fields exist", () => {
    const response = {
      status: 200,
      body: { id: 1, name: "Test", email: "test@example.com" },
    } as SupertestResponse;

    expect(() => assertResponseContains(response, ["id", "name", "email"])).not.toThrow();
  });

  it("should throw when fields are missing", () => {
    const response = {
      status: 200,
      body: { id: 1 },
    } as SupertestResponse;

    expect(() => assertResponseContains(response, ["id", "name"])).toThrow(
      "Response missing expected fields: name"
    );
  });

  it("should treat undefined values as missing", () => {
    const response = {
      status: 200,
      body: { id: 1, name: undefined },
    } as SupertestResponse;

    expect(() => assertResponseContains(response, ["id", "name"])).toThrow(
      "missing expected fields: name"
    );
  });
});

describe("assertPaginatedResponse", () => {
  it("should pass when response has valid pagination fields", () => {
    const response = {
      status: 200,
      body: { items: [1, 2, 3], total: 3, page: 1, pageSize: 10 },
    } as SupertestResponse;

    expect(() => assertPaginatedResponse(response)).not.toThrow();
  });

  it("should pass when item count matches expected", () => {
    const response = {
      status: 200,
      body: { items: [1, 2], total: 2, page: 1, pageSize: 10 },
    } as SupertestResponse;

    expect(() => assertPaginatedResponse(response, 2)).not.toThrow();
  });

  it("should throw when item count does not match expected", () => {
    const response = {
      status: 200,
      body: { items: [1, 2], total: 2, page: 1, pageSize: 10 },
    } as SupertestResponse;

    expect(() => assertPaginatedResponse(response, 5)).toThrow("Expected 5 items, got 2");
  });

  it("should throw when pagination fields are missing", () => {
    const response = {
      status: 200,
      body: { items: [] },
    } as SupertestResponse;

    expect(() => assertPaginatedResponse(response)).toThrow(
      "missing fields: total, page, pageSize"
    );
  });

  it("should throw when items is not an array", () => {
    const response = {
      status: 200,
      body: { items: "not an array", total: 0, page: 1, pageSize: 10 },
    } as SupertestResponse;

    expect(() => assertPaginatedResponse(response)).toThrow("'items' must be an array");
  });
});
