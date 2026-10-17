import { expect, test } from "bun:test";
import { executable, rlocation, spawnTarget } from "../../support/spawn.ts";

test("paths with a space resolve through the runfiles manifest only", async () => {
  // Bazel names the manifest after the executable, which is `<name>.exe` on Windows.
  const manifest = rlocation(`${executable("_main/bun/tests/run/spaces/spaces_test")}.runfiles_manifest`);
  const result = await spawnTarget("_main/bun/tests/run/spaces/spaces_test", {
    env: { RUNFILES_DIR: undefined, RUNFILES_MANIFEST_FILE: manifest },
  });
  expect(result.stderr).not.toContain("is not in the runfiles manifest");
  expect(result.exitCode).toBe(0);
  expect(result.stdout + result.stderr).toContain("manifest assertion ran");
});
