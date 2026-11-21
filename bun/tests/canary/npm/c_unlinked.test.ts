// Canary C-UNLINKED (feature 006, research Part 4 L25): a workspace named like a package the root
// aliases is not linked at its name, and its dependencies get the keys `./<name>/<dep>`, for an
// unscoped and a scoped name.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "the workspace dependency resolutions of _resolve_rows in bun/private/bun_lockfile.bzl";

test("keys ./<name>/<dep> of workspaces named like a root alias", async () => {
  const { lock } = await runInstall(
    {
      "package.json": manifest({
        name: "c-unlinked",
        workspaces: ["packages/*"],
        dependencies: { lib: "npm:a@1.0.0", "@scope/lib": "npm:c@1.0.0", b: "1.0.0" },
      }),
      "packages/lib/package.json": manifest({ name: "lib", version: "1.0.0", dependencies: { b: "2.0.0" } }),
      "packages/scoped/package.json": manifest({ name: "@scope/lib", version: "1.0.0", dependencies: { b: "2.0.0" } }),
      "packages/app/package.json": manifest({ name: "app", version: "1.0.0", dependencies: { lib: "workspace:*", "@scope/lib": "workspace:*" } }),
    },
    {
      // Red: the root aliases no package as lib or @scope/lib.
      alter: red({
        files: (f) => ({ ...f, "package.json": manifest({ name: "c-unlinked", workspaces: ["packages/*"], dependencies: { b: "1.0.0" } }) }),
      }),
    },
  );
  for (const key of ["./lib/b", "./@scope/lib/b"]) {
    if (lock.packages[key]?.[0] !== "b@2.0.0") canaryFail("C-UNLINKED", `key ${key}`, READER, LOCKFILE_SOURCE, Object.keys(lock.packages));
  }
});
