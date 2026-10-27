// Canary C-VER1 (FR-024, research L2, G7): a version-2 lockfile whose stamp is
// edited to 1 keeps lockfileVersion 1 when Bun 1.4.4 re-saves it, with entries
// of the shapes the reader reads (L9-L16).

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const ACCESS = "lockfileVersion 1 on re-save";
const READER = "SUPPORTED_VERSIONS and read_lockfile in bun/private/lockfile.bzl";

test("Bun keeps lockfileVersion 1 on re-save and writes the version-2 entry shapes", async () => {
  const first = await runInstall({ "package.json": manifest({ name: "c-ver1", dependencies: { a: "1.0.0" } }) });
  const edited = first.text.replace('"lockfileVersion": 2,', '"lockfileVersion": 1,');
  const { lock } = await runInstall(
    {
      "package.json": manifest({ name: "c-ver1", dependencies: { a: "1.0.0", "@scope/s": "1.0.0", p: "1.0.0", q: "1.0.0", "multi-os": "1.0.0" } }),
      "bun.lock": edited,
    },
    // Red: the stamp is left at 2.
    { dir: first.dir, alter: red({ lockfile: (text) => text.replace('"lockfileVersion": 1,', '"lockfileVersion": 2,') }) },
  );
  if (lock.lockfileVersion !== 1) canaryFail("C-VER1", ACCESS, READER, LOCKFILE_SOURCE, lock.lockfileVersion);
  const a = lock.packages.a;
  const s = lock.packages["@scope/s"];
  const p = lock.packages.p;
  const multi = lock.packages["multi-os"];
  const shapes =
    a.length === 4 &&
    typeof a[1] === "string" &&
    typeof a[3] === "string" &&
    a[2].dependencies?.b === "^1.0.0" &&
    typeof s[2].bin === "object" &&
    Array.isArray(p[2].optionalPeers) &&
    typeof p[2].peerDependencies === "object" &&
    Array.isArray(multi[2].os);
  if (!shapes) canaryFail("C-VER1", "entry shapes under lockfileVersion 1", READER, LOCKFILE_SOURCE, { a, s, p, multi });
});
