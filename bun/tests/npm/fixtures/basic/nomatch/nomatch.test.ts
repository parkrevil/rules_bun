import { expect, test } from "bun:test";
import { spawnTarget } from "../../../../support/spawn.ts";

test("nomatch finds no optional package on this platform", async () => {
  const result = await spawnTarget("_main/bun/tests/npm/fixtures/basic/nomatch/nomatch");
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("nomatch: no optional package matches this platform");
});
