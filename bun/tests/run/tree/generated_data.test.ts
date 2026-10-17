import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

test("generated data is found next to the test file", () => {
  expect(readFileSync(join(import.meta.dir, "generated.txt"), "utf8")).toBe("generated\n");
});
