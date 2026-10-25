import { expect, test } from "bun:test";
import c from "c";

test("the module's own lockfile", () => {
  expect(c).toEqual({ name: "c", version: "1.0.0", b: "2.0.0" });
});
