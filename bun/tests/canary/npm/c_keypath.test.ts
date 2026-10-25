// Canary C-KEYPATH (FR-024, research L8): a packages key is the path in Bun's
// hoisted tree: `c/b` is b as resolved under c, `w1/q` is q as resolved in
// workspace w1 (keyed by its package name), and a scoped package nested under a
// scoped package joins the two names with "/".

import { test } from "bun:test";
import { canaryFail, keysOf, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "split_key in bun/private/lockfile.bzl and the key walk in bun/private/resolve.bzl";

test("keys encode the hoisted tree", async () => {
  const { lock } = await runInstall(
    {
      "package.json": manifest({
        name: "c-keypath",
        workspaces: ["packages/*"],
        dependencies: { b: "1.0.0", c: "1.0.0", q: "1.0.0", "@scope/dep": "1.0.0", "@scope/dep-user": "1.0.0" },
      }),
      "packages/w1/package.json": manifest({ name: "w1", version: "1.0.0", dependencies: { q: "2.0.0" } }),
    },
    // Red: the root takes b@2.0.0, so c's b is hoisted.
    { alter: red({ files: (f) => ({ ...f, "package.json": f["package.json"].replace('"b": "1.0.0"', '"b": "2.0.0"') }) }) },
  );
  const expected = { "b@2.0.0": ["c/b"], "q@2.0.0": ["w1/q"], "@scope/dep@2.0.0": ["@scope/dep-user/@scope/dep"] };
  for (const [spec, keys] of Object.entries(expected)) {
    const actual = keysOf(lock, spec);
    if (JSON.stringify(actual) !== JSON.stringify(keys)) {
      canaryFail("C-KEYPATH", "packages key paths", READER, LOCKFILE_SOURCE, { spec, actual });
    }
  }
});
