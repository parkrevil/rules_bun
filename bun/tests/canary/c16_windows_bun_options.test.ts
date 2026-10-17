// Canary C16 (FR-028): pins that the Windows stub passes an inherited BUN_OPTIONS
// on to the first Bun process, which then runs code before or instead of the
// rule's launcher. When this fails, the stub changed: revisit the documented
// Windows BUN_OPTIONS limitation (FR-018a).

import { test } from "bun:test";
import { spawnTarget } from "../support/spawn.ts";

const MESSAGE =
  "the Windows stub no longer passes BUN_OPTIONS on to Bun: revisit the documented Windows " +
  "BUN_OPTIONS limitation (FR-018a); https://github.com/hermeticbuild/hermetic-launcher/issues/78";

test("an inherited BUN_OPTIONS with --eval runs in the first Bun process", async () => {
  const result = await spawnTarget("_main/bun/tests/run/hello", {
    env: { BUN_OPTIONS: '--eval=console.log("C16_EVAL_RAN")' },
  });
  if (!result.stdout.includes("C16_EVAL_RAN")) {
    throw new Error(`${MESSAGE}; observed ${JSON.stringify(result)}`);
  }
});
