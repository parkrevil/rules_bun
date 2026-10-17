import { expect, test } from "bun:test";
import { stale } from "./stale.ts";

test("imports a stale file", () => {
  expect(stale).toBe("stale");
});
