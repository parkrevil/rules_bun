import { expect, test } from "bun:test";
import p from "p-user";

test("p loads q@1.0.0 and no r", () => {
  expect(p).toMatchObject({ name: "p", version: "1.0.0", q: "1.0.0", r: null });
});
