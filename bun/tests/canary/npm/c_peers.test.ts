// Canary C-PEERS (FR-024, research L14, E1): slot 2 holds `peerDependencies`
// and `optionalPeers` (an array of names), and a package installed with two
// peer resolutions has one entry.

import { test } from "bun:test";
import { canaryFail, keysOf, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "read_lockfile in bun/private/lockfile.bzl and the peer rules in bun/private/resolve.bzl";

test("peers, optional peers, and one entry for two peer resolutions", async () => {
  const { lock } = await runInstall(
    {
      "package.json": manifest({ name: "c-peers", workspaces: ["packages/*"], dependencies: { p: "1.0.0", q: "1.0.0" } }),
      "packages/w1/package.json": manifest({ name: "w1", version: "1.0.0", dependencies: { p: "1.0.0", q: "2.0.0" } }),
    },
    // Red: the registry publishes r as a required peer.
    {
      alter: red({
        packument: (name, doc) => {
          if (name === "p") delete doc.versions["1.0.0"].peerDependenciesMeta;
          return doc;
        },
      }),
    },
  );
  const info = lock.packages.p?.[2];
  if (JSON.stringify(info?.peerDependencies) !== JSON.stringify({ q: "^1.0.0 || ^2.0.0", r: "^1.0.0" })) {
    canaryFail("C-PEERS", "info peerDependencies", READER, LOCKFILE_SOURCE, info);
  }
  if (JSON.stringify(info?.optionalPeers) !== JSON.stringify(["r"])) {
    canaryFail("C-PEERS", "info optionalPeers", READER, LOCKFILE_SOURCE, info);
  }
  const entries = keysOf(lock, "p@1.0.0");
  if (entries.length !== 1) canaryFail("C-PEERS", "one entry per peer-resolved package", READER, LOCKFILE_SOURCE, entries);
});
