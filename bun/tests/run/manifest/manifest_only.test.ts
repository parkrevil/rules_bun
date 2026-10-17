import { expect, test } from "bun:test";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { executable, rlocation, spawnTarget } from "../../support/spawn.ts";

const LAUNCH_CONFIG = "_main/bun/tests/run/hello.launch.json";

// The runfiles variables of a test that runs without a sandbox and without a
// runfiles tree: an empty RUNFILES_DIR, and Bazel's manifest.
function manifestOnly(manifest: string) {
  return {
    env: {
      RUNFILES_DIR: mkdtempSync(join(process.env.TEST_TMPDIR!, "empty-runfiles-")),
      RUNFILES_MANIFEST_FILE: manifest,
      RUNFILES_MANIFEST_ONLY: "1",
    },
  };
}

// Bazel writes the manifest next to the executable, named after it.
function manifestOf(target: string): string {
  return rlocation(`${executable(target)}.runfiles_manifest`);
}

test("a program runs from the manifest when the runfiles directory is empty", async () => {
  const result = await spawnTarget("_main/bun/tests/run/hello", manifestOnly(manifestOf("_main/bun/tests/run/hello")));
  expect(result.stderr).toBe("");
  expect(result.exitCode).toBe(0);
  expect(result.stdout).toBe("hello\n");
});

test("a test runs from the manifest when the runfiles directory is empty", async () => {
  const result = await spawnTarget(
    "_main/bun/tests/run/skeleton_test",
    manifestOnly(manifestOf("_main/bun/tests/run/skeleton_test")),
  );
  expect(result.exitCode).toBe(0);
});

test("a launch configuration missing from the manifest fails naming it", async () => {
  if (process.platform === "win32") {
    console.log("Not applicable on Windows: the stub reports a missing runfile its own way.");
    return;
  }
  const lines = readFileSync(manifestOf("_main/bun/tests/run/hello"), "utf8").split("\n");
  const kept = lines.filter((line) => !line.startsWith(`${LAUNCH_CONFIG} `));
  expect(kept.length).toBe(lines.length - 1);
  const manifest = join(mkdtempSync(join(process.env.TEST_TMPDIR!, "manifest-")), "MANIFEST");
  writeFileSync(manifest, kept.join("\n"));

  const result = await spawnTarget("_main/bun/tests/run/hello", manifestOnly(manifest));
  expect(result.exitCode).toBe(1);
  expect(result.stdout).toBe("");
  expect(result.stderr).toContain(LAUNCH_CONFIG);
});
