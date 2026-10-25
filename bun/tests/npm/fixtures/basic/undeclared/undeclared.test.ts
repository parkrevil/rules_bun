// US1-5: a package the lockfile lists but the target does not reach cannot be
// imported.

import { expect, test } from "bun:test";
import { spawnTarget } from "../../../../support/spawn.ts";

test("importing a package the target does not depend on fails", async () => {
  const result = await spawnTarget("_main/bun/tests/npm/fixtures/basic/undeclared/undeclared");
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toMatch(/Cannot find package 'c'|c\/index\.js is not declared by this target/);
});
