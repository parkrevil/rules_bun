// Canary C7 (FR-028): pins the Windows stub's argument parsing, which splits an
// argument containing `"` and drops runtime arguments past 128 (G1). When this
// fails, the stub changed: revisit the limitation and the waiting quote test.

import { test } from "bun:test";
import { spawnTarget } from "../support/spawn.ts";

const ECHO = "_main/bun/tests/run/args/echo";
const MESSAGE =
  "the Windows stub's argument parsing changed: revisit the documented Windows argument limitation " +
  "and the waiting Windows quote test (G1); https://github.com/hermeticbuild/hermetic-launcher/issues/80";

function pinned(holds: boolean, observed: unknown): void {
  if (!holds) throw new Error(`${MESSAGE}; observed ${JSON.stringify(observed)}`);
}

test("an argument containing a quote is split", async () => {
  const args = ['say "hi"'];
  const result = await spawnTarget(ECHO, { args });
  const { argv } = JSON.parse(result.stdout);
  pinned(JSON.stringify(argv) !== JSON.stringify(args), argv);
});

test("runtime arguments past 128 are dropped", async () => {
  const args = Array.from({ length: 130 }, (_, i) => `a${i}`);
  const result = await spawnTarget(ECHO, { args });
  const { argv } = JSON.parse(result.stdout);
  pinned(argv.length < args.length, argv.length);
});
