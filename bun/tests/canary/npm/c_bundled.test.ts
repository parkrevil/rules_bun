// Canary C-BUNDLED (feature 006, research Part 4 L26): the entry of a dependency its package
// bundles (bundleDependencies) carries info `bundled: true`.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "_entry in bun/private/lockfile.bzl, _parse_append_dependencies in bun/private/bun_lockfile.bzl and _find_resolution in bun/private/bun_lockfile.bzl";

test("a bundled dependency's entry is marked bundled", async () => {
  const { lock } = await runInstall(
    { "package.json": manifest({ name: "c-bundled", dependencies: { b: "2.0.0", bundler: "1.0.0" } }) },
    {
      // Red: the registry publishes bundler without bundleDependencies.
      alter: red({
        packument: (name, doc) => {
          if (name === "bundler") delete doc.versions["1.0.0"].bundleDependencies;
          return doc;
        },
      }),
    },
  );
  const entry = lock.packages["bundler/b"];
  if (entry?.[0] !== "b@1.0.0" || JSON.stringify(entry[2]) !== JSON.stringify({ bundled: true })) {
    canaryFail("C-BUNDLED", "info bundled", READER, LOCKFILE_SOURCE, entry);
  }
});
