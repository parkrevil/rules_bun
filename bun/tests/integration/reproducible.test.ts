// The npm extension is reproducible (FR-008, US2-7): `bazel mod deps
// --lockfile_mode=update` adds no entry for it to MODULE.bazel.lock. The test
// also writes `bazel mod show_extension` as show_extension.txt and `bazel mod
// show_repo` of every repository it lists as show_repo.txt into
// $TEST_UNDECLARED_OUTPUTS_DIR. CI uploads them from each OS and compares them
// with compare_mod_output (tasks.md T114, T131). The lockfile lists optional
// packages restricted by `os` and `cpu` (native-*), whose repositories and
// selection data would differ if the extension's output depended on the host.

import { afterAll, expect, test } from "bun:test";
import { readFileSync, realpathSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const inner = new Inner("fetch");
afterAll(() => inner.close());

const EXTENSION = "@rules_bun//bun:extensions.bzl%npm";

test(
  "no MODULE.bazel.lock entry; show_extension and show_repo output written",
  async () => {
    const deps = await inner.run(["mod", "deps", "--lockfile_mode=update"]);
    expect(deps.exitCode, deps.stderr).toBe(0);
    const lock = JSON.parse(readFileSync(join(inner.dir, "MODULE.bazel.lock"), "utf8"));
    const extensions = Object.keys(lock.moduleExtensions ?? {});
    expect(extensions.length).toBeGreaterThan(0);
    expect(extensions.filter((e) => e.endsWith("extensions.bzl%npm"))).toEqual([]);

    const extension = await inner.run(["mod", "show_extension", EXTENSION]);
    expect(extension.exitCode, extension.stderr).toBe(0);
    const repos = [...extension.stdout.matchAll(/^ {2}- (\S+)/gm)].map((m) => m[1]).sort();
    expect(repos).toContain("npm");
    expect(repos).toContain("npm__a__1.0.0");
    expect(repos).toContain("npm__native-darwin-arm64__1.0.0");
    expect(repos).toContain("npm__native-linux-x64__1.0.0");
    expect(repos).toContain("npm__native-win32-x64__1.0.0");
    const show = await inner.run(["mod", "show_repo", ...repos.map((r) => `@@rules_bun++npm+${r}`)]);
    expect(show.exitCode, show.stderr).toBe(0);
    // The loopback port and the workspace path differ between runs and machines.
    const normalized = (output: string) => {
      let text = output.replaceAll(inner.registry.url, "{REGISTRY}");
      for (const dir of [realpathSync(inner.dir), inner.dir]) text = text.replaceAll(dir, "{WORKSPACE}");
      return text;
    };
    const outputs = process.env.TEST_UNDECLARED_OUTPUTS_DIR!;
    writeFileSync(join(outputs, "show_extension.txt"), normalized(extension.stdout));
    writeFileSync(join(outputs, "show_repo.txt"), normalized(show.stdout));
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);
