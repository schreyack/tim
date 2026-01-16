/**
 * Application configuration using environment variables.
 * All config is validated with Zod at startup.
 */

import { z } from "zod";

const configSchema = z.object({
  databaseUrl: z.string().min(1),
  jwtSecret: z.string().min(32),
  jwtExpiryMinutes: z.number().int().positive().default(30),
  environment: z
    .enum(["development", "staging", "production"])
    .default("development"),
  port: z.number().int().positive().default(3000),
});

export type Config = z.infer<typeof configSchema>;

function loadConfig(): Config {
  const result = configSchema.safeParse({
    databaseUrl: process.env["DATABASE_URL"],
    jwtSecret: process.env["JWT_SECRET"],
    jwtExpiryMinutes: process.env["JWT_EXPIRY_MINUTES"]
      ? parseInt(process.env["JWT_EXPIRY_MINUTES"], 10)
      : undefined,
    environment: process.env["NODE_ENV"],
    port: process.env["PORT"] ? parseInt(process.env["PORT"], 10) : undefined,
  });

  if (!result.success) {
    const errors = result.error.errors
      .map((e) => `${e.path.join(".")}: ${e.message}`)
      .join(", ");
    throw new Error(`Configuration validation failed: ${errors}`);
  }

  return result.data;
}

export const config = loadConfig();
