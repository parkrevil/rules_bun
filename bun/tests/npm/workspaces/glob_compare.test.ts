// The workspace glob matcher against Bun 1.4.2 (research R9): for each case of
// glob_cases.bzl the pinned Bun's `install --lockfile-only` writes the
// lockfile's `workspaces` keys, which must equal the member set
// glob_members.json holds.

import { afterAll, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { startRegistry } from "../../support/npm_registry.ts";
import { rlocation } from "../../support/spawn.ts";

const DATA = JSON.parse(readFileSync(rlocation("_main/bun/tests/npm/workspaces/glob_members.json"), "utf8"));
const registry = startRegistry({ archives: [rlocation("_main/bun/tests/npm/registry/archives/b@1.0.0.tgz")] });
afterAll(() => registry.stop());

function tree(): string {
  const dir = mkdtempSync(join(process.env.TEST_TMPDIR!, "glob-"));
  for (const path of DATA.tree as string[]) mkdirSync(join(dir, path), { recursive: true });
  for (const path of DATA.manifests as string[]) {
    writeFileSync(join(dir, path, "package.json"), JSON.stringify({ name: `m-${path.replaceAll("/", "-").replaceAll(".", "_")}`, version: "1.0.0" }));
  }
  return dir;
}

for (const [name, workspaces] of Object.entries(DATA.cases as Record<string, unknown>)) {
  test(`${name}: ${JSON.stringify(workspaces)}`, async () => {
    const dir = tree();
    // A dependency, so that Bun writes a lockfile even when no member matches.
    writeFileSync(join(dir, "package.json"), JSON.stringify({ name: "root", private: true, workspaces, dependencies: { b: "1.0.0" } }));
    const child = Bun.spawn([process.execPath, "install", "--lockfile-only", `--registry=${registry.url}`], {
      cwd: dir,
      env: { ...process.env, BUN_INSTALL_CACHE_DIR: join(dir, ".cache"), NO_COLOR: "1" },
      stdout: "pipe",
      stderr: "pipe",
    });
    const [stderr, exitCode] = await Promise.all([new Response(child.stderr).text(), child.exited]);
    expect(exitCode, stderr).toBe(0);
    const lock = Bun.JSONC.parse(readFileSync(join(dir, "bun.lock"), "utf8")) as Record<string, any>;
    const keys = Object.keys(lock.workspaces).filter((k) => k !== "").sort();
    expect(DATA.members[name]).toEqual(keys);
  });
}
