/**
 * User CRUD endpoints.
 */

import { Router, type Request, type Response, type NextFunction } from "express";

import { prisma } from "../db/client.js";
import { validateBody } from "../middleware/validation.js";
import { userCreateSchema, type UserResponse } from "../schemas/user.js";
import { UserNotFoundError } from "../services/errors.js";
import { createUser, getUserById, deleteUser } from "../services/user.js";

const router = Router();

function toUserResponse(user: {
  id: string;
  email: string;
  isActive: boolean;
  createdAt: Date;
  updatedAt: Date;
}): UserResponse {
  return {
    id: user.id,
    email: user.email,
    isActive: user.isActive,
    createdAt: user.createdAt,
    updatedAt: user.updatedAt,
  };
}

router.post(
  "/",
  validateBody(userCreateSchema),
  async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = req.body as { email: string; password: string };
      const user = await createUser(prisma, data);
      res.status(201).json(toUserResponse(user));
    } catch (error) {
      next(error);
    }
  }
);

router.get(
  "/:id",
  async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const user = await getUserById(prisma, req.params["id"] ?? "");

      if (user === null) {
        throw new UserNotFoundError(req.params["id"] ?? "unknown");
      }

      res.json(toUserResponse(user));
    } catch (error) {
      next(error);
    }
  }
);

router.delete(
  "/:id",
  async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      await deleteUser(prisma, req.params["id"] ?? "");
      res.status(204).send();
    } catch (error) {
      next(error);
    }
  }
);

export { router as usersRouter };
