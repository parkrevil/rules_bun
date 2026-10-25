// Canary C-WSNAME (FR-024, research L5): each workspaces value holds the
// member's name.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

test("each workspaces value holds name", async () => {
  const { lock } = await runInstall(
    {
      "package.json": manifest({ name: "c-wsname", workspaces: ["packages/*"] }),
      "packages/w1/package.json": manifest({ name: "w1", version: "1.0.0" }),
    },
    // Red: the member is named differently.
    { alter: red({ files: (f) => ({ ...f, "packages/w1/package.json": manifest({ name: "renamed", version: "1.0.0" }) }) }) },
  );
  if (lock.workspaces[""]?.name !== "c-wsname" || lock.workspaces["packages/w1"]?.name !== "w1") {
    canaryFail("C-WSNAME", "workspaces[*].name", "read_lockfile in bun/private/lockfile.bzl", LOCKFILE_SOURCE, lock.workspaces);
  }
});
