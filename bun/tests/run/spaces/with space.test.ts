import { expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { spaced } from "./with space.ts";

test("a source with a space in its name is imported", () => {
  expect(spaced).toBe("spaced");
});

test("a data file with a space in its name is read", () => {
  expect(readFileSync(join(import.meta.dir, "with space.txt"), "utf8")).toBe("data with space\n");
});

test("the runfiles manifest escapes the space", () => {
  const manifest = process.env.RUNFILES_MANIFEST_FILE;
  if (!manifest || !existsSync(manifest)) {
    console.log("manifest assertion did not apply: RUNFILES_MANIFEST_FILE does not name a readable file");
    return;
  }
  const lines = readFileSync(manifest, "utf8").split("\n");
  const line = lines.find((l) => l.startsWith(" _main/bun/tests/run/spaces/with\\sspace.txt "));
  expect(line).toBeDefined();
  console.log("manifest assertion ran");
});
