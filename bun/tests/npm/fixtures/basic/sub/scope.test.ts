import { expect, test } from "bun:test";
import a from "a";

test("a package linked by the parent package resolves in its subpackage", () => {
  expect(a.name).toBe("a");
});
