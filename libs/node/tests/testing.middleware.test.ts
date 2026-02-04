import { describe, it, expect, vi } from "vitest";
import { createTestApp, createMockAuthMiddleware, createRequestCapture } from "../src/testing.js";

describe("createTestApp", () => {
  it("creates an express app", async () => {
    const app = await createTestApp();

    expect(app).toBeDefined();
    expect(typeof app.use).toBe("function");
    expect(typeof app.get).toBe("function");
  });

  it("allows adding routes via setup function", async () => {
    const app = await createTestApp((app) => {
      app.get("/test", (_req, res) => {
        res.json({ ok: true });
      });
    });

    expect(app).toBeDefined();
  });
});

describe("createMockAuthMiddleware", () => {
  it("attaches user to request", () => {
    const mockUser = { id: "user-1", role: "admin" };
    const middleware = createMockAuthMiddleware(mockUser);
    const req = {} as { user?: Record<string, unknown> };
    const res = {} as Response;
    const next = vi.fn();

    middleware(req as never, res as never, next);

    expect(req.user).toEqual(mockUser);
    expect(next).toHaveBeenCalled();
  });
});

describe("createRequestCapture", () => {
  it("captures request details", () => {
    const capture = createRequestCapture();
    const req = {
      method: "POST",
      path: "/api/users",
      body: { name: "Test" },
      headers: { "content-type": "application/json" },
    };
    const res = {};
    const next = vi.fn();

    capture.middleware(req as never, res as never, next);

    expect(capture.requests).toHaveLength(1);
    expect(capture.requests[0]).toEqual({
      method: "POST",
      path: "/api/users",
      body: { name: "Test" },
      headers: { "content-type": "application/json" },
    });
  });

  it("clear removes captured requests", () => {
    const capture = createRequestCapture();
    capture.requests.push({
      method: "GET",
      path: "/test",
      body: undefined,
      headers: {},
    });

    capture.clear();

    expect(capture.requests).toHaveLength(0);
  });
});
