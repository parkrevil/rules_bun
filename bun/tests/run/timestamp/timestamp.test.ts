// The launcher writes its start time to the file RULES_BUN_LAUNCH_TIMESTAMP
// names (test-only, FR-037), so launcher start can be measured up to a
// program's first line.

import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { spawnTarget } from "../../support/spawn.ts";

test("the launcher writes its start time before the program runs", async () => {
  const file = join(process.env.TEST_TMPDIR!, "launch-timestamp");
  const result = await spawnTarget("_main/bun/tests/run/timestamp/elapsed", {
    env: { RULES_BUN_LAUNCH_TIMESTAMP: file },
  });
  expect(result.exitCode, result.stderr).toBe(0);
  expect(readFileSync(file, "utf8")).toMatch(/^\d+$/);
  expect(Number(result.stdout.trim())).toBeGreaterThanOrEqual(0);
});
