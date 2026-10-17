import { expect, test } from "bun:test";
import { spawnTarget } from "../../support/spawn.ts";

// The target declares 22,001 files; resolving them before the length check took
// longer than Bun's default per-test timeout of 5 s on a CI runner (CI run
// 39050199840). 60 s keeps the test well inside the 300 s Bazel timeout.
const LAUNCH_TIMEOUT_MS = 60_000;

test("a declared set whose guard pattern is too long fails before Bun starts", async () => {
  const result = await spawnTarget("_main/bun/tests/run/guard/over_limit", { args: ["./stale.ts"] });
  expect(result.exitCode).toBe(1);
  expect(result.stderr).toMatch(/\/\/bun\/tests\/run\/guard:over_limit: .*\b22001 declared files\b.*\b1048576\b/);
}, LAUNCH_TIMEOUT_MS);
