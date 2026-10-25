import { expect, test } from "bun:test";
import a from "a";

test("a loads b@1.0.0", () => {
  expect(a).toEqual({ name: "a", version: "1.0.0", b: "1.0.0" });
});
