// US4-6: w1's optional dependency native-linux-x64 (os linux, cpu x64) is
// carried on Linux x64 only; elsewhere importing it fails with Bun's
// module-not-found error.

import { expect, test } from "bun:test";
import { spawnTarget } from "../../../../../support/spawn.ts";

test("the optional dependency loads only on its platform", async () => {
  const result = await spawnTarget("_main/bun/tests/npm/fixtures/workspace/packages/w1/optional");
  if (process.platform === "linux" && process.arch === "x64") {
    expect(result.stderr).toBe("");
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe("native-linux-x64\n");
  } else {
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("Cannot find package 'native-linux-x64'");
  }
});
