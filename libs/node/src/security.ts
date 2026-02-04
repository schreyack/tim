/**
 * TIM Shared Security Module
 *
 * Provides secure password hashing and JWT token handling.
 *
 * NEVER roll your own crypto. Use these helpers.
 *
 * @example
 * import { hashPassword, verifyPassword, createAccessToken } from "@tim/lib/security";
 *
 * const hashed = await hashPassword("user_password");
 * const isValid = await verifyPassword("user_password", hashed);
 *
 * const token = createAccessToken({ sub: userId }, secret, 30);
 */

import bcrypt from "bcrypt";
import { randomBytes, timingSafeEqual } from "crypto";
import jwt from "jsonwebtoken";

const SALT_ROUNDS = 12;

/**
 * Hash a password using bcrypt.
 *
 * @param password - Plain text password to hash
 * @returns Promise resolving to hashed password string
 */
export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, SALT_ROUNDS);
}

/**
 * Verify a password against a hash.
 *
 * Uses constant-time comparison to prevent timing attacks.
 *
 * @param plainPassword - Plain text password to verify
 * @param hashedPassword - Previously hashed password
 * @returns Promise resolving to true if password matches
 */
export async function verifyPassword(
  plainPassword: string,
  hashedPassword: string
): Promise<boolean> {
  return bcrypt.compare(plainPassword, hashedPassword);
}

/**
 * Token payload type.
 */
export interface TokenPayload {
  sub: string;
  [key: string]: unknown;
}

/**
 * Create a JWT access token.
 *
 * @param data - Payload data to encode (must include "sub")
 * @param secret - Secret key for signing (min 32 chars recommended)
 * @param expiresInMinutes - Token expiration time in minutes
 * @returns Encoded JWT token string
 */
export function createAccessToken(
  data: TokenPayload,
  secret: string,
  expiresInMinutes = 30
): string {
  const expiresInSeconds = expiresInMinutes * 60;
  return jwt.sign(data, secret, {
    algorithm: "HS256",
    expiresIn: expiresInSeconds,
  });
}

/**
 * Token validation error.
 */
export class TokenValidationError extends Error {
  constructor(
    message: string,
    public readonly detail?: string
  ) {
    super(message);
    this.name = "TokenValidationError";
  }
}

/**
 * Verify and decode a JWT token.
 *
 * @param token - JWT token string to verify
 * @param secret - Secret key used for signing
 * @returns Decoded token payload
 * @throws TokenValidationError if token is invalid or expired
 */
export function verifyToken(token: string, secret: string): TokenPayload {
  try {
    const payload = jwt.verify(token, secret, {
      algorithms: ["HS256"],
    }) as TokenPayload;
    return payload;
  } catch (error) {
    if (error instanceof jwt.TokenExpiredError) {
      throw new TokenValidationError("Token has expired", "expired");
    }
    if (error instanceof jwt.JsonWebTokenError) {
      throw new TokenValidationError("Invalid token", error.message);
    }
    throw new TokenValidationError("Token verification failed");
  }
}

/**
 * Verify token with fallback to previous secret (for key rotation).
 *
 * @param token - JWT token string to verify
 * @param primarySecret - Current secret key
 * @param fallbackSecret - Previous secret key (during rotation)
 * @returns Decoded token payload
 * @throws TokenValidationError if token is invalid with both secrets
 */
export function verifyTokenWithFallback(
  token: string,
  primarySecret: string,
  fallbackSecret?: string
): TokenPayload {
  try {
    return verifyToken(token, primarySecret);
  } catch (error) {
    if (fallbackSecret !== undefined) {
      return verifyToken(token, fallbackSecret);
    }
    throw error;
  }
}

/**
 * Generate a cryptographically secure random token.
 *
 * @param length - Number of random bytes (output will be 2x this in hex)
 * @returns Hex-encoded random token string
 */
export function generateSecureToken(length = 32): string {
  return randomBytes(length).toString("hex");
}

/**
 * Compare two strings in constant time.
 * Prevents timing attacks when comparing sensitive values.
 *
 * @param a - First string
 * @param b - Second string
 * @returns True if strings are equal
 */
export function constantTimeCompare(a: string, b: string): boolean {
  const bufA = Buffer.from(a);
  const bufB = Buffer.from(b);

  if (bufA.length !== bufB.length) {
    return false;
  }

  return timingSafeEqual(bufA, bufB);
}
