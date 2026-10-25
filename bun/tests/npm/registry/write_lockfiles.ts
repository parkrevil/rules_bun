// Writes the npm fixture projects under bun/tests/npm/fixtures/<project>/ and
// their bun.lock files (research R14). Run by hand with the pinned Bun from the
// repository root, after pack.ts:
//
//   $(bazel info output_base)/external/+bun+bun_linux-x64/bun bun/tests/npm/registry/write_lockfiles.ts [project...]
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
import { type ArchiveSpec, type IntegrityAlgorithm, type Registry, startRegistry } from "../../support/npm_registry.ts";

const here = import.meta.dir;
const archivesDir = join(here, "archives");
const fixtures = join(here, "..", "fixtures");

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

const STUB_BUILD = "# A workspace member of the fixture project.\n";

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
      assert(slot0(lock, "y/x") === "x@1.0.0" && slot0(lock, "z/x") === "x@1.0.0", "y/x and z/x are not both x@1.0.0");
      assert(walk(lock, "y/x", "b") !== walk(lock, "z/x", "b"), "the b walks of y/x and z/x reach the same key");
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
        // Bun 1.4.2 reads catalogs only under "workspaces" ("b@catalog: is not in
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
  // dependency with os darwin and cpu arm64, has a JavaScript bin.
  restricted: {
    noIntegrity: ["native-linux-x64@1.0.0"],
    files: () => ({
      "package.json": json({
        name: "restricted",
        private: true,
        dependencies: { native: "1.0.0" },
        optionalDependencies: { "bin-darwin-arm64": "1.0.0" },
      }),
    }),
    check(lock) {
      keys(lock, ["bin-darwin-arm64", "native", "native-linux-x64"]);
      assert(lock.packages["native-linux-x64"][3] === "", `native-linux-x64 integrity ${lock.packages["native-linux-x64"][3]}`);
      assert(lock.packages["bin-darwin-arm64"][2].bin?.rbin === "cli.js", "bin-darwin-arm64 has no rbin");
      assert(lock.packages["bin-darwin-arm64"][2].os === "darwin", `bin-darwin-arm64 os ${lock.packages["bin-darwin-arm64"][2].os}`);
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
  alg_sha384: {
    algorithm: "sha384",
    files: () => ({ "package.json": json({ name: "alg-sha384", private: true, dependencies: { a: "1.0.0" } }) }),
    check(lock) {
      assert(String(lock.packages.a[3]).startsWith("sha384-"), `a integrity ${lock.packages.a[3]}`);
    },
  },
};

function archives(project: Project): ArchiveSpec[] {
  return readdirSync(archivesDir)
    .filter((f) => f.endsWith(".tgz"))
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
async function generate(name: string, project: Project) {
  const registry = startRegistry({ archives: archives(project) });
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
      writeFileSync(join(out, "BUILD.bazel"), 'exports_files([\n    "bun.lock",\n    "package.json",\n])\n');
    }
    console.log(`${name}: lockfileVersion ${lock().lockfileVersion}`);
  } finally {
    registry.stop();
    rmSync(work, { recursive: true, force: true });
  }
}

const selected = process.argv.slice(2);
for (const [name, project] of Object.entries(projects)) {
  if (selected.length === 0 || selected.includes(name)) await generate(name, project);
}
