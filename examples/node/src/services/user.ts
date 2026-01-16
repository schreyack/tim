/**
 * User service for CRUD operations.
 */

import type { PrismaClient, User } from "@prisma/client";

import type { UserCreate } from "../schemas/user.js";
import { hashPassword, verifyPassword } from "./auth.js";
import { UserExistsError, UserNotFoundError } from "./errors.js";

export async function createUser(
  prisma: PrismaClient,
  data: UserCreate
): Promise<User> {
  const existing = await prisma.user.findUnique({
    where: { email: data.email },
  });

  if (existing !== null) {
    throw new UserExistsError(data.email);
  }

  const hashedPassword = await hashPassword(data.password);

  return prisma.user.create({
    data: {
      email: data.email,
      hashedPassword,
    },
  });
}

export async function getUserById(
  prisma: PrismaClient,
  id: string
): Promise<User | null> {
  return prisma.user.findUnique({ where: { id } });
}

export async function getUserByEmail(
  prisma: PrismaClient,
  email: string
): Promise<User | null> {
  return prisma.user.findUnique({ where: { email } });
}

export async function authenticate(
  prisma: PrismaClient,
  email: string,
  password: string
): Promise<User | null> {
  const user = await prisma.user.findUnique({ where: { email } });

  if (user === null) {
    return null;
  }

  const valid = await verifyPassword(password, user.hashedPassword);

  if (!valid) {
    return null;
  }

  return user;
}

export async function deleteUser(
  prisma: PrismaClient,
  id: string
): Promise<void> {
  const user = await prisma.user.findUnique({ where: { id } });

  if (user === null) {
    throw new UserNotFoundError(id);
  }

  await prisma.user.delete({ where: { id } });
}
