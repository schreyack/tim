/**
 * Test data factories for creating mock data.
 *
 * @module testing/factories
 */

/**
 * Test configuration override helper.
 *
 * Creates config values suitable for testing without real credentials.
 *
 * @param overrides - Values to override
 * @returns Test configuration object
 */
export function createMockConfig<T extends Record<string, unknown>>(
  overrides: Partial<T> = {}
): T {
  const defaults = {
    DATABASE_URL: "postgresql://test:test@localhost:5432/test_db", // pragma: allowlist secret
    JWT_SECRET: "test-secret-key-minimum-32-characters-long", // pragma: allowlist secret
    JWT_EXPIRY_MINUTES: 30,
    ENVIRONMENT: "test",
    LOG_LEVEL: "silent",
    PORT: 0, // Random available port
  };

  return { ...defaults, ...overrides } as unknown as T;
}

/**
 * User factory for creating test user data.
 */
export class UserFactory {
  private static counter = 0;

  /**
   * Create a test user object.
   *
   * @param overrides - Values to override
   * @returns Test user data
   */
  static create(
    overrides: Partial<{
      id: string;
      email: string;
      password: string;
      name: string;
      role: string;
      isActive: boolean;
    }> = {}
  ): {
    id: string;
    email: string;
    password: string;
    name: string;
    role: string;
    isActive: boolean;
  } {
    UserFactory.counter++;
    const n = UserFactory.counter;

    return {
      id: `user-${n}`,
      email: `testuser${n}@example.com`,
      password: `password${n}`, // pragma: allowlist secret
      name: `Test User ${n}`,
      role: "user",
      isActive: true,
      ...overrides,
    };
  }

  /**
   * Create multiple test users.
   *
   * @param count - Number of users to create
   * @param overrides - Values to override for all users
   * @returns Array of test user data
   */
  static createMany(
    count: number,
    overrides: Partial<{
      role: string;
      isActive: boolean;
    }> = {}
  ): Array<{
    id: string;
    email: string;
    password: string;
    name: string;
    role: string;
    isActive: boolean;
  }> {
    return Array.from({ length: count }, () => UserFactory.create(overrides));
  }

  /**
   * Reset the counter (call in beforeEach/afterEach).
   */
  static reset(): void {
    UserFactory.counter = 0;
  }
}

/**
 * Generic factory for creating test data.
 */
export class TestDataFactory<T extends Record<string, unknown>> {
  private counter = 0;
  private readonly defaultsFactory: (n: number) => T;

  constructor(defaultsFactory: (n: number) => T) {
    this.defaultsFactory = defaultsFactory;
  }

  /**
   * Create a single test object.
   */
  create(overrides: Partial<T> = {}): T {
    this.counter++;
    return { ...this.defaultsFactory(this.counter), ...overrides };
  }

  /**
   * Create multiple test objects.
   */
  createMany(count: number, overrides: Partial<T> = {}): T[] {
    return Array.from({ length: count }, () => this.create(overrides));
  }

  /**
   * Reset the counter.
   */
  reset(): void {
    this.counter = 0;
  }
}
