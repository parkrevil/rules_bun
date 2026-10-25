// Canary C-SLOT0 (FR-024, research L9, L22): slot 0 is `<name>@<version>` for an
// npm package, `<name>@workspace:<path>` (a one-element entry) for a member,
// `<name>@file:<path>` for a file dependency and `<name>@<url>` for a tarball URL.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "split_spec and the kind of an entry in bun/private/lockfile.bzl";

test("slot 0 of each entry kind", async () => {
  const { lock, url } = await runInstall(
    (registry) => ({
      "package.json": manifest({
        name: "c-slot0",
        workspaces: ["packages/*"],
        dependencies: { a: "1.0.0", local: "file:./local", tb: `${registry}/b/-/b-1.0.0.tgz`, w1: "workspace:*" },
      }),
      "packages/w1/package.json": manifest({ name: "w1", version: "1.0.0" }),
      "local/package.json": manifest({ name: "local", version: "1.0.0" }),
    }),
    // Red: a is an alias of b, so its slot 0 names b.
    { alter: red({ files: (f) => ({ ...f, "package.json": f["package.json"].replace('"a": "1.0.0"', '"a": "npm:b@1.0.0"') }) }) },
  );
  const p = lock.packages;
  const ok =
    p.a?.[0] === "a@1.0.0" &&
    JSON.stringify(p.w1) === JSON.stringify(["w1@workspace:packages/w1"]) &&
    p.local?.[0] === "local@file:local" &&
    p.tb?.[0] === `b@${url}/b/-/b-1.0.0.tgz`;
  if (!ok) canaryFail("C-SLOT0", "slot 0", READER, LOCKFILE_SOURCE, { a: p.a, w1: p.w1, local: p.local, tb: p.tb });
});
