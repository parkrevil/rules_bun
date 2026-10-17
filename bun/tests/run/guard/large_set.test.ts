import { expect, test } from "bun:test";
import { spawnTarget } from "../../support/spawn.ts";

const TARGET = "_main/bun/tests/run/guard/large_set";

// Each test launches a target with 10,000 declared files: about 0.3 s on Linux,
// but past Bun's default per-test timeout of 5 s on Windows, which ends the test
// and its target. 60 s per test keeps both well inside the 300 s Bazel timeout
// of a medium test.
const LAUNCH_TIMEOUT_MS = 60_000;

test("with 10,000 declared files a declared one imports", async () => {
  const result = await spawnTarget(TARGET, { args: ["./large_files/f09999.json"] });
  expect(result.exitCode, result.stderr).toBe(0);
  expect(result.stdout).toBe("imported\n");
}, LAUNCH_TIMEOUT_MS);

test("with 10,000 declared files an undeclared one fails naming it", async () => {
  const result = await spawnTarget(TARGET, { args: ["./stale.ts"] });
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toMatch(/\/\/bun\/tests\/run\/guard:large_set: \S*stale\.ts is not declared by this target/);
}, LAUNCH_TIMEOUT_MS);
