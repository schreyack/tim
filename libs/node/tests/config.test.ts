import { describe, it, expect, beforeEach, afterEach } from "vitest";
import {
  baseEnvSchema,
  createConfig,
  isProduction,
  isDevelopment,
  isTest,
  maskSecret,
  toSafeConfig,
  validateProductionConfig,
  type BaseEnv,
} from "../src/config.js";

describe("baseEnvSchema", () => {
  it("should validate valid configuration", () => {
    const result = baseEnvSchema.safeParse({
      DATABASE_URL: "postgresql://localhost:5432/test",
      JWT_SECRET: "a".repeat(32),
    });

    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.data.LOG_LEVEL).toBe("info");
      expect(result.data.NODE_ENV).toBe("development");
      expect(result.data.PORT).toBe(3000);
    }
  });

  it("should reject missing DATABASE_URL", () => {
    const result = baseEnvSchema.safeParse({
      JWT_SECRET: "a".repeat(32),
    });

    expect(result.success).toBe(false);
  });

  it("should reject short JWT_SECRET", () => {
    const result = baseEnvSchema.safeParse({
      DATABASE_URL: "postgresql://localhost:5432/test",
      JWT_SECRET: "short",
    });

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0].message).toContain("32 characters");
    }
  });

  it("should reject invalid LOG_LEVEL", () => {
    const result = baseEnvSchema.safeParse({
      DATABASE_URL: "postgresql://localhost:5432/test",
      JWT_SECRET: "a".repeat(32),
      LOG_LEVEL: "invalid",
    });

    expect(result.success).toBe(false);
  });
});

describe("createConfig", () => {
  const originalEnv = process.env;

  beforeEach(() => {
    process.env = { ...originalEnv };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it("creates config from valid environment", () => {
    process.env.DATABASE_URL = "postgresql://localhost:5432/test";
    process.env.JWT_SECRET = "a".repeat(32);

    const config = createConfig(baseEnvSchema);

    expect(config.DATABASE_URL).toBe("postgresql://localhost:5432/test");
    expect(config.JWT_SECRET).toBe("a".repeat(32));
  });

  it("throws with formatted error for invalid config", () => {
    process.env.DATABASE_URL = "postgresql://localhost:5432/test";
    // Missing JWT_SECRET

    expect(() => createConfig(baseEnvSchema)).toThrow("Environment validation failed");
  });
});

describe("environment checks", () => {
  it("isProduction returns true for production", () => {
    const config: BaseEnv = {
      DATABASE_URL: "postgresql://prod.example.com:5432/db",
      JWT_SECRET: "a".repeat(32),
      LOG_LEVEL: "info",
      NODE_ENV: "production",
      PORT: 3000,
      JWT_ALGORITHM: "HS256",
      ACCESS_TOKEN_EXPIRE_MINUTES: 30,
    };

    expect(isProduction(config)).toBe(true);
    expect(isDevelopment(config)).toBe(false);
  });

  it("isDevelopment returns true for development", () => {
    const config: BaseEnv = {
      DATABASE_URL: "postgresql://localhost:5432/test",
      JWT_SECRET: "a".repeat(32),
      LOG_LEVEL: "info",
      NODE_ENV: "development",
      PORT: 3000,
      JWT_ALGORITHM: "HS256",
      ACCESS_TOKEN_EXPIRE_MINUTES: 30,
    };

    expect(isDevelopment(config)).toBe(true);
    expect(isProduction(config)).toBe(false);
  });

  it("isTest returns true for test", () => {
    const config: BaseEnv = {
      DATABASE_URL: "postgresql://localhost:5432/test",
      JWT_SECRET: "a".repeat(32),
      LOG_LEVEL: "info",
      NODE_ENV: "test",
      PORT: 3000,
      JWT_ALGORITHM: "HS256",
      ACCESS_TOKEN_EXPIRE_MINUTES: 30,
    };

    expect(isTest(config)).toBe(true);
  });
});

describe("maskSecret", () => {
  it("should mask long secrets showing first and last 4 chars", () => {
    const result = maskSecret("abcd1234efgh5678");
    expect(result).toBe("abcd...5678");
  });

  it("should fully mask short secrets", () => {
    const result = maskSecret("short");
    expect(result).toBe("****");
  });

  it("should fully mask secrets of exactly 8 chars", () => {
    const result = maskSecret("12345678");
    expect(result).toBe("****");
  });
});

describe("toSafeConfig", () => {
  it("should mask sensitive fields", () => {
    const config: BaseEnv = {
      DATABASE_URL: "postgresql://user:password@localhost:5432/db",
      JWT_SECRET: "super_secret_key_that_is_long_enough",
      LOG_LEVEL: "info",
      NODE_ENV: "development",
      PORT: 3000,
      JWT_ALGORITHM: "HS256",
      ACCESS_TOKEN_EXPIRE_MINUTES: 30,
    };

    const safe = toSafeConfig(config);

    expect(safe.DATABASE_URL).toContain("...");
    expect(safe.JWT_SECRET).toContain("...");
    expect(safe.LOG_LEVEL).toBe("info");
    expect(safe.PORT).toBe(3000);
  });
});

describe("validateProductionConfig", () => {
  it("should pass for valid production config", () => {
    const config: BaseEnv = {
      DATABASE_URL: "postgresql://prod.example.com:5432/db",
      JWT_SECRET: "very_long_random_string_for_production_use",
      LOG_LEVEL: "info",
      NODE_ENV: "production",
      PORT: 3000,
      JWT_ALGORITHM: "HS256",
      ACCESS_TOKEN_EXPIRE_MINUTES: 30,
    };

    expect(() => validateProductionConfig(config)).not.toThrow();
  });

  it("should not validate non-production configs", () => {
    const config: BaseEnv = {
      DATABASE_URL: "postgresql://localhost:5432/db",
      JWT_SECRET: "test_secret_that_is_long_enough_here",
      LOG_LEVEL: "info",
      NODE_ENV: "development",
      PORT: 3000,
      JWT_ALGORITHM: "HS256",
      ACCESS_TOKEN_EXPIRE_MINUTES: 30,
    };

    // Should not throw even with localhost DB
    expect(() => validateProductionConfig(config)).not.toThrow();
  });

  it("should reject localhost DATABASE_URL in production", () => {
    const config: BaseEnv = {
      DATABASE_URL: "postgresql://localhost:5432/db",
      JWT_SECRET: "very_long_random_string_for_production_use",
      LOG_LEVEL: "info",
      NODE_ENV: "production",
      PORT: 3000,
      JWT_ALGORITHM: "HS256",
      ACCESS_TOKEN_EXPIRE_MINUTES: 30,
    };

    expect(() => validateProductionConfig(config)).toThrow("localhost");
  });

  it("should reject 127.0.0.1 DATABASE_URL in production", () => {
    const config: BaseEnv = {
      DATABASE_URL: "postgresql://127.0.0.1:5432/db",
      JWT_SECRET: "very_long_random_string_for_production_use",
      LOG_LEVEL: "info",
      NODE_ENV: "production",
      PORT: 3000,
      JWT_ALGORITHM: "HS256",
      ACCESS_TOKEN_EXPIRE_MINUTES: 30,
    };

    expect(() => validateProductionConfig(config)).toThrow("localhost");
  });

  it("should reject weak JWT_SECRET patterns in production", () => {
    const config: BaseEnv = {
      DATABASE_URL: "postgresql://prod.example.com:5432/db",
      JWT_SECRET: "my_secret_key_that_contains_secret_word",
      LOG_LEVEL: "info",
      NODE_ENV: "production",
      PORT: 3000,
      JWT_ALGORITHM: "HS256",
      ACCESS_TOKEN_EXPIRE_MINUTES: 30,
    };

    expect(() => validateProductionConfig(config)).toThrow("appears weak");
  });
});
