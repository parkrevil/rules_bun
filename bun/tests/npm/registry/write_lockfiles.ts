// Writes the npm fixture projects under bun/tests/npm/fixtures/<project>/ and
// their bun.lock files (research R14). Run by hand with the pinned Bun from the
// repository root, after pack.ts:
//
//   $(bazel info output_base)/external/+bun+bun_linux-x64/bun bun/tests/npm/registry/write_lockfiles.ts [project...]
//
// With --bun-1-4-2, run by Bun 1.4.2 (the dev toolchain bun_1_4_2 of MODULE.bazel,
// $(bazel info output_base)/external/+bun+bun_1_4_2_linux-x64/bun), it writes each corpus project
// (conformance_*) that Bun 1.4.2 can write and install into
// bun/tests/npm/conformance/bun_1_4_2/<project>/ instead: bun.lock, package.json and the workspace
// members' package.json files, without the BUILD files of the fixture (feature 006 US5, research
// R10); NOT_APPLICABLE_1_4_2 lists the others with the reason.
//
// For each project it writes the project files, copies them into a temporary
// directory, starts the loopback registry with the fixture archives and runs
// the pinned Bun's `install` there with an empty cache. It rewrites nothing Bun
// wrote: bun.lock (and every file Bun changed, such as package.json after
// `bun patch --commit`) is copied back as written. It then asserts the
// lockfile keys the project exists for and prints the lockfileVersion.

import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { type ArchiveSpec, FIXTURE_PORT, type IntegrityAlgorithm, type Registry, startRegistry } from "../../support/npm_registry.ts";
import { NOT_APPLICABLE_1_4_2 } from "../conformance/not_applicable_1_4_2.ts";

export { NOT_APPLICABLE_1_4_2 };

const here = import.meta.dir;
const archivesDir = join(here, "archives");
const fixtures = join(here, "..", "fixtures");
const BUN_1_4_2_FLAG = "--bun-1-4-2";
const bun142 = join(here, "..", "conformance", "bun_1_4_2");

type Files = Record<string, string>;

interface Project {
  /** Files of the project, given the loopback registry's URL. */
  files: (registry: string) => Files;
  /** Integrity algorithm the registry publishes; default sha512. */
  algorithm?: IntegrityAlgorithm;
  /** Archives published without an integrity. */
  noIntegrity?: string[];
  /** Runs Bun in the temporary project; default one `install`. */
  run?: (ctx: RunContext) => Promise<void>;
  /** Files copied back besides bun.lock. */
  keep?: string[];
  /** Checks the lockfile the pinned Bun wrote. */
  check: (lock: Lockfile) => void;
}

interface Lockfile {
  lockfileVersion: number;
  workspaces: Record<string, any>;
  packages: Record<string, any[]>;
  [key: string]: any;
}

interface RunContext {
  dir: string;
  registry: Registry;
  bun: (...args: string[]) => Promise<string>;
  lock: () => Lockfile;
}

function json(value: unknown): string {
  return JSON.stringify(value, null, 2) + "\n";
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(`write_lockfiles: ${message}`);
}

// Splits a lockfile key into package names, keeping "@scope/name" together.
function segments(key: string): string[] {
  const parts = key.split("/");
  const out: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    out.push(parts[i].startsWith("@") ? `${parts[i]}/${parts[++i]}` : parts[i]);
  }
  return out;
}

// The key a dependency `dep` of the entry at `key` resolves to (research R2).
function walk(lock: Lockfile, key: string, dep: string): string | undefined {
  const parts = segments(key);
  for (let n = parts.length; n >= 0; n--) {
    const candidate = [...parts.slice(0, n), dep].join("/");
    if (lock.packages[candidate]) return candidate;
  }
  return undefined;
}

function slot0(lock: Lockfile, key: string): string {
  assert(lock.packages[key], `bun.lock has no key ${key}`);
  return lock.packages[key][0];
}

function keys(lock: Lockfile, expected: string[]) {
  for (const key of expected) assert(lock.packages[key], `bun.lock has no key ${key}`);
}

const BASIC_DEPS: Record<string, string> = {
  "@scope/s": "1.0.0",
  a: "1.0.0",
  b: "1.0.0",
  "build-files": "1.0.0",
  c: "1.0.0",
  "cyc-a": "1.0.0",
  deep: "1.0.0",
  dirbin: "1.0.0",
  emptydir: "1.0.0",
  excluded: "1.0.0",
  "ident-a": "1.0.0",
  native: "1.0.0",
  negated: "1.0.0",
  nomatch: "1.0.0",
  "nonjs-bin": "1.0.0",
  p: "1.0.0",
  "p-user": "1.0.0",
  "pc-a": "1.0.0",
  "phantom-user": "1.0.0",
  q: "1.0.0",
  "q2-user": "1.0.0",
  scripted: "1.0.0",
  "single-bin": "1.0.0",
  spaced: "1.0.0",
  state: "1.0.0",
  toplevel: "1.0.0",
  "weird-bin": "1.0.0",
  x: "2.0.0",
  y: "1.0.0",
  z: "1.0.0",
};

const CONFORMANCE_LOAD = 'load("//bun/tests/npm/conformance:files.bzl", "conformance_files")\n';

// The conformance test copies every file of a project (bun/tests/npm/conformance/files.bzl).
const STUB_BUILD = `${CONFORMANCE_LOAD}\n# A workspace member of the fixture project.\n\nconformance_files()\n`;

function overridesProject(manifest: Record<string, unknown>, check: (lock: Lockfile) => void): Project {
  return {
    files: () => ({ "package.json": json({ name: "overrides", private: true, dependencies: { a: "1.0.0" }, ...manifest }) }),
    check,
  };
}

const projects: Record<string, Project> = {
  basic: {
    files: () => ({
      "package.json": json({ name: "basic", private: true, dependencies: BASIC_DEPS, trustedDependencies: ["scripted"] }),
    }),
    check(lock) {
      keys(lock, Object.keys(BASIC_DEPS));
      assert(slot0(lock, "c/b") === "b@2.0.0", "c/b is not b@2.0.0");
      assert(lock.trustedDependencies?.[0] === "scripted", "trustedDependencies is not [scripted]");
    },
  },
  workspace: {
    files: () => ({
      "package.json": json({
        name: "workspace-root",
        private: true,
        workspaces: { packages: ["packages/*", "!packages/excluded"], catalog: { q: "1.0.0" } },
        overrides: { r: "1.0.0" },
        dependencies: { a: "1.0.0", aliased: "npm:b@2.0.0", q: "catalog:" },
      }),
      "packages/w1/package.json": json({
        name: "w1",
        version: "1.0.0",
        dependencies: { a: "1.0.0", p: "1.0.0", "p-user": "1.0.0", q: "2.0.0", w2: "workspace:*" },
        devDependencies: { "single-bin": "1.0.0" },
        peerDependencies: { state: "1.0.0" },
        optionalDependencies: { "native-linux-x64": "1.0.0" },
      }),
      "packages/w1/BUILD.bazel": STUB_BUILD,
      "packages/w2/package.json": json({ name: "w2", version: "1.0.0", dependencies: { c: "1.0.0" } }),
      "packages/w2/BUILD.bazel": STUB_BUILD,
      "packages/excluded/package.json": json({ name: "excluded-member", version: "1.0.0", dependencies: { r: "1.0.0" } }),
      "packages/excluded/BUILD.bazel": STUB_BUILD,
    }),
    check(lock) {
      const members = Object.keys(lock.workspaces).sort();
      assert(JSON.stringify(members) === JSON.stringify(["", "packages/w1", "packages/w2"]), `workspaces keys ${members}`);
      assert(slot0(lock, "w1/q") === "q@2.0.0", "w1/q is not q@2.0.0");
      assert(slot0(lock, "q") === "q@1.0.0", "q is not q@1.0.0");
      assert(slot0(lock, "aliased") === "b@2.0.0", "aliased is not b@2.0.0");
      assert(slot0(lock, "w2") === "w2@workspace:packages/w2", "w2 is not a workspace entry");
      keys(lock, ["c/b", "state", "single-bin", "native-linux-x64", "p", "p-user"]);
    },
  },
  // US4-5: a member added and then removed with bun.lock updated, the root
  // package.json unchanged (members.test.ts copies both states).
  workspace_base: {
    files: () => ({
      "package.json": json({ name: "members-root", private: true, workspaces: ["packages/*"] }),
      "packages/w1/package.json": json({ name: "w1", version: "1.0.0", dependencies: { a: "1.0.0" } }),
    }),
    check(lock) {
      const members = Object.keys(lock.workspaces).sort();
      assert(JSON.stringify(members) === JSON.stringify(["", "packages/w1"]), `workspaces keys ${members}`);
    },
  },
  workspace_added: {
    files: () => ({
      "package.json": json({ name: "members-root", private: true, workspaces: ["packages/*"] }),
      "packages/w1/package.json": json({ name: "w1", version: "1.0.0", dependencies: { a: "1.0.0" } }),
      "packages/w3/package.json": json({ name: "w3", version: "1.0.0", dependencies: { c: "1.0.0" } }),
    }),
    check(lock) {
      const members = Object.keys(lock.workspaces).sort();
      assert(JSON.stringify(members) === JSON.stringify(["", "packages/w1", "packages/w3"]), `workspaces keys ${members}`);
      keys(lock, ["a", "b", "c", "c/b"]);
    },
  },
  version1: {
    files: () => ({ "package.json": json({ name: "version1", private: true, dependencies: { a: "1.0.0" } }) }),
    async run({ dir, bun }) {
      // Written as version 2, its stamp edited to 1, then re-saved by Bun after a
      // dependency is added (G7).
      await bun("install");
      const lockPath = join(dir, "bun.lock");
      const text = readFileSync(lockPath, "utf8");
      assert(text.includes('"lockfileVersion": 2,'), "the first install did not write lockfileVersion 2");
      writeFileSync(lockPath, text.replace('"lockfileVersion": 2,', '"lockfileVersion": 1,'));
      const manifest = JSON.parse(readFileSync(join(dir, "package.json"), "utf8"));
      manifest.dependencies.c = "1.0.0";
      writeFileSync(join(dir, "package.json"), json(manifest));
      await bun("install");
    },
    keep: ["package.json"],
    check(lock) {
      assert(lock.lockfileVersion === 1, `lockfileVersion ${lock.lockfileVersion}`);
      keys(lock, ["a", "b", "c", "c/b"]);
    },
  },
  overrides_top: overridesProject({ overrides: { b: "2.0.0" } }, (lock) => {
    assert(slot0(lock, "b") === "b@2.0.0", "b is not overridden to 2.0.0");
  }),
  overrides_object: overridesProject({ overrides: { a: { ".": "1.0.0", b: "2.0.0" } } }, () => {}),
  overrides_gt: overridesProject({ overrides: { "a>b": "2.0.0" } }, (lock) => {
    assert(lock.lockfileVersion === 3, `lockfileVersion ${lock.lockfileVersion}`);
  }),
  overrides_range: overridesProject({ overrides: { "a@^1.0.0>b": "2.0.0" } }, () => {}),
  overrides_path: overridesProject({ resolutions: { "a/b": "2.0.0" } }, () => {}),
  overrides_glob: overridesProject({ resolutions: { "**/a/**/b": "2.0.0" } }, () => {}),
  overrides_both: overridesProject({ overrides: { b: "2.0.0" }, resolutions: { b: "1.0.0" } }, (lock) => {
    assert(slot0(lock, "b") === "b@2.0.0", "overrides did not win over resolutions");
  }),
  overrides_deep: overridesProject({ overrides: { "a>b>c": "1.0.0" } }, () => {}),
  catalog: {
    files: () => ({
      "package.json": json({
        name: "catalog",
        private: true,
        // Bun 1.4.4 reads catalogs only under "workspaces" ("b@catalog: is not in
        // the catalog" for a top-level "catalog").
        workspaces: { packages: [], catalog: { b: "1.0.0" }, catalogs: { two: { q: "2.0.0" } } },
        dependencies: { b: "catalog:", q: "catalog:two" },
      }),
    }),
    check(lock) {
      assert(slot0(lock, "b") === "b@1.0.0", "b is not b@1.0.0");
      assert(slot0(lock, "q") === "q@2.0.0", "q is not q@2.0.0");
    },
  },
  unsupported: {
    noIntegrity: ["nointegrity@1.0.0"],
    files: (registry) => ({
      "package.json": json({
        name: "unsupported",
        private: true,
        dependencies: {
          a: "1.0.0",
          local: "file:./local",
          nointegrity: "1.0.0",
          r: "1.0.0",
          tb: `${registry}/b/-/b-1.0.0.tgz`,
        },
      }),
      "local/package.json": json({ name: "local", version: "1.0.0", main: "index.js" }),
      "local/index.js": 'module.exports = "local";\n',
    }),
    async run({ dir, bun }) {
      await bun("install");
      await bun("patch", "r");
      writeFileSync(join(dir, "node_modules", "r", "index.js"), 'module.exports = { name: "r", version: "patched" };\n');
      await bun("patch", "--commit", "node_modules/r");
    },
    keep: ["package.json", "patches"],
    check(lock) {
      keys(lock, ["a", "b", "local", "nointegrity", "r", "tb"]);
      assert(lock.patchedDependencies?.["r@1.0.0"], "patchedDependencies has no r@1.0.0");
    },
  },
  // The hoisted-install Edge Case: Bun writes configVersion 0 when it re-saves a
  // lockfile that has none (a lockfile from before configVersion, which Bun
  // installs hoisted). Written with configVersion 1, the field removed, then
  // re-saved by Bun after a dependency is added, as version1. phantom-user
  // requires b, which a hoisted install puts at the root.
  hoisted: {
    files: () => ({ "package.json": json({ name: "hoisted", private: true, dependencies: { "phantom-user": "1.0.0" } }) }),
    async run({ dir, bun }) {
      await bun("install");
      const lockPath = join(dir, "bun.lock");
      const lines = readFileSync(lockPath, "utf8").split("\n");
      const kept = lines.filter((line) => line.trim() !== '"configVersion": 1,');
      assert(kept.length === lines.length - 1, "the first install did not write configVersion 1");
      writeFileSync(lockPath, kept.join("\n"));
      const manifest = JSON.parse(readFileSync(join(dir, "package.json"), "utf8"));
      manifest.dependencies.b = "1.0.0";
      writeFileSync(join(dir, "package.json"), json(manifest));
      await bun("install");
    },
    keep: ["package.json"],
    check(lock) {
      assert(lock.configVersion === 0, `configVersion ${lock.configVersion}`);
      keys(lock, ["b", "phantom-user"]);
    },
  },
  // The aix mapping of the os/cpu Edge Case (T128): native-aix-x64 is an
  // optional package of aix-user whose os is aix and whose cpu has a constraint.
  aix: {
    files: () => ({ "package.json": json({ name: "aix", private: true, dependencies: { "aix-user": "1.0.0" } }) }),
    check(lock) {
      keys(lock, ["aix-user", "native-aix-x64"]);
      assert(lock.packages["native-aix-x64"][2].os === "aix", `native-aix-x64 os ${lock.packages["native-aix-x64"][2].os}`);
    },
  },
  // Platform-restricted optional packages that a link reaches only through its
  // platform select (T134, T136): native's native-linux-x64 is published without
  // an integrity, so it is unsupported; bin-darwin-arm64, a declared optional
  // dependency with os darwin and cpu arm64, has a JavaScript bin, and so has
  // bin-linux-x64-musl, with libc musl (specs/004-bun-1-4-4-upgrade research R11).
  restricted: {
    noIntegrity: ["native-linux-x64@1.0.0"],
    files: () => ({
      "package.json": json({
        name: "restricted",
        private: true,
        dependencies: { native: "1.0.0" },
        optionalDependencies: { "bin-darwin-arm64": "1.0.0", "bin-linux-x64-musl": "1.0.0" },
      }),
    }),
    check(lock) {
      keys(lock, ["bin-darwin-arm64", "native", "native-linux-x64"]);
      assert(lock.packages["native-linux-x64"][3] === "", `native-linux-x64 integrity ${lock.packages["native-linux-x64"][3]}`);
      assert(lock.packages["bin-darwin-arm64"][2].bin?.rbin === "cli.js", "bin-darwin-arm64 has no rbin");
      assert(lock.packages["bin-darwin-arm64"][2].os === "darwin", `bin-darwin-arm64 os ${lock.packages["bin-darwin-arm64"][2].os}`);
      assert(lock.packages["bin-linux-x64-musl"][2].libc === "musl", `bin-linux-x64-musl libc ${lock.packages["bin-linux-x64-musl"][2].libc}`);
    },
  },
  // FR-033 on files rules_bun renames (T138): the hub npm_renamed excludes
  // build-files' sub/BUILD.bazel and spaced's "file with space.js" by their
  // archive names.
  renamed: {
    files: () => ({
      "package.json": json({ name: "renamed", private: true, dependencies: { "build-files": "1.0.0", spaced: "1.0.0" } }),
    }),
    check(lock) {
      keys(lock, ["build-files", "spaced"]);
    },
  },
  // FR-017's missing peer: Bun installs a non-optional peer, so no lockfile it
  // writes lacks one; the entry of ident-a's peer state is removed after the
  // install (the only edit of what Bun wrote besides version1's stamp).
  // One package version whose dependency resolves to two versions in one closure: y/x and z/x are
  // x@1.0.0, and x's b is y's b@2.0.0 under y and the root's b@1.0.0 under z. Bun 1.4.4 writes a
  // y/x/b entry that keeps x@1.0.0's b one version, so the entry line is removed, as missing_peer
  // removes one, to give the ruleset's check a lockfile to reject (research R12).
  dependency_conflict: {
    files: () => ({
      "package.json": json({ name: "dependency-conflict", private: true, dependencies: { a: "1.0.0", b: "1.0.0", x: "2.0.0", y: "1.0.0", z: "1.0.0" } }),
    }),
    async run({ dir, bun }) {
      await bun("install");
      const lockPath = join(dir, "bun.lock");
      const lines = readFileSync(lockPath, "utf8").split("\n");
      const kept = lines.filter((line) => !line.trimStart().startsWith('"y/x/b": ["b@1.0.0"'));
      assert(kept.length === lines.length - 1, "bun.lock has no single y/x/b entry line");
      writeFileSync(lockPath, kept.join("\n"));
    },
    check(lock) {
      assert(slot0(lock, "y/x") === "x@1.0.0" && slot0(lock, "z/x") === "x@1.0.0", "y/x and z/x are not both x@1.0.0");
      const underY = walk(lock, "y/x", "b");
      const underZ = walk(lock, "z/x", "b");
      assert(underY && underZ && slot0(lock, underY) !== slot0(lock, underZ), "x@1.0.0's b is one version under y and z");
    },
  },
  missing_peer: {
    files: () => ({ "package.json": json({ name: "missing-peer", private: true, dependencies: { "ident-a": "1.0.0" } }) }),
    async run({ dir, bun }) {
      await bun("install");
      const lockPath = join(dir, "bun.lock");
      const lines = readFileSync(lockPath, "utf8").split("\n");
      const kept = lines.filter((line) => !line.trimStart().startsWith('"state": ["state@1.0.0"'));
      assert(kept.length === lines.length - 1, "bun.lock has no single state entry line");
      writeFileSync(lockPath, kept.join("\n"));
    },
    check(lock) {
      keys(lock, ["ident-a"]);
      assert(!("state" in lock.packages), "the state entry is still in bun.lock");
    },
  },
  // US6-5 and the bin naming rule (bins.test.ts): dirbin declares its
  // executables only through directories.bin; clash-bin's two bin names become
  // one target name.
  bins_dirbin: {
    files: () => ({
      "package.json": json({ name: "bins-dirbin", private: true, dependencies: { dirbin: "1.0.0", "single-bin": "1.0.0" } }),
    }),
    check(lock) {
      keys(lock, ["dirbin", "single-bin"]);
    },
  },
  // FR-012 (bins_test.bzl, bins.test.ts): node-bin's bins are a JavaScript
  // program for Node or Bun by their #! line, a shell script, a file with no
  // #! line, a directory, a file the hub excludes and bin/Build, a file the
  // package repository renames (specs/005-review-defect-fixes T089).
  bins_node: {
    files: () => ({ "package.json": json({ name: "bins-node", private: true, dependencies: { "node-bin": "1.0.0" } }) }),
    check(lock) {
      keys(lock, ["node-bin"]);
      assert(Object.keys(lock.packages["node-bin"][2].bin ?? {}).length === 10, "node-bin has not ten bin entries");
    },
  },
  // FR-006 (platforms_test.bzl): an optional package whose os and cpu are a
  // sole "any", which npm-install-checks' checkList matches everywhere.
  any_platform: {
    files: () => ({ "package.json": json({ name: "any-platform-user", private: true, optionalDependencies: { "any-platform": "1.0.0" } }) }),
    check(lock) {
      keys(lock, ["any-platform"]);
    },
  },
  bins_clash: {
    files: () => ({ "package.json": json({ name: "bins-clash", private: true, dependencies: { "clash-bin": "1.0.0" } }) }),
    check(lock) {
      keys(lock, ["clash-bin"]);
      assert(Object.keys(lock.packages["clash-bin"][2].bin ?? {}).length === 2, "clash-bin has not two bin entries");
    },
  },
  alg_sha256: {
    algorithm: "sha256",
    files: () => ({ "package.json": json({ name: "alg-sha256", private: true, dependencies: { a: "1.0.0" } }) }),
    check(lock) {
      assert(String(lock.packages.a[3]).startsWith("sha256-"), `a integrity ${lock.packages.a[3]}`);
    },
  },
  // The edge-case corpus of feature 006 (research R11): each project is a layout the conformance
  // test compares with the pinned Bun's isolated install.
  // FR-009, BC-2: workspaces named like packages the root aliases, unscoped and scoped
  // (prior-research U4); their own dependencies are written under "./<name>/".
  conformance_alias_workspace: {
    files: () => ({
      "package.json": json({
        name: "conformance-alias-workspace",
        private: true,
        workspaces: ["packages/*"],
        dependencies: { lib: "npm:a@1.0.0", "@scope/lib": "npm:c@1.0.0", b: "1.0.0", x: "2.0.0", y: "npm:q@2.0.0" },
      }),
      "packages/lib/package.json": json({ name: "lib", version: "1.0.0", dependencies: { b: "2.0.0", x: "2.0.0", y: "1.0.0" } }),
      "packages/lib/BUILD.bazel": STUB_BUILD,
      "packages/scoped/package.json": json({ name: "@scope/lib", version: "1.0.0", dependencies: { b: "2.0.0", q: "1.0.0" } }),
      "packages/scoped/BUILD.bazel": STUB_BUILD,
      "packages/app/package.json": json({ name: "app", version: "1.0.0", dependencies: { lib: "workspace:*", "@scope/lib": "workspace:*" } }),
      "packages/app/BUILD.bazel": STUB_BUILD,
    }),
    check(lock) {
      assert(slot0(lock, "lib") === "a@1.0.0", "lib is not a@1.0.0");
      assert(slot0(lock, "@scope/lib") === "c@1.0.0", "@scope/lib is not c@1.0.0");
      assert(Object.keys(lock.packages).some((k) => k.startsWith("./lib/")), "bun.lock has no key ./lib/<dep>");
      assert(Object.keys(lock.packages).some((k) => k.startsWith("./@scope/lib/")), "bun.lock has no key ./@scope/lib/<dep>");
    },
  },
  // FR-009, BC-1: optional dependencies listed under "unresolved", in a package and in workspaces.
  conformance_unresolved: {
    files: () => ({
      "package.json": json({
        name: "conformance-unresolved",
        private: true,
        workspaces: ["packages/*"],
        dependencies: { a: "1.0.0", "opt-user": "1.0.0", q: "1.0.0", state: "1.0.0" },
        optionalDependencies: { b: "^3.0.0" },
      }),
      "packages/w/package.json": json({ name: "w", version: "1.0.0", dependencies: { a: "1.0.0" }, optionalDependencies: { q: "^3.0.0" } }),
      "packages/w/BUILD.bazel": STUB_BUILD,
    }),
    check(lock) {
      assert(JSON.stringify(lock.packages["opt-user"]?.[2]?.unresolved) === '["state"]', "opt-user's unresolved is not [state]");
      assert(JSON.stringify(lock.workspaces[""].unresolved) === '["b"]', "the root's unresolved is not [b]");
      assert(JSON.stringify(lock.workspaces["packages/w"].unresolved) === '["q"]', "w's unresolved is not [q]");
    },
  },
  // FR-009, BC-3: optional and peer dependencies without a key, of the root and of a workspace.
  conformance_unbound: {
    files: () => ({
      "package.json": json({
        name: "conformance-unbound",
        private: true,
        workspaces: ["packages/*"],
        dependencies: { a: "1.0.0" },
        optionalDependencies: { state: "^3.0.0" },
        peerDependencies: { r: "^9.0.0" },
      }),
      "packages/w/package.json": json({
        name: "w",
        version: "1.0.0",
        dependencies: { a: "1.0.0" },
        optionalDependencies: { x: "^9.0.0" },
        peerDependencies: { q: "^9.0.0" },
      }),
      "packages/w/BUILD.bazel": STUB_BUILD,
    }),
    check(lock) {
      for (const name of ["state", "r", "x", "q"]) assert(!(name in lock.packages), `bun.lock has a key ${name}`);
      for (const ws of Object.values(lock.workspaces)) assert(!("unresolved" in ws), "a workspace lists unresolved names");
    },
  },
  // FR-009, BC-4: a registry package depending on a workspace member's name.
  conformance_registry_to_workspace: {
    files: () => ({
      "package.json": json({ name: "conformance-registry-to-workspace", private: true, workspaces: ["packages/*"], dependencies: { "member-user": "1.0.0" } }),
      "packages/member-lib/package.json": json({ name: "member-lib", version: "1.0.0", main: "index.js", dependencies: { b: "2.0.0" } }),
      "packages/member-lib/index.js": 'module.exports = { name: "member-lib" };\n',
      "packages/member-lib/BUILD.bazel": STUB_BUILD,
    }),
    check(lock) {
      assert(slot0(lock, "member-lib") === "member-lib@workspace:packages/member-lib", "member-lib is not the workspace");
      assert(lock.packages["member-user"][2].dependencies?.["member-lib"] === "^1.0.0", "member-user does not depend on member-lib");
    },
  },
  // FR-009, BC-5: a non-optional and an optional peer nothing provides (no version of state
  // matches ^3.0.0), in the root's and a workspace's tree.
  conformance_unprovided_peer: {
    files: () => ({
      "package.json": json({
        name: "conformance-unprovided-peer",
        private: true,
        workspaces: ["packages/*"],
        dependencies: { "peer-unprovided": "1.0.0", "peer-unprovided-opt": "1.0.0" },
      }),
      "packages/w/package.json": json({ name: "w", version: "1.0.0", dependencies: { "peer-unprovided": "1.0.0", "peer-unprovided-opt": "1.0.0" } }),
      "packages/w/BUILD.bazel": STUB_BUILD,
    }),
    check(lock) {
      assert(!("state" in lock.packages), "bun.lock has a key state");
      assert(JSON.stringify(lock.packages["peer-unprovided-opt"][2].optionalPeers) === '["state"]', "peer-unprovided-opt's state is not an optional peer");
    },
  },
  // FR-009, BC-6: one name@version at nested and hoisted keys (dependency_conflict's shape as Bun
  // writes it, one level deeper through nest).
  conformance_nested: {
    files: () => ({
      "package.json": json({
        name: "conformance-nested",
        private: true,
        dependencies: { a: "1.0.0", b: "1.0.0", nest: "1.0.0", x: "2.0.0", y: "1.0.0", z: "1.0.0" },
      }),
    }),
    check(lock) {
      assert(slot0(lock, "y/x") === "x@1.0.0" && slot0(lock, "z/x") === "x@1.0.0", "y/x and z/x are not both x@1.0.0");
      keys(lock, ["y/x/b", "y/b"]);
    },
  },
  // One package reached under two peer providers (two store entries) and under one (deduplicated).
  conformance_peer_contexts: {
    files: () => ({
      "package.json": json({
        name: "conformance-peer-contexts",
        private: true,
        workspaces: ["packages/*"],
        dependencies: { "p-user": "1.0.0", q: "1.0.0", "q2-user": "1.0.0" },
      }),
      "packages/w/package.json": json({ name: "w", version: "1.0.0", dependencies: { "p-user": "1.0.0", q: "1.0.0", r: "1.0.0" } }),
      "packages/w/BUILD.bazel": STUB_BUILD,
    }),
    check(lock) {
      assert(slot0(lock, "q2-user/q") === "q@2.0.0", "q2-user/q is not q@2.0.0");
      keys(lock, ["p", "r"]);
    },
  },
  // Two packages with a peer on one name that no ancestor declares, two versions of it in the
  // tree (S5, shared peer versions).
  conformance_shared_peer: {
    files: () => ({
      "package.json": json({
        name: "conformance-shared-peer",
        private: true,
        dependencies: { "ident-a": "1.0.0", "state-peer-any": "1.0.0", "state2-user": "1.0.0" },
      }),
    }),
    check(lock) {
      assert(slot0(lock, "state") === "state@1.0.0", "state is not state@1.0.0");
      assert(slot0(lock, "state2-user/state") === "state@2.0.0", "state2-user/state is not state@2.0.0");
    },
  },
  // FR-009, BC-7: non-optional and optional dependencies restricted to other operating systems,
  // of the root and of a package.
  conformance_platform: {
    files: () => ({
      "package.json": json({
        name: "conformance-platform",
        private: true,
        dependencies: { "nomatch-aix-ppc64": "1.0.0", "plat-user": "1.0.0" },
        optionalDependencies: { "native-darwin-arm64": "1.0.0" },
      }),
    }),
    check(lock) {
      assert(lock.packages["native-aix-x64"]?.[2]?.os === "aix", "native-aix-x64 is not restricted to aix");
      assert(lock.packages["plat-user"][2].dependencies?.["native-aix-x64"] === "1.0.0", "plat-user does not depend on native-aix-x64");
      keys(lock, ["nomatch-aix-ppc64", "nomatch-sunos-x64", "native-darwin-arm64"]);
    },
  },
  // T077: a peer whose provider up the node chain is an optional dependency restricted to another
  // OS (q: npm:q-darwin@1.0.0), so the store binds p's peer q per platform: to q-darwin@1.0.0 on
  // darwin, to the root's q@1.0.0 elsewhere (ISO L1032-L1047, L1074-L1170); through a registry
  // package (plat-peer-host's p) and through a workspace (w's p).
  conformance_platform_peer: {
    files: () => ({
      "package.json": json({ name: "conformance-platform-peer", private: true, dependencies: { "plat-peer-host": "1.0.0", q: "1.0.0" } }),
    }),
    check(lock) {
      assert(slot0(lock, "plat-peer-host/q") === "q-darwin@1.0.0", "plat-peer-host's q is not q-darwin@1.0.0");
      assert(lock.packages["plat-peer-host/q"][2]?.os === "darwin", "q-darwin is not restricted to darwin");
      assert(slot0(lock, "q") === "q@1.0.0", "the root's q is not q@1.0.0");
      assert(slot0(lock, "p") === "p@1.0.0", "p is not hoisted to the root");
    },
  },
  conformance_platform_peer_workspace: {
    files: () => ({
      "package.json": json({ name: "conformance-platform-peer-workspace", private: true, workspaces: ["packages/*"], dependencies: { q: "1.0.0" } }),
      "packages/w/package.json": json({ name: "w", version: "1.0.0", dependencies: { p: "1.0.0" }, optionalDependencies: { q: "npm:q-darwin@1.0.0" } }),
      "packages/w/BUILD.bazel": STUB_BUILD,
    }),
    check(lock) {
      assert(slot0(lock, "w/q") === "q-darwin@1.0.0", "w's q is not q-darwin@1.0.0");
      assert(slot0(lock, "q") === "q@1.0.0", "the root's q is not q@1.0.0");
    },
  },
  // T101: an edge the store has on some platform classes only. native optionally depends on
  // native-linux-x64-musl (libc musl), which the root depends on as well; off musl the store
  // drops native's optional edge, while the root's non-optional one stays (`Libc::for_dependency`,
  // resolver_hooks.rs L882-L890), so a target holding both must not link native's.
  conformance_platform_edge: {
    files: () => ({
      "package.json": json({
        name: "conformance-platform-edge",
        private: true,
        dependencies: { native: "1.0.0", "native-linux-x64-musl": "1.0.0" },
      }),
    }),
    check(lock) {
      assert(lock.packages["native"][2].optionalDependencies?.["native-linux-x64-musl"] === "1.0.0", "native does not optionally depend on native-linux-x64-musl");
      assert(lock.packages["native-linux-x64-musl"][2].libc === "musl", "native-linux-x64-musl is not restricted to musl");
      assert(walk(lock, "native", "native-linux-x64-musl") === "native-linux-x64-musl", "native's native-linux-x64-musl is not the root's");
    },
  },
  // T097: a workspace's peer plat-p: ^1.0.0 and the root's optional plat-p@2.0.0, restricted to
  // darwin, whose bins differ from plat-p@1.0.0's: the reviewer's case of a link whose root may be
  // a different package by platform.
  conformance_platform_root_package: {
    files: () => ({
      "package.json": json({
        name: "conformance-platform-root-package",
        private: true,
        workspaces: ["packages/*"],
        optionalDependencies: { "plat-p": "2.0.0" },
      }),
      "packages/w/package.json": json({ name: "w", version: "1.0.0", peerDependencies: { "plat-p": "^1.0.0" } }),
      "packages/w/BUILD.bazel": STUB_BUILD,
    }),
    check(lock) {
      assert(slot0(lock, "plat-p") === "plat-p@2.0.0", "the root's plat-p is not plat-p@2.0.0");
      assert(lock.packages["plat-p"][2]?.os === "darwin", "plat-p@2.0.0 is not restricted to darwin");
    },
  },
  // FR-009: overrides of the ranges of a peer (state) and of a peer a dependency provides (q).
  conformance_overrides: {
    files: () => ({
      "package.json": json({
        name: "conformance-overrides",
        private: true,
        dependencies: { "ident-a": "1.0.0", "p-user": "1.0.0" },
        overrides: { q: "2.0.0", state: "2.0.0" },
      }),
    }),
    check(lock) {
      assert(slot0(lock, "state") === "state@2.0.0", "state is not overridden to 2.0.0");
      assert(slot0(lock, "q") === "q@2.0.0", "q is not overridden to 2.0.0");
    },
  },
  // FR-009: a catalog: dependency and a workspace's catalog: peer.
  conformance_catalog: {
    files: () => ({
      "package.json": json({
        name: "conformance-catalog",
        private: true,
        workspaces: { packages: ["packages/*"], catalog: { q: "1.0.0", state: "2.0.0" } },
        dependencies: { "ident-a": "1.0.0", state: "catalog:" },
      }),
      "packages/w/package.json": json({ name: "w", version: "1.0.0", dependencies: { "p-user": "1.0.0" }, peerDependencies: { q: "catalog:" } }),
      "packages/w/BUILD.bazel": STUB_BUILD,
    }),
    check(lock) {
      assert(lock.workspaces["packages/w"].peerDependencies?.q === "catalog:", "w's peer q is not catalog:");
      assert(slot0(lock, "q") === "q@1.0.0", "q is not q@1.0.0");
      assert(slot0(lock, "state") === "state@2.0.0", "state is not state@2.0.0");
    },
  },
  // A package with bundleDependencies: its bundled dependency's entry carries "bundled": true.
  conformance_bundled: {
    files: () => ({
      "package.json": json({ name: "conformance-bundled", private: true, dependencies: { b: "2.0.0", bundler: "1.0.0" } }),
    }),
    check(lock) {
      assert(lock.packages["bundler/b"]?.[2]?.bundled === true, "bundler/b is not bundled");
    },
  },
  // BC-8: a patched package (unfetched, unsupported_reason) with a dependency, which Bun installs
  // and links: a@1.0.0 depends on b ^1.0.0.
  conformance_unfetched: {
    files: () => ({
      "package.json": json({ name: "conformance-unfetched", private: true, dependencies: { a: "1.0.0" } }),
    }),
    async run({ dir, bun }) {
      await bun("install");
      await bun("patch", "a");
      writeFileSync(join(dir, "node_modules", "a", "index.js"), 'module.exports = { name: "a", version: "patched" };\n');
      await bun("patch", "--commit", "node_modules/a");
    },
    keep: ["package.json", "patches"],
    check(lock) {
      assert(lock.patchedDependencies?.["a@1.0.0"], "patchedDependencies has no a@1.0.0");
      assert(lock.packages.a?.[2]?.dependencies?.b === "^1.0.0", "a does not depend on b");
      assert(slot0(lock, "b") === "b@1.0.0", "b is not b@1.0.0");
    },
  },
  // A peer whose only provider on its ancestor chain is an optional dependency
  // the lockfile lists under `unresolved` (spec Edge Cases): ident-a's peer
  // `state` under opt-user, whose optional `state ^3.0.0` is unresolved while
  // the tree holds state@2.0.0 through state2-user, which the root does not
  // declare `state` beside.
  conformance_unresolved_peer: {
    files: () => ({
      "package.json": json({
        name: "conformance-unresolved-peer",
        private: true,
        dependencies: { "opt-user": "1.0.0", "state2-user": "1.0.0" },
      }),
    }),
    check(lock) {
      assert(JSON.stringify(lock.packages["opt-user"]?.[2]?.unresolved) === '["state"]', "opt-user's unresolved is not [state]");
      assert(!("state" in (lock.workspaces[""].dependencies ?? {})), "the root declares state");
      assert(lock.packages["ident-a"]?.[2]?.peerDependencies?.state === "^1.0.0", "ident-a has no peer state");
      assert(Object.values(lock.packages).some((row) => row[0] === "state@2.0.0"), "the tree holds no state@2.0.0");
    },
  },
  alg_sha384: {
    algorithm: "sha384",
    files: () => ({ "package.json": json({ name: "alg-sha384", private: true, dependencies: { a: "1.0.0" } }) }),
    check(lock) {
      assert(String(lock.packages.a[3]).startsWith("sha384-"), `a integrity ${lock.packages.a[3]}`);
    },
  },
};

// A variant archive (`<store name>+<variant>.tgz`, pack.ts) is a second archive of
// a package version, which the registry cannot publish next to the first.
function archives(project: Project): ArchiveSpec[] {
  return readdirSync(archivesDir)
    .filter((f) => f.endsWith(".tgz") && !f.slice(f.lastIndexOf("@")).includes("+"))
    .sort()
    .map((f) => ({
      path: join(archivesDir, f),
      algorithm: project.noIntegrity?.includes(f.slice(0, -".tgz".length)) ? "none" : (project.algorithm ?? "sha512"),
    }));
}

function writeFiles(dir: string, files: Files) {
  for (const [name, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, name)), { recursive: true });
    writeFileSync(join(dir, name), text);
  }
}

// Bun runs as a child process without blocking this process, which serves the
// loopback registry it fetches from.
async function generate(name: string, project: Project, forBun142 = false) {
  const registry = startRegistry({ archives: archives(project), port: FIXTURE_PORT });
  const work = mkdtempSync(join(tmpdir(), `rules-bun-lock-${name}-`));
  try {
    const dir = join(work, name);
    const cache = join(work, "cache");
    const files = project.files(registry.url);
    writeFiles(dir, files);
    const bun = async (...args: string[]) => {
      const child = Bun.spawn([process.execPath, ...args], {
        cwd: dir,
        env: { ...process.env, BUN_INSTALL_CACHE_DIR: cache, BUN_CONFIG_REGISTRY: registry.url, NO_COLOR: "1" },
        stdin: "ignore",
        stdout: "pipe",
        stderr: "pipe",
      });
      const [stdout, stderr, exitCode] = await Promise.all([
        new Response(child.stdout).text(),
        new Response(child.stderr).text(),
        child.exited,
      ]);
      if (exitCode !== 0) throw new Error(`bun ${args.join(" ")} failed in ${name}:\n${stdout}${stderr}`);
      return stdout + stderr;
    };
    const lock = () => Bun.JSONC.parse(readFileSync(join(dir, "bun.lock"), "utf8")) as Lockfile;
    if (project.run) await project.run({ dir, registry, bun, lock });
    else await bun("install", `--registry=${registry.url}`);
    if (forBun142) {
      // Bun 1.4.2 writes its own forms; the project's check is of the pinned Bun's (1.4.4).
      const out = join(bun142, name);
      rmSync(out, { recursive: true, force: true });
      writeFiles(out, Object.fromEntries(Object.entries(files).filter(([file]) => !file.endsWith("BUILD.bazel"))));
      for (const kept of ["bun.lock", ...(project.keep ?? [])]) cpSync(join(dir, kept), join(out, kept), { recursive: true });
      writeFileSync(join(out, "BUILD.bazel"), `${CONFORMANCE_LOAD}\n# Written by Bun 1.4.2 (write_lockfiles.ts --bun-1-4-2).\n\nexports_files([\n    "bun.lock",\n    "package.json",\n])\n\nconformance_files()\n`);
      console.log(`${name}: lockfileVersion ${lock().lockfileVersion} (Bun ${Bun.version})`);
      return;
    }
    project.check(lock());

    const out = join(fixtures, name);
    // A checked-in BUILD file holds the fixture's targets; the stub is only for Bun.
    writeFiles(
      out,
      Object.fromEntries(
        Object.entries(files).filter(([file]) => !(file.endsWith("BUILD.bazel") && existsSync(join(out, file)))),
      ),
    );
    for (const kept of ["bun.lock", ...(project.keep ?? [])]) {
      rmSync(join(out, kept), { recursive: true, force: true });
      cpSync(join(dir, kept), join(out, kept), { recursive: true });
    }
    if (!existsSync(join(out, "BUILD.bazel"))) {
      writeFileSync(join(out, "BUILD.bazel"), `${CONFORMANCE_LOAD}\nexports_files([\n    "bun.lock",\n    "package.json",\n])\n\nconformance_files()\n`);
    }
    console.log(`${name}: lockfileVersion ${lock().lockfileVersion}`);
  } finally {
    registry.stop();
    rmSync(work, { recursive: true, force: true });
  }
}

if (import.meta.main) {
  const forBun142 = process.argv.includes(BUN_1_4_2_FLAG);
  const selected = process.argv.slice(2).filter((arg) => arg !== BUN_1_4_2_FLAG);
  if (forBun142 && Bun.version !== "1.4.2") throw new Error(`write_lockfiles: ${BUN_1_4_2_FLAG} needs Bun 1.4.2, not ${Bun.version}`);
  for (const [name, project] of Object.entries(projects)) {
    if (selected.length > 0 && !selected.includes(name)) continue;
    if (forBun142 && (!name.startsWith("conformance_") || name in NOT_APPLICABLE_1_4_2)) continue;
    await generate(name, project, forBun142);
  }
}
