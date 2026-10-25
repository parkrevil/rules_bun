// FR-022 with packages: carrying packages does not let a bun_binary or bun_test
// read a bunfig.toml or .env of its working directory, or install a package
// that bun.lock does not list (feature 002's isolation, research R5).

import { afterAll, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { startRegistry } from "../../../../support/npm_registry.ts";
import { rlocation, spawnTarget } from "../../../../support/spawn.ts";

const PACKAGE = "_main/bun/tests/npm/fixtures/basic/isolation";
const MARKER = "RULES_BUN_CWD_BUNFIG_PRELOAD";

// Serves the package missing.ts imports, so an install would succeed.
const registry = startRegistry({
  archives: [rlocation("_main/bun/tests/run/isolation/registry/rules-bun-fixture-pkg-1.0.0.tgz")],
});
afterAll(() => registry.stop());

// A working directory whose bunfig.toml preloads set.ts (for `bun` and
// `bun test`) and whose .env defines RULES_BUN_DOTENV.
function workingDirectory(): string {
  const dir = mkdtempSync(join(process.env.TEST_TMPDIR!, "cwd-"));
  writeFileSync(join(dir, "bunfig.toml"), 'preload = ["./set.ts"]\n\n[test]\npreload = ["./set.ts"]\n');
  writeFileSync(join(dir, "set.ts"), `globalThis.__RULES_BUN_BUNFIG = "read";\nconsole.error(${JSON.stringify(MARKER)});\n`);
  writeFileSync(join(dir, ".env"), "RULES_BUN_DOTENV=leaked\n");
  return dir;
}

test("probe loads a and reads no bunfig.toml or .env of its working directory", async () => {
  const result = await spawnTarget(`${PACKAGE}/probe`, { cwd: workingDirectory() });
  expect(result.exitCode, result.stderr).toBe(0);
  expect(JSON.parse(result.stdout)).toEqual({ a: "1.0.0", bunfig: null, dotenv: null });
  if (process.platform !== "win32") expect(result.stderr).not.toContain(MARKER);
});

test("probe_test loads a and reads no bunfig.toml or .env of its working directory", async () => {
  const result = await spawnTarget(`${PACKAGE}/probe_test`, { cwd: workingDirectory() });
  expect(result.exitCode, result.stdout + result.stderr).toBe(0);
  if (process.platform !== "win32") expect(result.stdout + result.stderr).not.toContain(MARKER);
});

for (const target of ["missing", "missing_test"]) {
  test(`${target} does not install a package bun.lock does not list`, async () => {
    const cache = mkdtempSync(join(process.env.TEST_TMPDIR!, "cache-"));
    const cwd = join(cache, "..", `${target}-cwd`);
    mkdirSync(cwd, { recursive: true });
    const result = await spawnTarget(`${PACKAGE}/${target}`, {
      cwd,
      env: { BUN_CONFIG_REGISTRY: registry.url, BUN_INSTALL_CACHE_DIR: cache },
    });
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout + result.stderr).toMatch(/Cannot find (?:module|package) ['"]rules-bun-fixture-pkg['"]/);
    expect(readdirSync(cache)).toEqual([]);
    expect(registry.log).toEqual([]);
  });
}
