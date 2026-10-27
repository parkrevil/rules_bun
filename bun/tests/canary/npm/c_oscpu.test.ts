// Canary C-OSCPU (FR-024, research L15): `os` and `cpu` are written as a string
// for one value and an array for several. Bun 1.4.4 writes `libc` beside them,
// which canary C-LIBC pins (feature 004 research R11).

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "the os and cpu of an entry in bun/private/lockfile.bzl";

test("os and cpu forms", async () => {
  const { lock } = await runInstall(
    { "package.json": manifest({ name: "c-oscpu", optionalDependencies: { "native-linux-x64": "1.0.0", "multi-os": "1.0.0" } }) },
    // Red: the registry publishes native-linux-x64 for two CPUs.
    {
      alter: red({
        packument: (name, doc) => {
          if (name === "native-linux-x64") doc.versions["1.0.0"].cpu = ["x64", "arm64"];
          return doc;
        },
      }),
    },
  );
  const one = lock.packages["native-linux-x64"]?.[2];
  const many = lock.packages["multi-os"]?.[2];
  if (one?.os !== "linux" || one?.cpu !== "x64") {
    canaryFail("C-OSCPU", "info os and cpu (one value)", READER, LOCKFILE_SOURCE, one);
  }
  if (JSON.stringify(many?.os) !== JSON.stringify(["linux", "darwin"]) || JSON.stringify(many?.cpu) !== JSON.stringify(["x64", "arm64"])) {
    canaryFail("C-OSCPU", "info os and cpu (several values)", READER, LOCKFILE_SOURCE, many);
  }
});
