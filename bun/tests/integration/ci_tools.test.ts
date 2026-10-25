// The CI check tools of tasks.md T113 and T114 on fixed inputs.

import { expect, test } from "bun:test";
import { firstDifference, normalize } from "./compare_mod_output.ts";
import { check, parseStream } from "./disk_cache_check.ts";

const spawn = (mnemonic: string, paths: string[], cacheHit: boolean) =>
  JSON.stringify({ mnemonic, targetLabel: `//:${mnemonic}`, inputs: paths.map((path) => ({ path, digest: { hash: "}{" } })), cacheHit }, null, 2);

test("the execution log is read as concatenated JSON objects", () => {
  const log = spawn("A", ["x"], true) + spawn("B", ['a"{.ts'], false);
  expect(parseStream(log).map((s) => s.mnemonic)).toEqual(["A", "B"]);
  expect(() => parseStream(log.slice(0, -1))).toThrow("ends inside a JSON value");
});

test("only spawns consuming a store link are checked, and a miss is reported", () => {
  const spawns = parseStream(
    spawn("Hit", ["bazel-out/x64_windows-fastbuild/bin/p/t.bun/.store/b@1.0.0/node_modules/c"], true) +
      spawn("Miss", ["bazel-out\\x64_windows-fastbuild\\bin\\p\\t.bun\\p\\node_modules\\b"], false) +
      spawn("Other", ["external/+npm+npm__b__1.0.0/package/node_modules/x", "p/node_modules/b/index.js"], false),
  );
  const { consuming, misses } = check(spawns);
  expect(consuming.map((s) => s.mnemonic)).toEqual(["Hit", "Miss"]);
  expect(misses.map((s) => s.mnemonic)).toEqual(["Miss"]);
});

const extension = (path: string, integrity = "sha512-AA==") => [
  `## @@rules_bun+//bun:extensions.bzl%npm:`,
  "",
  "Fetched repositories:",
  "  - npm (imported by <root>)",
  "  - npm__b__1.0.0",
  "",
  `## Usage in <root> from ${path}:14`,
  'npm.translate_lock(bun_lock="//:bun.lock")',
  "",
].join("\n") + `\u0000${integrity}`;

function outputs(path: string, integrity?: string, newline = "\n") {
  const [ext, value] = extension(path, integrity).split("\u0000");
  const repos = [
    "## @@bazel_tools+cc_configure_extension+local_config_cc:",
    `cc_autoconf(name = "${newline === "\n" ? "linux" : "windows"}")`,
    "## @@rules_bun++npm+npm__b__1.0.0:",
    `npm_package_repository(integrity = "${value}")`,
    "## @@rules_bun++npm+npm:",
    "npm_hub_repository()",
  ].join(newline);
  return normalize(ext.split("\n").join(newline), repos);
}

test("the outputs of two checkouts on two OSes compare equal", () => {
  const linux = outputs("/home/runner/work/rules_bun/e2e/smoke/MODULE.bazel");
  const windows = outputs("D:\\a\\rules_bun\\e2e\\smoke\\MODULE.bazel", undefined, "\r\n");
  expect(firstDifference(linux, windows)).toBeUndefined();
  expect(linux).toContain('npm_package_repository(integrity = "sha512-AA==")');
  expect(linux.join("\n")).not.toContain("cc_autoconf");
});

test("a differing repository definition is reported at its line", () => {
  const a = outputs("/w/MODULE.bazel");
  const b = outputs("/w/MODULE.bazel", "sha512-BB==");
  expect(firstDifference(a, b)).toEqual({
    line: a.indexOf('npm_package_repository(integrity = "sha512-AA==")') + 1,
    a: 'npm_package_repository(integrity = "sha512-AA==")',
    b: 'npm_package_repository(integrity = "sha512-BB==")',
  });
});

test("a listed repository without a show_repo section fails", () => {
  expect(() => normalize(extension("/w/MODULE.bazel").split("\u0000")[0], "")).toThrow("no section for @@rules_bun++npm+npm");
});
