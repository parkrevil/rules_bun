// Canary C-URL2 (FR-024, research L10, R11, E4): for an npm entry whose slot 1
// is "", Bun 1.4.2 requests `/{name}/-/{basename}-{version}.tgz` from the
// configured default registry, for scoped and unscoped packages alike.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const ACCESS = "npm entry slot 1 (reader)";
const READER = "package_url in bun/private/npmrc.bzl";

test('an empty slot 1 is fetched from the default registry at /{name}/-/{basename}-{version}.tgz', async () => {
  const files = { "package.json": manifest({ name: "c-url2", dependencies: { "@scope/s": "1.0.0", a: "1.0.0" } }) };
  const first = await runInstall(files, { lockfileOnly: true, registry: { tarballBase: "https://registry.npmjs.org" } });
  const slots = ["@scope/s", "a", "b"].map((key) => first.lock.packages[key]?.[1]);
  if (slots.some((slot) => slot !== "")) canaryFail("C-URL2", ACCESS, READER, LOCKFILE_SOURCE, { slots });

  let second;
  try {
    second = await runInstall(
      { ...files, "bun.lock": first.text },
      {
        dir: first.dir,
        frozenLockfile: true,
        // Red: the scoped entry records a full URL on a host nothing serves.
        alter: red({
          lockfile: (text) => text.replace('"@scope/s@1.0.0", ""', '"@scope/s@1.0.0", "http://127.0.0.1:9/@scope/s/-/s-1.0.0.tgz"'),
        }),
      },
    );
  } catch (error) {
    canaryFail("C-URL2", ACCESS, READER, LOCKFILE_SOURCE, String(error).split("\n").slice(0, 3).join(" "));
  }
  const tarballs = second.log.filter((entry) => entry.path.endsWith(".tgz")).map((entry) => entry.path).sort();
  const expected = ["/@scope/s/-/s-1.0.0.tgz", "/a/-/a-1.0.0.tgz", "/b/-/b-1.0.0.tgz"];
  if (JSON.stringify(tarballs) !== JSON.stringify(expected)) canaryFail("C-URL2", ACCESS, READER, LOCKFILE_SOURCE, { tarballs });
});
