// The differential conformance test of feature 006 (FR-007–FR-012, research R6–R9): for every
// project, the pinned Bun's isolated install of the committed bun.lock is the oracle, and the
// ruleset's resolution of the same lockfile, for the host's platform class (FR-010), must link the
// same graph.
//
// Exclusions are exactly the spec's Intentional Differences (FR-011):
//   ID-1 No lifecycle scripts: the oracle installs with --ignore-scripts.
//   ID-2 Selection by target platform: only the ruleset's class of the host is compared.
//   ID-3 No hoisting: node_modules/.bun/node_modules is not read (graph.ts, readBunGraph).
//   ID-4 Unfetched entries fail analysis: only that status is skipped (graph.ts, compare); the
//        entry's links are compared.
//   ID-12 Names that become one target name: the evaluation failure the ruleset side records as
//        `target_names` (fixture_results.bzl, npm_extension.bzl link_targets) is skipped; the
//        project's links are compared.
//
// RULES_BUN_CONFORMANCE_RED=1 redirects one edge of `workspace`'s ruleset graph (FR-011, red mode).
//
// Run by Bun 1.4.2 (conformance_1_4_2_test, --platforms=//bun/tests/npm/conformance:host_bun_1_4_2;
// US5, research R10), the oracle is Bun 1.4.2 and the projects are the lockfiles Bun 1.4.2 wrote
// for the corpus (bun_1_4_2/) and those of accepted/, which neither oracle's write_lockfiles.ts run
// wrote; since conformance_test asserts the ruleset links them as Bun 1.4.4 does, a difference
// there is a disagreement of the two Bun versions.

import { afterAll, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { rlocation, rlocationList } from "../../support/spawn.ts";
import { writeArchives } from "../scale/generate.ts";
import { classFor, compare, type Graph, hostTuple, readBunGraph } from "./graph.ts";
import { NOT_APPLICABLE_1_4_2 } from "./not_applicable_1_4_2.ts";
import { installWithBun } from "./oracle.ts";

// The oracle is the test's own Bun: 1.4.4, the pinned one, or 1.4.2, the second oracle (US5).
if (Bun.version !== "1.4.4" && Bun.version !== "1.4.2") throw new Error(`the conformance oracle must be Bun 1.4.4 or 1.4.2, not ${Bun.version}`);
const MODE_1_4_2 = Bun.version === "1.4.2";

const MAIN = "_main";

// Where the projects are (research R9), as repository-relative directories.
const FIXTURES = "bun/tests/npm/fixtures";
const SCALE = "bun/tests/npm/scale";
// The scale fixture's platform variant (T100), whose archives generate.ts writes with `platform`.
const SCALE_PLATFORM = `${SCALE}/platform`;
const INTEGRATION = "bun/tests/integration/workspaces";
const BUN_1_4_2 = "bun/tests/npm/conformance/bun_1_4_2";
// Lockfiles Bun installs that write_lockfiles.ts does not write with the pinned Bun (T107, T110,
// T150, T155).
const ACCEPTED = "bun/tests/npm/conformance/accepted";
const REFUSED = "bun/tests/npm/conformance/refused";
const ARCHIVES = `${MAIN}/bun/tests/npm/registry/archives`;
// The consumer module's project (T113). `e2e` is no package of the root module, so the
// npm_fixture_results extension copies its bun.lock and package.json; the oracle serves it the
// archives of fixtures/jsx, which fetch_react.ts took from the registry for the same three package
// versions and integrities.
const E2E = "e2e/smoke";
const E2E_ARCHIVES = `${MAIN}/bun/tests/npm/fixtures/jsx/archives`;

// Projects the oracle cannot install, each with the reason (research R9): only a project whose
// lockfile Bun refuses to load. The ruleset must refuse each as well (spec Edge Cases, FR-004).
export const NOT_APPLICABLE: Record<string, string> = {
  [`${REFUSED}/patch_path`]: 'its patchedDependencies value is not a string, which Bun\'s loader refuses ("Expected a string", bun.lock.rs L1910); written by hand, as no Bun writes it',
  [`${REFUSED}/lockfile_version_0_member`]: 'its lockfileVersion 0 lists a workspace member that no packages row holds, which Bun\'s loader refuses ("Failed to resolve root workspace dependency \'m\'", bun.lock.rs L2843): on lockfileVersion 0 a member is a package only through its row (L2263); written by hand, as the pinned Bun writes lockfileVersion 1 to 3 only',
};

// What a frozen install prints when Bun's text-lockfile loader refuses bun.lock
// (`report_lockfile_load_error`, src/install/PackageManager/install_with_manager.rs L1685–L1704 @
// bun-v1.4.4: "failed to {parse} lockfile: '{path}'"); a missing archive, a registry error or a
// port conflict fails the install with another message.
const LOADER_REFUSAL = "failed to parse lockfile: 'bun.lock'";

// Tarballs a project's lockfile names at another URL than the registry's own, served as the
// integration test that owns the project serves them (bun/tests/integration/multi.test.ts).
const EXTRA_FILES: Record<string, Record<string, string>> = {
  "bun/tests/integration/workspaces/multi_integrity/two": { "/variant/b/-/b-1.0.0.tgz": `${ARCHIVES}/b@1.0.0+variant.tgz` },
  "bun/tests/integration/workspaces/multi_source/two": { "/mirror/b/-/b-1.0.0.tgz": `${ARCHIVES}/b@1.0.0.tgz` },
};

// The red mode's project: one without a Behavior Change, so its red is not a BC difference.
const RED_PROJECT = "bun/tests/npm/fixtures/workspace";

type RulesetSide =
  | { classes: { platforms: [string | null, string | null, string | null][]; graph: Graph }[]; target_names?: string }
  | { error: string };

function repoMapping(apparent: string): string {
  // The runfiles repository mapping (bazel.build/extending/rules#runfiles_location): lines of
  // `<source canonical>,<target apparent>,<target canonical>`; the main repository's source is "".
  for (const line of readFileSync(rlocation("_repo_mapping"), "utf8").split("\n")) {
    const [source, target, canonical] = line.split(",");
    if (source === "" && target === apparent) return canonical;
  }
  throw new Error(`the runfiles repository mapping names no ${apparent}`);
}

const RESULTS_REPO = repoMapping("npm_fixture_results");
const graphs = JSON.parse(readFileSync(rlocation(`${RESULTS_REPO}/graphs.json`), "utf8")) as Record<string, RulesetSide>;

/** A project's directory in the runfiles. */
const projectDir = (project: string) => (project === E2E ? `${RESULTS_REPO}/${E2E}` : `${MAIN}/${project}`);

/** The projects the runfiles hold: directories with a bun.lock (research R9). */
function projectsInRunfiles(): string[] {
  const found = new Set<string>();
  const lockfiles = (base: string) =>
    rlocationList(`${MAIN}/${base}`)
      .filter((path) => path.endsWith("/bun.lock"))
      .map((path) => path.slice(MAIN.length + 1, -"/bun.lock".length));
  for (const base of [FIXTURES, BUN_1_4_2, ACCEPTED, REFUSED]) {
    let listed: string[] = [];
    try {
      listed = lockfiles(base);
    } catch {
      // bun_1_4_2, accepted or refused may hold no project yet.
    }
    for (const dir of listed) if (dir.split("/").length === base.split("/").length + 1) found.add(dir);
  }
  const scale = rlocationList(`${MAIN}/${SCALE}`);
  for (const dir of [SCALE, SCALE_PLATFORM]) if (scale.includes(`${MAIN}/${dir}/bun.lock`)) found.add(dir);
  for (const dir of lockfiles(INTEGRATION)) found.add(dir);
  if (rlocationList(`${RESULTS_REPO}/${E2E}`).includes(`${RESULTS_REPO}/${E2E}/bun.lock`)) found.add(E2E);
  return [...found].sort();
}

/** The archives the loopback registry serves for a project. */
function archivesFor(project: string, scaleDir: (platform: boolean) => string): string[] {
  if (project === E2E) return rlocationList(E2E_ARCHIVES).filter((path) => path.endsWith(".tgz")).map((path) => rlocation(path));
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
  // The two scale variants write different archives under the same names, so each has its own directory.
  if (project === SCALE || project === SCALE_PLATFORM) return [...paths, ...writeArchives(scaleDir(project === SCALE_PLATFORM), project === SCALE_PLATFORM)];
  return paths;
}

function redirectOneEdge(graph: Graph): string {
  // The first link of the root, by name, to the first entry of another name@version.
  const [name, target] = Object.entries(graph.holders[""]).sort(([a], [b]) => (a < b ? -1 : 1))[0];
  const current = graph.entries[Number(target.slice(2))];
  const other = graph.entries.findIndex((e) => `${e.name}@${e.version}` !== `${current.name}@${current.version}`);
  graph.holders[""][name] = `e:${other}`;
  return `the root's "${name}" redirected to ${graph.entries[other].name}@${graph.entries[other].version}`;
}

// The 1.4.2 run compares only the lockfiles Bun 1.4.2 wrote for the corpus, and those of accepted/.
const inRun = (project: string) => !MODE_1_4_2 || project.startsWith(`${BUN_1_4_2}/`) || project.startsWith(`${ACCEPTED}/`);
const projects = projectsInRunfiles().filter(inRun);
const notApplicable: Record<string, string> = MODE_1_4_2
  ? Object.fromEntries(Object.entries(NOT_APPLICABLE_1_4_2).map(([name, reason]) => [`${BUN_1_4_2}/${name}`, reason]))
  : NOT_APPLICABLE;
const host = hostTuple();
const compared: string[] = [];
const differences: string[] = [];
// Projects whose evaluation fails only by ID-12, with the error.
const targetNames: string[] = [];
const scaleDir = (platform: boolean) => join(process.env.TEST_TMPDIR!, platform ? "scale-platform-archives" : "scale-archives");

test("every project is on both sides (FR-009, US2-4)", () => {
  expect(Object.keys(graphs).filter(inRun).sort()).toEqual(projects);
  // A project 1.4.2 cannot write has no lockfile; any other not-applicable project is asserted below.
  if (!MODE_1_4_2) for (const project of Object.keys(NOT_APPLICABLE)) expect(projects).toContain(project);
});

test("every corpus project has a Bun 1.4.2 lockfile or a reason (US5-2, FR-013)", () => {
  // Every project, whichever Bun runs the test.
  const all = projectsInRunfiles();
  const corpus = all.filter((p) => p.startsWith(`${FIXTURES}/conformance_`)).map((p) => p.slice(FIXTURES.length + 1));
  const written = all.filter((p) => p.startsWith(`${BUN_1_4_2}/`)).map((p) => p.slice(BUN_1_4_2.length + 1));
  const problems: string[] = [];
  for (const name of corpus) {
    const listed = name in NOT_APPLICABLE_1_4_2;
    if (written.includes(name) && listed) problems.push(`${name}: has a Bun 1.4.2 lockfile and is listed as not applicable to Bun 1.4.2`);
    if (!written.includes(name) && !listed) {
      problems.push(`${name}: has no Bun 1.4.2 lockfile under ${BUN_1_4_2}/ and is not listed in NOT_APPLICABLE_1_4_2; run write_lockfiles.ts --bun-1-4-2 ${name} with Bun 1.4.2`);
    }
  }
  for (const name of [...written, ...Object.keys(NOT_APPLICABLE_1_4_2)]) {
    if (!corpus.includes(name)) problems.push(`${name}: is no corpus project under ${FIXTURES}/`);
  }
  expect(problems).toEqual([]);
});

test("every refused lockfile is not applicable (T099)", () => {
  for (const project of projectsInRunfiles().filter((p) => p.startsWith(`${REFUSED}/`))) expect(Object.keys(NOT_APPLICABLE)).toContain(project);
});

for (const project of projects) {
  test(
    project,
    async () => {
      if (project in notApplicable) {
        // Asserted, not skipped: the oracle's loader must still refuse it, and so must the
        // ruleset, which never links a graph for a lockfile Bun does not install (spec Edge
        // Cases), with an error naming the bun.lock label as every refusal of its reader does.
        await expect(installWithBun(projectDir(project), archivesFor(project, scaleDir))).rejects.toThrow(LOADER_REFUSAL);
        const side = graphs[project];
        const refused = "error" in side && side.error.startsWith(`${project}/bun.lock: `);
        if (!refused) differences.push(`${project}: Bun refuses the lockfile, the ruleset ${"error" in side ? `fails without naming ${project}/bun.lock (${side.error})` : "links it"}`);
        expect(refused, `${project}: the ruleset must refuse the lockfile naming ${project}/bun.lock`).toBe(true);
        return;
      }
      const files = Object.fromEntries(Object.entries(EXTRA_FILES[project] ?? {}).map(([url, path]) => [url, rlocation(path)]));
      const installed = await installWithBun(projectDir(project), archivesFor(project, scaleDir), { files });
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
        if (side.target_names !== undefined) targetNames.push(`${project}: ${side.target_names}`);
      }
      if (MODE_1_4_2 && difference !== undefined) {
        difference = `${project}: Bun 1.4.2 links this lockfile differently from Bun 1.4.4, which the ruleset follows (${difference.slice(project.length + 2)}); the ruleset cannot follow both (constitution V)`;
      }
      compared.push(project);
      if (difference !== undefined) differences.push(difference);
      expect(difference).toBeUndefined();
    },
    600_000,
  );
}

afterAll(() => {
  console.log(`oracle: Bun ${Bun.version}`);
  console.log(`host platform: ${JSON.stringify(host)}`);
  console.log(`compared ${compared.length} projects:\n  ${compared.join("\n  ")}`);
  console.log(`not applicable:\n${Object.entries(notApplicable).map(([p, r]) => `  ${p}: ${r}`).join("\n")}`);
  console.log(
    "excluded by name: ID-1 (no lifecycle scripts), ID-2 (selection by target platform), ID-3 (no hoisting), ID-4 (unfetched entries fail analysis), ID-12 (names that become one target name)",
  );
  console.log(`ID-12, links compared:${targetNames.length ? `\n  ${targetNames.join("\n  ")}` : " none"}`);
  console.log(`${differences.length} differences${differences.length ? `:\n  ${differences.join("\n  ")}` : ""}`);
});
