// Canary C-ROWINFO (feature 006, research Part 4 L31): a row whose resolution is not an npm version
// carries its info object, with the dependencies its package declares, in slot 1: a `file:` folder
// `["<name>@file:<path>", INFO]` and a tarball URL `["<name>@<url>", INFO, "<integrity>"]` (LOCK
// L720–L728 writer, L2557–L2591 reader). A local tarball (`file:<path>.tgz`) is written
// `["<name>@<path>.tgz", INFO, "<integrity>"]`, a resolution without a protocol that Bun reads as a
// local tarball (resolution.rs L192–L201; T175, research Part 4 L9, L31, L37).

import { test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { writeTgz } from "../../support/tar.ts";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "_entry in bun/private/lockfile.bzl (a non-npm row, # L31) and load_lockfile in bun/private/bun_lockfile.bzl";

test("the info object of a file: and a tarball-URL row is in slot 1", async () => {
  const { lock, url } = await runInstall(
    (url) => ({
      "package.json": manifest({
        name: "c-rowinfo",
        dependencies: { local: "file:./local", tb: `${url}/a/-/a-1.0.0.tgz` },
      }),
      "local/package.json": manifest({ name: "local", version: "1.0.0", dependencies: { c: "1.0.0" } }),
    }),
    {
      // Red: the folder declares no dependencies, so its info object is empty.
      alter: red({
        files: (files) => ({ ...files, "local/package.json": manifest({ name: "local", version: "1.0.0" }) }),
      }),
    },
  );
  const local = lock.packages.local;
  if (local?.length !== 2 || local[0] !== "local@file:local" || JSON.stringify(local[1]) !== JSON.stringify({ dependencies: { c: "1.0.0" } })) {
    canaryFail("C-ROWINFO", "info object of a file: row", READER, LOCKFILE_SOURCE, local);
  }
  const tb = lock.packages.tb;
  if (
    tb?.length !== 3 ||
    tb[0] !== `a@${url}/a/-/a-1.0.0.tgz` ||
    JSON.stringify(tb[1]) !== JSON.stringify({ dependencies: { b: "^1.0.0" } }) ||
    typeof tb[2] !== "string"
  ) {
    canaryFail("C-ROWINFO", "info object of a tarball-URL row", READER, LOCKFILE_SOURCE, tb);
  }
});

test("a local tarball row is its path, with the info object in slot 1 and the integrity in slot 2", async () => {
  const dir = mkdtempSync(join(process.env.TEST_TMPDIR!, "canary-"));
  const loc = manifest({ name: "loc", version: "1.0.0", dependencies: { c: "1.0.0" } });
  writeFileSync(join(dir, "loc-1.0.0.tgz"), writeTgz([{ name: "package/package.json", type: "file", data: new TextEncoder().encode(loc) }]));
  const { lock } = await runInstall(
    { "package.json": manifest({ name: "c-rowinfo-tgz", dependencies: { b: "file:loc-1.0.0.tgz" } }), "loc/package.json": loc },
    {
      dir,
      // Red: the dependency is the folder holding the same package.json, a `file:` row of 2 slots.
      alter: red({ files: (files) => ({ ...files, "package.json": files["package.json"].replace("file:loc-1.0.0.tgz", "file:loc") }) }),
    },
  );
  const b = lock.packages.b;
  if (
    b?.length !== 3 ||
    b[0] !== "loc@loc-1.0.0.tgz" ||
    JSON.stringify(b[1]) !== JSON.stringify({ dependencies: { c: "1.0.0" } }) ||
    typeof b[2] !== "string" ||
    !b[2].startsWith("sha512-")
  ) {
    canaryFail("C-ROWINFO", "local tarball row", "_kind and _entry in bun/private/lockfile.bzl (# L9, L31) and load_lockfile in bun/private/bun_lockfile.bzl (L37)", LOCKFILE_SOURCE, b);
  }
});
