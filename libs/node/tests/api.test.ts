import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Request, Response, NextFunction, Application } from "express";
import request from "supertest";
import express from "express";
import {
  AppError,
  NotFoundError,
  ConflictError,
  ValidationError,
  UnauthorizedError,
  ForbiddenError,
  securityHeadersMiddleware,
  rateLimitMiddleware,
  asyncHandler,
  setupErrorHandlers,
  createHealthRouter,
} from "../src/api.js";

describe("AppError", () => {
  it("should have correct status code and message", () => {
    const error = new AppError(500, "Server error");

    expect(error.statusCode).toBe(500);
    expect(error.message).toBe("Server error");
    expect(error.isOperational).toBe(true);
  });

  it("should include detail when provided", () => {
    const error = new AppError(400, "Bad request", "missing_field");

    expect(error.detail).toBe("missing_field");
  });

  it("should be markable as non-operational", () => {
    const error = new AppError(500, "Fatal error", undefined, false);

    expect(error.isOperational).toBe(false);
  });
});

describe("NotFoundError", () => {
  it("should have 404 status code", () => {
    const error = new NotFoundError();

    expect(error.statusCode).toBe(404);
    expect(error.message).toBe("Resource not found");
  });

  it("should allow custom message", () => {
    const error = new NotFoundError("User not found");

    expect(error.message).toBe("User not found");
  });
});

describe("ConflictError", () => {
  it("should have 409 status code", () => {
    const error = new ConflictError();

    expect(error.statusCode).toBe(409);
    expect(error.message).toBe("Resource already exists");
  });
});

describe("ValidationError", () => {
  it("should have 400 status code", () => {
    const error = new ValidationError();

    expect(error.statusCode).toBe(400);
    expect(error.message).toBe("Validation failed");
  });
});

describe("UnauthorizedError", () => {
  it("should have 401 status code", () => {
    const error = new UnauthorizedError();

    expect(error.statusCode).toBe(401);
    expect(error.message).toBe("Unauthorized");
  });
});

describe("ForbiddenError", () => {
  it("should have 403 status code", () => {
    const error = new ForbiddenError();

    expect(error.statusCode).toBe(403);
    expect(error.message).toBe("Forbidden");
  });
});

describe("securityHeadersMiddleware", () => {
  it("should set security headers", () => {
    const req = {} as Request;
    const res = {
      setHeader: vi.fn(),
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    securityHeadersMiddleware(req, res, next);

    expect(res.setHeader).toHaveBeenCalledWith("X-Content-Type-Options", "nosniff");
    expect(res.setHeader).toHaveBeenCalledWith("X-Frame-Options", "DENY");
    expect(res.setHeader).toHaveBeenCalledWith("X-XSS-Protection", "1; mode=block");
    expect(res.setHeader).toHaveBeenCalledWith(
      "Referrer-Policy",
      "strict-origin-when-cross-origin"
    );
    expect(res.setHeader).toHaveBeenCalledWith(
      "Content-Security-Policy",
      expect.stringContaining("default-src 'self'")
    );
    expect(next).toHaveBeenCalled();
  });
});

describe("rateLimitMiddleware", () => {
  beforeEach(() => {
    // Reset rate limit state between tests by using unique IPs
  });

  it("should allow requests under limit", () => {
    const middleware = rateLimitMiddleware(10);
    const req = {
      headers: {},
      ip: `192.168.1.${Math.random()}`,
      socket: { remoteAddress: undefined },
    } as unknown as Request;
    const res = {
      status: vi.fn().mockReturnThis(),
      json: vi.fn(),
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    middleware(req, res, next);

    expect(next).toHaveBeenCalled();
    expect(res.status).not.toHaveBeenCalled();
  });

  it("should block requests over limit", () => {
    const middleware = rateLimitMiddleware(2);
    const ip = `192.168.2.${Math.floor(Math.random() * 1000)}`;
    const req = {
      headers: {},
      ip,
      socket: { remoteAddress: undefined },
    } as unknown as Request;
    const res = {
      status: vi.fn().mockReturnThis(),
      json: vi.fn(),
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    // Make 3 requests (limit is 2)
    middleware(req, res, next);
    middleware(req, res, next);
    middleware(req, res, next);

    expect(res.status).toHaveBeenCalledWith(429);
    expect(res.json).toHaveBeenCalledWith({ error: "Too many requests" });
  });

  it("should use X-Forwarded-For header for IP", () => {
    const middleware = rateLimitMiddleware(10);
    const req = {
      headers: { "x-forwarded-for": "203.0.113.50, 70.41.3.18" },
      ip: "127.0.0.1",
      socket: { remoteAddress: undefined },
    } as unknown as Request;
    const res = {
      status: vi.fn().mockReturnThis(),
      json: vi.fn(),
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    middleware(req, res, next);

    expect(next).toHaveBeenCalled();
  });
});

describe("asyncHandler", () => {
  it("should pass successful result through", async () => {
    const handler = asyncHandler(async (_req, res) => {
      res.json({ success: true });
    });

    const req = {} as Request;
    const res = {
      json: vi.fn(),
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    handler(req, res, next);

    // Wait for async execution
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(res.json).toHaveBeenCalledWith({ success: true });
  });

  it("should catch errors and pass to next", async () => {
    const error = new Error("Test error");
    const handler = asyncHandler(async () => {
      throw error;
    });

    const req = {} as Request;
    const res = {} as Response;
    const next = vi.fn() as NextFunction;

    handler(req, res, next);

    // Wait for async execution
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(next).toHaveBeenCalledWith(error);
  });
});

describe("setupErrorHandlers", () => {
  it("should handle AppError with correct status", async () => {
    const app = express();
    app.use(express.json());
    app.get("/test", (_req, _res, next) => {
      next(new ValidationError("Invalid input"));
    });
    setupErrorHandlers(app);

    const response = await request(app).get("/test");

    expect(response.status).toBe(400);
    expect(response.body.error).toBe("Invalid input");
  });

  it("should include error detail when present", async () => {
    const app = express();
    app.use(express.json());
    app.get("/test", (_req, _res, next) => {
      next(new AppError(400, "Bad request", "field_missing"));
    });
    setupErrorHandlers(app);

    const response = await request(app).get("/test");

    expect(response.status).toBe(400);
    expect(response.body.detail).toBe("field_missing");
  });

  it("should return 404 for unknown routes", async () => {
    const app = express();
    app.use(express.json());
    setupErrorHandlers(app);

    const response = await request(app).get("/nonexistent");

    expect(response.status).toBe(404);
    expect(response.body.error).toBe("Resource not found");
  });

  it("should return 500 for unexpected errors", async () => {
    const app = express();
    app.use(express.json());
    app.get("/test", () => {
      throw new Error("Unexpected crash");
    });
    setupErrorHandlers(app);

    const response = await request(app).get("/test");

    expect(response.status).toBe(500);
    expect(response.body.error).toBe("Internal server error");
  });

  it("should log unexpected errors when logger provided", async () => {
    const logger = { error: vi.fn() };
    const app = express();
    app.use(express.json());
    app.get("/test", () => {
      throw new Error("Unexpected crash");
    });
    setupErrorHandlers(app, logger);

    await request(app).get("/test");

    expect(logger.error).toHaveBeenCalledWith(
      expect.objectContaining({
        error: "Unexpected crash",
        path: "/test",
        method: "GET",
      }),
      "Unhandled error"
    );
  });
});

describe("createHealthRouter", () => {
  it("should return healthy status on /health", async () => {
    const app = express();
    app.use(await createHealthRouter());

    const response = await request(app).get("/health");

    expect(response.status).toBe(200);
    expect(response.body.status).toBe("healthy");
  });

  it("should return ready status on /health/ready", async () => {
    const app = express();
    app.use(await createHealthRouter());

    const response = await request(app).get("/health/ready");

    expect(response.status).toBe(200);
    expect(response.body.status).toBe("ready");
  });

  it("should return detailed status on /health/live", async () => {
    const app = express();
    app.use(await createHealthRouter());

    const response = await request(app).get("/health/live");

    expect(response.status).toBe(200);
    expect(response.body.status).toBe("healthy");
    expect(response.body).toHaveProperty("timestamp");
    expect(response.body).toHaveProperty("uptime");
  });
});
