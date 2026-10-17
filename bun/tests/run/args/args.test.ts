import { expect, test } from "bun:test";
import { spawnTarget } from "../../support/spawn.ts";

const CASES: string[][] = [[""], ["a b"], ["", "a b", ""], ["--config=z"], ["--config=z", "x"]];

for (const args of CASES) {
  test(`arguments ${JSON.stringify(args)} arrive unchanged`, async () => {
    const result = await spawnTarget("_main/bun/tests/run/args/echo", { args });
    expect(result.exitCode).toBe(0);
    expect(JSON.parse(result.stdout)).toEqual({ argv: args, main: true });
  });
}

for (const args of [["--", "x"], ["--"]]) {
  test(`a leading "--" in ${JSON.stringify(args)} fails with an English error`, async () => {
    const result = await spawnTarget("_main/bun/tests/run/args/echo", { args });
    expect(result.exitCode).toBe(1);
    expect(result.stdout).toBe("");
    expect(result.stderr).toContain('"--" as the first program argument');
    expect(result.stderr).toContain("Bun 1.4.2 drops");
  });
}
