import { expect, test } from "bun:test";
import { spawnTarget } from "../../../support/spawn.ts";

test("runtime arguments reach bun test", async () => {
  const result = await spawnTarget("_main/bun/tests/run/protocol/args/slow_test", { args: ["--timeout=50"] });
  expect(result.exitCode).not.toBe(0);
  expect(result.stdout + result.stderr).toContain("timed out");
});

test("without a timeout argument the test passes", async () => {
  const result = await spawnTarget("_main/bun/tests/run/protocol/args/slow_test");
  expect(result.exitCode).toBe(0);
});
