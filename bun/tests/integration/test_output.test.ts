// The whole output of a failing bun_test reaches the test log (feature 007, FR-014, research
// R10). Bazel 9.2.0's Windows test wrapper drops what a test wrote last when that output is
// still in its pipe as the test exits, so an inner `bazel test --test_output=errors` prints a
// cut log. Each inner target of workspaces/test_output writes 512 KiB, then a marker line, then
// fails; every marker must be in what the inner Bazel prints.

import { afterAll, expect, test } from "bun:test";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const TARGETS = 8;

const inner = new Inner("test_output");
afterAll(async () => {
  await inner.close();
});

test(
  "each failing bun_test's log holds its marker",
  async () => {
    const result = await inner.run(["test", "//:all", "--test_output=errors"]);
    // Bazel prints the test logs (--test_output=errors) on standard output.
    const output = result.stdout + result.stderr;
    const markers = Array.from({ length: TARGETS }, (_, i) => `rules_bun marker ${i + 1}`);
    const missing = markers.filter((marker) => !output.includes(marker));
    console.log(missing.length ? `missing from the inner output: ${missing.join(", ")}` : "every marker is in the inner output");
    expect(result.exitCode).not.toBe(0);
    expect(missing).toEqual([]);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);
