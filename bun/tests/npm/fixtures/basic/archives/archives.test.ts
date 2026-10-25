import { expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";

// The directory of a package in the target's store.
const packageDir = (name: string) => dirname(require.resolve(`${name}/package.json`));

test("every file of an archive with BUILD files is carried under its own name (FR-035)", () => {
  const dir = packageDir("build-files");
  expect(readFileSync(join(dir, "BUILD"), "utf8")).toBe("# A BUILD file inside a package archive.\n");
  expect(readFileSync(join(dir, "sub", "BUILD.bazel"), "utf8")).toBe("# A BUILD.bazel file inside a package archive.\n");
  expect(readFileSync(join(dir, "sub", "x.js"), "utf8")).toBe('module.exports = "sub/x";\n');
  expect(require("build-files").dir).toBe(dir);
});

test("a file whose name holds a space loads", () => {
  expect(require("spaced")).toBe("file with space");
  expect(existsSync(join(packageDir("spaced"), "file with space.js"))).toBe(true);
});

test("an archive whose top-level directory is not package/ loads (FR-034)", () => {
  expect(require("toplevel")).toEqual({ name: "toplevel", version: "1.0.0" });
});

test("excluded contents are not carried (FR-033)", () => {
  const dir = packageDir("excluded");
  expect(require("excluded").dir).toBe(dir);
  expect(existsSync(join(dir, "docs", "guide.md"))).toBe(false);
  expect(existsSync(join(dir, "test", "x.test.js"))).toBe(false);
});

test("empty directories of an archive are not carried", () => {
  const dir = packageDir("emptydir");
  expect(require("emptydir").dir).toBe(dir);
  expect(existsSync(join(dir, "empty"))).toBe(false);
  expect(existsSync(join(dir, "nested"))).toBe(false);
});
