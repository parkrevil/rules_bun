// Canary C-ROWINFO (feature 006, research Part 4 L31): a row whose resolution is not an npm version
// carries its info object, with the dependencies its package declares, in slot 1: a `file:` folder
// `["<name>@file:<path>", INFO]` and a tarball URL `["<name>@<url>", INFO, "<integrity>"]` (LOCK
// L720–L728 writer, L2557–L2591 reader).

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "read_lockfile's non-npm rows (# L31) in bun/private/lockfile.bzl and parse_into_binary_lockfile in bun/private/bun_lockfile.bzl";

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
