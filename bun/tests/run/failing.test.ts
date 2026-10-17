import { expect, test } from "bun:test";

test("fails on purpose", () => {
  expect(1).toBe(2);
});
