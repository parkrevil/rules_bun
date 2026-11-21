// Canary C-VER0 (feature 006 BC-19 and ID-11, research L2): a version-2 lockfile whose stamp is
// edited to 0 is loaded by Bun 1.4.4 and re-saved with lockfileVersion 1, with the entry shapes
// the reader reads on version 1 (`Stringifier::version_to_write`, src/install/lockfile/bun.lock.rs
// L170–L177 and L195–L202 @ bun-v1.4.4: v0 is floored to v1, the lowest version whose content is
// what Bun writes). This pins that Bun loads version 0 and the remedy ID-11's error names.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const ACCESS = "lockfileVersion 0 on re-save";
const READER = "SUPPORTED_VERSIONS and read_lockfile in bun/private/lockfile.bzl";

test("Bun loads lockfileVersion 0 and re-saves it as 1 with the version-1 entry shapes", async () => {
  const first = await runInstall({ "package.json": manifest({ name: "c-ver0", dependencies: { a: "1.0.0" } }) });
  const edited = first.text.replace('"lockfileVersion": 2,', '"lockfileVersion": 0,');
  const { lock, output } = await runInstall(
    {
      "package.json": manifest({ name: "c-ver0", dependencies: { a: "1.0.0", p: "1.0.0", q: "1.0.0" } }),
      "bun.lock": edited,
    },
    // Red: the stamp is left at 2.
    { dir: first.dir, alter: red({ lockfile: (text) => text.replace('"lockfileVersion": 0,', '"lockfileVersion": 2,') }) },
  );
  // A lockfile Bun refuses is ignored and written again from the registry (`warn: Ignoring lockfile`).
  if (output.includes("Ignoring lockfile")) canaryFail("C-VER0", ACCESS, READER, LOCKFILE_SOURCE, output);
  if (lock.lockfileVersion !== 1) canaryFail("C-VER0", ACCESS, READER, LOCKFILE_SOURCE, lock.lockfileVersion);
  const a = lock.packages.a;
  const p = lock.packages.p;
  const shapes =
    a.length === 4 &&
    typeof a[1] === "string" &&
    typeof a[3] === "string" &&
    a[2].dependencies?.b === "^1.0.0" &&
    Array.isArray(p[2].optionalPeers) &&
    typeof p[2].peerDependencies === "object";
  if (!shapes) canaryFail("C-VER0", "entry shapes under lockfileVersion 0 re-saved", READER, LOCKFILE_SOURCE, { a, p });
});
