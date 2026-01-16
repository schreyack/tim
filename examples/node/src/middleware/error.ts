/**
 * Global error handling middleware.
 */

import type { Request, Response, NextFunction } from "express";

import { AppError, ValidationError } from "../services/errors.js";

interface ErrorResponse {
  detail: string;
  errors?: Array<{ path: string; message: string }>;
}

export function errorHandler(
  err: Error,
  _req: Request,
  res: Response,
  _next: NextFunction
): void {
  if (err instanceof ValidationError) {
    const response: ErrorResponse = {
      detail: err.message,
      errors: err.errors,
    };
    res.status(err.statusCode).json(response);
    return;
  }

  if (err instanceof AppError) {
    res.status(err.statusCode).json({ detail: err.message });
    return;
  }

  console.error("Unhandled error:", err);
  res.status(500).json({ detail: "Internal server error" });
}
