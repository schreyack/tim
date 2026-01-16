/**
 * Health check endpoint.
 */

import { Router, type Request, type Response } from "express";

const router = Router();

interface HealthResponse {
  status: "healthy";
  version: string;
}

router.get("/health", (_req: Request, res: Response): void => {
  const response: HealthResponse = {
    status: "healthy",
    version: "0.1.0",
  };
  res.json(response);
});

export { router as healthRouter };
