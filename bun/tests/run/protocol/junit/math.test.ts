import { describe, expect, test } from "bun:test";

describe("Math ops", () => {
  test("adds", () => {
    expect(1 + 1).toBe(2);
  });

  test("subtracts", () => {
    expect(2 - 1).toBe(1);
  });
});

test("other", () => {
  expect(true).toBe(true);
});
