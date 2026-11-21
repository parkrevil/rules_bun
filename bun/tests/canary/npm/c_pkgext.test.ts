// Canary C-PKGEXT (feature 006, research Part 4 L27): the package rows already carry the
// dependencies a top-level `packageExtensions` adds, and the top-level field lists only their
// names, so the loader binds them from the rows and does not read `packageExtensions`.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "load_lockfile in bun/private/bun_lockfile.bzl, which does not read packageExtensions";

const PROJECT = {
  name: "c-pkgext",
  dependencies: { a: "1.0.0" },
  packageExtensions: { "a@1.0.0": { dependencies: { c: "1.0.0" } } },
};

test("package rows carry the dependencies packageExtensions adds", async () => {
  const { lock } = await runInstall(
    { "package.json": manifest(PROJECT) },
    {
      // Red: the extension adds nothing.
      alter: red({ files: (f) => ({ ...f, "package.json": manifest({ ...PROJECT, packageExtensions: { "a@1.0.0": {} } }) }) }),
    },
  );
  const info = lock.packages.a?.[2];
  if (JSON.stringify(info?.dependencies) !== JSON.stringify({ b: "^1.0.0", c: "1.0.0" })) {
    canaryFail("C-PKGEXT", "info dependencies with packageExtensions", READER, LOCKFILE_SOURCE, info);
  }
  if (JSON.stringify(lock.packageExtensions) !== JSON.stringify({ "a@1.0.0": { dependencies: ["c"] } })) {
    canaryFail("C-PKGEXT", "packageExtensions", READER, LOCKFILE_SOURCE, lock.packageExtensions);
  }
});
