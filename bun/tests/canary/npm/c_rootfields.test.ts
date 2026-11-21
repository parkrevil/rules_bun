// Canary C-ROOTFIELDS (feature 006, research Part 4 L34, L35): the pinned Bun writes `configVersion`
// as a whole number (LOCK L373) and, for a project whose `trustedDependencies` names a package of
// the tree, `trustedDependencies` as an array of the names (LOCK L510–L527), and a frozen install
// loads that text and keeps it (LOCK L1861–L1888). read_lockfile in bun/private/lockfile.bzl reads
// both only to refuse a form Bun refuses (T125), so each must stay in the form it accepts.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "read_lockfile in bun/private/lockfile.bzl";

const FILES = {
  "package.json": manifest({ name: "c-rootfields", dependencies: { a: "1.0.0" }, trustedDependencies: ["a"] }),
};

// The lockfile the pinned Bun writes for FILES, as a frozen install of it leaves it.
async function written(field: string): Promise<Record<string, any>> {
  const first = await runInstall(FILES);
  const { lock } = await runInstall(
    { ...FILES, "bun.lock": first.text },
    {
      dir: first.dir,
      frozenLockfile: true,
      // Red: the field is removed from the lockfile, which a frozen install keeps.
      alter: red({
        lockfile: (text) => {
          const removed = text.replace(new RegExp(`\\n\\s*"${field}": (\\d+|\\[[^\\]]*\\]),`), "");
          if (removed === text) throw new Error(`red: the lockfile has no "${field}" to remove`);
          return removed;
        },
      }),
    },
  );
  return lock;
}

test("configVersion is written as a whole number of at least 0", async () => {
  const lock = await written("configVersion");
  const value = lock.configVersion;
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    canaryFail("C-ROOTFIELDS", "configVersion", READER, LOCKFILE_SOURCE, value);
  }
});

test("trustedDependencies is written as an array of the trusted names", async () => {
  const lock = await written("trustedDependencies");
  const value = lock.trustedDependencies;
  if (!Array.isArray(value) || value.some((name) => typeof name !== "string") || JSON.stringify(value) !== JSON.stringify(["a"])) {
    canaryFail("C-ROOTFIELDS", "trustedDependencies", READER, LOCKFILE_SOURCE, value);
  }
});
