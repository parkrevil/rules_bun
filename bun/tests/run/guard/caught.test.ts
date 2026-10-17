import { expect, test } from "bun:test";
import { spawnTarget } from "../../support/spawn.ts";

test("a guard error the program catches does not fail the run", async () => {
  const result = await spawnTarget("_main/bun/tests/run/guard/caught");
  expect(result.exitCode, result.stderr).toBe(0);
  expect(result.stdout).toBe("caught\n");
});
