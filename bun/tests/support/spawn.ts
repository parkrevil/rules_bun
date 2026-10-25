// Helpers for spawn tests (FR-021): a passing bun_test lists a `manual` target in
// `data`, resolves its executable through runfiles and starts it.

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

// Variables of the Bazel test protocol that the spawned target must not inherit
// from the spawning test unless the caller sets them.
const PROTOCOL_VARIABLES = [
  "XML_OUTPUT_FILE",
  "TEST_TOTAL_SHARDS",
  "TEST_SHARD_INDEX",
  "TEST_SHARD_STATUS_FILE",
  "TESTBRIDGE_TEST_ONLY",
  "COVERAGE_DIR",
];

let manifest: Map<string, string> | undefined;

function readManifest(path: string): Map<string, string> {
  const entries = new Map<string, string>();
  for (const line of readFileSync(path, "utf8").split("\n")) {
    if (line === "") continue;
    if (line.startsWith(" ")) {
      // An escaped line (Bazel's SourceManifestAction; rules_python runfiles.py).
      const rest = line.slice(1);
      const space = rest.indexOf(" ");
      const link = rest.slice(0, space).replaceAll("\\s", " ").replaceAll("\\n", "\n").replaceAll("\\b", "\\");
      const target = rest.slice(space + 1).replaceAll("\\n", "\n").replaceAll("\\b", "\\");
      entries.set(link, target);
    } else {
      const space = line.indexOf(" ");
      entries.set(line.slice(0, space), line.slice(space + 1));
    }
  }
  return entries;
}

/** Resolves an rlocation path through RUNFILES_MANIFEST_FILE or RUNFILES_DIR. */
export function rlocation(path: string): string {
  const manifestFile = process.env.RUNFILES_MANIFEST_FILE;
  if (manifestFile) {
    manifest ??= readManifest(manifestFile);
    const found = manifest.get(path);
    if (found === undefined) throw new Error(`${path} is not in the runfiles manifest ${manifestFile}`);
    return found;
  }
  const dir = process.env.RUNFILES_DIR;
  if (dir) {
    const found = join(dir, path);
    if (!existsSync(found)) throw new Error(`${path} is not in the runfiles directory ${dir}`);
    return found;
  }
  throw new Error("neither RUNFILES_MANIFEST_FILE nor RUNFILES_DIR is set");
}

/**
 * Returns the rlocation paths of the runfiles directly or indirectly under the
 * rlocation directory `dir`, sorted, through RUNFILES_MANIFEST_FILE or
 * RUNFILES_DIR.
 */
export function rlocationList(dir: string): string[] {
  const prefix = dir.endsWith("/") ? dir : `${dir}/`;
  const manifestFile = process.env.RUNFILES_MANIFEST_FILE;
  if (manifestFile) {
    manifest ??= readManifest(manifestFile);
    return [...manifest.keys()].filter((k) => k.startsWith(prefix)).sort();
  }
  const root = process.env.RUNFILES_DIR;
  if (root) {
    const found: string[] = [];
    const visit = (path: string) => {
      for (const entry of readdirSync(join(root, path), { withFileTypes: true })) {
        const child = `${path}/${entry.name}`;
        if (statSync(join(root, child)).isDirectory()) visit(child);
        else found.push(child);
      }
    };
    visit(prefix.slice(0, -1));
    return found.sort();
  }
  throw new Error("neither RUNFILES_MANIFEST_FILE nor RUNFILES_DIR is set");
}

/** Returns the rlocation path of a target's executable on the running OS. */
export function executable(rlocationPath: string): string {
  return process.platform === "win32" ? `${rlocationPath}.exe` : rlocationPath;
}

export interface SpawnOptions {
  args?: string[];
  /** Variables to set; `undefined` removes a variable. */
  env?: Record<string, string | undefined>;
  cwd?: string;
  stdin?: string;
}

export interface SpawnResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** Starts the executable of a target, given its rlocation path, and waits for it. */
export async function spawnTarget(rlocationPath: string, options: SpawnOptions = {}): Promise<SpawnResult> {
  const env: Record<string, string> = {};
  for (const [name, value] of Object.entries(process.env)) {
    if (value !== undefined && !PROTOCOL_VARIABLES.includes(name)) env[name] = value;
  }
  for (const [name, value] of Object.entries(options.env ?? {})) {
    if (value === undefined) delete env[name];
    else env[name] = value;
  }

  const child = Bun.spawn([rlocation(executable(rlocationPath)), ...(options.args ?? [])], {
    cwd: options.cwd,
    env,
    stdin: options.stdin === undefined ? "ignore" : Buffer.from(options.stdin),
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
    child.exited,
  ]);
  return { exitCode, stdout, stderr };
}

/**
 * Returns the `name` of each `<testcase>` of a JUnit report that ran. Bun lists a
 * test that a filter or a shard left out as a `<testcase>` holding `<skipped />`;
 * those are not returned. A report that was not written has none.
 */
export function testCaseNames(reportPath: string): string[] {
  if (!existsSync(reportPath)) return [];
  const xml = readFileSync(reportPath, "utf8");
  const names: string[] = [];
  for (const m of xml.matchAll(/<testcase\b([^>]*?)(?:\/>|>([\s\S]*?)<\/testcase>)/g)) {
    if (m[2]?.includes("<skipped")) continue;
    const name = /\bname="([^"]*)"/.exec(m[1]);
    if (name) names.push(name[1]);
  }
  return names;
}
