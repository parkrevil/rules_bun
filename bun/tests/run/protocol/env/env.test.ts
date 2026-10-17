import { expect, test } from "bun:test";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

test("declared variables are set", () => {
  expect(process.env.RULES_BUN_DECLARED).toBe("declared");
});

test("an inherited variable the invoking environment does not set is unset", () => {
  expect(process.env.RULES_BUN_UNSET).toBeUndefined();
});

test("a declared and inherited variable keeps its declared value when not set by the caller", () => {
  expect(process.env.RULES_BUN_BOTH).toBe("declared");
});

test("TEST_TMPDIR is writable", () => {
  const file = join(process.env.TEST_TMPDIR!, "written.txt");
  writeFileSync(file, "written");
  expect(readFileSync(file, "utf8")).toBe("written");
});

test("the test protocol variables are set", () => {
  expect(process.env.TEST_SRCDIR).toBeTruthy();
  expect(process.env.TEST_WORKSPACE).toBeTruthy();
  expect(process.env.TEST_TMPDIR).toBeTruthy();
});
