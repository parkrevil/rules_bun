// Canary C-VER (FR-024, research L2, G7): Bun 1.4.2 writes lockfileVersion 2 for
// a plain install and 3 for a scoped override.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const ACCESS = "lockfileVersion";
const READER = "SUPPORTED_VERSIONS and read_lockfile in bun/private/lockfile.bzl";

test("a plain install writes lockfileVersion 2", async () => {
  const { lock } = await runInstall({ "package.json": manifest({ name: "c-ver", dependencies: { a: "1.0.0" } }) });
  if (lock.lockfileVersion !== 2) canaryFail("C-VER", ACCESS, READER, LOCKFILE_SOURCE, lock.lockfileVersion);
});

test("a scoped override writes lockfileVersion 3", async () => {
  const { lock } = await runInstall(
    { "package.json": manifest({ name: "c-ver", dependencies: { a: "1.0.0" }, overrides: { "a>b": "2.0.0" } }) },
    // Red: a flat override instead of the scoped one.
    { alter: red({ files: (f) => ({ ...f, "package.json": f["package.json"].replace('"a>b"', '"b"') }) }) },
  );
  if (lock.lockfileVersion !== 3) canaryFail("C-VER", ACCESS, READER, LOCKFILE_SOURCE, lock.lockfileVersion);
});
