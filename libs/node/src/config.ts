/**
 * TIM Shared Configuration Module
 *
 * Provides Zod-based configuration validation for TIM Node.js projects.
 *
 * @example
 * import { createConfig, baseEnvSchema } from "@tim/lib/config";
 *
 * const envSchema = baseEnvSchema.extend({
 *   STRIPE_API_KEY: z.string().min(1),
 *   FEATURE_X_ENABLED: z.coerce.boolean().default(false),
 * });
 *
 * export const config = createConfig(envSchema);
 */

import { z } from "zod";

/**
 * Base environment schema with common TIM settings.
 * Extend this with project-specific settings.
 */
export const baseEnvSchema = z.object({
  // Required settings
  DATABASE_URL: z.string().min(1, "DATABASE_URL is required"),
  JWT_SECRET: z
    .string()
    .min(32, "JWT_SECRET must be at least 32 characters"),

  // Optional settings with defaults
  LOG_LEVEL: z
    .enum(["debug", "info", "warn", "error"])
    .default("info"),
  NODE_ENV: z
    .enum(["development", "test", "staging", "production"])
    .default("development"),
  PORT: z.coerce.number().int().positive().default(3000),

  // JWT settings
  JWT_ALGORITHM: z.literal("HS256").default("HS256"),
  ACCESS_TOKEN_EXPIRE_MINUTES: z.coerce.number().int().positive().default(30),
});

export type BaseEnv = z.infer<typeof baseEnvSchema>;

/**
 * Create validated configuration from environment variables.
 *
 * @param schema - Zod schema to validate against
 * @returns Validated configuration object
 * @throws Error if validation fails (with detailed error messages)
 *
 * @example
 * const config = createConfig(baseEnvSchema.extend({
 *   CUSTOM_VAR: z.string(),
 * }));
 */
export function createConfig<T extends z.ZodTypeAny>(
  schema: T
): z.infer<T> {
  const result = schema.safeParse(process.env);

  if (!result.success) {
    const formatted = result.error.issues
      .map((issue) => `  - ${issue.path.join(".")}: ${issue.message}`)
      .join("\n");

    throw new Error(
      `Environment validation failed:\n${formatted}\n\nCheck your .env file or environment variables.`
    );
  }

  return result.data as z.infer<T>;
}

/**
 * Check if running in production environment.
 */
export function isProduction(config: BaseEnv): boolean {
  return config.NODE_ENV === "production";
}

/**
 * Check if running in development environment.
 */
export function isDevelopment(config: BaseEnv): boolean {
  return config.NODE_ENV === "development";
}

/**
 * Check if running in test environment.
 */
export function isTest(config: BaseEnv): boolean {
  return config.NODE_ENV === "test";
}

/**
 * Mask a secret value for safe logging.
 *
 * @param value - Secret value to mask
 * @returns Masked value showing first and last 4 characters
 */
export function maskSecret(value: string): string {
  if (value.length <= 8) {
    return "****";
  }
  return `${value.slice(0, 4)}...${value.slice(-4)}`;
}

/**
 * Get config values safe for logging (secrets masked).
 */
export function toSafeConfig(config: BaseEnv): Record<string, unknown> {
  const sensitiveKeys = new Set(["DATABASE_URL", "JWT_SECRET"]);
  const result: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(config)) {
    if (sensitiveKeys.has(key) && typeof value === "string") {
      result[key] = maskSecret(value);
    } else {
      result[key] = value;
    }
  }

  return result;
}

/**
 * Validate production configuration.
 * Throws if configuration is unsafe for production.
 */
export function validateProductionConfig(config: BaseEnv): void {
  if (!isProduction(config)) {
    return;
  }

  const errors: string[] = [];

  // Check for localhost database in production
  if (
    config.DATABASE_URL.includes("localhost") ||
    config.DATABASE_URL.includes("127.0.0.1")
  ) {
    errors.push("DATABASE_URL cannot be localhost in production");
  }

  // Check for weak JWT secret patterns
  const weakPatterns = ["secret", "password", "12345", "test"];
  const lowerSecret = config.JWT_SECRET.toLowerCase();
  for (const pattern of weakPatterns) {
    if (lowerSecret.includes(pattern)) {
      errors.push(`JWT_SECRET appears weak (contains "${pattern}")`);
      break;
    }
  }

  if (errors.length > 0) {
    throw new Error(
      `Production configuration validation failed:\n${errors.map((e) => `  - ${e}`).join("\n")}`
    );
  }
}
