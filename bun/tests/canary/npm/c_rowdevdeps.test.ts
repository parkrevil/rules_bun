// Canary C-ROWDEVDEPS (feature 006, research Part 4 L32): the row of a `file:` folder package carries
// the `devDependencies` its package.json declares (a folder is read with dev dependencies,
// resolver_hooks.rs L1251–L1256 Features::FOLDER; written by LOCK L950–L1004 with the groups of
// L1478–L1483, read by L3405–L3490).

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "_entry in bun/private/lockfile.bzl (devDependencies, # L32) and _parse_append_dependencies in bun/private/bun_lockfile.bzl";

test("a folder package's row carries its devDependencies", async () => {
  const { lock } = await runInstall(
    {
      "package.json": manifest({ name: "c-rowdevdeps", dependencies: { local: "file:./local" } }),
      "local/package.json": manifest({ name: "local", version: "1.0.0", devDependencies: { b: "1.0.0" } }),
    },
    {
      // Red: the folder declares b as an ordinary dependency, so the row has no devDependencies.
      alter: red({
        files: (files) => ({ ...files, "local/package.json": manifest({ name: "local", version: "1.0.0", dependencies: { b: "1.0.0" } }) }),
      }),
    },
  );
  const local = lock.packages.local;
  if (local?.[0] !== "local@file:local" || JSON.stringify(local[1]) !== JSON.stringify({ devDependencies: { b: "1.0.0" } })) {
    canaryFail("C-ROWDEVDEPS", "info devDependencies of a folder row", READER, LOCKFILE_SOURCE, local);
  }
  if (lock.packages.b?.[0] !== "b@1.0.0") {
    canaryFail("C-ROWDEVDEPS", "the row of a folder's dev dependency", READER, LOCKFILE_SOURCE, lock.packages);
  }
});
