import { describe, it, expect, vi } from "vitest";
import { withRollback, cleanTables } from "../src/testing.js";

describe("withRollback", () => {
  it("should roll back transaction after test", async () => {
    const mockTx = { query: vi.fn() };
    const mockPrisma = {
      $transaction: vi.fn(async (fn: (tx: unknown) => Promise<void>) => {
        await fn(mockTx);
      }),
    };

    await withRollback(mockPrisma, async (tx) => {
      expect(tx).toBe(mockTx);
    });
  });

  it("re-throws non-rollback errors", async () => {
    const mockPrisma = {
      $transaction: vi.fn(async () => {
        throw new Error("Real error");
      }),
    };

    await expect(
      withRollback(mockPrisma, async () => {
        /* empty */
      })
    ).rejects.toThrow("Real error");
  });
});

describe("cleanTables", () => {
  it("should truncate specified tables", async () => {
    const mockPrisma = {
      $executeRawUnsafe: vi.fn().mockResolvedValue(0),
    };

    await cleanTables(mockPrisma, ["users", "posts"]);

    expect(mockPrisma.$executeRawUnsafe).toHaveBeenCalledTimes(2);
    expect(mockPrisma.$executeRawUnsafe).toHaveBeenCalledWith(
      'TRUNCATE TABLE "users" RESTART IDENTITY CASCADE'
    );
    expect(mockPrisma.$executeRawUnsafe).toHaveBeenCalledWith(
      'TRUNCATE TABLE "posts" RESTART IDENTITY CASCADE'
    );
  });

  it("should reject invalid table names", async () => {
    const mockPrisma = {
      $executeRawUnsafe: vi.fn(),
    };

    await expect(cleanTables(mockPrisma, ["users; DROP TABLE"])).rejects.toThrow(
      "Invalid table name"
    );
  });
});
