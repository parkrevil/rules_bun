// Canary C-BIN (FR-024, research L16): `bin` is written as a string or an
// object as the manifest writes it; `directories.bin` is written as `binDir`,
// not `bin`.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "the bin of an entry in bun/private/lockfile.bzl";

test("bin forms and binDir", async () => {
  const { lock } = await runInstall(
    { "package.json": manifest({ name: "c-bin", dependencies: { "single-bin": "1.0.0", "@scope/s": "1.0.0", dirbin: "1.0.0" } }) },
    // Red: the registry publishes single-bin's bin as an object.
    {
      alter: red({
        packument: (name, doc) => {
          if (name === "single-bin") doc.versions["1.0.0"].bin = { "single-bin": "cli.ts" };
          return doc;
        },
      }),
    },
  );
  const single = lock.packages["single-bin"]?.[2];
  const scoped = lock.packages["@scope/s"]?.[2];
  const dir = lock.packages.dirbin?.[2];
  if (single?.bin !== "cli.ts") canaryFail("C-BIN", "info bin (string)", READER, LOCKFILE_SOURCE, single);
  if (JSON.stringify(scoped?.bin) !== JSON.stringify({ "s-tool": "bin/tool.js", "s-other": "bin/other.mjs" })) {
    canaryFail("C-BIN", "info bin (object)", READER, LOCKFILE_SOURCE, scoped);
  }
  if (dir?.binDir !== "bin" || "bin" in (dir ?? {})) canaryFail("C-BIN", "info binDir", READER, LOCKFILE_SOURCE, dir);
});
