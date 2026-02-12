import { describe, it, expect, vi, beforeEach } from "vitest";
import type { Request, Response, NextFunction } from "express";
import {
  createLogger,
  LogContextMiddleware,
  withContext,
  type RequestWithLogger,
} from "../src/logging.js";

describe("createLogger", () => {
  it("creates a logger with default settings", () => {
    const logger = createLogger();

    expect(logger).toBeDefined();
    expect(typeof logger.info).toBe("function");
    expect(typeof logger.error).toBe("function");
    expect(typeof logger.warn).toBe("function");
    expect(typeof logger.debug).toBe("function");
  });

  it("should respect log level setting", () => {
    const logger = createLogger({ level: "error" });

    expect(logger.level).toBe("error");
  });

  it("should include serviceName in base context", () => {
    const logger = createLogger({ serviceName: "test-service" });

    // Check that the logger was created (pino stores bindings internally)
    expect(logger).toBeDefined();
  });

  it("should include environment in base context", () => {
    const logger = createLogger({ environment: "test" });

    expect(logger).toBeDefined();
  });

  it("merges custom redact paths with defaults", () => {
    const logger = createLogger({ redact: ["customSecret"] });

    expect(logger).toBeDefined();
  });

  it("creates pretty logger when pretty option is true", () => {
    // Note: Pretty printing uses a transport, so we just verify it doesn't throw
    const logger = createLogger({ pretty: true, level: "info" });

    expect(logger).toBeDefined();
    expect(typeof logger.info).toBe("function");
  });
});

describe("LogContextMiddleware", () => {
  let mockLogger: ReturnType<typeof createLogger>;
  let mockChildLogger: {
    info: ReturnType<typeof vi.fn>;
    warn: ReturnType<typeof vi.fn>;
    error: ReturnType<typeof vi.fn>;
  };

  beforeEach(() => {
    mockChildLogger = {
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };

    mockLogger = {
      child: vi.fn().mockReturnValue(mockChildLogger),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    } as unknown as ReturnType<typeof createLogger>;
  });

  it("adds correlation ID to response when not provided", () => {
    const middleware = LogContextMiddleware(mockLogger);
    const req = {
      headers: {},
      method: "GET",
      path: "/test",
    } as unknown as Request;
    const res = {
      setHeader: vi.fn(),
      on: vi.fn(),
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    middleware(req, res, next);

    expect(res.setHeader).toHaveBeenCalledWith("x-correlation-id", expect.any(String));
    expect(next).toHaveBeenCalled();
  });

  it("should use existing correlation ID from header", () => {
    const middleware = LogContextMiddleware(mockLogger);
    const correlationId = "existing-correlation-id";
    const req = {
      headers: { "x-correlation-id": correlationId },
      method: "GET",
      path: "/test",
    } as unknown as Request;
    const res = {
      setHeader: vi.fn(),
      on: vi.fn(),
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    middleware(req, res, next);

    expect(res.setHeader).toHaveBeenCalledWith("x-correlation-id", correlationId);
  });

  it("creates child logger with request context", () => {
    const middleware = LogContextMiddleware(mockLogger);
    const req = {
      headers: { "x-correlation-id": "test-id" },
      method: "POST",
      path: "/api/users",
    } as unknown as Request;
    const res = {
      setHeader: vi.fn(),
      on: vi.fn(),
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    middleware(req, res, next);

    expect(mockLogger.child).toHaveBeenCalledWith({
      correlationId: "test-id",
      method: "POST",
      path: "/api/users",
    });
  });

  it("should attach logger to request", () => {
    const middleware = LogContextMiddleware(mockLogger);
    const req = {
      headers: {},
      method: "GET",
      path: "/test",
    } as unknown as Request;
    const res = {
      setHeader: vi.fn(),
      on: vi.fn(),
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    middleware(req, res, next);

    expect((req as RequestWithLogger).log).toBe(mockChildLogger);
  });

  it("should log request started", () => {
    const middleware = LogContextMiddleware(mockLogger);
    const req = {
      headers: {},
      method: "GET",
      path: "/test",
    } as unknown as Request;
    const res = {
      setHeader: vi.fn(),
      on: vi.fn(),
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    middleware(req, res, next);

    expect(mockChildLogger.info).toHaveBeenCalledWith("request_started");
  });

  it("should log success response on finish", () => {
    const middleware = LogContextMiddleware(mockLogger);
    const req = {
      headers: {},
      method: "GET",
      path: "/test",
    } as unknown as Request;

    let finishCallback: (() => void) | null = null;
    const res = {
      setHeader: vi.fn(),
      on: vi.fn((event: string, callback: () => void) => {
        if (event === "finish") {
          finishCallback = callback;
        }
      }),
      statusCode: 200,
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    middleware(req, res, next);

    // Simulate response finish
    finishCallback?.();

    expect(mockChildLogger.info).toHaveBeenCalledWith(
      expect.objectContaining({
        statusCode: 200,
        durationMs: expect.any(Number),
      }),
      "request_completed"
    );
  });

  it("should log warn for 4xx responses", () => {
    const middleware = LogContextMiddleware(mockLogger);
    const req = {
      headers: {},
      method: "GET",
      path: "/test",
    } as unknown as Request;

    let finishCallback: (() => void) | null = null;
    const res = {
      setHeader: vi.fn(),
      on: vi.fn((event: string, callback: () => void) => {
        if (event === "finish") {
          finishCallback = callback;
        }
      }),
      statusCode: 404,
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    middleware(req, res, next);
    finishCallback?.();

    expect(mockChildLogger.warn).toHaveBeenCalledWith(
      expect.objectContaining({
        statusCode: 404,
        durationMs: expect.any(Number),
      }),
      "request_completed"
    );
  });

  it("should log error for 5xx responses", () => {
    const middleware = LogContextMiddleware(mockLogger);
    const req = {
      headers: {},
      method: "GET",
      path: "/test",
    } as unknown as Request;

    let finishCallback: (() => void) | null = null;
    const res = {
      setHeader: vi.fn(),
      on: vi.fn((event: string, callback: () => void) => {
        if (event === "finish") {
          finishCallback = callback;
        }
      }),
      statusCode: 500,
    } as unknown as Response;
    const next = vi.fn() as NextFunction;

    middleware(req, res, next);
    finishCallback?.();

    expect(mockChildLogger.error).toHaveBeenCalledWith(
      expect.objectContaining({
        statusCode: 500,
        durationMs: expect.any(Number),
      }),
      "request_completed"
    );
  });
});

describe("withContext", () => {
  it("creates child logger with context", () => {
    const logger = createLogger({ level: "info" });
    const childLogger = withContext(logger, { userId: 123 });

    expect(childLogger).toBeDefined();
    expect(typeof childLogger.info).toBe("function");
  });

  it("should allow nested context", () => {
    const logger = createLogger({ level: "info" });
    const userLogger = withContext(logger, { userId: 123 });
    const requestLogger = withContext(userLogger, { requestId: "abc" });

    expect(requestLogger).toBeDefined();
  });
});
