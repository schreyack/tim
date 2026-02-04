import { describe, it, expect, beforeEach } from "vitest";
import { createMockConfig, UserFactory, TestDataFactory } from "../src/testing.js";

describe("createMockConfig", () => {
  it("should return default test config when called without arguments", () => {
    const config = createMockConfig();

    expect(config.DATABASE_URL).toContain("test");
    expect(config.JWT_SECRET).toBeDefined();
    expect(config.ENVIRONMENT).toBe("test");
    expect(config.LOG_LEVEL).toBe("silent");
  });

  it("should apply overrides when provided", () => {
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

  it("should create unique users when called multiple times", () => {
    const user1 = UserFactory.create();
    const user2 = UserFactory.create();

    expect(user1.id).not.toBe(user2.id);
    expect(user1.email).not.toBe(user2.email);
  });

  it("should apply overrides when provided", () => {
    const user = UserFactory.create({ role: "admin", isActive: false });

    expect(user.role).toBe("admin");
    expect(user.isActive).toBe(false);
    expect(user.email).toContain("@example.com");
  });

  it("should create multiple users when using createMany", () => {
    const users = UserFactory.createMany(3);

    expect(users).toHaveLength(3);
    expect(new Set(users.map((u) => u.id)).size).toBe(3);
  });

  it("should apply overrides to all users when using createMany with overrides", () => {
    const users = UserFactory.createMany(2, { role: "moderator" });

    expect(users[0].role).toBe("moderator");
    expect(users[1].role).toBe("moderator");
  });

  it("should reset counter when reset is called", () => {
    const user1 = UserFactory.create();
    UserFactory.reset();
    const user2 = UserFactory.create();

    expect(user1.id).toBe(user2.id);
  });
});

describe("TestDataFactory", () => {
  it("should create data with factory function when called", () => {
    const factory = new TestDataFactory((n) => ({
      id: `item-${n.toString()}`,
      name: `Item ${n.toString()}`,
    }));

    const item = factory.create();

    expect(item.id).toBe("item-1");
    expect(item.name).toBe("Item 1");
  });

  it("should apply overrides when provided", () => {
    const factory = new TestDataFactory((n) => ({
      id: `item-${n.toString()}`,
      name: `Item ${n.toString()}`,
    }));

    const item = factory.create({ name: "Custom Name" });

    expect(item.id).toBe("item-1");
    expect(item.name).toBe("Custom Name");
  });

  it("should create many items with unique values when using createMany", () => {
    const factory = new TestDataFactory((n) => ({ id: n }));

    const items = factory.createMany(3);

    expect(items.map((i) => i.id)).toEqual([1, 2, 3]);
  });

  it("should reset counter when reset is called", () => {
    const factory = new TestDataFactory((n) => ({ id: n }));

    factory.create();
    factory.reset();
    const item = factory.create();

    expect(item.id).toBe(1);
  });
});
