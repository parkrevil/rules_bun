import { expect, test } from "bun:test";
import { spawnTarget } from "../../support/spawn.ts";

const PACKAGE = "_main/bun/tests/run/guard";

function expectRejected(result: { exitCode: number; stderr: string }, target: string, file: string): void {
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toMatch(
    new RegExp(`//bun/tests/run/guard:${target}: \\S*${file.replace(".", "\\.")} is not declared by this target`),
  );
}

test("declared ESM, CommonJS and JSON files load", async () => {
  const result = await spawnTarget(`${PACKAGE}/guarded`, { args: ["declared"] });
  expect(result.exitCode, result.stderr).toBe(0);
});

for (const [name, file] of [
  ["stale", "stale.ts"],
  ["climb", "climb.ts"],
  ["imports", "imports_target.ts"],
  ["node_modules", "index.js"],
  ["cjs", "undeclared.cjs"],
  ["json", "undeclared.json"],
  ["original", "declared.json"],
]) {
  test(`an undeclared import (${name}) fails naming ${file}`, async () => {
    expectRejected(await spawnTarget(`${PACKAGE}/guarded`, { args: [name] }), "guarded", file);
  });
}

test("an undeclared path with line terminators fails", async () => {
  const result = await spawnTarget(`${PACKAGE}/guarded`, { args: ["newline"] });
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("is not declared by this target");
});

test("a static import of a stale file fails", async () => {
  expectRejected(await spawnTarget(`${PACKAGE}/static_stale`), "static_stale", "stale.ts");
});

test("a preload importing an undeclared file fails", async () => {
  expectRejected(await spawnTarget(`${PACKAGE}/preload_undeclared_test`), "preload_undeclared_test", "stale.ts");
});

test("under --isolate an undeclared import in the second test file fails", async () => {
  expectRejected(await spawnTarget(`${PACKAGE}/isolate_test`, { args: ["--isolate"] }), "isolate_test", "stale.ts");
});
