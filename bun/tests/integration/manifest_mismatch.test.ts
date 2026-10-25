// A package.json changed without updating bun.lock (FR-006, US2-6): evaluation
// fails naming the file, the package and the difference, and tells the
// consumer to run bun install and commit bun.lock.

import { afterAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const inner = new Inner("manifest_mismatch");
afterAll(() => inner.close());
const MANIFEST = JSON.parse(readFileSync(join(inner.dir, "package.json"), "utf8"));
const REMEDY = "run `bun install` and commit bun.lock";

test(
  "an unchanged manifest evaluates",
  async () => {
    const result = await inner.run(["query", "//..."]);
    expect(result.exitCode, result.stderr).toBe(0);
  },
  INNER_TIMEOUT,
);

const CASES: [string, (m: any) => void, string[]][] = [
  ["a root dependency added", (m) => (m.dependencies.c = "1.0.0"), ['"c"', '"1.0.0"']],
  ["a catalog entry changed", (m) => (m.workspaces.catalog.a = "2.0.0"), ['"a"', '"2.0.0"', '"1.0.0"']],
  ["an override changed", (m) => (m.overrides.b = "2.0.0"), ['"b"', '"2.0.0"', '"1.0.0"']],
];

for (const [name, edit, texts] of CASES) {
  test(
    `${name} without updating bun.lock fails evaluation`,
    async () => {
      const manifest = structuredClone(MANIFEST);
      edit(manifest);
      inner.write("package.json", JSON.stringify(manifest, null, 2));
      const result = await inner.run(["query", "//..."]);
      const line = result.stderr.split("\n").find((l) => l.startsWith("Error in fail:")) ?? result.stderr;
      console.log(line);
      expect(result.exitCode).not.toBe(0);
      for (const text of ["//:package.json", ...texts, REMEDY]) expect(line).toContain(text);
      assertOffline(inner.log);
    },
    INNER_TIMEOUT,
  );
}
