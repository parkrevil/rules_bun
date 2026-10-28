// FR-007, US8 (research R6, D2): a Linux or macOS build of a bun_binary and a
// bun_test fetches no hermetic-launcher stub, the Windows launcher's template
// and finalizer, which the loopback registry would serve as runfiles-stub-* and
// finalize-stub-*. The inner build starts with an empty repository cache.

import { expect, test } from "bun:test";
import { assertOffline, INNER_TIMEOUT, runInner } from "./support/inner.ts";

test(
  "a Linux or macOS build requests no hermetic-launcher stub",
  async () => {
    const result = await runInner("launcher_fetch", ["test", "//...", "--test_output=errors"]);
    expect(result.repositoryCacheWasEmpty).toBe(true);
    expect(result.exitCode, result.stderr).toBe(0);
    const stubs = result.log.map((e) => e.path).filter((p) => p.includes("runfiles-stub-") || p.includes("finalize-stub-"));
    expect(stubs).toEqual([]);
    assertOffline(result.log);
  },
  INNER_TIMEOUT,
);
