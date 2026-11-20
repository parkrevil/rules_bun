import { expect, test } from "bun:test";
import p from "p-user";

// p's optional peer r is linked from the lockfile's own entry, as the pinned Bun links it (feature
// 006 BC-9).
test("p loads q@1.0.0 and r@1.0.0", () => {
  expect(p).toMatchObject({ name: "p", version: "1.0.0", q: "1.0.0", r: "1.0.0" });
});
