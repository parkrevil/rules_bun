import { expect, test } from "bun:test";
// A package that no target declares and no node_modules holds.
import pkg from "rules-bun-fixture-pkg";

test("the package is imported", () => {
  expect(pkg).toBe("installed");
});
