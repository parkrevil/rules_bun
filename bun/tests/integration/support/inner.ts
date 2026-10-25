// The Bazel-in-Bazel harness (research G5, G10). A test runs the pinned Bazel on
// an inner workspace from bun/tests/integration/workspaces/, offline: modules
// from a local file:// registry and rules_bun from --override_module, an empty
// repository cache of its own, and every download rewritten to a loopback server
// that serves the archives the outer build fetched and the test's npm packages.

import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, relative } from "node:path";
import { type ArchiveSpec, type LogEntry, type Registry, type RegistryOptions, startRegistry } from "../../support/npm_registry.ts";

/**
 * Timeout of one integration test case, in milliseconds: an inner Bazel build
 * takes far longer than bun test's default of 5 seconds.
 */
export const INNER_TIMEOUT = 20 * 60 * 1000;

/** Files whose text gets `{NAME}` placeholders replaced when a workspace is assembled. */
const TEXT_FILE = /(?:^|\/)(?:[^/]*\.(?:bazel|bzl|json|lock|ts|tsx|js|mjs|cjs|txt|npmrc|netrc|toml)|BUILD|\.npmrc|\.netrc|\.bazelrc)$/;

/**
 * Copies the directory `src` to `dest`, replacing each `{NAME}` of
 * `substitutions` in text files.
 */
export function assembleWorkspace(src: string, dest: string, substitutions: Record<string, string>) {
  const visit = (dir: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const from = join(dir, entry.name);
      const to = join(dest, relative(src, from));
      if (statSync(from).isDirectory()) {
        visit(from);
        continue;
      }
      writeAssembled(to, readFileSync(from), relative(src, from).split("\\").join("/"), substitutions);
    }
  };
  visit(src);
}

function writeAssembled(to: string, bytes: Buffer, rel: string, substitutions: Record<string, string>) {
  mkdirSync(dirname(to), { recursive: true });
  if (TEXT_FILE.test(rel) && Object.keys(substitutions).length > 0) {
    let text = bytes.toString("utf8");
    for (const [name, value] of Object.entries(substitutions)) text = text.replaceAll(`{${name}}`, value);
    writeFileSync(to, text);
  } else {
    writeFileSync(to, bytes);
  }
}

interface Inputs {
  archives: Record<string, string>;
  bazel: string;
  registry: string[];
  rules_bun: string[];
  workspaces: string[];
}

const INPUTS = "_main/bun/tests/integration/inner_inputs.json";
const REGISTRY_PREFIX = "_main/bun/tests/integration/registry/";
const WORKSPACES_PREFIX = "_main/bun/tests/integration/workspaces/";

let runfilesManifest: Map<string, string> | undefined;

// Resolves an rlocation path (no repository mapping: every path here is
// canonical, as inner_inputs.json writes it).
function rlocation(path: string): string {
  const manifest = process.env.RUNFILES_MANIFEST_FILE;
  if (manifest) {
    if (!runfilesManifest) {
      runfilesManifest = new Map();
      for (const line of readFileSync(manifest, "utf8").split("\n")) {
        if (line === "" || line.startsWith(" ")) continue;
        const space = line.indexOf(" ");
        runfilesManifest.set(line.slice(0, space), line.slice(space + 1));
      }
    }
    const found = runfilesManifest.get(path);
    if (found === undefined) throw new Error(`${path} is not in the runfiles manifest ${manifest}`);
    return found;
  }
  const dir = process.env.RUNFILES_DIR;
  if (dir) return join(dir, path);
  throw new Error("neither RUNFILES_MANIFEST_FILE nor RUNFILES_DIR is set");
}

let inputs: Inputs | undefined;
function readInputs(): Inputs {
  inputs ??= JSON.parse(readFileSync(rlocation(INPUTS), "utf8")) as Inputs;
  return inputs;
}

export interface InnerOptions {
  /** npm package archives the loopback server publishes (research R15). */
  npmArchives?: (string | ArchiveSpec)[];
  /** Other options of the loopback server (credential, static files, ...). */
  registry?: Omit<RegistryOptions, "archives">;
  /** `{NAME}` → value in the workspace's text files; `{REGISTRY}` is the loopback URL. */
  substitutions?: Record<string, string>;
  /** Environment of the inner Bazel; `undefined` removes a variable. */
  env?: Record<string, string | undefined>;
  /** Startup options before the command. */
  startup?: string[];
  /** Replaces the rewrite of every non-loopback URL to the loopback server. */
  downloaderConfig?: (loopback: string) => string;
}

export interface InnerResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

/** An inner workspace and its loopback server; `run` may be called several times. */
export class Inner {
  readonly root: string;
  readonly dir: string;
  readonly outputUserRoot: string;
  readonly repositoryCache: string;
  readonly registry: Registry;
  readonly repositoryCacheWasEmpty: boolean;
  private readonly substitutions: Record<string, string>;
  private readonly flags: string[];
  private readonly env: Record<string, string>;
  private readonly startup: string[];

  constructor(workspace: string, options: InnerOptions = {}) {
    const inputs = readInputs();
    this.root = mkdtempSync(join(process.env.TEST_TMPDIR!, "i"));
    // A short output user root (bazel.build, configure/windows: "Avoid long path issues").
    this.outputUserRoot = join(this.root, "o");
    this.repositoryCache = join(this.root, "c");
    this.repositoryCacheWasEmpty = !existsSync(this.repositoryCache);

    const files: Record<string, string> = {};
    for (const [path, rloc] of Object.entries(inputs.archives)) files[path] = rlocation(rloc);
    this.registry = startRegistry({ ...options.registry, archives: options.npmArchives, files: { ...files, ...options.registry?.files } });

    this.substitutions = { REGISTRY: this.registry.url, ...options.substitutions };
    this.dir = join(this.root, "w");
    this.assemble(workspace, this.dir);

    const registryDir = join(this.root, "r");
    for (const rloc of inputs.registry) {
      const rel = rloc.slice(REGISTRY_PREFIX.length);
      mkdirSync(dirname(join(registryDir, rel)), { recursive: true });
      copyFileSync(rlocation(rloc), join(registryDir, rel));
    }
    const moduleDir = join(this.root, "m");
    for (const rloc of inputs.rules_bun) {
      const rel = rloc.slice("_main/".length);
      mkdirSync(dirname(join(moduleDir, rel)), { recursive: true });
      copyFileSync(rlocation(rloc), join(moduleDir, rel));
    }

    const config = join(this.root, "downloader.cfg");
    const rewrite = `rewrite ((?!127\\.0\\.0\\.1[:/]).*) ${this.registry.url}/$1\n`;
    writeFileSync(config, options.downloaderConfig ? options.downloaderConfig(this.registry.url) : rewrite);

    this.flags = [
      `--registry=${fileUrl(registryDir)}`,
      `--override_module=rules_bun=${moduleDir}`,
      `--repository_cache=${this.repositoryCache}`,
      `--downloader_config=${config}`,
    ];
    this.startup = [`--output_user_root=${this.outputUserRoot}`, "--nosystem_rc", "--nohome_rc", ...(options.startup ?? [])];
    this.env = {};
    for (const [name, value] of Object.entries({ ...process.env, ...options.env })) {
      if (value !== undefined) this.env[name] = value;
    }
    for (const name of Object.keys(this.env)) {
      // The outer test's protocol and runfiles variables are not the inner build's.
      if (/^(TEST_|TESTBRIDGE_|XML_OUTPUT_FILE|COVERAGE|RUNFILES_|JAVA_RUNFILES|BUILD_WORKSPACE_DIRECTORY|BUILD_WORKING_DIRECTORY|RULES_BUN_)/.test(name)) {
        if (name !== "TEST_TMPDIR") delete this.env[name];
      }
    }
  }

  /**
   * Writes the files of the directory `workspace` under
   * bun/tests/integration/workspaces/ to `dest`, with the substitutions of this
   * session (`{REGISTRY}`); for a module the inner workspace depends on.
   */
  assemble(workspace: string, dest: string) {
    const prefix = `${WORKSPACES_PREFIX}${workspace}/`;
    const sources = readInputs().workspaces.filter((p) => p.startsWith(prefix));
    if (sources.length === 0) throw new Error(`no inner workspace ${workspace} under ${WORKSPACES_PREFIX}`);
    for (const rloc of sources) {
      const rel = rloc.slice(prefix.length);
      writeAssembled(join(dest, rel), readFileSync(rlocation(rloc)), rel, this.substitutions);
    }
  }

  /** The output base of the inner workspace (`bazel info output_base`). */
  async outputBase(): Promise<string> {
    const result = await this.run(["info", "output_base"], { flags: false });
    return result.stdout.trim();
  }

  /**
   * Runs the inner Bazel: `bazel <startup> <command> <harness flags> <rest>`.
   * The harness flags are left out for commands that take none (`shutdown`,
   * `info` when asked).
   */
  async run(args: string[], { flags = true }: { flags?: boolean } = {}): Promise<InnerResult> {
    const [command, ...rest] = args;
    const takesFlags = flags && !["shutdown", "version"].includes(command);
    const argv = [rlocation(readInputs().bazel), ...this.startup, command, ...(takesFlags ? this.flags : []), ...rest];
    const child = Bun.spawn(argv, { cwd: this.dir, env: this.env, stdin: "ignore", stdout: "pipe", stderr: "pipe" });
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(child.stdout).text(),
      new Response(child.stderr).text(),
      child.exited,
    ]);
    return { exitCode, stdout, stderr };
  }

  /** Writes a file of the inner workspace. */
  write(path: string, text: string | Uint8Array) {
    mkdirSync(dirname(join(this.dir, path)), { recursive: true });
    writeFileSync(join(this.dir, path), text);
  }

  get log(): LogEntry[] {
    return this.registry.log;
  }

  /** Stops the inner Bazel server and the loopback server. */
  async close() {
    await this.run(["shutdown"]);
    this.registry.stop();
  }
}

function fileUrl(path: string): string {
  const slashed = path.split("\\").join("/");
  return slashed.startsWith("/") ? `file://${slashed}` : `file:///${slashed}`;
}

export interface RunInnerResult extends InnerResult {
  log: LogEntry[];
  outputBase: string;
  repositoryCacheWasEmpty: boolean;
}

/** Runs one inner Bazel command on a fresh inner workspace and stops its server. */
export async function runInner(workspace: string, args: string[], options: InnerOptions = {}): Promise<RunInnerResult> {
  const inner = new Inner(workspace, options);
  try {
    const result = await inner.run(args);
    const outputBase = (await inner.run(["info", "output_base"], { flags: false })).stdout.trim();
    return { ...result, log: inner.log, outputBase, repositoryCacheWasEmpty: inner.repositoryCacheWasEmpty };
  } finally {
    await inner.close();
  }
}

/** Fails naming every request the loopback server answered as unknown. */
export function assertOffline(log: LogEntry[]) {
  const unknown = log.filter((e) => e.unknown).map((e) => `${e.method} ${e.path}`);
  if (unknown.length > 0) {
    throw new Error(`the inner build requested paths the loopback server does not serve:\n${unknown.join("\n")}`);
  }
}
