import { expect, test } from "bun:test";

test("the inner workspace runs a bun_test", () => {
  expect(1 + 1).toBe(2);
});
