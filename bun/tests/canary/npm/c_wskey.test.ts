// Canary C-WSKEY (FR-024, research L4): workspace member keys are paths
// relative to the lockfile.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

test("a member's workspaces key is its path relative to the lockfile", async () => {
  const { lock } = await runInstall(
    {
      "package.json": manifest({ name: "c-wskey", workspaces: ["packages/*"] }),
      "packages/w1/package.json": manifest({ name: "w1", version: "1.0.0", dependencies: { a: "1.0.0" } }),
    },
    // Red: the member lives in another directory.
    {
      alter: red({
        files: (f) => ({ "package.json": f["package.json"], "packages/elsewhere/package.json": f["packages/w1/package.json"] }),
      }),
    },
  );
  const keys = Object.keys(lock.workspaces).sort();
  if (JSON.stringify(keys) !== JSON.stringify(["", "packages/w1"])) {
    canaryFail("C-WSKEY", "workspaces keys", "read_lockfile in bun/private/lockfile.bzl", LOCKFILE_SOURCE, keys);
  }
});
