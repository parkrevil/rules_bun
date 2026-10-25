// US6-1: a package's bin entries run as programs, with their arguments.

import { expect, test } from "bun:test";
import { spawnTarget } from "../../../../support/spawn.ts";

const BASIC = "_main/bun/tests/npm/fixtures/basic/node_modules";

test("a string bin runs with its arguments", async () => {
  const result = await spawnTarget(`${BASIC}/single-bin/bin/single-bin`, { args: ["x", "a b"] });
  expect(result.stderr).toBe("");
  expect(result.exitCode).toBe(0);
  expect(JSON.parse(result.stdout)).toEqual(["x", "a b"]);
});

test("a bin of a scoped package's object bin runs with its arguments", async () => {
  const result = await spawnTarget(`${BASIC}/@scope/s/bin/s-tool`, { args: ["y"] });
  expect(result.stderr).toBe("");
  expect(result.exitCode).toBe(0);
  expect(JSON.parse(result.stdout)).toEqual({ bin: "s-tool", args: ["y"] });
});
