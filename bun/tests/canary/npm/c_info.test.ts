// Canary C-INFO (FR-024, research L11): slot 2 of an npm entry is an object.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

test("slot 2 is an object", async () => {
  const { lock } = await runInstall({ "package.json": manifest({ name: "c-info", dependencies: { a: "1.0.0", b: "1.0.0" } }) }, {
    // Red: a is no longer installed, so its entry is missing.
    alter: red({ files: () => ({ "package.json": manifest({ name: "c-info", dependencies: { b: "1.0.0" } }) }) }),
  });
  for (const key of ["a", "b"]) {
    const info = lock.packages[key]?.[2];
    if (info === null || typeof info !== "object" || Array.isArray(info)) {
      canaryFail("C-INFO", "npm entry slot 2", "read_lockfile in bun/private/lockfile.bzl", LOCKFILE_SOURCE, lock.packages[key]);
    }
  }
});
