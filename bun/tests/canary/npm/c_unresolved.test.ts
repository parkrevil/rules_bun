// Canary C-UNRESOLVED (feature 006, research Part 4 L23, L24): an optional dependency no version
// satisfies, while the tree holds a package of its name, is listed by name under `unresolved`, on
// the package entry that declares it and on the workspace that declares it (LOCK L302–L320).

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "_parse_append_dependencies in bun/private/bun_lockfile.bzl";

test("unresolved optional dependencies of a package and of workspaces", async () => {
  const { lock } = await runInstall(
    {
      "package.json": manifest({
        name: "c-unresolved",
        workspaces: ["packages/*"],
        dependencies: { a: "1.0.0", "opt-user": "1.0.0", q: "1.0.0" },
        optionalDependencies: { b: "^3.0.0" },
      }),
      "packages/w/package.json": manifest({ name: "w", version: "1.0.0", optionalDependencies: { q: "^3.0.0" } }),
    },
    {
      // Red: the registry publishes opt-user's optional state with a range state@1.0.0 satisfies.
      alter: red({
        packument: (name, doc) => {
          if (name === "opt-user") doc.versions["1.0.0"].optionalDependencies.state = "1.0.0";
          return doc;
        },
      }),
    },
  );
  const info = lock.packages["opt-user"]?.[2];
  if (JSON.stringify(info?.unresolved) !== JSON.stringify(["state"])) {
    canaryFail("C-UNRESOLVED", "info unresolved", READER, LOCKFILE_SOURCE, info);
  }
  for (const [path, name] of [["", "b"], ["packages/w", "q"]]) {
    const workspace = lock.workspaces[path];
    if (JSON.stringify(workspace?.unresolved) !== JSON.stringify([name])) {
      canaryFail("C-UNRESOLVED", "workspaces[*].unresolved", READER, LOCKFILE_SOURCE, { path, workspace });
    }
  }
});
