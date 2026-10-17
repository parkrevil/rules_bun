import { expect, test } from "bun:test";
import { spawnTarget } from "../../support/spawn.ts";

test("the program reads its standard input", async () => {
  const result = await spawnTarget("_main/bun/tests/run/stdin/cat", { stdin: "ping\n" });
  expect(result.exitCode).toBe(0);
  expect(result.stdout).toBe("ping\n");
});
