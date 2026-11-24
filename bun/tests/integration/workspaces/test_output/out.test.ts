// This inner test prints a large output ending in a marker and fails, so the outer test
// `test_output_test` can check that the inner Bazel shows each failing test's whole output
// (feature 007, research R10).
import { expect, test } from "bun:test";

test("prints a large output ending in a marker, then fails", () => {
  const size = Number(process.env.SIZE);
  const line = "x".repeat(63) + "\n";
  process.stdout.write(line.repeat(Math.ceil(size / line.length)).slice(0, size));
  process.stdout.write(`${process.env.MARKER}\n`);
  expect(process.env.MARKER).toBe("");
});
