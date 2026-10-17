import { expect, test } from "bun:test";
import { existsSync, mkdtempSync } from "node:fs";
import { dirname, isAbsolute, join, relative } from "node:path";
import { executable, rlocation, spawnTarget } from "../../support/spawn.ts";

const TARGETS = ["_main/bun/tests/run/relative/print_runfiles", "_main/bun/tests/run/relative/print_runfiles_test"];

// The runfiles variables the target printed: each one it exported is absolute.
function printedRunfiles(stdout: string): { dir?: string; manifest?: string } {
  const line = stdout.split("\n").find((l) => l.startsWith("RUNFILES "));
  expect(line).toBeDefined();
  return JSON.parse(line!.slice("RUNFILES ".length));
}

function expectAbsoluteOrEmpty(value: string | undefined) {
  if (value) expect(isAbsolute(value)).toBe(true);
}

for (const target of TARGETS) {
  test(`${target} exports an absolute RUNFILES_DIR given a relative one`, async () => {
    if (!existsSync(join(process.env.RUNFILES_DIR!, target))) {
      console.log("Not applicable without a runfiles tree: the manifest case below covers it.");
      return;
    }
    const cwd = mkdtempSync(join(process.env.TEST_TMPDIR!, "relative-tree-"));
    const result = await spawnTarget(target, {
      cwd,
      env: {
        RUNFILES_DIR: relative(cwd, process.env.RUNFILES_DIR!),
        RUNFILES_MANIFEST_FILE: undefined,
        RUNFILES_MANIFEST_ONLY: undefined,
      },
    });
    expect(result.stderr).not.toContain("rules_bun");
    expect(result.exitCode).toBe(0);
    const printed = printedRunfiles(result.stdout);
    expect(printed.dir).toBeTruthy();
    expect(isAbsolute(printed.dir!)).toBe(true);
    expectAbsoluteOrEmpty(printed.manifest);
  });

  test(`${target} exports an absolute RUNFILES_MANIFEST_FILE given only a relative one`, async () => {
    const cwd = mkdtempSync(join(process.env.TEST_TMPDIR!, "relative-manifest-"));
    const manifest = rlocation(`${executable(target)}.runfiles_manifest`);
    const result = await spawnTarget(target, {
      cwd,
      env: {
        RUNFILES_DIR: undefined,
        RUNFILES_MANIFEST_FILE: relative(cwd, manifest),
        RUNFILES_MANIFEST_ONLY: undefined,
      },
    });
    expect(result.stderr).not.toContain("rules_bun");
    expect(result.exitCode).toBe(0);
    const printed = printedRunfiles(result.stdout);
    expect(printed.manifest).toBeTruthy();
    expect(isAbsolute(printed.manifest!)).toBe(true);
    expectAbsoluteOrEmpty(printed.dir);
  });
}

for (const target of TARGETS) {
  test(`${target} started by a relative path exports an absolute RUNFILES_MANIFEST_FILE`, async () => {
    // Without runfiles variables the Bash runfiles library finds `$0.runfiles_manifest`.
    const path = rlocation(executable(target));
    const cwd = dirname(dirname(path));
    const env: Record<string, string> = {};
    for (const [name, value] of Object.entries(process.env)) {
      if (value !== undefined && !name.startsWith("RUNFILES_")) env[name] = value;
    }
    const child = Bun.spawn([`./${relative(cwd, path)}`], { cwd, env, stdout: "pipe", stderr: "pipe" });
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(child.stdout).text(),
      new Response(child.stderr).text(),
      child.exited,
    ]);
    expect(stderr).not.toContain("rules_bun");
    expect(exitCode).toBe(0);
    const printed = printedRunfiles(stdout);
    expect(printed.manifest).toBeTruthy();
    expect(isAbsolute(printed.manifest!)).toBe(true);
    expectAbsoluteOrEmpty(printed.dir);
  });
}
