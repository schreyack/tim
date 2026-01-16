/**
 * TIM Shared Logging Module
 *
 * Provides structured JSON logging using pino for all TIM Node.js projects.
 *
 * @example
 * import { createLogger, LogContextMiddleware } from "@tim/lib/logging";
 *
 * const logger = createLogger({ level: "info", serviceName: "my-api" });
 * logger.info({ userId: 123 }, "User created");
 *
 * // Express middleware
 * app.use(LogContextMiddleware(logger));
 */

import pino, { type Logger, type LoggerOptions } from "pino";
import type { Request, Response, NextFunction } from "express";

/**
 * Options for creating a logger.
 */
export interface CreateLoggerOptions {
  /** Log level (debug, info, warn, error) */
  level?: string;
  /** Service name to include in all logs */
  serviceName?: string;
  /** Environment name to include in all logs */
  environment?: string;
  /** Enable pretty printing for development */
  pretty?: boolean;
  /** Custom redaction paths */
  redact?: string[];
}

/**
 * Create a configured pino logger.
 *
 * @param options - Logger configuration options
 * @returns Configured pino logger
 *
 * @example
 * const logger = createLogger({
 *   level: config.LOG_LEVEL,
 *   serviceName: "user-service",
 *   environment: config.NODE_ENV,
 * });
 */
export function createLogger(options: CreateLoggerOptions = {}): Logger {
  const {
    level = "info",
    serviceName,
    environment,
    pretty = false,
    redact = [],
  } = options;

  const defaultRedact = [
    "password",
    "token",
    "authorization",
    "cookie",
    "jwt",
    "apiKey",
    "secret",
  ];

  const pinoOptions: LoggerOptions = {
    level,
    redact: [...defaultRedact, ...redact],
    formatters: {
      level: (label: string) => ({ level: label }),
    },
    timestamp: pino.stdTimeFunctions.isoTime,
    base: {
      ...(serviceName !== undefined && { service: serviceName }),
      ...(environment !== undefined && { environment }),
    },
  };

  if (pretty) {
    return pino({
      ...pinoOptions,
      transport: {
        target: "pino-pretty",
        options: {
          colorize: true,
          translateTime: "SYS:standard",
          ignore: "pid,hostname",
        },
      },
    });
  }

  return pino(pinoOptions);
}

/**
 * Express middleware to add logging context to requests.
 *
 * Adds:
 * - Correlation ID (from header or generated)
 * - Request timing
 * - Request/response logging
 *
 * @param logger - Pino logger instance
 * @returns Express middleware function
 *
 * @example
 * const logger = createLogger({ serviceName: "my-api" });
 * app.use(LogContextMiddleware(logger));
 */
export function LogContextMiddleware(
  logger: Logger
): (req: Request, res: Response, next: NextFunction) => void {
  return (req: Request, res: Response, next: NextFunction): void => {
    const startTime = Date.now();

    // Get or generate correlation ID
    const correlationId =
      (req.headers["x-correlation-id"] as string | undefined) ?? generateId();

    // Add correlation ID to response
    res.setHeader("x-correlation-id", correlationId);

    // Create child logger with request context
    const childLogger = logger.child({
      correlationId,
      method: req.method,
      path: req.path,
    });

    // Attach to request for use in handlers
    (req as RequestWithLogger).log = childLogger;

    // Log request start
    childLogger.info("request_started");

    // Log response on finish
    res.on("finish", () => {
      const duration = Date.now() - startTime;
      const logData = {
        statusCode: res.statusCode,
        durationMs: duration,
      };

      if (res.statusCode >= 500) {
        childLogger.error(logData, "request_completed");
      } else if (res.statusCode >= 400) {
        childLogger.warn(logData, "request_completed");
      } else {
        childLogger.info(logData, "request_completed");
      }
    });

    next();
  };
}

/**
 * Extended Request type with logger attached.
 */
export interface RequestWithLogger extends Request {
  log: Logger;
}

/**
 * Generate a unique ID for correlation.
 */
function generateId(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 11)}`;
}

/**
 * Create a child logger with bound context.
 *
 * @param logger - Parent logger
 * @param context - Context to bind
 * @returns Child logger with context
 *
 * @example
 * const userLogger = withContext(logger, { userId: 123 });
 * userLogger.info("User action"); // Will include userId
 */
export function withContext(
  logger: Logger,
  context: Record<string, unknown>
): Logger {
  return logger.child(context);
}
