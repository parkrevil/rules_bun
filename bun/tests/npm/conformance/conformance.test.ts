// The differential conformance test of feature 006 (FR-007–FR-012, research R6–R9): for every
// project, the pinned Bun's isolated install of the committed bun.lock is the oracle, and the
// ruleset's resolution of the same lockfile, for the host's platform class (FR-010), must link the
// same graph.
//
// Exclusions are exactly the spec's Intentional Differences (FR-011):
//   ID-1 No lifecycle scripts: the oracle installs with --ignore-scripts.
//   ID-2 Selection by target platform: only the ruleset's class of the host is compared.
//   ID-3 No hoisting: node_modules/.bun/node_modules is not read (graph.ts, readBunGraph).
//
// RULES_BUN_CONFORMANCE_RED=1 redirects one edge of `workspace`'s ruleset graph (FR-011, red mode).

import { afterAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { rlocation, rlocationList } from "../../support/spawn.ts";
import { writeArchives } from "../scale/generate.ts";
import { classFor, compare, type Graph, hostTuple, readBunGraph } from "./graph.ts";
import { installWithBun } from "./oracle.ts";

const MAIN = "_main";

// Where the projects are (research R9), as repository-relative directories.
const FIXTURES = "bun/tests/npm/fixtures";
const SCALE = "bun/tests/npm/scale";
const INTEGRATION = "bun/tests/integration/workspaces";
const BUN_1_4_2 = "bun/tests/npm/conformance/bun_1_4_2";
const ARCHIVES = `${MAIN}/bun/tests/npm/registry/archives`;

// Projects the oracle cannot install, each with the reason (research R9): only a project whose
// package.json disagrees with its lockfile on purpose, or whose lockfile Bun refuses to load.
export const NOT_APPLICABLE: Record<string, string> = {
  "bun/tests/integration/workspaces/stale_link":
    "its bun.lock is a template whose {PHANTOM_INFO} stale_link.test.ts fills in, so Bun cannot load it as written",
};

// Tarballs a project's lockfile names at another URL than the registry's own, served as the
// integration test that owns the project serves them (bun/tests/integration/multi.test.ts).
const EXTRA_FILES: Record<string, Record<string, string>> = {
  "bun/tests/integration/workspaces/multi_integrity/two": { "/variant/b/-/b-1.0.0.tgz": `${ARCHIVES}/b@1.0.0+variant.tgz` },
  "bun/tests/integration/workspaces/multi_source/two": { "/mirror/b/-/b-1.0.0.tgz": `${ARCHIVES}/b@1.0.0.tgz` },
};

// The red mode's project: one without a Behavior Change, so its red is not a BC difference.
const RED_PROJECT = "bun/tests/npm/fixtures/workspace";

type RulesetSide = { classes: { platforms: [string | null, string | null, string | null][]; graph: Graph }[] } | { error: string };

function repoMapping(apparent: string): string {
  // The runfiles repository mapping (bazel.build/extending/rules#runfiles_location): lines of
  // `<source canonical>,<target apparent>,<target canonical>`; the main repository's source is "".
  for (const line of readFileSync(rlocation("_repo_mapping"), "utf8").split("\n")) {
    const [source, target, canonical] = line.split(",");
    if (source === "" && target === apparent) return canonical;
  }
  throw new Error(`the runfiles repository mapping names no ${apparent}`);
}

const graphs = JSON.parse(readFileSync(rlocation(`${repoMapping("npm_fixture_results")}/graphs.json`), "utf8")) as Record<string, RulesetSide>;

/** The projects the runfiles hold: directories with a bun.lock (research R9). */
function projectsInRunfiles(): string[] {
  const found = new Set<string>();
  const lockfiles = (base: string) =>
    rlocationList(`${MAIN}/${base}`)
      .filter((path) => path.endsWith("/bun.lock"))
      .map((path) => path.slice(MAIN.length + 1, -"/bun.lock".length));
  for (const base of [FIXTURES, BUN_1_4_2]) {
    let listed: string[] = [];
    try {
      listed = lockfiles(base);
    } catch {
      // bun_1_4_2 may hold no project yet.
    }
    for (const dir of listed) if (dir.split("/").length === base.split("/").length + 1) found.add(dir);
  }
  if (rlocationList(`${MAIN}/${SCALE}`).includes(`${MAIN}/${SCALE}/bun.lock`)) found.add(SCALE);
  for (const dir of lockfiles(INTEGRATION)) found.add(dir);
  return [...found].sort();
}

/** The archives the loopback registry serves for a project. */
function archivesFor(project: string, scaleDir: () => string): string[] {
  const fixture = rlocationList(ARCHIVES)
    .filter((path) => path.endsWith(".tgz"))
    // A variant archive (`<store name>+<variant>`, pack.ts) is a second archive of a version.
    .filter((path) => !path.slice(path.lastIndexOf("@")).slice(0, -".tgz".length).includes("+"));
  const names = new Set(fixture.map((path) => path.slice(path.lastIndexOf("/") + 1)));
  // A project's own archives (for example fixtures/jsx/archives), unless the fixture set has one.
  const own = rlocationList(`${MAIN}/${project}`)
    .filter((path) => path.endsWith(".tgz") && path.includes("/archives/"))
    .filter((path) => !names.has(path.slice(path.lastIndexOf("/") + 1)));
  const paths = [...fixture, ...own].map((path) => rlocation(path));
  return project === SCALE ? [...paths, ...writeArchives(scaleDir())] : paths;
}

function redirectOneEdge(graph: Graph): string {
  // The first link of the root, by name, to the first entry of another name@version.
  const [name, target] = Object.entries(graph.holders[""]).sort(([a], [b]) => (a < b ? -1 : 1))[0];
  const current = graph.entries[Number(target.slice(2))];
  const other = graph.entries.findIndex((e) => `${e.name}@${e.version}` !== `${current.name}@${current.version}`);
  graph.holders[""][name] = `e:${other}`;
  return `the root's "${name}" redirected to ${graph.entries[other].name}@${graph.entries[other].version}`;
}

const projects = projectsInRunfiles();
const host = hostTuple();
const compared: string[] = [];
const differences: string[] = [];
let scaleArchives: string | undefined;
const scaleDir = () => (scaleArchives ??= join(process.env.TEST_TMPDIR!, "scale-archives"));

test("every project is on both sides (FR-009, US2-4)", () => {
  expect(Object.keys(graphs).sort()).toEqual(projects);
  for (const project of Object.keys(NOT_APPLICABLE)) expect(projects).toContain(project);
});

for (const project of projects) {
  test(
    project,
    async () => {
      if (project in NOT_APPLICABLE) {
        // Asserted, not skipped: the oracle must still refuse it.
        await expect(installWithBun(`${MAIN}/${project}`, archivesFor(project, scaleDir))).rejects.toThrow();
        return;
      }
      const files = Object.fromEntries(Object.entries(EXTRA_FILES[project] ?? {}).map(([url, path]) => [url, rlocation(path)]));
      const installed = await installWithBun(`${MAIN}/${project}`, archivesFor(project, scaleDir), { files });
      const bun = readBunGraph(installed.dir, installed.workspaces);
      const side = graphs[project];
      let difference: string | undefined;
      if ("error" in side) {
        difference = `${project}: the ruleset fails (${side.error}), Bun installs the lockfile`;
      } else {
        const ruleset = structuredClone(classFor(host, side.classes).graph);
        if (process.env.RULES_BUN_CONFORMANCE_RED && project === RED_PROJECT) {
          console.log(`red mode: ${redirectOneEdge(ruleset)}`);
        }
        difference = compare(project, ruleset, bun);
      }
      compared.push(project);
      if (difference !== undefined) differences.push(difference);
      expect(difference).toBeUndefined();
    },
    600_000,
  );
}

afterAll(() => {
  console.log(`host platform: ${JSON.stringify(host)}`);
  console.log(`compared ${compared.length} projects:\n  ${compared.join("\n  ")}`);
  console.log(`not applicable:\n${Object.entries(NOT_APPLICABLE).map(([p, r]) => `  ${p}: ${r}`).join("\n")}`);
  console.log("excluded by name: ID-1 (no lifecycle scripts), ID-2 (selection by target platform), ID-3 (no hoisting)");
  console.log(`${differences.length} differences${differences.length ? `:\n  ${differences.join("\n  ")}` : ""}`);
});
