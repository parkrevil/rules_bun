import { expect, test } from "bun:test";
import { spawnTarget } from "../../support/spawn.ts";

// Not run on Windows: the hermetic-launcher stub splits arguments containing `"`
// there (hermeticbuild/hermetic-launcher#80, G1).
test("arguments containing quotes arrive unchanged", async () => {
  const args = ['"q"', 'a"b', 'a\\"b'];
  const result = await spawnTarget("_main/bun/tests/run/args/echo", { args });
  expect(result.exitCode).toBe(0);
  expect(JSON.parse(result.stdout)).toEqual({ argv: args, main: true });
});
