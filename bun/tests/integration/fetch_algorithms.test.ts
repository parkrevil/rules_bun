// Packages whose bun.lock integrity uses sha256 or sha384 are fetched and
// verified like sha512 ones (FR-009, constitution III). Bun 1.4.2 writes every
// integrity as the digest's unpadded base64 followed by "==" (canary
// C-INTEGRITY), which Bazel's downloader rejects as invalid base64 for these
// digest lengths; the extension pads the base64 correctly (tasks.md T121).

import { afterAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const ARCHIVES = ["a@1.0.0", "b@1.0.0"].map((p) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`));
const FIXTURES = "_main/bun/tests/npm/fixtures";

const inner = new Inner("replace", { npmArchives: ARCHIVES, substitutions: { REPLACEMENTS: "", EXTRA: "" } });
afterAll(() => inner.close());

// The fixture lockfiles record the loopback port of the run that wrote them.
const lockfile = (project: string) =>
  readFileSync(rlocation(`${FIXTURES}/${project}/bun.lock`), "utf8").replaceAll(/http:\/\/127\.0\.0\.1:\d+/g, inner.registry.url);

test(
  "sha256 and sha384 packages are downloaded and verified",
  async () => {
    inner.write("s256/bun.lock", lockfile("alg_sha256"));
    inner.write("s384/bun.lock", lockfile("alg_sha384"));
    inner.write("s512/bun.lock", lockfile("alg_sha256"));
    for (const [dir, project] of [["s256", "alg_sha256"], ["s384", "alg_sha384"], ["s512", "alg_sha256"]]) {
      inner.write(`${dir}/package.json`, readFileSync(rlocation(`${FIXTURES}/${project}/package.json`)));
    }
    const result = await inner.run(["build", "//s256:node_modules/a", "//s384:node_modules/a"]);
    if (result.exitCode !== 0) console.error(result.stderr);
    expect(result.exitCode).toBe(0);
    const fetched = inner.log.filter((e) => e.path.endsWith(".tgz")).map((e) => `${e.path} ${e.status}`);
    // One download per hub: the two integrities are different cache keys.
    expect(fetched.sort()).toEqual(["/a/-/a-1.0.0.tgz 200", "/a/-/a-1.0.0.tgz 200", "/b/-/b-1.0.0.tgz 200", "/b/-/b-1.0.0.tgz 200"]);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);
