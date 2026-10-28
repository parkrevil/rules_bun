// Helpers for the bun.lock canaries (FR-024, research R17): each canary writes a
// project under TEST_TMPDIR, runs the pinned Bun's installer against a loopback
// registry serving the fixture archives, and checks one lockfile access.

import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { rlocation, rlocationList } from "../../support/spawn.ts";
import { type ArchiveSpec, type LogEntry, type RegistryOptions, startRegistry } from "../../support/npm_registry.ts";

export type Files = Record<string, string>;

/** How a canary's fixture is altered to record its red (SC-007); default none. */
export interface Alter {
  /** Edits the project files before the run. */
  files?: (files: Files) => Files;
  /** Edits the text of a bun.lock the project holds before the run. */
  lockfile?: (text: string) => string;
  /** Edits a packument before the registry serves it. */
  packument?: (name: string, packument: Record<string, any>) => Record<string, any>;
}

export interface InstallOptions {
  /** `install --lockfile-only`. */
  lockfileOnly?: boolean;
  /** `install --frozen-lockfile`. */
  frozenLockfile?: boolean;
  /** Further `install` arguments. */
  args?: string[];
  alter?: Alter;
  /** Archives to serve, by store name (`@scope+s@1.0.0`); default every fixture archive. */
  archives?: string[];
  /** Integrity algorithm per store name; default sha512. */
  algorithms?: Record<string, ArchiveSpec["algorithm"]>;
  /** Registry options other than the archives. */
  registry?: Omit<RegistryOptions, "archives">;
  /** A directory to run in again, holding a project an earlier run wrote. */
  dir?: string;
}

export interface InstallResult {
  /** The project directory. */
  dir: string;
  /** The loopback registry's URL. */
  url: string;
  /** The text of the bun.lock the run left. */
  text: string;
  /** That text, decoded as JSONC. */
  lock: Record<string, any>;
  /** Every request the registry answered. */
  log: LogEntry[];
  /** Bun's output. */
  output: string;
}

const ARCHIVES = "_main/bun/tests/npm/registry/archives";

function fixtureArchives(names: string[] | undefined, algorithms: InstallOptions["algorithms"]): ArchiveSpec[] {
  return rlocationList(ARCHIVES)
    .filter((path) => path.endsWith(".tgz"))
    .map((path) => ({ path, store: path.slice(ARCHIVES.length + 1, -".tgz".length) }))
    // A variant archive (`<store name>+<variant>`, pack.ts) is a second archive of a package
    // version, which the registry cannot publish next to the first.
    .filter(({ store }) => (names === undefined ? !store.slice(store.lastIndexOf("@")).includes("+") : names.includes(store)))
    .map(({ path, store }) => ({ path: rlocation(path), algorithm: algorithms?.[store] ?? "sha512" }));
}

function writeFiles(dir: string, files: Files) {
  for (const [name, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, name)), { recursive: true });
    writeFileSync(join(dir, name), text);
  }
}

/**
 * Writes `files` (given the registry URL) into a new project under TEST_TMPDIR,
 * or into `options.dir`, and runs `bun install --registry=<loopback>` there.
 * Fails when Bun fails.
 */
export async function runInstall(
  files: Files | ((url: string) => Files),
  options: InstallOptions = {},
): Promise<InstallResult> {
  const registry = startRegistry({
    ...options.registry,
    archives: fixtureArchives(options.archives, options.algorithms),
    packument: options.alter?.packument ?? options.registry?.packument,
  });
  try {
    const dir = options.dir ?? mkdtempSync(join(process.env.TEST_TMPDIR!, "canary-"));
    let projectFiles = typeof files === "function" ? files(registry.url) : files;
    if (options.alter?.files) projectFiles = options.alter.files(projectFiles);
    if (options.alter?.lockfile && projectFiles["bun.lock"] !== undefined) {
      projectFiles = { ...projectFiles, "bun.lock": options.alter.lockfile(projectFiles["bun.lock"]) };
    }
    writeFiles(dir, projectFiles);

    const args = ["install", `--registry=${registry.url}`];
    if (options.lockfileOnly) args.push("--lockfile-only");
    if (options.frozenLockfile) args.push("--frozen-lockfile");
    args.push(...(options.args ?? []));
    const child = Bun.spawn([process.execPath, ...args], {
      cwd: dir,
      env: {
        ...process.env,
        BUN_INSTALL_CACHE_DIR: mkdtempSync(join(process.env.TEST_TMPDIR!, "canary-cache-")),
        BUN_CONFIG_REGISTRY: registry.url,
        NO_COLOR: "1",
      },
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
    });
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(child.stdout).text(),
      new Response(child.stderr).text(),
      child.exited,
    ]);
    const output = stdout + stderr;
    if (exitCode !== 0) throw new Error(`bun ${args.join(" ")} failed with exit ${exitCode}:\n${output}`);
    const text = readFileSync(join(dir, "bun.lock"), "utf8");
    return { dir, url: registry.url, text, lock: Bun.JSONC.parse(text) as Record<string, any>, log: registry.log, output };
  } finally {
    registry.stop();
  }
}

/** Throws the canary failure of research R17. */
export function canaryFail(id: string, access: string, readerFunction: string, source: string, observed?: unknown): never {
  if (observed !== undefined) console.error(`canary ${id} observed: ${JSON.stringify(observed)}`);
  throw new Error(`rules_bun canary ${id}: Bun's bun.lock ${access} changed: revisit ${readerFunction}; source ${source}`);
}

/** The source every bun.lock canary names: the blog post bun.com links for the format. */
export const LOCKFILE_SOURCE = "https://bun.com/blog/bun-lock-text-lockfile";

/** JSON text of a package.json. */
export function manifest(value: Record<string, unknown>): string {
  return JSON.stringify(value, null, 2) + "\n";
}

/**
 * The alteration of a canary's fixture that records its red (SC-007): `alter`
 * when RULES_BUN_CANARY_RED is set (`bazel test --test_env=RULES_BUN_CANARY_RED=1
 * //bun/tests/canary/npm:canaries`), otherwise none.
 */
export function red(alter: Alter): Alter | undefined {
  return process.env.RULES_BUN_CANARY_RED ? alter : undefined;
}

/** Entries of a lockfile's `packages` whose slot 0 is `spec`. */
export function keysOf(lock: Record<string, any>, spec: string): string[] {
  return Object.entries(lock.packages as Record<string, any[]>)
    .filter(([, entry]) => entry[0] === spec)
    .map(([key]) => key)
    .sort();
}
