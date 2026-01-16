/**
 * Request validation middleware using Zod.
 */

import type { Request, Response, NextFunction } from "express";
import type { ZodSchema, ZodError } from "zod";

import { ValidationError } from "../services/errors.js";

export function validateBody<T>(
  schema: ZodSchema<T>
): (req: Request, res: Response, next: NextFunction) => void {
  return (req: Request, _res: Response, next: NextFunction): void => {
    const result = schema.safeParse(req.body);

    if (!result.success) {
      const errors = formatZodErrors(result.error);
      next(new ValidationError("Validation failed", errors));
      return;
    }

    req.body = result.data;
    next();
  };
}

function formatZodErrors(
  error: ZodError
): Array<{ path: string; message: string }> {
  return error.errors.map((e) => ({
    path: e.path.join("."),
    message: e.message,
  }));
}
