// Canary C-WSOPTPEERS (feature 006, research Part 4 L33): a workspace whose package.json marks a peer
// optional (peerDependenciesMeta) is written with that peer under `peerDependencies` and its name
// under `optionalPeers` (LOCK L1184–L1240 writer, L1192–L1197; L3372–L3400 reader).

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "read_lockfile in bun/private/lockfile.bzl (a workspace's optionalPeers, # L33) and _parse_append_dependencies in bun/private/bun_lockfile.bzl";

const member = (optional: boolean) =>
  manifest({
    name: "w",
    version: "1.0.0",
    peerDependencies: { q: "^1.0.0" },
    ...(optional ? { peerDependenciesMeta: { q: { optional: true } } } : {}),
  });

test("a workspace's optional peer is listed under optionalPeers", async () => {
  const { lock } = await runInstall(
    {
      "package.json": manifest({ name: "c-wsoptpeers", workspaces: ["packages/*"], dependencies: { q: "1.0.0" } }),
      "packages/w/package.json": member(true),
    },
    {
      // Red: the peer is not marked optional.
      alter: red({ files: (files) => ({ ...files, "packages/w/package.json": member(false) }) }),
    },
  );
  const workspace = lock.workspaces["packages/w"];
  if (
    JSON.stringify(workspace?.peerDependencies) !== JSON.stringify({ q: "^1.0.0" }) ||
    JSON.stringify(workspace?.optionalPeers) !== JSON.stringify(["q"])
  ) {
    canaryFail("C-WSOPTPEERS", "workspaces[*].optionalPeers", READER, LOCKFILE_SOURCE, workspace);
  }
});
