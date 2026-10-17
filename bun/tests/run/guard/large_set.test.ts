import { expect, test } from "bun:test";
import { spawnTarget } from "../../support/spawn.ts";

const TARGET = "_main/bun/tests/run/guard/large_set";

test("with 10,000 declared files a declared one imports", async () => {
  const result = await spawnTarget(TARGET, { args: ["./large_files/f09999.json"] });
  expect(result.exitCode, result.stderr).toBe(0);
  expect(result.stdout).toBe("imported\n");
});

test("with 10,000 declared files an undeclared one fails naming it", async () => {
  const result = await spawnTarget(TARGET, { args: ["./stale.ts"] });
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toMatch(/\/\/bun\/tests\/run\/guard:large_set: \S*stale\.ts is not declared by this target/);
});
