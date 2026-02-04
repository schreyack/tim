import { describe, it, expect } from "vitest";
import { sleep, waitFor, createMock, createSequenceMock } from "../src/testing.js";

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
    await expect(waitFor(() => false, { timeout: 50, interval: 10 })).rejects.toThrow(
      "Condition not met within 50ms"
    );
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
    const mock = createSequenceMock(["success", new Error("failure"), "recovered"]);

    expect(await mock()).toBe("success");
    await expect(mock()).rejects.toThrow("failure");
    expect(await mock()).toBe("recovered");
  });
});
