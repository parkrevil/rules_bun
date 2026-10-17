import { expect, test } from "bun:test";
import { covered } from "./covered.ts";

test("covered doubles a positive number", () => {
  expect(covered(2)).toBe(4);
});
