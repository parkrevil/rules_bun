// Canary C-WSDEPS (FR-024, research L6): a member's devDependencies,
// optionalDependencies and peerDependencies are recorded exactly as written.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const MEMBER = {
  name: "w1",
  version: "1.0.0",
  dependencies: { w2: "workspace:*" },
  devDependencies: { q: "catalog:" },
  optionalDependencies: { aliased: "npm:b@2.0.0" },
  peerDependencies: { state: "1.0.0" },
};

test("member dependency maps are recorded as written", async () => {
  const { lock } = await runInstall(
    {
      "package.json": manifest({ name: "c-wsdeps", workspaces: { packages: ["packages/*"], catalog: { q: "1.0.0" } } }),
      "packages/w1/package.json": manifest(MEMBER),
      "packages/w2/package.json": manifest({ name: "w2", version: "1.0.0" }),
    },
    // Red: the member writes its dev dependency as a version, not "catalog:".
    {
      alter: red({
        files: (f) => ({ ...f, "packages/w1/package.json": manifest({ ...MEMBER, devDependencies: { q: "1.0.0" } }) }),
      }),
    },
  );
  const w1 = lock.workspaces["packages/w1"] ?? {};
  for (const kind of ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"] as const) {
    if (JSON.stringify(w1[kind]) !== JSON.stringify(MEMBER[kind])) {
      canaryFail("C-WSDEPS", `workspaces[*].${kind}`, "read_lockfile in bun/private/lockfile.bzl", LOCKFILE_SOURCE, w1);
    }
  }
});
