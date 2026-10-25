// The JSX program fails when the markup differs (US1-2).

import { expect, test } from "bun:test";
import { spawnTarget } from "../../../support/spawn.ts";

test("render exits non-zero naming the mismatch when other markup is expected", async () => {
  const result = await spawnTarget("_main/bun/tests/npm/fixtures/jsx/render", { args: ["<p>other</p>"] });
  expect(result.exitCode).not.toBe(0);
  expect(result.stderr).toContain("markup mismatch");
});
