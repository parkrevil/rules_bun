// The Bazel-in-Bazel harness (G5, G10): the pinned Bazel runs an inner module
// that loads rules_bun, offline, with an empty repository cache.

import { expect, test } from "bun:test";
import { assertOffline, INNER_TIMEOUT, runInner } from "./support/inner.ts";

test("the inner build runs a bun_test offline with an empty repository cache", async () => {
  const result = await runInner("toolchain", ["test", "//..."]);
  console.log(`loopback requests: ${result.log.length}\n${result.stderr.split("\n").slice(-6).join("\n")}`);
  expect(result.repositoryCacheWasEmpty).toBe(true);
  if (result.exitCode !== 0) console.error(result.stderr);
  expect(result.exitCode).toBe(0);
  assertOffline(result.log);
}, INNER_TIMEOUT);
