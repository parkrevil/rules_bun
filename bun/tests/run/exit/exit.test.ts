import { expect, test } from "bun:test";
import { spawnTarget } from "../../support/spawn.ts";

test("bazel run passes on the program's exit code", async () => {
  const result = await spawnTarget("_main/bun/tests/run/exit/exit3");
  expect(result.exitCode).toBe(3);
});
