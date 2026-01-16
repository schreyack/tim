import { describe, it, expect, beforeEach, vi } from "vitest";
import {
  createTestApp,
  createMockConfig,
  UserFactory,
  TestDataFactory,
  assertResponseOk,
  assertResponseCreated,
  assertResponseError,
  assertResponseContains,
  assertPaginatedResponse,
  createMockAuthMiddleware,
  createRequestCapture,
  withRollback,
  cleanTables,
  sleep,
  waitFor,
  createMock,
  createSequenceMock,
} from "../src/testing.js";
import type { Response as SupertestResponse } from "supertest";

describe("createTestApp", () => {
  it("creates an express app", () => {
    const app = createTestApp();

    expect(app).toBeDefined();
    expect(typeof app.use).toBe("function");
    expect(typeof app.get).toBe("function");
  });

  it("allows adding routes via setup function", () => {
    const app = createTestApp((app) => {
      app.get("/test", (_req, res) => {
        res.json({ ok: true });
      });
    });

    expect(app).toBeDefined();
  });
});

describe("createMockConfig", () => {
  it("returns default test config", () => {
    const config = createMockConfig();

    expect(config.DATABASE_URL).toContain("test");
    expect(config.JWT_SECRET).toBeDefined();
    expect(config.ENVIRONMENT).toBe("test");
    expect(config.LOG_LEVEL).toBe("silent");
  });

  it("allows overrides", () => {
    const config = createMockConfig({
      PORT: 8080,
      ENVIRONMENT: "staging",
    });

    expect(config.PORT).toBe(8080);
    expect(config.ENVIRONMENT).toBe("staging");
  });
});

describe("UserFactory", () => {
  beforeEach(() => {
    UserFactory.reset();
  });

  it("creates unique users", () => {
    const user1 = UserFactory.create();
    const user2 = UserFactory.create();

    expect(user1.id).not.toBe(user2.id);
    expect(user1.email).not.toBe(user2.email);
  });

  it("allows overrides", () => {
    const user = UserFactory.create({ role: "admin", isActive: false });

    expect(user.role).toBe("admin");
    expect(user.isActive).toBe(false);
    expect(user.email).toContain("@example.com");
  });

  it("creates multiple users", () => {
    const users = UserFactory.createMany(3);

    expect(users).toHaveLength(3);
    expect(new Set(users.map((u) => u.id)).size).toBe(3);
  });

  it("applies overrides to many users", () => {
    const users = UserFactory.createMany(2, { role: "moderator" });

    expect(users[0].role).toBe("moderator");
    expect(users[1].role).toBe("moderator");
  });

  it("reset clears counter", () => {
    const user1 = UserFactory.create();
    UserFactory.reset();
    const user2 = UserFactory.create();

    expect(user1.id).toBe(user2.id);
  });
});

describe("TestDataFactory", () => {
  it("creates data with factory function", () => {
    const factory = new TestDataFactory((n) => ({
      id: `item-${n}`,
      name: `Item ${n}`,
    }));

    const item = factory.create();

    expect(item.id).toBe("item-1");
    expect(item.name).toBe("Item 1");
  });

  it("allows overrides", () => {
    const factory = new TestDataFactory((n) => ({
      id: `item-${n}`,
      name: `Item ${n}`,
    }));

    const item = factory.create({ name: "Custom Name" });

    expect(item.id).toBe("item-1");
    expect(item.name).toBe("Custom Name");
  });

  it("creates many with unique values", () => {
    const factory = new TestDataFactory((n) => ({ id: n }));

    const items = factory.createMany(3);

    expect(items.map((i) => i.id)).toEqual([1, 2, 3]);
  });

  it("reset clears counter", () => {
    const factory = new TestDataFactory((n) => ({ id: n }));

    factory.create();
    factory.reset();
    const item = factory.create();

    expect(item.id).toBe(1);
  });
});

describe("assertResponseOk", () => {
  it("passes for 200 response", () => {
    const response = { status: 200, body: {} } as SupertestResponse;

    expect(() => assertResponseOk(response)).not.toThrow();
  });

  it("passes for custom expected status", () => {
    const response = { status: 204, body: {} } as SupertestResponse;

    expect(() => assertResponseOk(response, 204)).not.toThrow();
  });

  it("throws for unexpected status", () => {
    const response = { status: 400, body: { error: "Bad" } } as SupertestResponse;

    expect(() => assertResponseOk(response)).toThrow("Expected status 200, got 400");
  });
});

describe("assertResponseCreated", () => {
  it("passes for 201 response", () => {
    const response = { status: 201, body: {} } as SupertestResponse;

    expect(() => assertResponseCreated(response)).not.toThrow();
  });

  it("throws for non-201 response", () => {
    const response = { status: 200, body: {} } as SupertestResponse;

    expect(() => assertResponseCreated(response)).toThrow("Expected status 201");
  });
});

describe("assertResponseError", () => {
  it("passes for expected error status", () => {
    const response = { status: 404, body: {} } as SupertestResponse;

    expect(() => assertResponseError(response, 404)).not.toThrow();
  });

  it("checks error message when provided", () => {
    const response = {
      status: 400,
      body: { error: "Validation failed" },
    } as SupertestResponse;

    expect(() =>
      assertResponseError(response, 400, "Validation failed")
    ).not.toThrow();
  });

  it("throws for wrong message", () => {
    const response = {
      status: 400,
      body: { error: "Wrong message" },
    } as SupertestResponse;

    expect(() =>
      assertResponseError(response, 400, "Expected message")
    ).toThrow('Expected error message "Expected message"');
  });

  it("checks message field as fallback", () => {
    const response = {
      status: 400,
      body: { message: "Validation failed" },
    } as SupertestResponse;

    expect(() =>
      assertResponseError(response, 400, "Validation failed")
    ).not.toThrow();
  });
});

describe("assertResponseContains", () => {
  it("passes when all fields exist", () => {
    const response = {
      status: 200,
      body: { id: 1, name: "Test", email: "test@example.com" },
    } as SupertestResponse;

    expect(() =>
      assertResponseContains(response, ["id", "name", "email"])
    ).not.toThrow();
  });

  it("throws for missing fields", () => {
    const response = {
      status: 200,
      body: { id: 1 },
    } as SupertestResponse;

    expect(() => assertResponseContains(response, ["id", "name"])).toThrow(
      "Response missing expected fields: name"
    );
  });

  it("treats undefined values as missing", () => {
    const response = {
      status: 200,
      body: { id: 1, name: undefined },
    } as SupertestResponse;

    expect(() => assertResponseContains(response, ["id", "name"])).toThrow(
      "missing expected fields: name"
    );
  });
});

describe("assertPaginatedResponse", () => {
  it("passes for valid paginated response", () => {
    const response = {
      status: 200,
      body: { items: [1, 2, 3], total: 3, page: 1, pageSize: 10 },
    } as SupertestResponse;

    expect(() => assertPaginatedResponse(response)).not.toThrow();
  });

  it("validates item count when provided", () => {
    const response = {
      status: 200,
      body: { items: [1, 2], total: 2, page: 1, pageSize: 10 },
    } as SupertestResponse;

    expect(() => assertPaginatedResponse(response, 2)).not.toThrow();
  });

  it("throws for wrong item count", () => {
    const response = {
      status: 200,
      body: { items: [1, 2], total: 2, page: 1, pageSize: 10 },
    } as SupertestResponse;

    expect(() => assertPaginatedResponse(response, 5)).toThrow(
      "Expected 5 items, got 2"
    );
  });

  it("throws for missing pagination fields", () => {
    const response = {
      status: 200,
      body: { items: [] },
    } as SupertestResponse;

    expect(() => assertPaginatedResponse(response)).toThrow(
      "missing fields: total, page, pageSize"
    );
  });

  it("throws if items is not an array", () => {
    const response = {
      status: 200,
      body: { items: "not an array", total: 0, page: 1, pageSize: 10 },
    } as SupertestResponse;

    expect(() => assertPaginatedResponse(response)).toThrow(
      "'items' must be an array"
    );
  });
});

describe("createMockAuthMiddleware", () => {
  it("attaches user to request", () => {
    const mockUser = { id: "user-1", role: "admin" };
    const middleware = createMockAuthMiddleware(mockUser);
    const req = {} as { user?: Record<string, unknown> };
    const res = {} as Response;
    const next = vi.fn();

    middleware(req as never, res as never, next);

    expect(req.user).toEqual(mockUser);
    expect(next).toHaveBeenCalled();
  });
});

describe("createRequestCapture", () => {
  it("captures request details", () => {
    const capture = createRequestCapture();
    const req = {
      method: "POST",
      path: "/api/users",
      body: { name: "Test" },
      headers: { "content-type": "application/json" },
    };
    const res = {};
    const next = vi.fn();

    capture.middleware(req as never, res as never, next);

    expect(capture.requests).toHaveLength(1);
    expect(capture.requests[0]).toEqual({
      method: "POST",
      path: "/api/users",
      body: { name: "Test" },
      headers: { "content-type": "application/json" },
    });
  });

  it("clear removes captured requests", () => {
    const capture = createRequestCapture();
    capture.requests.push({
      method: "GET",
      path: "/test",
      body: undefined,
      headers: {},
    });

    capture.clear();

    expect(capture.requests).toHaveLength(0);
  });
});

describe("withRollback", () => {
  it("rolls back transaction after test", async () => {
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
  it("truncates specified tables", async () => {
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

  it("rejects invalid table names", async () => {
    const mockPrisma = {
      $executeRawUnsafe: vi.fn(),
    };

    await expect(cleanTables(mockPrisma, ["users; DROP TABLE"])).rejects.toThrow(
      "Invalid table name"
    );
  });
});

describe("sleep", () => {
  it("waits for specified duration", async () => {
    const start = Date.now();

    await sleep(50);

    const elapsed = Date.now() - start;
    expect(elapsed).toBeGreaterThanOrEqual(45);
  });
});

describe("waitFor", () => {
  it("resolves when condition is true", async () => {
    let count = 0;

    await waitFor(
      () => {
        count++;
        return count >= 3;
      },
      { interval: 10 }
    );

    expect(count).toBe(3);
  });

  it("times out if condition never met", async () => {
    await expect(
      waitFor(() => false, { timeout: 50, interval: 10 })
    ).rejects.toThrow("Condition not met within 50ms");
  });

  it("handles async conditions", async () => {
    let count = 0;

    await waitFor(
      async () => {
        count++;
        await sleep(5);
        return count >= 2;
      },
      { interval: 10 }
    );

    expect(count).toBe(2);
  });
});

describe("createMock", () => {
  it("tracks function calls", () => {
    const mock = createMock((x: number) => x * 2);

    const result = mock(5);

    expect(result).toBe(10);
    expect(mock.calls).toHaveLength(1);
    expect(mock.calls[0]).toEqual({ args: [5], result: 10 });
  });

  it("works without implementation", () => {
    const mock = createMock();

    mock(1, 2, 3);

    expect(mock.calls).toHaveLength(1);
    expect(mock.calls[0].args).toEqual([1, 2, 3]);
  });

  it("reset clears calls", () => {
    const mock = createMock();
    mock(1);
    mock(2);

    mock.reset();

    expect(mock.calls).toHaveLength(0);
  });
});

describe("createSequenceMock", () => {
  it("returns responses in order", async () => {
    const mock = createSequenceMock([1, 2, 3]);

    expect(await mock()).toBe(1);
    expect(await mock()).toBe(2);
    expect(await mock()).toBe(3);
  });

  it("cycles through responses", async () => {
    const mock = createSequenceMock(["a", "b"]);

    expect(await mock()).toBe("a");
    expect(await mock()).toBe("b");
    expect(await mock()).toBe("a");
  });

  it("throws errors when Error in sequence", async () => {
    const mock = createSequenceMock([
      "success",
      new Error("failure"),
      "recovered",
    ]);

    expect(await mock()).toBe("success");
    await expect(mock()).rejects.toThrow("failure");
    expect(await mock()).toBe("recovered");
  });
});
