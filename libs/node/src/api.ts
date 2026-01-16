/**
 * TIM Shared API Module
 *
 * Provides Express middleware, error handlers, and utilities.
 *
 * @example
 * import { setupErrorHandlers, securityHeadersMiddleware } from "@tim/lib/api";
 *
 * const app = express();
 * app.use(securityHeadersMiddleware);
 * setupErrorHandlers(app);
 */

import type { Request, Response, NextFunction, Application } from "express";

/**
 * Base application error class.
 * Subclass this for specific error types.
 */
export class AppError extends Error {
  public readonly statusCode: number;
  public readonly isOperational: boolean;
  public readonly detail: string | undefined;

  constructor(
    statusCode: number,
    message: string,
    detail?: string,
    isOperational: boolean = true
  ) {
    super(message);
    this.statusCode = statusCode;
    this.isOperational = isOperational;
    this.detail = detail;
    this.name = this.constructor.name;
    Error.captureStackTrace(this, this.constructor);
  }
}

/**
 * Resource not found error (404).
 */
export class NotFoundError extends AppError {
  constructor(message: string = "Resource not found", detail?: string) {
    super(404, message, detail);
  }
}

/**
 * Conflict error (409).
 */
export class ConflictError extends AppError {
  constructor(message: string = "Resource already exists", detail?: string) {
    super(409, message, detail);
  }
}

/**
 * Validation error (400).
 */
export class ValidationError extends AppError {
  constructor(message: string = "Validation failed", detail?: string) {
    super(400, message, detail);
  }
}

/**
 * Unauthorized error (401).
 */
export class UnauthorizedError extends AppError {
  constructor(message: string = "Unauthorized", detail?: string) {
    super(401, message, detail);
  }
}

/**
 * Forbidden error (403).
 */
export class ForbiddenError extends AppError {
  constructor(message: string = "Forbidden", detail?: string) {
    super(403, message, detail);
  }
}

/**
 * Setup error handlers for Express app.
 *
 * @param app - Express application instance
 * @param logger - Optional logger for error logging
 */
export function setupErrorHandlers(
  app: Application,
  logger?: { error: (obj: object, msg: string) => void }
): void {
  // 404 handler
  app.use((_req: Request, _res: Response, next: NextFunction) => {
    next(new NotFoundError());
  });

  // Error handler
  app.use(
    (err: Error, req: Request, res: Response, _next: NextFunction): void => {
      if (err instanceof AppError && err.isOperational) {
        res.status(err.statusCode).json({
          error: err.message,
          ...(err.detail !== undefined && { detail: err.detail }),
        });
        return;
      }

      // Log unexpected errors
      if (logger !== undefined) {
        logger.error(
          {
            error: err.message,
            stack: err.stack,
            path: req.path,
            method: req.method,
          },
          "Unhandled error"
        );
      }

      res.status(500).json({
        error: "Internal server error",
      });
    }
  );
}

/**
 * Security headers middleware.
 *
 * Adds standard security headers to all responses.
 */
export function securityHeadersMiddleware(
  _req: Request,
  res: Response,
  next: NextFunction
): void {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("X-XSS-Protection", "1; mode=block");
  res.setHeader("Referrer-Policy", "strict-origin-when-cross-origin");
  res.setHeader(
    "Content-Security-Policy",
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'"
  );
  next();
}

/**
 * Rate limit state (in-memory - use Redis for production).
 */
const rateLimitState = new Map<string, number[]>();

/**
 * Simple rate limiting middleware.
 *
 * For production, use Redis-based rate limiting instead.
 *
 * @param requestsPerMinute - Max requests per client per minute
 */
export function rateLimitMiddleware(
  requestsPerMinute: number = 60
): (req: Request, res: Response, next: NextFunction) => void {
  return (req: Request, res: Response, next: NextFunction): void => {
    const clientIp = getClientIp(req);
    const now = Date.now();
    const windowMs = 60000; // 1 minute

    // Get or initialize client's request timestamps
    let timestamps = rateLimitState.get(clientIp) ?? [];

    // Filter to only requests within the window
    timestamps = timestamps.filter((t) => now - t < windowMs);

    if (timestamps.length >= requestsPerMinute) {
      res.status(429).json({ error: "Too many requests" });
      return;
    }

    // Record this request
    timestamps.push(now);
    rateLimitState.set(clientIp, timestamps);

    next();
  };
}

/**
 * Get client IP from request.
 */
function getClientIp(req: Request): string {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string") {
    return forwarded.split(",")[0]?.trim() ?? "unknown";
  }
  return req.ip ?? req.socket.remoteAddress ?? "unknown";
}

/**
 * Create health check router.
 *
 * @returns Express router with health endpoints
 */
export function createHealthRouter(): import("express").Router {
  const { Router } = require("express") as typeof import("express");
  const router = Router();

  router.get("/health", (_req: Request, res: Response) => {
    res.json({ status: "healthy" });
  });

  router.get("/health/ready", (_req: Request, res: Response) => {
    res.json({ status: "ready" });
  });

  router.get("/health/live", (_req: Request, res: Response) => {
    res.json({
      status: "healthy",
      timestamp: Date.now(),
      uptime: process.uptime(),
    });
  });

  return router;
}

/**
 * Typed request body interface.
 */
export interface TypedRequest<T> extends Request {
  body: T;
}

/**
 * Async handler wrapper to catch errors.
 *
 * @param fn - Async request handler
 * @returns Wrapped handler that catches errors
 */
export function asyncHandler<T>(
  fn: (req: TypedRequest<T>, res: Response, next: NextFunction) => Promise<void>
): (req: Request, res: Response, next: NextFunction) => void {
  return (req: Request, res: Response, next: NextFunction): void => {
    Promise.resolve(fn(req as TypedRequest<T>, res, next)).catch(next);
  };
}
