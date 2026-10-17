import { expect, test } from "bun:test";
import { rlocation, spawnTarget } from "../../support/spawn.ts";

test("BUN_OPTIONS fails the launch before the program runs", async () => {
  const result = await spawnTarget("_main/bun/tests/run/isolation/probe", { env: { BUN_OPTIONS: "--define=X:1" } });
  expect(result.exitCode).toBe(1);
  expect(result.stderr).toContain("BUN_OPTIONS");
  expect(result.stdout).toBe("");
});

test("BUN_OPTIONS fails a bun_test before the tests run", async () => {
  const result = await spawnTarget("_main/bun/tests/run/isolation/probe_test", {
    env: { BUN_OPTIONS: "--define=X:1" },
  });
  expect(result.exitCode).toBe(1);
  expect(result.stderr).toContain("BUN_OPTIONS");
  expect(result.stderr).not.toContain("probe.test.ts");
});

test("launcher.js itself rejects BUN_OPTIONS before it reads the launch configuration", () => {
  const result = Bun.spawnSync(
    [process.execPath, rlocation("_main/bun/private/launcher.js"), "missing.launch.json"],
    { env: { ...process.env, BUN_OPTIONS: "--define=X:1" } },
  );
  expect(result.exitCode).toBe(1);
  expect(result.stderr.toString()).toContain("rules_bun: BUN_OPTIONS is set");
});
