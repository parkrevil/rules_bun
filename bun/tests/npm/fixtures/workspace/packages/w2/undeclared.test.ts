// US4-1: a workspace member cannot import a package only another workspace
// package declares.

import { expect, test } from "bun:test";
import { spawnTarget } from "../../../../../support/spawn.ts";

test("w2 cannot import a, which only the root and w1 declare", async () => {
  const result = await spawnTarget("_main/bun/tests/npm/fixtures/workspace/packages/w2/undeclared");
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toMatch(/Cannot find package 'a'|a\/index\.js is not declared by this target/);
});
