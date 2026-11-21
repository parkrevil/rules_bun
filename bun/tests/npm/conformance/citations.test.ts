// Every function of the rebuilt resolver names the Bun source lines it carries over (feature 006
// FR-002, SC-004, quickstart Q6): each `def` of `bun/private/bun_*.bzl` and `resolve.bzl`, and the
// resolver functions of `platforms.bzl` (research R3), has a docstring line
// `Bun: <file> L<a>–L<b> @ bun-v1.4.4` naming a file of research Part 1; in `resolve.bzl` and
// `platforms.bzl` a function may instead state that it is the adapter (research R3, R4).
//
// RULES_BUN_CITATIONS_RED=1 adds a function without a citation to the checked text, and the test
// must fail naming it.

import { expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { rlocation } from "../../support/spawn.ts";

const MODULES = ["bun_semver", "bun_install_types", "bun_lockfile", "bun_tree", "bun_isolated_store", "resolve", "platforms"];

// The modules where a function may be the adapter instead of citing Bun (research R3, R4).
const ADAPTERS = new Set(["resolve", "platforms"]);

// `platforms.bzl` is also the toolchain's platform table; only these of its functions resolve.
const ONLY: Record<string, Set<string>> = {
  platforms: new Set(["platform_tuples", "platform_bits", "platform_classes", "npm_only_names", "_check_list", "package_platforms"]),
};

// The files of research Part 1 (LOCK, LOCKFILE, TREE, REACH, PRUNED, META, ISO, STORE, HOOKS,
// SEMVER, INSTALL, and the types and helpers those call).
const PART_1 = new Set([
  "src/install/lockfile/bun.lock.rs",
  "src/install/lockfile.rs",
  "src/install/lockfile/Tree.rs",
  "src/install/lockfile/reachable.rs",
  "src/install/lockfile/pruned_workspaces.rs",
  "src/install/lockfile/Package/Meta.rs",
  "src/install/isolated_install.rs",
  "src/install/isolated_install/Store.rs",
  "src/install_types/resolver_hooks.rs",
  "src/semver/Version.rs",
  "src/semver/SemverQuery.rs",
  "src/semver/SemverRange.rs",
  "src/semver/lib.rs",
  "src/semver/intersects.rs",
  "src/install/PackageManager/install_with_manager.rs",
  "src/install/dependency.rs",
  "src/install/resolution.rs",
  "src/install/npm.rs",
  "src/install/lockfile/CatalogMap.rs",
  "src/install/lockfile/OverrideMap.rs",
  "src/install/lockfile/override_selector.rs",
  "src/install/lockfile/Package.rs",
  "src/install/PackageManager/PackageManagerOptions.rs",
  "src/install/PackageManager/CommandLineArguments.rs",
  "src/install/hosted_git_info.rs",
  "src/install/repository.rs",
  "src/install/integrity.rs",
  "src/install/PackageInstaller.rs",
]);

const CITATION = /^\s*Bun: ((?:src\/install|src\/install_types|src\/semver)\/\S+) L(\d+)–L(\d+) @ bun-v1\.4\.4\s*$/;

interface Uncited {
  module: string;
  name: string;
  reason: string;
}

function uncited(module: string, text: string): Uncited[] {
  const found: Uncited[] = [];
  const defs = [...text.matchAll(/^def (\w+)\([^)]*\):\n((?: {4}"""[\s\S]*?"""\n)?)/gm)];
  for (const [, name, docstring] of defs) {
    if (ONLY[module] && !ONLY[module].has(name)) {
      continue;
    }
    if (!docstring) {
      found.push({ module, name, reason: "has no docstring" });
      continue;
    }
    const lines = docstring.split("\n");
    const citations = lines.map((line) => line.match(CITATION)).filter((m) => m !== null);
    const bad = citations.filter((m) => !PART_1.has(m[1]) || Number(m[2]) > Number(m[3]));
    if (bad.length > 0) {
      found.push({ module, name, reason: `cites ${bad.map((m) => m[1]).join(", ")}, not a file of research Part 1` });
    } else if (citations.length === 0 && !(ADAPTERS.has(module) && docstring.includes("This is the adapter"))) {
      found.push({ module, name, reason: "cites no Bun source lines" });
    }
  }
  return found;
}

test("every function of the resolver cites Bun's lines at bun-v1.4.4", () => {
  const all: Uncited[] = [];
  let functions = 0;
  for (const module of MODULES) {
    let text = readFileSync(rlocation(`_main/bun/private/${module}.bzl`), "utf8");
    if (module === "resolve" && process.env.RULES_BUN_CITATIONS_RED === "1") {
      text += '\ndef _red_mode(x):\n    """A function that cites nothing."""\n    return x\n';
      console.log("red mode: an uncited function _red_mode added to resolve.bzl");
    }
    functions += [...text.matchAll(/^def (\w+)\(/gm)].filter(([, name]) => !ONLY[module] || ONLY[module].has(name)).length;
    all.push(...uncited(module, text));
  }
  console.log(`${functions} functions checked in ${MODULES.length} modules`);
  expect(all.map((u) => `bun/private/${u.module}.bzl: ${u.name} ${u.reason}`)).toEqual([]);
});
