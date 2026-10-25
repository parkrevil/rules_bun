// Scale (FR-037, SC-010, research G8): the 2,000-package fixture through the
// npm extension, the package layout and the launcher. The archives are
// regenerated under TEST_TMPDIR with bun/tests/npm/scale/generate.ts, so the
// inner build's integrity check is also the check that the generator is
// deterministic (tasks.md decision 8). Every value is printed; the plan's
// bounds are asserted on Linux.

import { afterAll, expect, test } from "bun:test";
import { lstatSync, readdirSync, readFileSync, realpathSync } from "node:fs";
import { join, normalize, sep } from "node:path";
import { packageName, scalePackages, WIDTH, writeArchives } from "../npm/scale/generate.ts";
import { rlocation } from "../support/spawn.ts";
import { assertOffline, Inner } from "./support/inner.ts";

// Research G8.
const MAX_EVALUATION_MS = 10_000;
const MAX_LAUNCH_OVERHEAD_MS = 2_000;
const RUNS = 5;

const packages = scalePackages();
const P = packages.length;
const E = packages.reduce((n, p) => n + p.dependencies.length, 0);
const L = WIDTH;

const inner = new Inner("scale", { npmArchives: writeArchives(join(process.env.TEST_TMPDIR!, "scale-archives")) });
afterAll(() => inner.close());

const BASE = readFileSync(join(inner.dir, "MODULE.bazel"), "utf8");
const TAG = 'npm = use_extension("@rules_bun//bun:extensions.bzl", "npm")\nnpm.translate_lock(name = "npm_scale", bun_lock = "//:bun.lock")\nuse_repo(npm, "npm_scale")\n';
const DEPS = Array.from({ length: WIDTH }, (_, k) => `        ":node_modules/${packageName(0, k)}",`).join("\n");
const BUILD = `load("@npm_scale//:defs.bzl", "npm_link_all_packages")
load("@rules_bun//bun:defs.bzl", "bun_binary")

npm_link_all_packages()

bun_binary(
    name = "scale",
    entry_point = "elapsed.ts",
    deps = [
${DEPS}
    ],
)

bun_binary(
    name = "baseline",
    entry_point = "elapsed.ts",
)
`;

const median = (values: number[]) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];

async function bazel(args: string[]) {
  const result = await inner.run(args);
  if (result.exitCode !== 0) throw new Error(`bazel ${args.join(" ")} failed:\n${result.stderr}`);
  return result;
}

async function timed(args: string[]): Promise<number> {
  const start = performance.now();
  await bazel(args);
  return performance.now() - start;
}

// `bazel mod deps` wall time on a fresh server, so that the extension, whose
// result the lockfile does not hold (it is reproducible), is evaluated again.
async function modDeps(module: string): Promise<number> {
  inner.write("MODULE.bazel", module);
  await inner.run(["shutdown"]);
  return timed(["mod", "deps"]);
}

function actionCount(stdout: string): number {
  return (JSON.parse(stdout).actions ?? []).length;
}

// Milliseconds from the launcher's start to the program's first line.
async function launch(name: string): Promise<number> {
  const stamp = join(inner.root, `${name}.stamp`);
  // Not the outer test's runfiles and protocol variables, as Inner leaves them out.
  const env: Record<string, string> = { RULES_BUN_LAUNCH_TIMESTAMP: stamp };
  for (const [key, value] of Object.entries(process.env)) {
    if (value !== undefined && !/^(TEST_|TESTBRIDGE_|XML_OUTPUT_FILE|COVERAGE|RUNFILES_|JAVA_RUNFILES|RULES_BUN_)/.test(key)) env[key] = value;
  }
  const child = Bun.spawn([join(inner.dir, "bazel-bin", name)], { cwd: inner.dir, env, stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, exitCode] = await Promise.all([new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited]);
  if (exitCode !== 0) throw new Error(`${name} exited ${exitCode}:\n${stderr}`);
  return Number(stdout.trim());
}

// The length of the load guard's pattern for the target, computed by the
// launcher's own functions (bun/private/launcher.js, from escapeRegExp up to
// registerGuard) on the declared set the launcher builds (declaredSet).
function guardPatternLength(name: string): number {
  const source = readFileSync(join(inner.root, "m", "bun", "private", "launcher.js"), "utf8");
  const start = source.indexOf("function escapeRegExp(");
  const end = source.indexOf("function registerGuard(");
  if (start === -1 || end === -1) throw new Error("launcher.js no longer defines escapeRegExp before registerGuard");
  const guardPattern = new Function(`${source.slice(start, end)}\nreturn guardPattern;`)();
  const runfiles = join(inner.dir, "bazel-bin", `${name}.runfiles`);
  const config = JSON.parse(readFileSync(join(inner.dir, "bazel-bin", `${name}.launch.json`), "utf8"));
  const real = (path: string) => realpathSync(join(runfiles, path));
  const paths = config.copies.map(([copy]: [string]) => real(copy));
  const root = real(config.entry_point).slice(0, -(sep + normalize(config.entry_point_tree)).length);
  const prefixes = (config.directories ?? []).map((d: string) => root + sep + d.split("/").join(sep) + sep);
  return guardPattern(paths, prefixes).length;
}

// Bytes of the regular files under the target's store, and of those not
// hardlinked (written by the copy rather than linked).
function storeBytes(name: string): { total: number; unlinked: number } {
  let total = 0;
  let unlinked = 0;
  const visit = (dir: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      if (entry.isDirectory()) visit(path);
      else if (entry.isFile()) {
        const stat = lstatSync(path);
        total += stat.size;
        if (stat.nlink === 1) unlinked += stat.size;
      }
    }
  };
  visit(join(inner.dir, "bazel-bin", `${name}.bun`, ".store"));
  return { total, unlinked };
}

test(
  "the 2,000-package fixture stays within the plan's bounds",
  async () => {
    const lock = readFileSync(rlocation("_main/bun/tests/npm/scale/bun.lock"), "utf8");
    inner.write("bun.lock", lock.replaceAll(/http:\/\/127\.0\.0\.1:\d+/g, inner.registry.url));
    inner.write("package.json", readFileSync(rlocation("_main/bun/tests/npm/scale/package.json")));
    inner.write("BUILD.bazel", 'load("@rules_bun//bun:defs.bzl", "bun_binary")\n\nbun_binary(\n    name = "baseline",\n    entry_point = "elapsed.ts",\n)\n');

    await modDeps(BASE); // the first server start and module resolution
    const without: number[] = [];
    const withTag: number[] = [];
    for (let i = 0; i < 3; i++) {
      without.push(await modDeps(BASE));
      withTag.push(await modDeps(BASE + "\n" + TAG));
    }
    const evaluation = median(withTag) - median(without);

    inner.write("BUILD.bazel", BUILD);
    const scaleActions = actionCount((await bazel(["aquery", "--output=jsonproto", "//:scale"])).stdout);
    const A = actionCount((await bazel(["aquery", "--output=jsonproto", "//:baseline"])).stdout);
    await bazel(["build", "//:baseline"]);
    const copyWall = await timed(["build", "//:scale"]);
    const bytes = storeBytes("scale");

    const scaleLaunch: number[] = [];
    const baselineLaunch: number[] = [];
    for (let i = 0; i < RUNS; i++) {
      scaleLaunch.push(await launch("scale"));
      baselineLaunch.push(await launch("baseline"));
    }
    const overhead = median(scaleLaunch) - median(baselineLaunch);
    const patternLength = guardPatternLength("scale");

    console.log(
      [
        `packages P = ${P}, edges E = ${E}, direct links L = ${L}`,
        `extension evaluation: ${evaluation.toFixed(0)} ms (bazel mod deps median with the tag ${median(withTag).toFixed(0)} ms [${withTag.map((t) => t.toFixed(0)).join(", ")}], without ${median(without).toFixed(0)} ms [${without.map((t) => t.toFixed(0)).join(", ")}])`,
        `actions of //:scale: ${scaleActions}; P + E + L + A = ${P + E + L + A} (A = ${A}, the actions of //:baseline)`,
        `bazel build //:scale after analysis (the store copies and links): ${copyWall.toFixed(0)} ms; store files ${bytes.total} bytes, ${bytes.unlinked} of them not hardlinked`,
        `launcher start: //:scale median ${median(scaleLaunch)} ms [${scaleLaunch.join(", ")}], //:baseline median ${median(baselineLaunch)} ms [${baselineLaunch.join(", ")}], overhead ${overhead} ms`,
        `guard pattern length of //:scale: ${patternLength} characters`,
      ].join("\n"),
    );

    expect(scaleActions).toBe(P + E + L + A);
    if (process.platform === "linux") {
      expect(evaluation).toBeLessThanOrEqual(MAX_EVALUATION_MS);
      expect(overhead).toBeLessThanOrEqual(MAX_LAUNCH_OVERHEAD_MS);
    }
    assertOffline(inner.log);
  },
  60 * 60 * 1000,
);
