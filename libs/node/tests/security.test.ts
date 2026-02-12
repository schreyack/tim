import { describe, it, expect } from "vitest";
import {
  hashPassword,
  verifyPassword,
  createAccessToken,
  verifyToken,
  verifyTokenWithFallback,
  generateSecureToken,
  constantTimeCompare,
  TokenValidationError,
} from "../src/security.js";

describe("hashPassword", () => {
  it("returns bcrypt hash", async () => {
    const password = "secure_password_123";
    const hashed = await hashPassword(password);

    expect(hashed).toMatch(/^\$2[aby]\$/);
    expect(hashed.length).toBe(60);
  });

  it("should produce different hashes for same password", async () => {
    const password = "secure_password_123";
    const hash1 = await hashPassword(password);
    const hash2 = await hashPassword(password);

    expect(hash1).not.toBe(hash2);
  });
});

describe("verifyPassword", () => {
  it("returns true for correct password", async () => {
    const password = "secure_password_123";
    const hashed = await hashPassword(password);

    const result = await verifyPassword(password, hashed);
    expect(result).toBe(true);
  });

  it("returns false for incorrect password", async () => {
    const password = "secure_password_123";
    const hashed = await hashPassword(password);

    const result = await verifyPassword("wrong_password", hashed);
    expect(result).toBe(false);
  });

  it("returns false for empty password", async () => {
    const hashed = await hashPassword("secure_password_123");

    const result = await verifyPassword("", hashed);
    expect(result).toBe(false);
  });
});

describe("createAccessToken", () => {
  const secret = "a".repeat(32);

  it("creates valid JWT token", () => {
    const token = createAccessToken({ sub: "user123" }, secret);

    expect(token.split(".")).toHaveLength(3);
  });

  it("should include payload data in token", () => {
    const token = createAccessToken({ sub: "user123", role: "admin" }, secret);

    const payload = verifyToken(token, secret);
    expect(payload.sub).toBe("user123");
    expect(payload.role).toBe("admin");
  });
});

describe("verifyToken", () => {
  const secret = "a".repeat(32);

  it("should verify valid token", () => {
    const token = createAccessToken({ sub: "user123" }, secret);
    const payload = verifyToken(token, secret);

    expect(payload.sub).toBe("user123");
  });

  it("throws for wrong secret", () => {
    const token = createAccessToken({ sub: "user123" }, secret);

    expect(() => verifyToken(token, "wrong_secret".repeat(3))).toThrow(TokenValidationError);
  });

  it("throws for expired token", () => {
    const token = createAccessToken({ sub: "user123" }, secret, -1);

    expect(() => verifyToken(token, secret)).toThrow("expired");
  });

  it("throws for malformed token", () => {
    expect(() => verifyToken("not.a.valid.jwt", secret)).toThrow(TokenValidationError);
  });
});

describe("verifyTokenWithFallback", () => {
  const primarySecret = "primary_secret_" + "a".repeat(20);
  const fallbackSecret = "fallback_secret" + "b".repeat(20);

  it("verifies with primary secret", () => {
    const token = createAccessToken({ sub: "user123" }, primarySecret);
    const payload = verifyTokenWithFallback(token, primarySecret);

    expect(payload.sub).toBe("user123");
  });

  it("should fall back to secondary secret", () => {
    const token = createAccessToken({ sub: "user123" }, fallbackSecret);
    const payload = verifyTokenWithFallback(token, primarySecret, fallbackSecret);

    expect(payload.sub).toBe("user123");
  });

  it("throws when both secrets fail", () => {
    const token = createAccessToken({ sub: "user123" }, "other_" + "c".repeat(28));

    expect(() => verifyTokenWithFallback(token, primarySecret, fallbackSecret)).toThrow(
      TokenValidationError
    );
  });

  it("throws when no fallback and primary fails", () => {
    const token = createAccessToken({ sub: "user123" }, "other_" + "c".repeat(28));

    expect(() => verifyTokenWithFallback(token, primarySecret)).toThrow(TokenValidationError);
  });
});

describe("generateSecureToken", () => {
  it("should generate hex string of correct length", () => {
    const token = generateSecureToken();

    expect(token).toMatch(/^[0-9a-f]+$/);
    expect(token.length).toBe(64); // 32 bytes = 64 hex chars
  });

  it("should respect custom length", () => {
    const token = generateSecureToken(16);

    expect(token.length).toBe(32); // 16 bytes = 32 hex chars
  });

  it("should generate unique tokens", () => {
    const tokens = Array.from({ length: 100 }, () => generateSecureToken());
    const unique = new Set(tokens);

    expect(unique.size).toBe(100);
  });
});

describe("constantTimeCompare", () => {
  it("returns true for equal strings", () => {
    expect(constantTimeCompare("abc123", "abc123")).toBe(true);
  });

  it("returns false for different strings", () => {
    expect(constantTimeCompare("abc123", "xyz789")).toBe(false);
  });

  it("returns false for different length strings", () => {
    expect(constantTimeCompare("short", "much_longer_string")).toBe(false);
  });

  it("returns true for empty strings", () => {
    expect(constantTimeCompare("", "")).toBe(true);
  });
});

describe("TokenValidationError", () => {
  it("should have correct name", () => {
    const error = new TokenValidationError("message");
    expect(error.name).toBe("TokenValidationError");
  });

  it("should include detail", () => {
    const error = new TokenValidationError("message", "expired");
    expect(error.detail).toBe("expired");
  });
});
