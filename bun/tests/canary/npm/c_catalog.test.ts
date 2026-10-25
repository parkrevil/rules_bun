// Canary C-CATALOG (FR-006, research L19, R9): Bun 1.4.2 writes the root
// package.json's catalog and named catalogs as top-level `catalog` and
// `catalogs`, as written, and keeps `catalog:` specifiers in `workspaces`.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const ACCESS = "catalog and catalogs";
const READER = "read_lockfile in bun/private/lockfile.bzl and compare_manifests in bun/private/workspaces.bzl";

test("catalog and catalogs are written as the manifest writes them", async () => {
  const { lock } = await runInstall(
    {
      "package.json": manifest({
        name: "c-catalog",
        workspaces: { packages: [], catalog: { b: "1.0.0" }, catalogs: { two: { q: "2.0.0" } } },
        dependencies: { b: "catalog:", q: "catalog:two" },
      }),
    },
    // Red: the named catalog is renamed.
    { alter: red({ files: (f) => ({ "package.json": f["package.json"].replaceAll('two', "three") }) }) },
  );
  const observed = { catalog: lock.catalog, catalogs: lock.catalogs, dependencies: lock.workspaces[""].dependencies };
  const expected = { catalog: { b: "1.0.0" }, catalogs: { two: { q: "2.0.0" } }, dependencies: { b: "catalog:", q: "catalog:two" } };
  if (JSON.stringify(observed) !== JSON.stringify(expected)) canaryFail("C-CATALOG", ACCESS, READER, LOCKFILE_SOURCE, observed);
});
