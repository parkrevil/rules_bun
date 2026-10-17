import { expect, test } from "bun:test";
import { spawnTarget } from "../support/spawn.ts";

test("a failing bun_test exits non-zero and names the failing test", async () => {
  const result = await spawnTarget("_main/bun/tests/run/failing_test");
  expect(result.exitCode).not.toBe(0);
  expect(result.stdout + result.stderr).toContain("fails on purpose");
});
