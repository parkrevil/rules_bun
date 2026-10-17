import { expect, test } from "bun:test";

test("runs under Bun", () => {
  expect(typeof Bun.version).toBe("string");
});
