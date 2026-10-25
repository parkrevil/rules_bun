// Two lockfile entries of one name@version that disagree on what to download
// (research R3, Edge Case): evaluation fails naming both keys and both values,
// because one package repository serves every entry of a name@version.

import { afterAll, expect, test } from "bun:test";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const inner = new Inner("conflict");
afterAll(() => inner.close());

const A = "sha512-ZN8qIKY1QfDNI87yGjMJ0P+giZGVXiLIIAmYZ8rAK152GIlo+Dwq6bxxFoBOKYIZouhXnJuFIAORlsLbhuBzbQ==";
const B = "sha512-adhSJ1usdqGRkLPIY2RVgacsucUkiidhiTbrqq/ibfaFRV94fo6p+dM3wTr8DyKRxMtCUKXeO70q4Dyc30dP4w==";
const C = "sha512-ixBAWXVphpPrhrRBi/pi1fdOz72WYFOI6JR2W7xxOhhPNM9dUDtqjYOB7qme4wCjLwcJKzGJt3vGmA3x1MyoWw==";
const OTHER = "sha512-/b1IpgijxGDDhzGXLX7uNz9MRXh4yXD6Q1sra8gGGFlmw+Q3L2mluSOUR/3lGLlPYW8IPVPyIvK1A8IeK/wO+w==";

function lockfile(nested: [string, string]): string {
  const url = (p: string) => `${inner.registry.url}/${p}/-/${p}-1.0.0.tgz`;
  return JSON.stringify({
    lockfileVersion: 2,
    workspaces: { "": { name: "conflict", dependencies: { a: "1.0.0", c: "1.0.0" } } },
    packages: {
      a: ["a@1.0.0", url("a"), { dependencies: { b: "^1.0.0" } }, A],
      b: ["b@1.0.0", url("b"), {}, B],
      c: ["c@1.0.0", url("c"), { dependencies: { b: "^1.0.0" } }, C],
      "c/b": ["b@1.0.0", nested[0], {}, nested[1]],
    },
  });
}

test(
  "consistent entries evaluate",
  async () => {
    inner.write("bun.lock", lockfile([`${inner.registry.url}/b/-/b-1.0.0.tgz`, B]));
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
