import { expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";

// The directory of a package in the target's store.
const packageDir = (name: string) => dirname(require.resolve(`${name}/package.json`));

test("an excluded BUILD.bazel is not carried; the other files are (FR-033, FR-035)", () => {
  const dir = packageDir("build-files");
  expect(existsSync(join(dir, "sub", "BUILD.bazel"))).toBe(false);
  expect(existsSync(join(dir, "BUILD"))).toBe(true);
  expect(existsSync(join(dir, "sub", "x.js"))).toBe(true);
});

test("an excluded file whose name holds a space is not carried (FR-033)", () => {
  const dir = packageDir("spaced");
  expect(existsSync(join(dir, "file with space.js"))).toBe(false);
  expect(existsSync(join(dir, "index.js"))).toBe(true);
});
