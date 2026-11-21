// Renaming the files a glob would lose (FR-017, research R7): an archive
// holding both BUILD and build in one directory gets two distinct safe names,
// each mapped back to its original path, and no diagnostic fires; an archive
// that already holds the safe name a file is renamed to fails the fetch with
// the collision diagnostic of _make_addressable (specs/005-review-defect-fixes
// T088). Linux only: on a case-insensitive file system the two names of
// case-build@1.0.0 are one file once extracted. The workspace's committed bun.lock
// holds both packages, and each test builds one, so only its archive is fetched; the
// conformance test compares that bun.lock with the pinned Bun's install (feature 006
// T143).

import { afterAll, expect, test } from "bun:test";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const archive = (p: string) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`);
const inner = new Inner("rename", { npmArchives: [archive("case-build@1.0.0"), archive("rename-collision@1.0.0")] });
afterAll(() => inner.close());

const errorLine = (stderr: string) => stderr.split("\n").find((l) => l.startsWith("Error in fail:")) ?? stderr;

test(
  "BUILD and build in one directory get two safe names, each mapped back",
  async () => {
    const result = await inner.run(["build", "//:node_modules/case-build"]);
    expect(result.exitCode, result.stderr).toBe(0);
    assertOffline(inner.log);

    const external = join(await inner.outputBase(), "external");
    const repo = readdirSync(external).find((n) => n.endsWith("npm__case-build__1.0.0"));
    expect(repo, readdirSync(external).join(", ")).toBeDefined();
    const build = readFileSync(join(external, repo!, "BUILD.bazel"), "utf8");
    const renamed = JSON.parse(build.match(/replace_prefixes = (\{[^}]*\})/)![1]);
    expect(renamed).toEqual({ "case/_rules_bun_1_": "case/BUILD", "case/_rules_bun_2_": "case/build" });
    expect(readdirSync(join(external, repo!, "package", "case")).sort()).toEqual(["_rules_bun_1_", "_rules_bun_2_"]);

    const files = await inner.run(["cquery", "--output=files", "//:node_modules/case-build"]);
    expect(files.exitCode, files.stderr).toBe(0);
    const execroot = (await inner.run(["info", "execution_root"])).stdout.trim();
    // The package's instance tree, holding its files under their original paths.
    const output = files.stdout
      .split("\n")
      .map((l) => l.trim())
      .find((l) => l.endsWith("npm__case-build__1.0.0/tree"));
    expect(output, files.stdout).toBeDefined();
    const tree = join(execroot, output!);
    expect(readdirSync(join(tree, "case")).sort()).toEqual(["BUILD", "build"]);
    expect(readFileSync(join(tree, "case", "BUILD"), "utf8")).toBe('module.exports = "case/BUILD";\n');
    expect(readFileSync(join(tree, "case", "build"), "utf8")).toBe('module.exports = "case/build";\n');
    expect(existsSync(join(tree, "case", "_rules_bun_1_"))).toBe(false);
  },
  INNER_TIMEOUT,
);

test(
  "a safe name the archive already holds fails with the collision diagnostic",
  async () => {
    const result = await inner.run(["build", "//:node_modules/rename-collision"]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    expect(errorLine(result.stderr)).toContain(
      "rules_bun: cannot rename BUILD in the package rename-collision@1.0.0 to _rules_bun_1_: the archive already holds _rules_bun_1_",
    );
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);
