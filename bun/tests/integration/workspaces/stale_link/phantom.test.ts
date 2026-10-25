import { expect, test } from "bun:test";
import phantomUser from "phantom-user";

test("phantom-user loads b", () => {
  expect(phantomUser()).toBeDefined();
});
