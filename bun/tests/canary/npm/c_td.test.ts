// Canary C-TD (FR-023, research G4): Bun 1.4.2 writes no trustedDependencies
// for an empty list, though bun.com says the lockfile records it even when
// empty, and writes the list when it is not empty. rules_bun reads neither and
// documents the difference.

import { test } from "bun:test";
import { canaryFail, manifest, red, runInstall } from "./support.ts";

const ACCESS = "trustedDependencies";
const REVISIT = "the documentation of trustedDependencies in bun/private/run.bzl";
const SOURCE = "https://bun.com/docs/pm/lifecycle";

test("an empty trustedDependencies is not written", async () => {
  const { lock } = await runInstall(
    { "package.json": manifest({ name: "c-td", dependencies: { scripted: "1.0.0" }, trustedDependencies: [] }) },
    // Red: the list is not empty.
    { lockfileOnly: true, alter: red({ files: (f) => ({ "package.json": f["package.json"].replace('"trustedDependencies": []', '"trustedDependencies": ["scripted"]') }) }) },
  );
  if ("trustedDependencies" in lock) canaryFail("C-TD", ACCESS, REVISIT, SOURCE, lock.trustedDependencies);
});

test("a non-empty trustedDependencies is written", async () => {
  // --lockfile-only: the canary pins what the lockfile records and must not run the
  // package's postinstall, which needs a host `node`.
  const { lock } = await runInstall(
    { "package.json": manifest({ name: "c-td", dependencies: { scripted: "1.0.0" }, trustedDependencies: ["scripted"] }) },
    { lockfileOnly: true },
  );
  if (JSON.stringify(lock.trustedDependencies) !== JSON.stringify(["scripted"])) {
    canaryFail("C-TD", ACCESS, REVISIT, SOURCE, lock.trustedDependencies);
  }
});
