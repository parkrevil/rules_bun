import { expect, test } from "bun:test";
import { spawnTarget } from "../../support/spawn.ts";

test("a command line longer than 32,767 characters fails before Bun starts", async () => {
  const result = await spawnTarget("_main/bun/tests/run/length/long_cmdline_test");
  expect(result.exitCode).toBe(1);
  expect(result.stderr).toMatch(/\/\/bun\/tests\/run\/length:long_cmdline_test: .*\b\d{5,}\b.*\b32767\b/);
});
