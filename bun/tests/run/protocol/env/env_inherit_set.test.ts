// Run as:
//   RULES_BUN_INHERITED=set RULES_BUN_BOTH=inherited \
//     bazel test //bun/tests/run/protocol/env:env_inherit_set_test
import { expect, test } from "bun:test";

test("an inherited variable set by the invoking environment is set", () => {
  expect(process.env.RULES_BUN_INHERITED).toBe("set");
});

test("an inherited value takes precedence over a declared one", () => {
  expect(process.env.RULES_BUN_BOTH).toBe("inherited");
});
