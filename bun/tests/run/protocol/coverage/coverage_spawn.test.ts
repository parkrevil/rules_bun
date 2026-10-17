import { expect, test } from "bun:test";
import { mkdirSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { spawnTarget } from "../../../support/spawn.ts";

test("COVERAGE_DIR receives one bunlcov_<uuid>.dat naming the source by its path", async () => {
  const dir = join(process.env.TEST_TMPDIR!, "coverage");
  mkdirSync(dir, { recursive: true });
  const result = await spawnTarget("_main/bun/tests/run/protocol/coverage/coverage_target_test", {
    env: { COVERAGE_DIR: dir },
  });
  expect(result.exitCode).toBe(0);

  const files = readdirSync(dir);
  expect(files.length).toBe(1);
  expect(files[0]).toMatch(/^bunlcov_[0-9a-f-]{36}\.dat$/);

  const records = readFileSync(join(dir, files[0]), "utf8")
    .split("\n")
    .filter((line) => line.startsWith("SF:"));
  expect(records).toContain("SF:bun/tests/run/protocol/coverage/covered.ts");
  expect(records.filter((r) => r.includes("launcher.js") || r.includes(".bun/"))).toEqual([]);
});
