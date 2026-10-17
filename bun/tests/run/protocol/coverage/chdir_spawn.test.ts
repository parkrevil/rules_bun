import { expect, test } from "bun:test";
import { mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { spawnTarget } from "../../../support/spawn.ts";

test("a coverage record that names no declared file fails the test and writes no .dat", async () => {
  const dir = join(process.env.TEST_TMPDIR!, "coverage");
  mkdirSync(dir, { recursive: true });
  const result = await spawnTarget("_main/bun/tests/run/protocol/coverage/coverage_chdir_target_test", {
    env: { COVERAGE_DIR: dir },
  });
  expect(result.exitCode).toBe(1);
  expect(result.stderr).toMatch(
    /\/\/bun\/tests\/run\/protocol\/coverage:coverage_chdir_target_test: coverage record SF:\S.* names no declared file/,
  );
  expect(readdirSync(dir)).toEqual([]);
});
