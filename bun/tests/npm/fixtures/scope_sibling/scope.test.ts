import { expect, test } from "bun:test";
import { spawnTarget } from "../../../support/spawn.ts";

test("a package does not resolve outside the package that links it", async () => {
  const result = await spawnTarget("_main/bun/tests/npm/fixtures/scope_sibling/main");
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toMatch(/Cannot find (package|module) 'a'/);
});
