// BC-12 (feature 006): the root's plat-peer-host is a different store entry by target platform.
// Off darwin its own q (q-darwin@1.0.0) is disabled, so its p binds the peer q to the root's
// q@1.0.0, which leaks to plat-peer-host: its store directory carries a peer hash.

import { expect, test } from "bun:test";
import { realpathSync } from "node:fs";
import { createRequire } from "node:module";

const posix = (path: string) => realpathSync(path).replaceAll("\\", "/");

test.skipIf(process.platform === "darwin")("plat-peer-host's p binds its peer q to the root's q@1.0.0", () => {
  const host = require.resolve("plat-peer-host");
  const p = createRequire(host).resolve("p");
  const q = createRequire(p).resolve("q");
  expect(posix(host)).toMatch(/\.store\/plat-peer-host@1\.0\.0\+[0-9a-f]{16}\/node_modules\/plat-peer-host\//);
  expect(posix(q)).toContain("/.store/q@1.0.0/node_modules/q/");
  expect(require("plat-peer-host").p.q).toBe("1.0.0");
});
