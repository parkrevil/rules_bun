// BC-16 (feature 006): plat-peer-host@1.0.0 is one store entry on every platform, and its p is a
// different one by target platform. On darwin p binds its peer q to the root's q, q-darwin@1.0.0;
// elsewhere q-darwin is disabled, so p binds no q and loading it fails, as in Bun's install.

import { expect, test } from "bun:test";
import { realpathSync } from "node:fs";
import { createRequire } from "node:module";

const posix = (path: string) => realpathSync(path).replaceAll("\\", "/");
const host = require.resolve("plat-peer-host");
const p = createRequire(host).resolve("p");

test("plat-peer-host has no peer bindings", () => {
  expect(posix(host)).toContain("/.store/plat-peer-host@1.0.0/node_modules/plat-peer-host/");
});

test.if(process.platform === "darwin")("on darwin p binds its peer q to q-darwin@1.0.0", () => {
  expect(posix(p)).toMatch(/\.store\/p@1\.0\.0\+[0-9a-f]{16}\/node_modules\/p\//);
  expect(posix(createRequire(p).resolve("q"))).toContain("/.store/q-darwin@1.0.0/node_modules/q-darwin/");
  expect(require("plat-peer-host").p.q).toBe("1.0.0");
});

test.skipIf(process.platform === "darwin")("off darwin p binds no q", () => {
  expect(posix(p)).toContain("/.store/p@1.0.0/node_modules/p/");
  expect(() => createRequire(p).resolve("q")).toThrow();
});
