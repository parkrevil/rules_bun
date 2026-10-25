import { expect, test } from "bun:test";
import b from "b";

test("this lockfile's b", () => {
  expect(b.version).toBe("1.0.0");
});
