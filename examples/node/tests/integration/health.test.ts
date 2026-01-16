/**
 * Integration tests for health API - test_what_when_then naming.
 */

import { describe, it, expect, beforeAll, afterAll } from "vitest";
import request from "supertest";
import type { Express } from "express";

// Mock config before importing app
process.env["DATABASE_URL"] = "postgresql://test:test@localhost:5432/test";
process.env["JWT_SECRET"] = "test-secret-key-minimum-32-characters";

import { createApp } from "../../src/app.js";

describe("Health API", () => {
  let app: Express;

  beforeAll(() => {
    app = createApp();
  });

  describe("GET /api/v1/health", () => {
    it("should_get_health_returns_healthy_status", async () => {
      const response = await request(app).get("/api/v1/health");

      expect(response.status).toBe(200);
      expect(response.body).toEqual({
        status: "healthy",
        version: "0.1.0",
      });
    });

    it("should_get_health_includes_security_headers", async () => {
      const response = await request(app).get("/api/v1/health");

      expect(response.headers["x-content-type-options"]).toBe("nosniff");
      expect(response.headers["x-frame-options"]).toBe("SAMEORIGIN");
    });
  });
});
