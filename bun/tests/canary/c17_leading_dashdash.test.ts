// Canary C17 (FR-009, FR-010): pins that the toolchain's Bun drops a `--`
// directly after the entry point and keeps one that is not first, when run as
// the launcher runs a bun_binary (`--no-env-file`, an absolute entry point).
// When this fails, revisit the launcher's refusal of a leading `--`
// (bun/private/launcher.js, bun_binary doc).

import { expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const MESSAGE = "revisit the launcher's refusal of a leading `--` (bun/private/launcher.js, bun_binary doc)";

// RULES_BUN_CANARY_RED=1 alters the expectation, so the canary is seen failing
// (the convention of bun/tests/canary/npm/support.ts).
const RED = Boolean(process.env.RULES_BUN_CANARY_RED);

const cases: [string, string[], string][] = [
  ["a -- directly after the entry point is dropped", ["--", "x"], RED ? '["--","x"]' : '["x"]'],
  ["a -- after another argument is kept", ["a", "--", "b"], '["a","--","b"]'],
];

for (const [name, args, expected] of cases) {
  test(name, () => {
    const dir = mkdtempSync(join(process.env.TEST_TMPDIR!, "c17-"));
    const script = join(dir, "args.js");
    writeFileSync(script, "console.log(JSON.stringify(process.argv.slice(2)));\n");
    const result = Bun.spawnSync([process.execPath, "--no-env-file", script, ...args], { cwd: dir });
    const observed = { stdout: result.stdout.toString().trim(), exitCode: result.exitCode };
    expect(observed, `${MESSAGE}; observed ${JSON.stringify(observed)}`).toEqual({ stdout: expected, exitCode: 0 });
  });
}
