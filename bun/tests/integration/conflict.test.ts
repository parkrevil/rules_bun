// Two lockfile entries of one name@version that disagree on what to download (feature 006 BC-17).
// The pinned Bun keeps one package per name@version, the first row's, with its integrity and URL
// (`append_package_dedupe`, src/install/lockfile.rs L2684–L2711 @ bun-v1.4.4), and installs such a
// lockfile; the ruleset downloads that package once, from the first row's URL, verified against
// the first row's integrity. integrity/bun.lock and url/bun.lock are the workspace's bun.lock with
// the "c/b" row's integrity or URL changed, written by hand, as no Bun writes two such rows; the
// conformance test compares the pinned Bun's install of each with the ruleset's graph (research R9).

import { afterAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const archive = (p: string) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`);
const inner = new Inner("conflict", { npmArchives: [archive("a@1.0.0"), archive("b@1.0.0"), archive("c@1.0.0")] });
afterAll(() => inner.close());

// The committed lockfile (workspaces/conflict/bun.lock, which the conformance test compares with
// the pinned Bun's install, feature 006 T143), whose "c/b" entry repeats b's.
const CONSISTENT = readFileSync(join(inner.dir, "bun.lock"), "utf8");

test(
  "consistent entries evaluate",
  async () => {
    inner.write("bun.lock", CONSISTENT);
    const result = await inner.run(["query", "//..."]);
    expect(result.exitCode, result.stderr).toBe(0);
  },
  INNER_TIMEOUT,
);

// The URL case runs first, while the repository cache holds no b@1.0.0, so b is downloaded and
// the request shows which URL; the integrity case then finds b cached under the first row's
// integrity, which would miss if the ruleset verified against the other row's.
const VARIANTS: [string, string, string[] | undefined][] = [
  ["url", "URLs", ["/b/-/b-1.0.0.tgz"]],
  ["integrity", "integrities", undefined],
];

for (const [variant, what, requests] of VARIANTS) {
  test(
    `two entries of b@1.0.0 with different ${what} download b as the first row records it`,
    async () => {
      const lockfile = readFileSync(join(inner.dir, variant, "bun.lock"), "utf8");
      if (lockfile === CONSISTENT) throw new Error(`workspaces/conflict/${variant}/bun.lock is the consistent lockfile`);
      inner.write("bun.lock", lockfile);
      const start = inner.log.length;
      const result = await inner.run(["build", "//:node_modules/c"]);
      expect(result.exitCode, result.stderr).toBe(0);
      const paths = inner.log.slice(start).map((e) => e.path).filter((p) => p.includes("b-1.0.0.tgz"));
      if (requests) expect(paths).toEqual(requests);
      else expect(paths.filter((p) => p !== "/b/-/b-1.0.0.tgz")).toEqual([]);
      assertOffline(inner.log);
    },
    INNER_TIMEOUT,
  );
}
