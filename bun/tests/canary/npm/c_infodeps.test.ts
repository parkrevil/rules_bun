// Canary C-INFODEPS (FR-024, research L13; feature 006 L30): slot 2 holds `dependencies` and
// `optionalDependencies` as the package's manifest writes them, npm ranges of every form (`~`,
// hyphen, x-range, `||`) unchanged, the forms bun_semver.bzl parses.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

test("info dependencies and optionalDependencies", async () => {
  const { lock } = await runInstall({ "package.json": manifest({ name: "c-infodeps", dependencies: { a: "1.0.0", negated: "1.0.0" } }) }, {
    // Red: the registry publishes a without dependencies.
    alter: red({
      packument: (name, doc) => {
        if (name === "a") delete doc.versions["1.0.0"].dependencies;
        return doc;
      },
    }),
  });
  const a = lock.packages.a?.[2];
  const negated = lock.packages.negated?.[2];
  if (JSON.stringify(a?.dependencies) !== JSON.stringify({ b: "^1.0.0" })) {
    canaryFail("C-INFODEPS", "info dependencies", "read_lockfile in bun/private/lockfile.bzl", LOCKFILE_SOURCE, a);
  }
  if (JSON.stringify(negated?.optionalDependencies) !== JSON.stringify({ "negated-not-win": "1.0.0" })) {
    canaryFail("C-INFODEPS", "info optionalDependencies", "read_lockfile in bun/private/lockfile.bzl", LOCKFILE_SOURCE, negated);
  }
});

test("info dependency ranges are written as the manifest writes them", async () => {
  const { lock } = await runInstall({ "package.json": manifest({ name: "c-infodeps-ranges", dependencies: { "range-user": "1.0.0" } }) }, {
    // Red: the registry publishes range-user's ranges as exact versions.
    alter: red({
      packument: (name, doc) => {
        if (name === "range-user") {
          doc.versions["1.0.0"].dependencies = { a: "1.0.0", b: "1.0.0", c: "1.0.0" };
          doc.versions["1.0.0"].optionalDependencies = { "ident-a": "1.0.0" };
        }
        return doc;
      },
    }),
  });
  const info = lock.packages["range-user"]?.[2];
  const reader = "parse_query in bun/private/bun_semver.bzl";
  if (JSON.stringify(info?.dependencies) !== JSON.stringify({ a: "~1.0.0", b: "1.0.0 - 1.9.9", c: "1.x" })) {
    canaryFail("C-INFODEPS", "info dependencies ranges", reader, LOCKFILE_SOURCE, info);
  }
  if (JSON.stringify(info?.optionalDependencies) !== JSON.stringify({ "ident-a": "^1.0.0 || ^2.0.0" })) {
    canaryFail("C-INFODEPS", "info optionalDependencies ranges", reader, LOCKFILE_SOURCE, info);
  }
});
