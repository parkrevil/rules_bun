import { expect, test } from "bun:test";
import { mkdtempSync } from "node:fs";
import { join } from "node:path";
import { covered } from "./covered.ts";

// Bun 1.4.4 writes coverage SF: values relative to the working directory at exit
// (G15), so after this chdir they name no declared file.
test("covered runs, then the test leaves the working directory", () => {
  expect(covered(2)).toBe(4);
  process.chdir(mkdtempSync(join(process.env.TEST_TMPDIR!, "chdir-")));
});
