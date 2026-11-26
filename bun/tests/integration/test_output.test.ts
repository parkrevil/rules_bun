// The whole output of a failing bun_test reaches the test log (feature 007, FR-014, research
// R10). Bazel 9.2.0's Windows test wrapper drops what a test wrote last when that output is
// still in its pipe as the test exits, so an inner `bazel test --test_output=errors` prints a
// cut log. Each inner target of workspaces/test_output writes 512 KiB (Bazel prints no log over
// --experimental_ui_max_stdouterr_bytes, 1 MiB), then a marker line, then
// fails; each target's log must hold its marker and end with Bun's summary, the last line Bun writes
// (research Part 6 D6).

import { afterAll, expect, test } from "bun:test";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const TARGETS = 16;
const LAST_LINE = "Ran 1 test across 1 file.";

const inner = new Inner("test_output");
afterAll(async () => {
  await inner.close();
});

test(
  "each failing bun_test's log is whole",
  async () => {
    const result = await inner.run(["test", "//:all", "--test_output=errors"]);
    // Bazel prints the test logs (--test_output=errors) on standard output.
    const output = result.stdout + result.stderr;
    const missing: string[] = [];
    for (let i = 1; i <= TARGETS; i++) {
      const start = output.indexOf(`Test output for //:out_${i}:`);
      const end = start === -1 ? -1 : output.indexOf("=".repeat(80), start);
      const log = start === -1 ? "" : output.slice(start, end === -1 ? undefined : end);
      if (!log.includes(`rules_bun marker ${i}`)) missing.push(`marker ${i}`);
      if (!log.includes(LAST_LINE)) missing.push(`last line of out_${i}`);
    }
    console.log(missing.length ? `missing from the inner output: ${missing.join(", ")}` : "every log is whole");
    expect(result.exitCode).not.toBe(0);
    expect(missing).toEqual([]);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);
