import { expect, test } from "bun:test";
import b from "b";

test("the source loads b", () => {
  expect(b).toBeDefined();
});
