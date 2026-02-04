/**
 * Database test utilities for Prisma-based testing.
 *
 * @module testing/database
 */

/**
 * Transaction rollback helper for database tests.
 *
 * Wraps test in a transaction that rolls back after completion.
 * Requires Prisma client with $transaction support.
 *
 * @param prisma - Prisma client instance
 * @param testFn - Test function to run within transaction
 */
export async function withRollback<T>(
  prisma: {
    $transaction: <R>(
      fn: (tx: unknown) => Promise<R>,
      options?: { timeout?: number }
    ) => Promise<R>;
  },
  testFn: (tx: unknown) => Promise<T>
): Promise<void> {
  try {
    await prisma.$transaction(
      async (tx) => {
        await testFn(tx);
        throw new Error("ROLLBACK");
      },
      { timeout: 30000 }
    );
  } catch (error) {
    if (error instanceof Error && error.message === "ROLLBACK") {
      return;
    }
    throw error;
  }
}

/**
 * Clean specific tables in test database.
 *
 * @param prisma - Prisma client instance
 * @param tableNames - Tables to truncate
 */
export async function cleanTables(
  prisma: {
    $executeRawUnsafe: (query: string) => Promise<number>;
  },
  tableNames: string[]
): Promise<void> {
  for (const table of tableNames) {
    // Validate table name to prevent SQL injection
    if (!/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(table)) {
      throw new Error(`Invalid table name: ${table}`);
    }
    await prisma.$executeRawUnsafe(`TRUNCATE TABLE "${table}" RESTART IDENTITY CASCADE`);
  }
}
