// Canary C-WSVERSION (feature 006, research Part 4 L28): a workspace's `version` is written in
// `workspaces`, and a member's peer on that workspace's name with a range the version satisfies
// is linked to the workspace.

import { test } from "bun:test";
import { realpathSync } from "node:fs";
import { join } from "node:path";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "parse_into_binary_lockfile and linked_member in bun/private/bun_lockfile.bzl";

test("workspace versions and a peer bound to a workspace", async () => {
  const { dir, lock } = await runInstall(
    {
      "package.json": manifest({ name: "c-wsversion", workspaces: ["packages/*"], dependencies: { w: "workspace:*" } }),
      "packages/w/package.json": manifest({ name: "w", version: "1.0.0", peerDependencies: { q: "^1.0.0" } }),
      "packages/q/package.json": manifest({ name: "q", version: "1.5.0" }),
    },
    {
      args: ["--linker", "isolated"],
      // Red: the workspace q has no version.
      alter: red({ files: (f) => ({ ...f, "packages/q/package.json": manifest({ name: "q" }) }) }),
    },
  );
  const q = lock.workspaces["packages/q"];
  if (q?.version !== "1.5.0") canaryFail("C-WSVERSION", "workspaces[*].version", READER, LOCKFILE_SOURCE, q);
  const linked = realpathSync(join(dir, "packages/w/node_modules/q"));
  if (linked !== realpathSync(join(dir, "packages/q"))) {
    canaryFail("C-WSVERSION", "a peer bound to a workspace by version", READER, LOCKFILE_SOURCE, linked);
  }
});
