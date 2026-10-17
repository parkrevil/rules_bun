import { expect, test } from "bun:test";
import { spawnTarget } from "../../support/spawn.ts";

test("a declared set whose guard pattern is too long fails before Bun starts", async () => {
  const result = await spawnTarget("_main/bun/tests/run/guard/over_limit", { args: ["./stale.ts"] });
  expect(result.exitCode).toBe(1);
  expect(result.stderr).toMatch(/\/\/bun\/tests\/run\/guard:over_limit: .*\b22001 declared files\b.*\b1048576\b/);
});
