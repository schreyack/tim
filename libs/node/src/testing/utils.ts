/**
 * Test utility functions for timing and mocking.
 *
 * @module testing/utils
 */

/**
 * Wait for a specified duration.
 *
 * @param ms - Milliseconds to wait
 */
export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Wait for a condition to be true.
 *
 * @param condition - Function that returns true when condition is met
 * @param options - Timeout and interval options
 */
export async function waitFor(
  condition: () => boolean | Promise<boolean>,
  options: { timeout?: number; interval?: number } = {}
): Promise<void> {
  const { timeout = 5000, interval = 100 } = options;
  const start = Date.now();

  while (Date.now() - start < timeout) {
    if (await condition()) {
      return;
    }
    await sleep(interval);
  }

  throw new Error(`Condition not met within ${timeout.toString()}ms`);
}

/**
 * Create a mock function that tracks calls.
 *
 * @param implementation - Optional implementation
 * @returns Mock function with call tracking
 */
export function createMock<T extends (...args: unknown[]) => unknown>(
  implementation?: T
): T & {
  calls: { args: Parameters<T>; result: ReturnType<T> }[];
  reset: () => void;
} {
  const calls: { args: Parameters<T>; result: ReturnType<T> }[] = [];

  const mock = ((...args: Parameters<T>): ReturnType<T> => {
    const result = implementation?.(...args) as ReturnType<T>;
    calls.push({ args, result });
    return result;
  }) as T & {
    calls: { args: Parameters<T>; result: ReturnType<T> }[];
    reset: () => void;
  };

  mock.calls = calls;
  mock.reset = (): void => {
    calls.length = 0;
  };

  return mock;
}

/**
 * Create a mock that resolves/rejects based on call count.
 *
 * @param responses - Array of responses (or Error to reject)
 * @returns Mock function that returns responses in order
 */
export function createSequenceMock<T>(responses: (T | Error)[]): () => Promise<T> {
  let callCount = 0;

  return (): Promise<T> => {
    const response = responses[callCount % responses.length];
    callCount++;

    if (response instanceof Error) {
      return Promise.reject(response);
    }
    return Promise.resolve(response as T);
  };
}
