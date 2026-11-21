// The scale fixture (FR-037, SC-010, research G8; tasks.md decision 8): 2,000
// deterministic npm packages in 20 layers of 100. Package k of a layer depends
// on packages k, 7k + 3 and 13k + 5 (mod 100) of the next layer, every fourth
// package is scoped, and one package holds a file at a deep path. The root
// project depends on the 100 packages of the first layer.
//
// The platform variant (feature 006 T100, plan R13) adds an esbuild-like set of
// per-platform optional packages (`os` and `cpu`, and `libc` on Linux x64 and
// arm64) under `scale-native`, which every tenth package depends on, so that
// each platform class of the resolver builds its own store.
//
// `writeArchives(dir)` writes the archives with fixed mtimes, modes and gzip
// level, so the same archives, and the integrity bun.lock records, come out of
// every run; the scale test regenerates them at test time. Run by hand with the
// pinned Bun from the repository root to write bun.lock and package.json next to
// this file, or, with --platform, the variant's into platform/:
//
//   $(bazel info output_base)/external/+bun+bun_linux-x64/bun bun/tests/npm/scale/generate.ts [--platform]

import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FIXTURE_PORT, startRegistry } from "../../support/npm_registry.ts";
import { type TarEntry, writeTgz } from "../../support/tar.ts";

export const LAYERS = 20;
export const WIDTH = 100;

const MTIME = 499162500; // 1985-10-26T08:15:00Z, the mtime npm writes into package archives.
const DEEP = "package/lib/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/index.js";
const encoder = new TextEncoder();

export interface ScalePackage {
  name: string;
  version: string;
  dependencies: string[];
  optionalDependencies?: string[];
  os?: string[];
  cpu?: string[];
  libc?: string[];
}

export const NATIVE = "scale-native";

// The variant's per-platform packages, as esbuild publishes them: `[os, cpu, libc]`.
const NATIVE_TARGETS: [string, string, string?][] = [
  ["aix", "ppc64"],
  ["android", "arm"],
  ["android", "arm64"],
  ["android", "x64"],
  ["darwin", "arm64"],
  ["darwin", "x64"],
  ["freebsd", "arm64"],
  ["freebsd", "x64"],
  ["linux", "arm"],
  ["linux", "arm64", "glibc"],
  ["linux", "arm64", "musl"],
  ["linux", "ia32"],
  ["linux", "riscv64"],
  ["linux", "s390x"],
  ["linux", "x64", "glibc"],
  ["linux", "x64", "musl"],
  ["netbsd", "x64"],
  ["openbsd", "arm64"],
  ["openbsd", "x64"],
  ["sunos", "x64"],
  ["win32", "arm64"],
  ["win32", "ia32"],
  ["win32", "x64"],
];

function nativeName([os, cpu, libc]: [string, string, string?]): string {
  return `@scale/native-${os}-${cpu}${libc ? `-${libc}` : ""}`;
}

export function packageName(layer: number, k: number): string {
  const id = `l${String(layer).padStart(2, "0")}-${String(k).padStart(2, "0")}`;
  return k % 4 === 0 ? `@scale/${id}` : `scale-${id}`;
}

/** The packages in a fixed order, each with the names it depends on; `platform` adds the variant's. */
export function scalePackages(platform = false): ScalePackage[] {
  const packages: ScalePackage[] = [];
  for (let layer = 0; layer < LAYERS; layer++) {
    for (let k = 0; k < WIDTH; k++) {
      const next = layer + 1 < LAYERS ? [k, (7 * k + 3) % WIDTH, (13 * k + 5) % WIDTH] : [];
      const dependencies = [...new Set(next)].sort((x, y) => x - y).map((j) => packageName(layer + 1, j));
      if (platform && k % 10 === 0) dependencies.push(NATIVE);
      packages.push({ name: packageName(layer, k), version: "1.0.0", dependencies });
    }
  }
  if (platform) {
    packages.push({ name: NATIVE, version: "1.0.0", dependencies: [], optionalDependencies: NATIVE_TARGETS.map(nativeName) });
    for (const target of NATIVE_TARGETS) {
      const [os, cpu, libc] = target;
      packages.push({ name: nativeName(target), version: "1.0.0", dependencies: [], os: [os], cpu: [cpu], ...(libc ? { libc: [libc] } : {}) });
    }
  }
  return packages;
}

/** The root project's package.json. */
export function rootManifest(): string {
  const dependencies: Record<string, string> = {};
  for (let k = 0; k < WIDTH; k++) dependencies[packageName(0, k)] = "1.0.0";
  return JSON.stringify({ name: "scale", private: true, dependencies }, null, 2) + "\n";
}

function archive(pkg: ScalePackage, deep: boolean): Uint8Array {
  const manifest = {
    name: pkg.name,
    version: pkg.version,
    main: "index.js",
    dependencies: Object.fromEntries(pkg.dependencies.map((d) => [d, "^1.0.0"])),
    ...(pkg.optionalDependencies ? { optionalDependencies: Object.fromEntries(pkg.optionalDependencies.map((d) => [d, "1.0.0"])) } : {}),
    ...(pkg.os ? { os: pkg.os } : {}),
    ...(pkg.cpu ? { cpu: pkg.cpu } : {}),
    ...(pkg.libc ? { libc: pkg.libc } : {}),
  };
  const entries: TarEntry[] = [
    { name: "package/package.json", type: "file", data: encoder.encode(JSON.stringify(manifest, null, 2) + "\n"), mode: 0o644 },
    { name: "package/index.js", type: "file", data: encoder.encode(`module.exports = ${JSON.stringify(pkg.name)};\n`), mode: 0o644 },
  ];
  if (deep) entries.push({ name: DEEP, type: "file", data: encoder.encode("module.exports = 1;\n"), mode: 0o644 });
  return writeTgz(entries, MTIME);
}

/** Writes every archive to `dir` as `<store name>.tgz` and returns their paths. */
export function writeArchives(dir: string, platform = false): string[] {
  mkdirSync(dir, { recursive: true });
  const deep = packageName(LAYERS - 1, WIDTH - 1);
  return scalePackages(platform).map((pkg) => {
    const path = join(dir, `${pkg.name.replace("/", "+")}@${pkg.version}.tgz`);
    writeFileSync(path, archive(pkg, pkg.name === deep));
    return path;
  });
}

async function main(platform: boolean) {
  const work = mkdtempSync(join(tmpdir(), "rules-bun-scale-"));
  try {
    const registry = startRegistry({ archives: writeArchives(join(work, "archives"), platform), port: FIXTURE_PORT });
    try {
      const project = join(work, "project");
      mkdirSync(project);
      writeFileSync(join(project, "package.json"), rootManifest());
      const child = Bun.spawn([process.execPath, "install", "--lockfile-only", `--registry=${registry.url}`], {
        cwd: project,
        env: { ...process.env, BUN_INSTALL_CACHE_DIR: join(work, "cache"), NO_COLOR: "1" },
        stdout: "pipe",
        stderr: "pipe",
      });
      const [stderr, exitCode] = await Promise.all([new Response(child.stderr).text(), child.exited]);
      if (exitCode !== 0) throw new Error(`bun install failed: ${stderr}`);
      const lock = readFileSync(join(project, "bun.lock"), "utf8");
      const out = platform ? join(import.meta.dir, "platform") : import.meta.dir;
      mkdirSync(out, { recursive: true });
      writeFileSync(join(out, "bun.lock"), lock);
      writeFileSync(join(out, "package.json"), rootManifest());
      const packages = scalePackages(platform);
      const edges = packages.reduce((n, p) => n + p.dependencies.length, 0);
      const keys = Object.keys(Bun.JSONC.parse(lock).packages).length;
      console.log(`packages ${packages.length}, edges ${edges}, bun.lock package keys ${keys}`);
    } finally {
      registry.stop();
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

if (import.meta.main) await main(process.argv.includes("--platform"));
