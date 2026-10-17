import { expect, test } from "bun:test";

test("the declared preload ran before the test file", () => {
  expect((globalThis as Record<string, unknown>).__RULES_BUN_PRELOAD).toBe("loaded");
});
