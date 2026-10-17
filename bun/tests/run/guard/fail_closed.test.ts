import { expect, test } from "bun:test";
import { join } from "node:path";
import { rlocation } from "../../support/spawn.ts";

// Starts the toolchain's Bun with the guard preloaded, on a declared entry point
// or, under `bun test`, on a declared test file.
function run(config: string | undefined, mode: "program" | "test" = "program") {
  const env: Record<string, string | undefined> = { ...process.env, RULES_BUN_LAUNCH_CONFIG: config };
  if (config === undefined) delete env.RULES_BUN_LAUNCH_CONFIG;
  const guard = `--preload=${rlocation("_main/bun/private/launcher.js")}`;
  const argv =
    mode === "program"
      ? [process.execPath, guard, rlocation("_main/bun/tests/run/guard/marker.ts")]
      : [process.execPath, "test", guard, rlocation("_main/bun/tests/run/guard/marker.test.ts")];
  const result = Bun.spawnSync(argv, { env });
  return { exitCode: result.exitCode, stdout: result.stdout.toString(), stderr: result.stderr.toString() };
}

test("without RULES_BUN_LAUNCH_CONFIG the guard rejects every module", () => {
  const result = run(undefined);
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toMatch(/load guard: RULES_BUN_LAUNCH_CONFIG is not set/);
  expect(result.stdout).not.toContain("ENTRY_POINT_RAN");
});

test("with a missing launch configuration the guard rejects every module", () => {
  const missing = join(process.env.TEST_TMPDIR!, "missing.launch.json");
  const result = run(missing);
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain(`load guard: cannot read the launch configuration ${missing}`);
  expect(result.stdout).not.toContain("ENTRY_POINT_RAN");
});

test("under bun test, without RULES_BUN_LAUNCH_CONFIG the guard rejects the test file with its error", () => {
  const result = run(undefined, "test");
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toMatch(/rules_bun load guard: RULES_BUN_LAUNCH_CONFIG is not set/);
  expect(result.stdout).not.toContain("TEST_FILE_RAN");
  expect(result.stdout).not.toContain("TEST_BODY_RAN");
});

test("under bun test, with a missing launch configuration the guard rejects the test file with its error", () => {
  const missing = join(process.env.TEST_TMPDIR!, "missing.launch.json");
  const result = run(missing, "test");
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain(`rules_bun load guard: cannot read the launch configuration ${missing}`);
  expect(result.stdout).not.toContain("TEST_FILE_RAN");
  expect(result.stdout).not.toContain("TEST_BODY_RAN");
});
