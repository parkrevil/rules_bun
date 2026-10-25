// US1-7 on a lockfile with configVersion 0: rules_bun lays packages out
// isolated whatever the lockfile was written for, so a phantom import fails.

import { expect, test } from "bun:test";
import { spawnTarget } from "../../../support/spawn.ts";

test("a phantom import fails with module-not-found on a hoisted lockfile", async () => {
  const result = await spawnTarget("_main/bun/tests/npm/fixtures/hoisted/phantom");
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toMatch(/Cannot find (package|module) 'b'/);
});
