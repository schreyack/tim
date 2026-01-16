/**
 * Express application factory.
 */

import express, { type Express, type Request, type Response, type NextFunction } from "express";
import helmet from "helmet";

import { authRouter } from "./api/auth.js";
import { healthRouter } from "./api/health.js";
import { usersRouter } from "./api/users.js";
import { errorHandler } from "./middleware/error.js";

export function createApp(): Express {
  const app = express();

  // Security middleware
  app.use(helmet());

  // Body parsing
  app.use(express.json());

  // API routes
  app.use("/api/v1", healthRouter);
  app.use("/api/v1/auth", authRouter);
  app.use("/api/v1/users", usersRouter);

  // Error handling
  app.use(errorHandler);

  return app;
}
