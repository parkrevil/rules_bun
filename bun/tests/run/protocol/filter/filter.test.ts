import { expect, test } from "bun:test";
import { join } from "node:path";
import { spawnTarget, testCaseNames } from "../../../support/spawn.ts";

const MATH = "_main/bun/tests/run/protocol/junit/math_test";

test("a filter with describe labels runs only the named test", async () => {
  const report = join(process.env.TEST_TMPDIR!, "describe.xml");
  const result = await spawnTarget(MATH, {
    env: { TESTBRIDGE_TEST_ONLY: "Math ops adds", XML_OUTPUT_FILE: report },
  });
  expect(result.exitCode).toBe(0);
  expect(testCaseNames(report)).toEqual(["adds"]);
});

test("a filter that matches no test fails and runs nothing", async () => {
  const report = join(process.env.TEST_TMPDIR!, "nomatch.xml");
  const result = await spawnTarget(MATH, {
    env: { TESTBRIDGE_TEST_ONLY: "nomatch", XML_OUTPUT_FILE: report },
  });
  expect(result.exitCode).toBe(1);
  expect(testCaseNames(report)).toEqual([]);
});
