import { expect, test } from "bun:test";
import { join } from "node:path";
import { spawnTarget, testCaseNames } from "../../../support/spawn.ts";

test("XML_OUTPUT_FILE receives a JUnit report with every test", async () => {
  const report = join(process.env.TEST_TMPDIR!, "junit.xml");
  const result = await spawnTarget("_main/bun/tests/run/protocol/junit/math_test", {
    env: { XML_OUTPUT_FILE: report },
  });
  expect(result.exitCode).toBe(0);
  expect(testCaseNames(report).sort()).toEqual(["adds", "other", "subtracts"]);
});
