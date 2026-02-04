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
export function createMockConfig<T extends Record<string, unknown>>(overrides: Partial<T> = {}): T {
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
 * User test data type.
 */
export interface TestUser {
  id: string;
  email: string;
  password: string;
  name: string;
  role: string;
  isActive: boolean;
}

/**
 * User factory interface.
 */
interface UserFactoryMethods {
  create(overrides?: Partial<TestUser>): TestUser;
  createMany(count: number, overrides?: Partial<Pick<TestUser, "role" | "isActive">>): TestUser[];
  reset(): void;
}

/**
 * User factory for creating test user data.
 */
function createUserFactory(): UserFactoryMethods {
  let counter = 0;

  return {
    /**
     * Create a test user object.
     *
     * @param overrides - Values to override
     * @returns Test user data
     */
    create(overrides: Partial<TestUser> = {}): TestUser {
      counter++;
      const n = counter;

      return {
        id: `user-${n.toString()}`,
        email: `testuser${n.toString()}@example.com`,
        password: `password${n.toString()}`, // pragma: allowlist secret
        name: `Test User ${n.toString()}`,
        role: "user",
        isActive: true,
        ...overrides,
      };
    },

    /**
     * Create multiple test users.
     *
     * @param count - Number of users to create
     * @param overrides - Values to override for all users
     * @returns Array of test user data
     */
    createMany(
      count: number,
      overrides: Partial<Pick<TestUser, "role" | "isActive">> = {}
    ): TestUser[] {
      return Array.from({ length: count }, () => this.create(overrides));
    },

    /**
     * Reset the counter (call in beforeEach/afterEach).
     */
    reset(): void {
      counter = 0;
    },
  };
}

export const UserFactory = createUserFactory();

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
