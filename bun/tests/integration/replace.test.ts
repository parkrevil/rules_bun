// npm.replace_package (research G3, FR-026): a replacement archive is checked
// against the integrity each lockfile records, with the algorithm it names; it
// applies to every lockfile of the module and is ignored when none lists it;
// only the root module may use it, once per package.

import { afterAll, beforeAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { integrity } from "../support/npm_registry.ts";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner, INNER_TIMEOUT } from "./support/inner.ts";

const ARCHIVES = "_main/bun/tests/npm/registry/archives";
const FIXTURES = "_main/bun/tests/npm/fixtures";
const TEMPLATE = readFileSync(rlocation("_main/bun/tests/integration/workspaces/replace/MODULE.bazel"), "utf8");
const A = readFileSync(rlocation(`${ARCHIVES}/a@1.0.0.tgz`));
const B = readFileSync(rlocation(`${ARCHIVES}/b@1.0.0.tgz`));
const TARGETS = ["//s256:node_modules/a", "//s384:node_modules/a", "//s512:node_modules/a"];

function replacement(pkg: string, label: string): string {
  return `npm.replace_package(package = "${pkg}", replacement = "${label}")`;
}

function moduleFile(replacements: string[], extra = ""): string {
  return TEMPLATE.replace("{REPLACEMENTS}", replacements.join("\n")).replace("{EXTRA}", extra);
}

function setUp(inner: Inner) {
  inner.write("s256/bun.lock", readFileSync(rlocation(`${FIXTURES}/alg_sha256/bun.lock`)));
  inner.write("s384/bun.lock", readFileSync(rlocation(`${FIXTURES}/alg_sha384/bun.lock`)));
  inner.write("s512/bun.lock", readFileSync(rlocation(`${FIXTURES}/basic/bun.lock`)));
  inner.write("s256/package.json", readFileSync(rlocation(`${FIXTURES}/alg_sha256/package.json`)));
  inner.write("s384/package.json", readFileSync(rlocation(`${FIXTURES}/alg_sha384/package.json`)));
  inner.write("s512/package.json", readFileSync(rlocation(`${FIXTURES}/basic/package.json`)));
  inner.write("archives/a@1.0.0.tgz", A);
  inner.write("archives/b@1.0.0.tgz", B);
}

const GOOD = [
  replacement("a@1.0.0", "//archives:a@1.0.0.tgz"),
  replacement("b@1.0.0", "//archives:b@1.0.0.tgz"),
  // No lockfile lists it: ignored, as rules_js ignores it.
  replacement("unlisted@9.9.9", "//archives:b@1.0.0.tgz"),
];

let good: Inner;
let bad: Inner;
beforeAll(() => {
  good = new Inner("replace", { substitutions: { REPLACEMENTS: GOOD.join("\n"), EXTRA: "" } });
  setUp(good);
  bad = new Inner("replace", { substitutions: { REPLACEMENTS: "", EXTRA: "" } });
  setUp(bad);
});
afterAll(async () => {
  await good?.close();
  await bad?.close();
});

test(
  "matching archives pass for sha256, sha384 and sha512, one replacement serving three lockfiles",
  async () => {
    const result = await good.run(["build", ...TARGETS]);
    if (result.exitCode !== 0) console.error(result.stderr);
    expect(result.exitCode).toBe(0);
    assertOffline(good.log);
    expect(good.log.filter((e) => e.path.endsWith(".tgz"))).toEqual([]);
  },
  INNER_TIMEOUT,
);

test(
  "a wrong archive fails naming the package, the archive and both values",
  async () => {
    bad.write("MODULE.bazel", moduleFile([replacement("a@1.0.0", "//archives:b@1.0.0.tgz"), replacement("b@1.0.0", "//archives:b@1.0.0.tgz")]));
    const result = await bad.run(["build", "//s512:node_modules/a"]);
    console.log(result.stderr.split("\n").find((line) => line.includes("rules_bun:")));
    expect(result.exitCode).not.toBe(0);
    const recorded = readFileSync(rlocation(`${FIXTURES}/basic/bun.lock`), "utf8").match(/"a@1\.0\.0", "[^"]*", \{[^}]*\} *\}, "([^"]+)"/)![1];
    expect(result.stderr).toContain("a@1.0.0");
    expect(result.stderr).toContain("//archives:b@1.0.0.tgz");
    expect(result.stderr).toContain(recorded);
    expect(result.stderr).toContain(integrity(B, "sha512"));
  },
  INNER_TIMEOUT,
);

test(
  "a non-root module's replace_package fails evaluation naming the module",
  async () => {
    bad.write(
      "MODULE.bazel",
      moduleFile(GOOD.slice(0, 2), 'bazel_dep(name = "other", version = "1.0.0")\nlocal_path_override(module_name = "other", path = "other")'),
    );
    const result = await bad.run(["build", "//s512:node_modules/a"]);
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("npm.replace_package");
    expect(result.stderr).toContain("other");
    expect(result.stderr).toContain("root module");
  },
  INNER_TIMEOUT,
);

test(
  "a package replaced twice fails evaluation naming it",
  async () => {
    bad.write("MODULE.bazel", moduleFile([...GOOD.slice(0, 2), replacement("a@1.0.0", "//archives:b@1.0.0.tgz")]));
    const result = await bad.run(["build", "//s512:node_modules/a"]);
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("a@1.0.0");
    expect(result.stderr).toContain("twice");
  },
  INNER_TIMEOUT,
);

test(
  "an archive that is not visible to the generated repository fails with Bazel's visibility error (feature 005 FR-020)",
  async () => {
    // A package that exports its archive to itself only (bazel.build concepts/visibility).
    bad.write("hidden/BUILD.bazel", 'exports_files(["a@1.0.0.tgz"], visibility = ["//hidden:__pkg__"])\n');
    bad.write("hidden/a@1.0.0.tgz", A);
    bad.write("MODULE.bazel", moduleFile([replacement("a@1.0.0", "//hidden:a@1.0.0.tgz"), replacement("b@1.0.0", "//archives:b@1.0.0.tgz")]));
    const result = await bad.run(["build", "//s512:node_modules/a"]);
    console.log(result.stderr.split("\n").find((line) => line.includes("visib")));
    expect(result.exitCode).not.toBe(0);
    expect(result.stderr).toContain("//hidden:a@1.0.0.tgz");
    expect(result.stderr).toContain("target '//hidden:a@1.0.0.tgz' is not visible from");
  },
  INNER_TIMEOUT,
);
