/**
 * Authentication endpoints.
 */

import { Router, type Request, type Response, type NextFunction } from "express";

import { prisma } from "../db/client.js";
import { validateBody } from "../middleware/validation.js";
import { loginSchema, type TokenResponse } from "../schemas/user.js";
import { createToken } from "../services/auth.js";
import { AuthenticationError } from "../services/errors.js";
import { authenticate } from "../services/user.js";

const router = Router();

router.post(
  "/login",
  validateBody(loginSchema),
  async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { email, password } = req.body as { email: string; password: string };
      const user = await authenticate(prisma, email, password);

      if (user === null) {
        throw new AuthenticationError("Invalid email or password");
      }

      const token = createToken(user.id);
      const response: TokenResponse = {
        accessToken: token,
        tokenType: "bearer",
      };

      res.json(response);
    } catch (error) {
      next(error);
    }
  }
);

export { router as authRouter };
