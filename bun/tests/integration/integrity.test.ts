// A downloaded archive that does not match the integrity bun.lock records
// (US2-1, FR-009, constitution III): the fetch fails, naming the package's
// download, and nothing is built from it.

import { afterAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const archive = (p: string) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`);

// a's packument as published, but b's bytes served for a's tarball.
const inner = new Inner("fetch", {
  npmArchives: [{ path: archive("a@1.0.0"), serve: readFileSync(archive("b@1.0.0")) }, archive("b@1.0.0")],
});
afterAll(() => inner.close());

test(
  "an altered archive of a fails the build naming a's download",
  async () => {
    const result = await inner.run(["build", "//:a_test"]);
    const output = result.stderr;
    console.log(output.split("\n").filter((l) => /ERROR|Error/.test(l)).join("\n"));
    expect(result.exitCode).not.toBe(0);
    expect(output).toContain("Checksum");
    expect(output).toContain("/a/-/a-1.0.0.tgz");
    expect(output).toMatch(/npm__a__1\.0\.0/);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);
