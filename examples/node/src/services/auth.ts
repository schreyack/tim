/**
 * Authentication service for JWT and password handling.
 */

import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";

import { config } from "../config.js";
import { AuthenticationError } from "./errors.js";

const SALT_ROUNDS = 12;

export interface TokenPayload {
  sub: string;
  iat: number;
  exp: number;
}

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, SALT_ROUNDS);
}

export async function verifyPassword(
  password: string,
  hash: string
): Promise<boolean> {
  return bcrypt.compare(password, hash);
}

export function createToken(userId: string): string {
  const expiresInSeconds = config.jwtExpiryMinutes * 60;

  return jwt.sign({ sub: userId }, config.jwtSecret, {
    expiresIn: expiresInSeconds,
  });
}

export function verifyToken(token: string): string {
  try {
    const payload = jwt.verify(token, config.jwtSecret) as TokenPayload;
    return payload.sub;
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      throw new AuthenticationError("Token has expired");
    }
    if (error instanceof jwt.JsonWebTokenError) {
      throw new AuthenticationError("Invalid token");
    }
    throw new AuthenticationError("Token validation failed");
  }
}
