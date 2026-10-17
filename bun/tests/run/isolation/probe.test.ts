import { expect, test } from "bun:test";
import { readdirSync, realpathSync } from "node:fs";
import { basename, dirname } from "node:path";

// The copy-tree root: the ancestor of this file's directory named probe_test.bun.
function copyTreeRoot(): string {
  let dir = import.meta.dir;
  while (basename(dir) !== "probe_test.bun") {
    const parent = dirname(dir);
    if (parent === dir) throw new Error(`no ancestor of ${import.meta.dir} is named probe_test.bun`);
    dir = parent;
  }
  return realpathSync(dir);
}

test("no undeclared bunfig.toml is read", () => {
  expect((globalThis as Record<string, unknown>).__RULES_BUN_BUNFIG).toBeUndefined();
});

test("no undeclared .env is loaded", () => {
  expect(process.env.RULES_BUN_DOTENV).toBeUndefined();
});

test("the working directory is the copy-tree root, which holds no file", () => {
  expect(process.cwd()).toBe(copyTreeRoot());
  const files = readdirSync(process.cwd(), { withFileTypes: true }).filter((e) => !e.isDirectory());
  expect(files.map((e) => e.name)).toEqual([]);
});
