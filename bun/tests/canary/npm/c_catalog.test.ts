// Canary C-CATALOG (FR-006, FR-011, research L19, R8, R9; feature 007): Bun 1.4.4
// writes the root package.json's catalog and named catalogs as top-level
// `catalog` and `catalogs`, as written, and keeps `catalog:` specifiers in
// `workspaces`. It also pins which catalogs and entries Bun reads from
// package.json, which the comparison relies on: the `workspaces` object's when
// it holds `catalog` or `catalogs`, else the top level's only when a
// `workspaces` field exists; entries whose value is not a string are skipped.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const ACCESS = "catalog and catalogs";
const READER = "root_catalogs in bun/private/bun_package.bzl, catalog_parse_append in bun/private/bun_catalog_map.bzl and _parse_catalog in bun/private/bun_lockfile.bzl";

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

/** Runs `bun install` on `pkg` (red-altered by `redPkg`) and compares the catalogs Bun writes. */
async function catalogsWritten(pkg: Record<string, any>, redPkg: (p: any) => Record<string, any>, expected: Record<string, unknown>) {
  const { lock } = await runInstall(
    { "package.json": manifest(pkg) },
    { alter: red({ files: (f) => ({ "package.json": manifest(redPkg(JSON.parse(f["package.json"]))) }) }) },
  );
  const observed = { catalog: lock.catalog, catalogs: lock.catalogs };
  if (!Bun.deepEquals(observed, expected)) canaryFail("C-CATALOG", ACCESS, READER, LOCKFILE_SOURCE, observed);
}

test("the workspaces object's catalog wins over the top level's", async () => {
  await catalogsWritten(
    {
      name: "c-catalog",
      workspaces: { packages: [], catalog: { b: "2.0.0" } },
      catalog: { b: "1.0.0", q: "2.0.0" },
      catalogs: { g: { q: "1.0.0" } },
      dependencies: { b: "catalog:" },
    },
    // Red: the workspaces object no longer holds a catalog, so Bun reads the top level.
    (p) => {
      p.workspaces = { packages: [], catalogNot: p.workspaces.catalog };
      return p;
    },
    { catalog: { b: "2.0.0" }, catalogs: undefined },
  );
});

test("the top level's catalog is not read without a workspaces field", async () => {
  await catalogsWritten(
    { name: "c-catalog", catalog: { b: "2.0.0" }, dependencies: { b: "1.0.0" } },
    // Red: a workspaces field makes Bun read the top level.
    (p) => ({ ...p, workspaces: [] }),
    { catalog: undefined, catalogs: undefined },
  );
});

test("catalog entries whose value is not a string are skipped", async () => {
  await catalogsWritten(
    { name: "c-catalog", workspaces: { packages: [], catalog: { b: "2.0.0", q: 1 } }, dependencies: { b: "catalog:" } },
    // Red: the entry becomes a string, so Bun writes it too.
    (p) => {
      p.workspaces.catalog.q = "1.0.0";
      return p;
    },
    { catalog: { b: "2.0.0" }, catalogs: undefined },
  );
});
