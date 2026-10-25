// C-WINNAME (FR-036, research G2): an archive holding `aux.js` (a reserved
// Windows device name) and `a:b.js` (a character Windows file names cannot
// hold), replaced into an inner workspace and built on Windows. rules_bun
// promises nothing of its own here; Bazel 9.2.0's extraction may rename, drop or
// fail. The canary pins what it does and fails when that changes, naming the
// FR-036 documentation to revisit (tasks.md T059).

import { afterAll, expect, test } from "bun:test";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { integrity } from "../../support/npm_registry.ts";
import { rlocation } from "../../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "../../integration/support/inner.ts";

const ARCHIVE = readFileSync(rlocation("_main/bun/tests/npm/registry/archives/winname@1.0.0.tgz"));
const SOURCE = "https://bazel.build/versions/9.2.0/rules/lib/builtins/repository_ctx#extract";

// What Bazel 9.2.0 does on Windows, observed on 2026-10-25 (Windows, local, WSL
// interop; tasks.md T141): extracting `a:b.js` throws InvalidPathException
// ("Illegal char <:>") and the inner Bazel exits 37, so nothing is built and the
// package repository holds no package/ directory.
const EXPECTED_WINDOWS: Observation = { built: false, files: null, renamed: null };
// On Linux and macOS both names are valid; `a:b.js` is renamed only because
// `:` is outside Bazel's target-name set (research R4).
const EXPECTED_POSIX: Observation = {
  built: true,
  files: ["_rules_bun_1_", "aux.js", "index.js", "package.json"],
  renamed: { _rules_bun_1_: "a:b.js" },
};

interface Observation {
  built: boolean;
  files: string[] | null;
  renamed: Record<string, string> | null;
}

const inner = new Inner("winname");
afterAll(() => inner.close());

function listFiles(dir: string, prefix = ""): string[] {
  return readdirSync(dir).flatMap((name) =>
    statSync(join(dir, name)).isDirectory() ? listFiles(join(dir, name), `${prefix}${name}/`) : [`${prefix}${name}`],
  );
}

test(
  "Bazel's extraction of Windows-invalid names is unchanged",
  async () => {
    inner.write("winname@1.0.0.tgz", ARCHIVE);
    inner.write(
      "bun.lock",
      JSON.stringify({
        lockfileVersion: 2,
        workspaces: { "": { name: "winname-canary", dependencies: { winname: "1.0.0" } } },
        packages: { winname: ["winname@1.0.0", "", {}, integrity(ARCHIVE, "sha512")] },
      }),
    );
    const result = await inner.run(["build", "//:node_modules/winname"]);
    console.log(result.stderr.split("\n").filter((l) => /ERROR|Error/.test(l)).join("\n"));
    // The loopback request log is the only evidence that the inner build used no
    // external network on Windows, where this canary runs.
    assertOffline(inner.log);
    const external = join(await inner.outputBase(), "external");
    const repo = existsSync(external) ? readdirSync(external).find((n) => n.endsWith("npm__winname__1.0.0")) : undefined;
    const build = repo && join(external, repo, "BUILD.bazel");
    const observed: Observation = {
      built: result.exitCode === 0,
      files: repo && existsSync(join(external, repo, "package")) ? listFiles(join(external, repo, "package")).sort() : null,
      renamed: build && existsSync(build) ? JSON.parse(readFileSync(build, "utf8").match(/replace_prefixes = (\{[^}]*\})/)![1]) : null,
    };
    const expected = process.platform === "win32" ? EXPECTED_WINDOWS : EXPECTED_POSIX;
    try {
      expect(observed).toEqual(expected as Observation);
    } catch {
      console.error(`canary C-WINNAME observed: ${JSON.stringify(observed)}`);
      throw new Error(
        `rules_bun canary C-WINNAME: Bazel 9.2.0's extraction of Windows-invalid file names changed: revisit the FR-036 documentation of package archives in bun/private/run.bzl; source ${SOURCE}`,
      );
    }
  },
  INNER_TIMEOUT,
);
