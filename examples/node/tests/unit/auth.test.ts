/**
 * Tests for auth service - test_what_when_then naming.
 */

import { describe, it, expect, beforeAll } from "vitest";

// Mock config before importing auth service
process.env["DATABASE_URL"] = "postgresql://test:test@localhost:5432/test";
process.env["JWT_SECRET"] = "test-secret-key-minimum-32-characters";

import {
  hashPassword,
  verifyPassword,
  createToken,
  verifyToken,
} from "../../src/services/auth.js";
import { AuthenticationError } from "../../src/services/errors.js";

describe("hashPassword", () => {
  it("should_hash_password_with_valid_input_returns_hash", async () => {
    const password = "secure_password_123";
    const hashed = await hashPassword(password);

    expect(hashed).not.toBe(password);
    expect(hashed.length).toBeGreaterThan(50);
  });

  it("should_hash_password_with_same_input_returns_different_hashes", async () => {
    const password = "secure_password_123";
    const hash1 = await hashPassword(password);
    const hash2 = await hashPassword(password);

    expect(hash1).not.toBe(hash2);
  });
});

describe("verifyPassword", () => {
  it("should_verify_password_with_correct_password_returns_true", async () => {
    const password = "secure_password_123";
    const hashed = await hashPassword(password);

    const result = await verifyPassword(password, hashed);

    expect(result).toBe(true);
  });

  it("should_verify_password_with_incorrect_password_returns_false", async () => {
    const password = "secure_password_123";
    const hashed = await hashPassword(password);

    const result = await verifyPassword("wrong_password", hashed);

    expect(result).toBe(false);
  });
});

describe("createToken", () => {
  it("should_create_token_with_user_id_returns_jwt", () => {
    const userId = "user-123";
    const token = createToken(userId);

    expect(typeof token).toBe("string");
    expect(token.length).toBeGreaterThan(50);
  });
});

describe("verifyToken", () => {
  it("should_verify_token_with_valid_token_returns_user_id", () => {
    const userId = "user-123";
    const token = createToken(userId);

    const result = verifyToken(token);

    expect(result).toBe(userId);
  });

  it("should_verify_token_with_invalid_token_throws_error", () => {
    expect(() => verifyToken("invalid-token")).toThrow(AuthenticationError);
  });

  it("should_verify_token_with_tampered_token_throws_error", () => {
    const token = createToken("user-123");
    const tampered = token.slice(0, -5) + "XXXXX";

    expect(() => verifyToken(tampered)).toThrow(AuthenticationError);
  });
});
