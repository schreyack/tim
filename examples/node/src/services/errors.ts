/**
 * Custom error classes for the application.
 */

export class AppError extends Error {
  constructor(
    message: string,
    public readonly statusCode: number
  ) {
    super(message);
    this.name = "AppError";
  }
}

export class AuthenticationError extends AppError {
  constructor(message = "Authentication failed") {
    super(message, 401);
    this.name = "AuthenticationError";
  }
}

export class UserNotFoundError extends AppError {
  constructor(identifier: string) {
    super(`User not found: ${identifier}`);
    this.name = "UserNotFoundError";
    this.statusCode = 404;
  }
}

export class UserExistsError extends AppError {
  constructor(email: string) {
    super(`User already exists: ${email}`);
    this.name = "UserExistsError";
    this.statusCode = 409;
  }
}

export class ValidationError extends AppError {
  constructor(
    message: string,
    public readonly errors: Array<{ path: string; message: string }>
  ) {
    super(message);
    this.name = "ValidationError";
    this.statusCode = 422;
  }
}
