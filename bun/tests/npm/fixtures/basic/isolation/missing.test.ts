import { expect, test } from "bun:test";
import a from "a";
import pkg from "rules-bun-fixture-pkg";

test("a package bun.lock does not list loads", () => {
  expect(a.version).toBe("1.0.0");
  expect(pkg).toBeDefined();
});
