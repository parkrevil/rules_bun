// Canary C-INFODEPS (FR-024, research L13): slot 2 holds `dependencies` and
// `optionalDependencies` as the package's manifest writes them.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

test("info dependencies and optionalDependencies", async () => {
  const { lock } = await runInstall({ "package.json": manifest({ name: "c-infodeps", dependencies: { a: "1.0.0", negated: "1.0.0" } }) }, {
    // Red: the registry publishes a without dependencies.
    alter: red({
      packument: (name, doc) => {
        if (name === "a") delete doc.versions["1.0.0"].dependencies;
        return doc;
      },
    }),
  });
  const a = lock.packages.a?.[2];
  const negated = lock.packages.negated?.[2];
  if (JSON.stringify(a?.dependencies) !== JSON.stringify({ b: "^1.0.0" })) {
    canaryFail("C-INFODEPS", "info dependencies", "read_lockfile in bun/private/lockfile.bzl", LOCKFILE_SOURCE, a);
  }
  if (JSON.stringify(negated?.optionalDependencies) !== JSON.stringify({ "negated-not-win": "1.0.0" })) {
    canaryFail("C-INFODEPS", "info optionalDependencies", "read_lockfile in bun/private/lockfile.bzl", LOCKFILE_SOURCE, negated);
  }
});
