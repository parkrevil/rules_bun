// A link an earlier build left in the copy tree (research "Decisions during
// implementation", 2026-10-21, R6; FR-013, US1-7): Bazel does not delete
// outputs a newer build no longer declares, so after phantom-user loses its
// dependency on b in bun.lock, the old link .store/phantom-user@1.0.0/
// node_modules/b remains and points into b's store entry, which the target
// still carries. The launcher must fail before Bun starts, naming the link and
// telling the user to run bazel clean (tasks.md T122).

import { afterAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const ARCHIVES = ["b@1.0.0", "phantom-user@1.0.0"].map((p) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`));

const inner = new Inner("stale_link", { npmArchives: ARCHIVES });
afterAll(() => inner.close());
const lockfile = readFileSync(join(inner.dir, "bun.lock"), "utf8");

test(
  "a link left by an earlier build fails the launch naming it",
  async () => {
    inner.write("bun.lock", lockfile.replace("{PHANTOM_INFO}", '{ "dependencies": { "b": "1.0.0" } }'));
    const declared = await inner.run(["test", "//:phantom_test", "--test_output=errors"]);
    expect(declared.exitCode, declared.stdout + declared.stderr).toBe(0);

    inner.write("bun.lock", lockfile.replace("{PHANTOM_INFO}", "{}"));
    const stale = await inner.run(["test", "//:phantom_test", "--test_output=errors"]);
    const output = stale.stdout + stale.stderr;
    console.log(output.split("\n").filter((l) => /error|declare|clean/i.test(l)).join("\n"));
    expect(stale.exitCode).not.toBe(0);
    expect(output).toMatch(
      /@@\/\/:phantom_test: \S+\/phantom_test\.bun\/\.store\/phantom-user@1\.0\.0\/node_modules\/b is not a package link this target declares; an earlier build left it behind, run "bazel clean" and build again/,
    );
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);
