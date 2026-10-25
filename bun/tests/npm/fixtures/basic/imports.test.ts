// Real runs of package imports (US1-4, US1-6): each package loads its own
// dependency versions from the target's store.

import { expect, test } from "bun:test";
import a from "a";
import c from "c";
import s from "@scope/s";

test("a loads b@1.0.0", () => {
  expect(a).toEqual({ name: "a", version: "1.0.0", b: "1.0.0" });
});

test("c loads b@2.0.0", () => {
  expect(c).toEqual({ name: "c", version: "1.0.0", b: "2.0.0" });
});

test("a scoped package loads", () => {
  expect(s).toEqual({ name: "@scope/s", version: "1.0.0" });
});
