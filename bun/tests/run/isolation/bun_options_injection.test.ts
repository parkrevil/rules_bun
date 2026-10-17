import { expect, test } from "bun:test";
import { rlocation, spawnTarget } from "../../support/spawn.ts";

// bun.com documents BUN_OPTIONS as arguments prepended to any Bun execution, so
// these would run code in the launcher's own Bun process.
const INJECTIONS: [string, () => string, string][] = [
  ["--eval", () => '--eval=console.log("BUN_OPTIONS_EVAL_RAN")', "BUN_OPTIONS_EVAL_RAN"],
  [
    "--preload",
    () => `--preload=${rlocation("_main/bun/tests/run/isolation/bun_options_preload.ts")}`,
    "BUN_OPTIONS_PRELOAD_RAN",
  ],
];

for (const target of ["probe", "probe_test"]) {
  for (const [name, options, marker] of INJECTIONS) {
    test(`BUN_OPTIONS with ${name} fails ${target} before any Bun starts`, async () => {
      const result = await spawnTarget(`_main/bun/tests/run/isolation/${target}`, {
        env: { BUN_OPTIONS: options() },
      });
      expect(result.stdout + result.stderr).not.toContain(marker);
      expect(result.stderr).toContain("BUN_OPTIONS");
      expect(result.exitCode).toBe(1);
    });
  }
}

test("an empty BUN_OPTIONS fails probe before any Bun starts", async () => {
  const result = await spawnTarget("_main/bun/tests/run/isolation/probe", { env: { BUN_OPTIONS: "" } });
  expect(result.stdout).toBe("");
  expect(result.stderr).toContain("BUN_OPTIONS");
  expect(result.exitCode).toBe(1);
});
