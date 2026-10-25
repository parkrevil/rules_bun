// p's optional peer r is provided by nothing the target declares; p catches
// the failure of require("r"), and this test fails with it.

import { expect, test } from "bun:test";
import p from "p";

test("r does not load", () => {
  expect(p.q).toBe("2.0.0");
  throw new Error(`r did not load: ${p.rError}`);
});
