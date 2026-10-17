import { expect, test } from "bun:test";

// Declared by no target: it must never run.
test("undeclared test file runs", () => {
  expect("undeclared.test.ts ran").toBe("never");
});
