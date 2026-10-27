// Canary C-INTEGRITY (FR-024, research L12): slot 3 of an npm entry is the SRI
// the packument published, in the form Bun 1.4.4 writes it: the digest's
// unpadded base64 followed by "==" whatever the algorithm, which is the
// published value for sha512 only.

import { test } from "bun:test";
import { readFileSync } from "node:fs";
import { integrity } from "../../support/npm_registry.ts";
import { rlocation } from "../../support/spawn.ts";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "normalize_integrity in bun/private/lockfile.bzl";
const ALGORITHMS = { "a@1.0.0": "sha256", "b@1.0.0": "sha384", "c@1.0.0": "sha512" } as const;

/** What Bun 1.4.4 writes for a published SRI value. */
function written(published: string): string {
  return published.replace(/=*$/, "") + "==";
}

test("slot 3 is the published integrity as Bun writes it", async () => {
  const { lock } = await runInstall({ "package.json": manifest({ name: "c-integrity", dependencies: { a: "1.0.0", c: "1.0.0" } }) }, {
    algorithms: ALGORITHMS,
    // Red: the packument publishes no integrity.
    alter: red({
      packument: (_name, doc) => {
        for (const v of Object.values(doc.versions as Record<string, any>)) delete v.dist.integrity;
        return doc;
      },
    }),
  });
  for (const [store, algorithm] of Object.entries(ALGORITHMS)) {
    const key = store.slice(0, store.indexOf("@"));
    const published = integrity(readFileSync(rlocation(`_main/bun/tests/npm/registry/archives/${store}.tgz`)), algorithm);
    const slot = lock.packages[key]?.[3];
    if (slot !== written(published)) canaryFail("C-INTEGRITY", `npm entry slot 3 (${algorithm})`, READER, LOCKFILE_SOURCE, { published, slot });
  }
});
