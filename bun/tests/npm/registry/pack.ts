// Packs the npm fixture package sources into the checked-in archives
// (research R14). Run by hand with the pinned Bun from the repository root:
//
//   $(bazel info output_base)/external/+bun+bun_linux-x64/bun bun/tests/npm/registry/pack.ts
//
// Every source under packages/<name>@<version>/ is packed with `bun pm pack`
// into archives/<store name>.tgz (a scope's "/" written "+"). Two archives are
// written by this script instead: toplevel@1.0.0 with the top-level directory
// toplevel/ instead of package/ (FR-034), and winname@1.0.0 holding
// package/aux.js and package/a:b.js (G2), names no Windows checkout can hold,
// and emptydir@1.0.0 holding the empty directories package/empty/ and
// package/nested/inner/, which neither git nor `bun pm pack` carries. All three
// get fixed modes and mtimes. Each archive's sha512 SRI is printed.

import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { integrity } from "../../support/npm_registry.ts";
import { readTgz, type TarEntry, writeTgz } from "../../support/tar.ts";

const here = import.meta.dir;
const sources = join(here, "packages");
const archives = join(here, "archives");
const encoder = new TextEncoder();

function sourceDirs(): string[] {
  const dirs: string[] = [];
  for (const name of readdirSync(sources).sort()) {
    const path = join(sources, name);
    if (name.startsWith("@")) {
      for (const inner of readdirSync(path).sort()) dirs.push(join(path, inner));
    } else if (statSync(path).isDirectory()) {
      dirs.push(path);
    }
  }
  return dirs;
}

function storeName(manifest: { name: string; version: string }): string {
  return `${manifest.name.replace("/", "+")}@${manifest.version}`;
}

function pack(dir: string): Uint8Array {
  const out = mkdtempSync(join(tmpdir(), "rules-bun-pack-"));
  try {
    const result = Bun.spawnSync(
      [process.execPath, "pm", "pack", "--ignore-scripts", "--quiet", "--filename", join(out, "out.tgz")],
      { cwd: dir, stdout: "pipe", stderr: "pipe" },
    );
    if (result.exitCode !== 0) throw new Error(`bun pm pack failed in ${dir}: ${result.stderr.toString()}`);
    return new Uint8Array(readFileSync(join(out, "out.tgz")));
  } finally {
    rmSync(out, { recursive: true, force: true });
  }
}

const MTIME = 499162500; // 1985-10-26T08:15:00Z, the mtime npm writes into package archives.

function fileEntry(name: string, text: string): TarEntry {
  return { name, type: "file", data: encoder.encode(text), mode: 0o644 };
}

function directoryEntry(name: string): TarEntry {
  return { name, type: "directory", data: new Uint8Array(), mode: 0o755 };
}

const special: Record<string, (packed: Uint8Array) => Uint8Array> = {
  "emptydir@1.0.0": (packed) =>
    writeTgz(
      [
        ...readTgz(packed)
          .filter((e) => e.type === "file")
          .map((e) => ({ ...e, mode: 0o644 })),
        directoryEntry("package/empty/"),
        directoryEntry("package/nested/"),
        directoryEntry("package/nested/inner/"),
      ],
      MTIME,
    ),
  "toplevel@1.0.0": (packed) =>
    writeTgz(
      readTgz(packed)
        .filter((e) => e.type === "file")
        .map((e) => ({ ...e, name: e.name.replace(/^package\//, "toplevel/"), mode: 0o644 })),
      MTIME,
    ),
  "winname@1.0.0": (packed) =>
    writeTgz(
      [
        ...readTgz(packed)
          .filter((e) => e.type === "file")
          .map((e) => ({ ...e, mode: 0o644 })),
        fileEntry("package/aux.js", 'module.exports = "aux";\n'),
        fileEntry("package/a:b.js", 'module.exports = "a:b";\n'),
      ],
      MTIME,
    ),
};

mkdirSync(archives, { recursive: true });
for (const file of readdirSync(archives)) {
  if (file.endsWith(".tgz")) rmSync(join(archives, file));
}
const bunVersion = Bun.spawnSync([process.execPath, "--version"]).stdout.toString().trim();
console.log(`bun ${bunVersion}`);
for (const dir of sourceDirs()) {
  const manifest = JSON.parse(readFileSync(join(dir, "package.json"), "utf8"));
  const name = storeName(manifest);
  let bytes = pack(dir);
  if (special[name]) bytes = special[name](bytes);
  writeFileSync(join(archives, `${name}.tgz`), bytes);
  console.log(`${name}.tgz ${integrity(bytes)}`);
}
