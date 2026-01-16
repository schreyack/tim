/**
 * Tests for validation schemas - test_what_when_then naming.
 */

import { describe, it, expect } from "vitest";

import {
  userCreateSchema,
  loginSchema,
  userUpdateSchema,
} from "../../src/schemas/user.js";

describe("userCreateSchema", () => {
  it("should_validate_user_create_with_valid_data_succeeds", () => {
    const data = {
      email: "test@example.com",
      password: "secure_password_123",
    };

    const result = userCreateSchema.safeParse(data);

    expect(result.success).toBe(true);
  });

  it("should_validate_user_create_with_invalid_email_fails", () => {
    const data = {
      email: "not-an-email",
      password: "secure_password_123",
    };

    const result = userCreateSchema.safeParse(data);

    expect(result.success).toBe(false);
  });

  it("should_validate_user_create_with_short_password_fails", () => {
    const data = {
      email: "test@example.com",
      password: "short",
    };

    const result = userCreateSchema.safeParse(data);

    expect(result.success).toBe(false);
  });

  it("should_validate_user_create_with_missing_email_fails", () => {
    const data = {
      password: "secure_password_123",
    };

    const result = userCreateSchema.safeParse(data);

    expect(result.success).toBe(false);
  });
});

describe("loginSchema", () => {
  it("should_validate_login_with_valid_data_succeeds", () => {
    const data = {
      email: "test@example.com",
      password: "any_password",
    };

    const result = loginSchema.safeParse(data);

    expect(result.success).toBe(true);
  });

  it("should_validate_login_with_invalid_email_fails", () => {
    const data = {
      email: "not-an-email",
      password: "any_password",
    };

    const result = loginSchema.safeParse(data);

    expect(result.success).toBe(false);
  });

  it("should_validate_login_with_empty_password_fails", () => {
    const data = {
      email: "test@example.com",
      password: "",
    };

    const result = loginSchema.safeParse(data);

    expect(result.success).toBe(false);
  });
});

describe("userUpdateSchema", () => {
  it("should_validate_user_update_with_email_only_succeeds", () => {
    const data = {
      email: "new@example.com",
    };

    const result = userUpdateSchema.safeParse(data);

    expect(result.success).toBe(true);
  });

  it("should_validate_user_update_with_empty_object_succeeds", () => {
    const data = {};

    const result = userUpdateSchema.safeParse(data);

    expect(result.success).toBe(true);
  });

  it("should_validate_user_update_with_invalid_email_fails", () => {
    const data = {
      email: "not-an-email",
    };

    const result = userUpdateSchema.safeParse(data);

    expect(result.success).toBe(false);
  });
});
