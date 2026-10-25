// Several lockfiles and non-root modules (FR-032, US9): one hub per lockfile,
// each project's targets get its own versions (US9-1); a module the root
// depends on uses the extension for its own lockfile (US9-2); two tags asking
// for one hub name, in one module or across two, fail evaluation naming every
// module and the name (US9-3). A root module's npm.replace_package applies to
// the lockfile of a module it depends on too, as rules_js applies it (FR-026,
// research G3).

import { afterAll, expect, test } from "bun:test";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const archive = (p: string) => rlocation(`_main/bun/tests/npm/registry/archives/${p}.tgz`);
const inner = new Inner("multi_root", { npmArchives: [archive("b@1.0.0"), archive("b@2.0.0"), archive("c@1.0.0")] });
afterAll(() => inner.close());

const BASE = readFileSync(join(inner.dir, "MODULE.bazel"), "utf8");
const DEPENDENCY = 'bazel_dep(name = "npm_user", version = "1.0.0")\n';

// A second file:// registry holding the module npm_user (workspaces/multi_dep)
// as a local_path source, passed after the harness's registry.
const extra = join(inner.root, "extra_registry");
const depDir = join(inner.root, "dep");
inner.assemble("multi_dep", depDir);
mkdirSync(join(extra, "modules", "npm_user", "1.0.0"), { recursive: true });
writeFileSync(join(extra, "bazel_registry.json"), "{}\n");
writeFileSync(join(extra, "modules", "npm_user", "metadata.json"), JSON.stringify({ versions: ["1.0.0"] }));
writeFileSync(join(extra, "modules", "npm_user", "1.0.0", "MODULE.bazel"), readFileSync(join(depDir, "MODULE.bazel")));
writeFileSync(join(extra, "modules", "npm_user", "1.0.0", "source.json"), JSON.stringify({ type: "local_path", path: depDir }));
const slashed = extra.split("\\").join("/");
const EXTRA_REGISTRY = `--registry=${slashed.startsWith("/") ? "file://" : "file:///"}${slashed}`;

const errorLine = (stderr: string) => stderr.split("\n").find((l) => l.startsWith("Error in fail:")) ?? stderr;

test(
  "US9-1: two lockfiles of the root module, each project with its own versions",
  async () => {
    inner.write("MODULE.bazel", BASE);
    const result = await inner.run(["test", "//one:b_test", "//two:b_test", "--test_output=errors"]);
    expect(result.exitCode, result.stdout + result.stderr).toBe(0);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "US9-2: a module the root depends on uses the extension for its own lockfile",
  async () => {
    inner.write("MODULE.bazel", BASE + DEPENDENCY);
    const result = await inner.run(["test", "@npm_user//:c_test", "//one:b_test", "--test_output=errors", EXTRA_REGISTRY]);
    expect(result.exitCode, result.stdout + result.stderr).toBe(0);
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "FR-026: a root replacement applies to a non-root module's lockfile",
  async () => {
    // b@1.0.0's archive as c@1.0.0: the check against npm_user's lockfile fails.
    inner.write("archives/BUILD.bazel", 'exports_files(["c.tgz"])\n');
    inner.write("archives/c.tgz", readFileSync(archive("b@1.0.0")));
    const replace = 'npm.replace_package(package = "c@1.0.0", replacement = "//archives:c.tgz")\n';
    inner.write("MODULE.bazel", BASE + DEPENDENCY + replace);
    const result = await inner.run(["test", "@npm_user//:c_test", "--test_output=errors", EXTRA_REGISTRY]);
    console.log(result.stderr.split("\n").find((line) => line.includes("rules_bun:")));
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("c@1.0.0");
    expect(result.stderr).toContain("//archives:c.tgz");
    assertOffline(inner.log);
  },
  INNER_TIMEOUT,
);

test(
  "US9-3: two tags of one module asking for one hub name fail evaluation",
  async () => {
    inner.write("MODULE.bazel", BASE.replace('name = "npm_two"', 'name = "npm_one"').replace(', "npm_two")', ")"));
    const result = await inner.run(["query", "//one:all"]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    const line = errorLine(result.stderr);
    for (const part of ['"npm_one"', "the root module", "//one:bun.lock", "//two:bun.lock"]) expect(line).toContain(part);
  },
  INNER_TIMEOUT,
);

test(
  "US9-3: tags of two modules asking for one hub name fail evaluation",
  async () => {
    inner.write("MODULE.bazel", BASE.replace('name = "npm_two"', 'name = "npm_user_npm"').replace('"npm_two")', '"npm_user_npm")') + DEPENDENCY);
    const result = await inner.run(["query", "//one:all", EXTRA_REGISTRY]);
    console.log(errorLine(result.stderr));
    expect(result.exitCode).not.toBe(0);
    const line = errorLine(result.stderr);
    for (const part of ['"npm_user_npm"', "the root module", "npm_user@1.0.0"]) expect(line).toContain(part);
  },
  INNER_TIMEOUT,
);
