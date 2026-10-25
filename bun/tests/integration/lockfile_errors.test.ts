// Lockfiles the extension cannot read (FR-007, US2-5): each fails module
// evaluation with an English error naming the file and the remedy. The last
// case is the Edge Case of one package version whose entries record different
// integrities, one of them unsupported (`sha1`).

import { afterAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const inner = new Inner("lockfile_errors");
afterAll(() => inner.close());
const MODULE = readFileSync(join(inner.dir, "MODULE.bazel"), "utf8");

const lockfile = (version: number) =>
  JSON.stringify({ lockfileVersion: version, workspaces: { "": { name: "lockfile-errors" } }, packages: {} });

const CASES: [string, string, string | Uint8Array, string[]][] = [
  [
    "a bun.lockb label",
    "bun.lockb",
    // The start of a binary lockfile: "#!/usr/bin/env bun\nbun-lockfile-format-v0\n" and binary data.
    new Uint8Array([...new TextEncoder().encode("#!/usr/bin/env bun\nbun-lockfile-format-v0\n"), 0, 1, 2, 255]),
    ["//:bun.lockb", "binary lockfile", "bun install --save-text-lockfile --frozen-lockfile --lockfile-only"],
  ],
  ["lockfileVersion 0", "bun.lock", lockfile(0), ["//:bun.lock", "lockfileVersion 0 is not supported", "run `bun install` with Bun 1.4.2 and commit bun.lock"]],
  ["lockfileVersion 4", "bun.lock", lockfile(4), ["//:bun.lock", "lockfileVersion 4 is not supported", "run `bun install` with Bun 1.4.2 and commit bun.lock"]],
  ["invalid JSONC", "bun.lock", '{ "lockfileVersion": 2, /* not closed', ["//:bun.lock", "is not closed", "run `bun install` to rewrite bun.lock"]],
  [
    "two entries of one package version with different integrities, one unsupported",
    "bun.lock",
    JSON.stringify({
      lockfileVersion: 2,
      workspaces: { "": { name: "lockfile-errors" } },
      packages: {
        a: ["a@1.0.0", "", {}, "sha512-AAAA"],
        b: ["b@1.0.0", "", { dependencies: { a: "1.0.0" } }, "sha512-BBBB"],
        "b/a": ["a@1.0.0", "", {}, "sha1-CCCC"],
      },
    }),
    ['//:bun.lock: the entries "a" and "b/a" of a@1.0.0 record different integrity values, "sha512-AAAA" and "sha1-CCCC"', "run `bun install` to rewrite bun.lock"],
  ],
];

for (const [name, file, content, expected] of CASES) {
  test(
    `${name} fails evaluation naming the file and the remedy`,
    async () => {
      inner.write("MODULE.bazel", MODULE.replace("{LOCKFILE}", file));
      inner.write(file, content);
      const result = await inner.run(["build", "//..."]);
      const line = result.stderr.split("\n").find((l) => l.startsWith("Error in fail:")) ?? result.stderr;
      console.log(line);
      expect(result.exitCode).not.toBe(0);
      for (const text of expected) expect(line).toContain(text);
      assertOffline(inner.log);
    },
    INNER_TIMEOUT,
  );
}
