// The oracle of the conformance test (research R6): the pinned Bun's isolated install of a
// project's committed bun.lock, offline, against the loopback registry. Bun is the test's own
// runtime (`process.execPath`), the registered target toolchain's Bun (constitution III).

import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { FIXTURE_PORT, startRegistry } from "../../support/npm_registry.ts";
import { rlocation, rlocationList } from "../../support/spawn.ts";

export interface InstallResult {
  /** The directory Bun installed in. */
  dir: string;
  /** The workspace paths of the lockfile (`""` for the root). */
  workspaces: string[];
}

// The fixture writers' placeholder for the loopback registry's URL (bun/tests/integration).
const REGISTRY_PLACEHOLDER = "{REGISTRY}";

/** Copies the project at rlocation path `project` from the runfiles (as a manifest or a directory
 * lists them), every file but `BUILD.bazel` and `node_modules`, and fills in the registry URL. */
function copyProject(project: string, to: string, registryUrl: string) {
  for (const path of rlocationList(project)) {
    const relative = path.slice(project.length + 1);
    const parts = relative.split("/");
    if (parts[parts.length - 1] === "BUILD.bazel" || parts.includes("node_modules")) continue;
    const target = join(to, ...parts);
    mkdirSync(dirname(target), { recursive: true });
    const name = parts[parts.length - 1];
    if (name === "bun.lock" || name === "package.json") {
      writeFileSync(target, readFileSync(rlocation(path), "utf8").replaceAll(REGISTRY_PLACEHOLDER, registryUrl));
    } else {
      copyFileSync(rlocation(path), target);
    }
  }
}

/**
 * Copies the project at rlocation path `project` (every file but `BUILD.bazel` and `node_modules`)
 * under TEST_TMPDIR and runs
 * `bun install --frozen-lockfile --ignore-scripts --linker isolated` there with an empty cache,
 * the loopback registry serving `archives` (and `files`, URL path → file) on the port the fixture
 * lockfiles name. Throws with
 * Bun's output when the install fails.
 */
export async function installWithBun(
  project: string,
  archives: string[],
  options: { bun?: string; files?: Record<string, string> } = {},
): Promise<InstallResult> {
  const registry = startRegistry({ archives, files: options.files, port: FIXTURE_PORT });
  try {
    const work = mkdtempSync(join(process.env.TEST_TMPDIR!, "oracle-"));
    const dir = join(work, basename(project));
    copyProject(project, dir, registry.url);
    const cache = join(work, "cache");
    mkdirSync(cache);
    const args = ["install", "--frozen-lockfile", "--ignore-scripts", "--linker", "isolated", `--registry=${registry.url}`];
    const child = Bun.spawn([options.bun ?? process.execPath, ...args], {
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
    if (exitCode !== 0) throw new Error(`bun ${args.join(" ")} failed in ${project} with exit ${exitCode}:\n${stdout}${stderr}`);
    const lock = Bun.JSONC.parse(readFileSync(join(dir, "bun.lock"), "utf8")) as { workspaces?: Record<string, unknown> };
    return { dir, workspaces: Object.keys(lock.workspaces ?? { "": {} }).sort() };
  } finally {
    registry.stop();
  }
}
