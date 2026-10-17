// Imports a sibling file this target does not declare; the import must fail.
import { expect, test } from "bun:test";
import { undeclared } from "./undeclared.ts";

test("imports an undeclared sibling", () => {
  expect(undeclared).toBe("undeclared");
});
