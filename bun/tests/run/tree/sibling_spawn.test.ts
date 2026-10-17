import { expect, test } from "bun:test";
import { executable, rlocation, spawnTarget } from "../../support/spawn.ts";

const MISSING = "Cannot find module './undeclared.ts'";

// Bazel's runfiles manifest only, without the runfiles directory. Bazel names it
// after the executable, which is `<name>.exe` on Windows.
function manifestOnly(target: string) {
  const manifest = rlocation(`${executable(`_main/bun/tests/run/tree/${target}`)}.runfiles_manifest`);
  return { env: { RUNFILES_DIR: undefined, RUNFILES_MANIFEST_FILE: manifest } };
}

test("an undeclared sibling file cannot be imported", async () => {
  const result = await spawnTarget("_main/bun/tests/run/tree/sibling");
  expect(result.exitCode).not.toBe(0);
  expect(result.stdout).not.toContain("undeclared");
  expect(result.stderr).toContain(MISSING);
});

test("an undeclared sibling file cannot be imported through the manifest", async () => {
  const result = await spawnTarget("_main/bun/tests/run/tree/sibling", manifestOnly("sibling"));
  expect(result.exitCode).not.toBe(0);
  expect(result.stdout).not.toContain("undeclared");
  expect(result.stderr).toContain(MISSING);
});

test("a test cannot import an undeclared sibling file", async () => {
  const result = await spawnTarget("_main/bun/tests/run/tree/sibling_test");
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain(MISSING);
});

test("a test cannot import an undeclared sibling file through the manifest", async () => {
  const result = await spawnTarget("_main/bun/tests/run/tree/sibling_test", manifestOnly("sibling_test"));
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain(MISSING);
});
