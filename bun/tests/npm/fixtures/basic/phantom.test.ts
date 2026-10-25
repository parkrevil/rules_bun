// US1-7: a package cannot load a package it does not declare, even one the
// target itself declares; here no source-tree node_modules exists.

import { expect, test } from "bun:test";
import { spawnTarget } from "../../../support/spawn.ts";

test("a phantom import fails with module-not-found", async () => {
  const result = await spawnTarget("_main/bun/tests/npm/fixtures/basic/phantom");
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toMatch(/Cannot find (package|module) 'b'/);
});
