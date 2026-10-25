// Canary C-ALIAS (FR-024, research L21): an `npm:` alias gets the alias as its
// key and the real package in slot 0.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

test("an alias key names another package in slot 0", async () => {
  const { lock } = await runInstall({ "package.json": manifest({ name: "c-alias", dependencies: { aliased: "npm:b@2.0.0" } }) }, {
    // Red: the alias points at b@1.0.0.
    alter: red({ files: (f) => ({ "package.json": f["package.json"].replace("npm:b@2.0.0", "npm:b@1.0.0") }) }),
  });
  const entry = lock.packages.aliased;
  if (entry?.[0] !== "b@2.0.0") canaryFail("C-ALIAS", "alias key and slot 0", "split_spec in bun/private/lockfile.bzl", LOCKFILE_SOURCE, entry);
});
