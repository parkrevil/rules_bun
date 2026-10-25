// US1-3: a test that depends only on a library reaches the library's packages.

import { expect, test } from "bun:test";
import { versions } from "./lib.ts";

test("the library's package loads with its own dependency", () => {
  expect(versions).toEqual({ a: "1.0.0", b: "1.0.0" });
});
