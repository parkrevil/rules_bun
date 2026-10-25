// Canary C-URL1 (FR-024, research L10, E2, E4): Bun 1.4.2 writes slot 1 as ""
// when the manifest's tarball is under https://registry.npmjs.org/, and the
// full URL otherwise.

import { test } from "bun:test";
import { canaryFail, LOCKFILE_SOURCE, manifest, red, runInstall } from "./support.ts";

const READER = "the URL construction of an empty slot in bun/private/npm_extension.bzl";
const files = { "package.json": manifest({ name: "c-url1", dependencies: { "@scope/s": "1.0.0" } }) };

test("slot 1 is empty for a tarball under the default registry", async () => {
  const { lock } = await runInstall(files, {
    lockfileOnly: true,
    registry: { tarballBase: "https://registry.npmjs.org" },
    // Red: the manifest's tarball is on another host.
    alter: red({ packument: (_name, doc) => JSON.parse(JSON.stringify(doc).replaceAll("https://registry.npmjs.org", "https://example.com")) }),
  });
  const slot = lock.packages["@scope/s"]?.[1];
  if (slot !== "") canaryFail("C-URL1", "npm entry slot 1 (writer)", READER, LOCKFILE_SOURCE, slot);
});

test("slot 1 is the full URL for a tarball elsewhere", async () => {
  const { lock, url } = await runInstall(files, { lockfileOnly: true });
  const slot = lock.packages["@scope/s"]?.[1];
  if (slot !== `${url}/@scope/s/-/s-1.0.0.tgz`) canaryFail("C-URL1", "npm entry slot 1 (writer)", READER, LOCKFILE_SOURCE, slot);
});
