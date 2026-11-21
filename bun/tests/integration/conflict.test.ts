// Two lockfile entries of one name@version that disagree on what to download
// (research R3, Edge Case): evaluation fails naming both keys and both values,
// because one package repository serves every entry of a name@version.

import { afterAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const inner = new Inner("conflict");
afterAll(() => inner.close());

const B = "sha512-adhSJ1usdqGRkLPIY2RVgacsucUkiidhiTbrqq/ibfaFRV94fo6p+dM3wTr8DyKRxMtCUKXeO70q4Dyc30dP4w==";
const OTHER = "sha512-/b1IpgijxGDDhzGXLX7uNz9MRXh4yXD6Q1sra8gGGFlmw+Q3L2mluSOUR/3lGLlPYW8IPVPyIvK1A8IeK/wO+w==";

// The committed lockfile (workspaces/conflict/bun.lock, which the conformance test compares with
// the pinned Bun's install, feature 006 T143), whose "c/b" entry repeats b's.
const CONSISTENT = readFileSync(join(inner.dir, "bun.lock"), "utf8");
const NESTED = `"c/b": ["b@1.0.0", "${inner.registry.url}/b/-/b-1.0.0.tgz", {}, "${B}"]`;
if (!CONSISTENT.includes(NESTED)) throw new Error(`workspaces/conflict/bun.lock holds no ${NESTED}`);

/** The committed lockfile with the "c/b" entry's URL and integrity replaced. */
const lockfile = (nested: [string, string]) => CONSISTENT.replace(NESTED, `"c/b": ["b@1.0.0", "${nested[0]}", {}, "${nested[1]}"]`);

test(
  "consistent entries evaluate",
  async () => {
    inner.write("bun.lock", CONSISTENT);
    const result = await inner.run(["query", "//..."]);
    expect(result.exitCode, result.stderr).toBe(0);
  },
  INNER_TIMEOUT,
);

const CASES: [string, () => [string, string], () => string[]][] = [
  ["different integrities", () => [`${inner.registry.url}/b/-/b-1.0.0.tgz`, OTHER], () => [B, OTHER]],
  ["different URLs", () => [`${inner.registry.url}/mirror/b-1.0.0.tgz`, B], () => [`${inner.registry.url}/b/-/b-1.0.0.tgz`, `${inner.registry.url}/mirror/b-1.0.0.tgz`]],
];

for (const [name, nested, values] of CASES) {
  test(
    `two entries of b@1.0.0 with ${name} fail evaluation naming both`,
    async () => {
      inner.write("bun.lock", lockfile(nested()));
      const result = await inner.run(["query", "//..."]);
      const line = result.stderr.split("\n").find((l) => l.startsWith("Error in fail:")) ?? result.stderr;
      console.log(line);
      expect(result.exitCode).not.toBe(0);
      for (const text of ['"b"', '"c/b"', "b@1.0.0", ...values()]) expect(line).toContain(text);
      assertOffline(inner.log);
    },
    INNER_TIMEOUT,
  );
}
