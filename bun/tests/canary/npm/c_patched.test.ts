// Canary C-PATCHED (FR-010, research L20, R13): `bun patch --commit` writes
// `patchedDependencies` keyed `name@version`, which unsupported_reason matches
// against each entry's name and version.

import { expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { startRegistry } from "../../support/npm_registry.ts";
import { rlocation } from "../../support/spawn.ts";
import { canaryFail, LOCKFILE_SOURCE, manifest, red } from "./support.ts";

const ACCESS = "patchedDependencies";
const READER = "read_lockfile in bun/private/lockfile.bzl and unsupported_reason in bun/private/resolve.bzl";

test("bun patch --commit writes patchedDependencies keyed name@version", async () => {
  const registry = startRegistry({
    archives: ["q@1.0.0", "r@1.0.0"].map((p) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`)),
  });
  try {
    const dir = mkdtempSync(join(process.env.TEST_TMPDIR!, "c-patched-"));
    let files = { "package.json": manifest({ name: "c-patched", dependencies: { r: "1.0.0" } }) };
    // Red: the project depends on q instead, so q is the package patched.
    const alter = red({ files: (f) => ({ "package.json": f["package.json"].replace('"r"', '"q"') }) });
    if (alter?.files) files = alter.files(files);
    writeFileSync(join(dir, "package.json"), files["package.json"]);
    const name = Object.keys(JSON.parse(files["package.json"]).dependencies)[0];
    const env = {
      ...process.env,
      BUN_CONFIG_REGISTRY: registry.url,
      BUN_INSTALL_CACHE_DIR: mkdtempSync(join(process.env.TEST_TMPDIR!, "c-patched-cache-")),
      NO_COLOR: "1",
    };
    // Asynchronous: the loopback registry runs in this process.
    const bun = async (...args: string[]) => {
      const child = Bun.spawn([process.execPath, ...args], { cwd: dir, env, stdout: "pipe", stderr: "pipe" });
      const [stderr, exitCode] = await Promise.all([new Response(child.stderr).text(), child.exited]);
      expect(exitCode, `bun ${args.join(" ")}: ${stderr}`).toBe(0);
    };
    await bun("install", `--registry=${registry.url}`);
    await bun("patch", name);
    writeFileSync(join(dir, "node_modules", name, "index.js"), "module.exports = 'patched';\n");
    await bun("patch", "--commit", `node_modules/${name}`);
    const lock = Bun.JSONC.parse(readFileSync(join(dir, "bun.lock"), "utf8")) as Record<string, any>;
    const keys = Object.keys(lock.patchedDependencies ?? {});
    if (JSON.stringify(keys) !== JSON.stringify(["r@1.0.0"])) canaryFail("C-PATCHED", ACCESS, READER, LOCKFILE_SOURCE, keys);
  } finally {
    registry.stop();
  }
});
