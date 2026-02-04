/**
 * Test middleware utilities for Express testing.
 *
 * @module testing/middleware
 */

import type { Application, Request, Response, NextFunction } from "express";

/**
 * Create a test Express application with minimal middleware.
 *
 * @param setupRoutes - Optional function to add routes to the app
 * @returns Configured Express app for testing
 */
export async function createTestApp(
  setupRoutes?: (app: Application) => void
): Promise<Application> {
  const express = await import("express");
  const app = express.default();

  app.use(express.default.json());

  if (setupRoutes !== undefined) {
    setupRoutes(app);
  }

  return app;
}

/**
 * Create a mock authentication middleware for testing.
 *
 * @param mockUser - User data to attach to request
 * @returns Express middleware that attaches mock user
 */
export function createMockAuthMiddleware(
  mockUser: Record<string, unknown>
): (req: Request, res: Response, next: NextFunction) => void {
  return (req: Request, _res: Response, next: NextFunction): void => {
    (req as Request & { user: Record<string, unknown> }).user = mockUser;
    next();
  };
}

/**
 * Create a middleware that captures requests for assertion.
 *
 * @returns Object with middleware and captured requests array
 */
export function createRequestCapture(): {
  middleware: (req: Request, res: Response, next: NextFunction) => void;
  requests: {
    method: string;
    path: string;
    body: unknown;
    headers: Record<string, string | string[] | undefined>;
  }[];
  clear: () => void;
} {
  const requests: {
    method: string;
    path: string;
    body: unknown;
    headers: Record<string, string | string[] | undefined>;
  }[] = [];

  return {
    middleware: (req: Request, _res: Response, next: NextFunction): void => {
      requests.push({
        method: req.method,
        path: req.path,
        body: req.body,
        headers: req.headers as Record<string, string | string[] | undefined>,
      });
      next();
    },
    requests,
    clear: (): void => {
      requests.length = 0;
    },
  };
}
