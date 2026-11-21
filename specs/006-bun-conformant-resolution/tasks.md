---

description: "Task list for feature 006: link what the pinned Bun links, by construction and by test"
---

# Tasks: Link What the Pinned Bun Links, by Construction and by Test

**Input**: Design documents from `specs/006-bun-conformant-resolution/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/public-api.md,
contracts/conformance-graph.md, quickstart.md

**Tests**: required. The plan's constraint "test-first: each BC recorded as a conformance difference
before the fix" and SC-003: the conformance test, the corpus and the canaries exist and are seen
failing (or, for canaries, seen failing in red mode) before the resolver changes; every new
Starlark module has its unit tests written and seen failing first.

**Organization**: Tasks are grouped by user story (spec US1–US5) in the plan's implementation order:
US2 (the conformance test, run on `main`'s resolver), US4 (canaries for every field the carry-over
will read), US1 (the carry-over), US3 (traceability), US5 (Bun 1.4.2). Paths are relative to the
repository root.

**Conventions used in every task**:

- Work and commit on branch `006-bun-conformant-resolution` (from `main` at `c485a75`). One PR at
  the end (T066).
- `B` is the development toolchain's Bun:
  `B="$(bazel info output_base)/external/+bun+bun_linux-x64/bun"`.
- `SRC` is `/tmp/bun006-src/bun-v1.4.4/`, `SRC142` is `/tmp/bun006-src/bun-v1.4.2/` (T004): Bun's
  source at the tag, read only, never built or run.
- "Cite" means: the function's docstring holds the line
  `Bun: <path under oven-sh/bun> L<a>–L<b> @ bun-v1.4.4` (for example
  `Bun: src/install/lockfile/bun.lock.rs L3347–L3543 @ bun-v1.4.4`), one per Bun range it carries
  over, each range re-read in `SRC` before it is written (research Part 1: line numbers are of the
  files at the tag).
- "Carry over" means: the Starlark function has the structure of the cited Bun function (same
  steps, same order, same names where Starlark allows; Bun's ID-indexed arrays stay lists indexed
  by the same IDs, research R1). Nothing is fitted to a fixture's output (P1). Starlark has no
  `while` and no recursion: each Bun loop is a `for` over `range(_LIMIT)` with an explicit stack or
  queue. Exhausting `_LIMIT` (2^30) ends the loop without an error, as `main`'s `resolve.bzl`
  loops do; no evaluation reaches it and no test can (user, 2026-11-21, research Part 6, T087).
- "Record red" / "record green" means: append to `specs/006-bun-conformant-resolution/tdd-log.md`
  one row with the task ID, the test target, the exact command, the platform it ran on, the result
  and a short excerpt of the failure text (red) or the pass line (green). A red that fails for a
  reason other than the one under test (a typo, a missing load) does not count: fix the test and
  re-run.
- Fixture archives are produced only by `bun/tests/npm/registry/pack.ts` and fixture lockfiles only
  by `bun/tests/npm/registry/write_lockfiles.ts`, both run with `$B` (or the 1.4.2 Bun in T058) from
  the repository root. Never edit a `.tgz` or a Bun-written `bun.lock` by hand.
- Downloads go into a new, empty directory under `/tmp/bun006-*`, never next to a script.
- "Stop and report" means: change nothing more for that item and tell the user what was observed.
- A conformance difference that no BC of the spec explains is a new Behavior Change: stop and
  report; after the user approves it, add it to spec "Behavior Changes" and
  `contracts/public-api.md` as the next `BC-n` before anything fixes it (spec: "Any further
  difference the conformance test finds is added here before it is fixed").
- Every diagnostic, `doc =` string, docstring, comment and commit message is in English. Every
  diagnostic this feature adds starts with the `bun.lock` label (`<label>: `) as `lockfile.bzl`'s
  do, and never prints a value the reader has not checked.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US5)

---

## Phase 1: Setup

**Purpose**: Branch, the user's plan-gate answers in the spec, Bun's source at the tags, a green
baseline.

- [X] T001 Confirm `git branch --show-current` prints `006-bun-conformant-resolution`,
  `git merge-base HEAD main` is `c485a75`, and `git status --short` shows only
  `specs/006-bun-conformant-resolution/`; commit that directory as
  `docs: specify feature 006, link what the pinned Bun links`
- [X] T002 Write the plan-gate answers of research Part 6 (user, 2026-10-29) into the spec and
  contracts: in `specs/006-bun-conformant-resolution/spec.md` add **ID-3 No hoisting**
  (`node_modules/.bun/node_modules` and the root `node_modules` fallback are not reproduced; the
  graph is FR-008's) to "Intentional Differences", and **BC-6** (one package per `name@version`,
  bound by Bun's row evidence), **BC-7** (a non-optional dependency whose package's `os`/`cpu`
  exclude the target platform is not carried there) and **BC-8** (the dependencies of an unfetched
  entry, `unsupported_reason`, get instances; no target name changes) to "Behavior Changes"; in
  `contracts/public-api.md` drop "(pending D2)" and add the BC-8 row; in
  `contracts/conformance-graph.md` and `data-model.md` make `ID-3` an unconditional exclusion; in
  `quickstart.md` Q1 list ID-1–ID-3; in `plan.md` make the Summary and Phases say BC-1…BC-8 and
  mark the Open decisions answered. Commit
  as `docs: record the plan-gate answers of feature 006`
- [X] T003 [P] Create `specs/006-bun-conformant-resolution/tdd-log.md` with a title, one paragraph
  stating the test-first rule (plan Constraints, SC-003), and a table with the columns `Task`,
  `Target`, `Command`, `Platform`, `Result`, `Excerpt`
- [X] T004 [P] Fetch Bun's source into new empty directories `/tmp/bun006-src/bun-v1.4.4/` and
  `/tmp/bun006-src/bun-v1.4.2/`: every file of research Part 1 (LOCK, LOCKFILE, TREE, REACH, PRUNED,
  META, ISO, STORE, HOOKS, SEMVER's `Version.rs`, `SemverQuery.rs`, `SemverRange.rs`, `lib.rs`,
  INSTALL) and `test/cli/install/semver.test.ts`, each with
  `curl -fsSL https://raw.githubusercontent.com/oven-sh/bun/<tag>/<path> -o <dir>/<path>`. Confirm
  `wc -l` at `bun-v1.4.4` gives `bun.lock.rs` 3,543, `lockfile.rs` 3,914, `Tree.rs` 2,242,
  `isolated_install.rs` 2,714 (research Part 1); on any difference stop and report
- [X] T005 [P] Baseline: run `bazel test //...` in the root and in `e2e/smoke/`, and
  `bazel test //bun/tests/integration:scale_test --test_output=all`; record each in `tdd-log.md` as
  the baseline, including the evaluation time `scale_test` prints (research R13, "on `main`"). If
  anything fails, stop and report (AGENTS.md: do not widen the task)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The edge-case corpus (research R11) and the ruleset side of the graph (contract
"Ruleset side"), which the conformance test (US2), the canaries (US4), the resolver's unit tests
(US1) and the 1.4.2 run (US5) all read.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T006 [P] Archives for the corpus: for each project of research R11's table, list the packages
  its layout needs; reuse an archive under `bun/tests/npm/registry/archives/` where one fits; add
  each missing package's sources under `bun/tests/npm/registry/packages/<name>@<version>/` (at least
  `opt-user@1.0.0`, research R11, a package whose optional dependency Bun lists under `unresolved`;
  a package depending on a workspace member's name; a package with a non-optional and one with an
  optional peer nothing provides; packages restricted by `os`/`cpu` to another OS) and pack them with
  `$B bun/tests/npm/registry/pack.ts` into `bun/tests/npm/registry/archives/`; add a corpus
  project `conformance_bundled` (a package with `bundleDependencies`) and, if the carry-over reads
  `packageExtensions`, one that uses it, so conformance checks every field the loader reads. Never
  alter a packument to serve an archive (research R11)
- [X] T007 Add the corpus to `projects` in `bun/tests/npm/registry/write_lockfiles.ts`, one entry
  per row of research R11 (`conformance_alias_workspace` with an unscoped `lib` and a scoped
  `@scope/lib` workspace, root aliasing `lib: npm:a@1.0.0` and `@scope/lib: npm:c@1.0.0`;
  `conformance_unresolved` in a package and in a workspace; `conformance_unbound` with an optional
  and a peer dependency without a key, root and workspace; `conformance_registry_to_workspace`;
  `conformance_unprovided_peer` non-optional and optional; `conformance_nested`;
  `conformance_peer_contexts`; `conformance_shared_peer`; `conformance_platform` non-optional and
  optional; `conformance_overrides`; `conformance_catalog`), each with a `check` asserting the
  lockfile form it exists for (for example: the entry's `unresolved` lists the name; a key
  `./lib/<dep>` and a key `./@scope/lib/<dep>` exist; no key exists for the optional or peer
  dependency). Run `$B bun/tests/npm/registry/write_lockfiles.ts <each conformance_ project>` to
  write `bun/tests/npm/fixtures/conformance_<case>/` with a `BUILD.bazel` like the other fixtures'.
  If the pinned Bun cannot produce a layout (its `check` fails), stop and report (depends on T006)
- [X] T008 [P] Write `bun/tests/npm/conformance/graph_test.bzl` (skylib `unittest`) for a function
  `conformance_graphs(resolution, tuples)` in `bun/tests/npm/conformance/graph.bzl`, on hand-built
  `resolve.bzl` outputs of the shape of data-model "Ruleset output": a `closure` link appears for
  every tuple; an `optional` link only for the tuples its `[os, cpu, libc]` requirements match, the
  way `bun/private/npm_repositories.bzl` turns them into `select()` (glibc, musl, and `libc` `null`
  off Linux); instances reached from no holder in a tuple are absent from that tuple's graph; tuples
  with equal graphs are one class; an `error` resolution yields `{"error": <message>}`; the output is
  the contract's Graph JSON (`holders`, `entries`, targets `e:<index>` / `w:<path>`). Register it in
  `bun/tests/npm/conformance/BUILD.bazel`; record red
- [X] T009 Implement `conformance_graphs` in `bun/tests/npm/conformance/graph.bzl`, with the tuples
  of research R3 taken from `bun/private/platforms.bzl` (every `NPM_OS` × `NPM_CPU`, `libc` ∈
  {`glibc`, `musl`, unconstrained} on Linux, none elsewhere); it reads only `resolve.bzl`'s output,
  so it serves `main`'s resolver and the adapter of T047 unchanged; record green (depends on T008)
- [X] T010 Extend `bun/tests/npm/fixture_results.bzl`: enumerate the projects of research R9
  (every directory under `bun/tests/npm/fixtures/` with a `bun.lock`, `bun/tests/npm/scale/`, every
  `bun.lock` under `bun/tests/integration/workspaces/`, and every directory under
  `bun/tests/npm/conformance/bun_1_4_2/`, which may not exist yet); keep `RESULTS` keyed as today
  for `bun/tests/npm/fixtures/` so existing unit tests are unchanged; have `_results_repo` also
  write `graphs.json` (repository-relative project directory → `{"classes": [{"platforms": …,
  "graph": …}]}` or `{"error": …}`, contract "Ruleset side") from `conformance_graphs`, and
  `exports_files(["graphs.json"])` in its `BUILD.bazel` (depends on T009)
- [X] T011 Run `bazel run //:gazelle` and `bazel test //bun/tests/npm/...`; existing suites must
  pass as at T005, except a suite that iterates over every fixture and now meets a corpus project
  showing a BC (for example `conformance_unbound` failing resolution, BC-3): record such a failure in
  `tdd-log.md` with its BC as an expected red, change nothing to hide it; any other failure: stop and
  report

**Checkpoint**: the corpus exists with Bun-written lockfiles, and `@npm_fixture_results//:graphs.json`
holds `main`'s resolver's graph for every project

---

## Phase 3: User Story 2 - Maintainers learn of any difference from a failing test (Priority: P1) 🎯 MVP

**Goal**: A conformance test makes the pinned Bun the oracle for every project (FR-007–FR-012).

**Independent Test**: `bazel test //bun/tests/npm/conformance:conformance_test` runs on `main`'s
resolver and fails exactly with the differences BC-1…BC-8 describe (Q3), and its red mode fails
naming the injected binding (Q2).

### Tests for User Story 2 (write first, see red)

- [X] T012 [P] [US2] Write `bun/tests/npm/conformance/graph.test.ts` (`bun:test`) for `compare` of
  `graph.ts`: two graphs equal up to entry order and indices are equal; one entry versus two entries
  of one `name@version` with different peer bindings differ (entry counts count, research R8); a
  holder linking a different target, a missing link and an extra link each differ; the failure text
  is exactly the contract's ("`<project>: <holder or name@version (peer bindings)> links "<dep>" to
  <ruleset target>, Bun links it to <oracle target>`", or "no link"); record red (module missing)

### Implementation for User Story 2

- [X] T013 [P] [US2] Write `bun/tests/npm/conformance/oracle.ts`: `installWithBun(project)` copies
  the whole project directory except `BUILD.bazel` and `node_modules` (so `file:` folders,
  `patches/` and workspace members come along) into a new directory under `TEST_TMPDIR`, starts the loopback registry of `bun/tests/support/npm_registry.ts` on
  `FIXTURE_PORT` serving `bun/tests/npm/registry/archives/` and the project's own `archives/` (for
  example `bun/tests/npm/fixtures/jsx/archives`), and runs `process.execPath install
  --frozen-lockfile --ignore-scripts --linker isolated --registry=<loopback>` through
  `bun/tests/support/spawn.ts` with an empty `BUN_INSTALL_CACHE_DIR` (research R6); a failing
  install throws with Bun's output. Bun is the test's own toolchain Bun; nothing is fetched from the
  network and no host tool runs (constitution III)
- [X] T014 [P] [US2] Write `bun/tests/npm/conformance/graph.ts`: `readBunGraph(dir, workspaces)` per
  research R7 (holders: the root and each workspace path of the lockfile's `workspaces`, and each
  `node_modules/.bun/<dir>` except `node_modules/.bun/node_modules` (ID-3); links: each symlink or
  junction in a holder's `node_modules`, scoped names one level down, `.bin` and dot entries
  skipped; targets by `realpath`; entry identity from the linked `package.json`'s `name` and
  `version`, never from the directory name); `compare(project, ruleset, bun)` by partition
  refinement (research R8) returning the first difference in the contract's failure text;
  `hostTuple()` from `process.platform`, `process.arch` and, on Linux, the C library detected as
  `bun/tests/canary/npm/c_libc.test.ts` detects it; `classFor(tuple, classes)` (depends on T012)
- [X] T015 [US2] Write `bun/tests/npm/conformance/conformance.test.ts`: read
  `@npm_fixture_results//:graphs.json` and enumerate the projects of research R9 from its runfiles;
  a project present on one side only fails (FR-009, US2-4); a fixed `NOT_APPLICABLE` map (project →
  reason; only projects whose `package.json` disagrees with the lockfile on purpose, as
  `bun/tests/integration/workspaces/manifest_mismatch`, or whose lockfile Bun refuses to load) is
  asserted exactly and printed; for any other project the oracle cannot install, the test fails;
  for each project compare the ruleset class of `hostTuple()` with `installWithBun` (a ruleset
  `error` is a difference naming the error); print the projects compared, the exclusions `ID-1`,
  `ID-2`, `ID-3` by name and `0 differences`; with `RULES_BUN_CONFORMANCE_RED=1` redirect one edge
  of `dependency_conflict`'s ruleset graph to another entry before comparing (FR-011) (depends on
  T013, T014)
- [X] T016 [US2] In `bun/tests/npm/conformance/BUILD.bazel` add `bun_test` targets `graph_test_ts`
  (for `graph.test.ts`) and `conformance_test` (for `conformance.test.ts`, `data` = every file of
  every compared project except `BUILD.bazel` (lockfile, manifests, `file:` folders, `patches/`,
  `archives/`) through filegroups,
  `bun/tests/npm/registry/archives`, `bun/tests/support` sources, `@npm_fixture_results//:graphs.json`;
  timeout sized for the scale project), so both run under `bazel test //...`; run
  `bazel run //:gazelle`
- [X] T017 [US2] Run `bazel test //bun/tests/npm/conformance:graph_test_ts` (record green) and
  `bazel test //bun/tests/npm/conformance:conformance_test --test_output=errors` on `main`'s
  resolver (record red, Q3): each failing project's first difference is recorded with the BC it
  shows (BC-1 `conformance_unresolved`, BC-2 `conformance_alias_workspace`, BC-3
  `conformance_unbound`, BC-4 `conformance_registry_to_workspace`, BC-5 `conformance_unprovided_peer`
  and `missing_peer`, BC-6 `dependency_conflict` and `conformance_nested`, BC-7
  `conformance_platform` only where the host is excluded, BC-8 `unsupported`). A project that
  differs for no BC, or a BC that shows no difference: stop and report
- [X] T018 [US2] Make `RULES_BUN_CONFORMANCE_RED=1` redirect one edge of `basic` (a project with no
  Behavior Change, so its red cannot be confused with a BC difference); run `bazel test
  //bun/tests/npm/conformance:conformance_test --test_env=RULES_BUN_CONFORMANCE_RED=1
  --test_output=errors` (Q2) and record that it fails naming `basic`, the dependent, the dependency
  and both bindings. Run Q2 again after T051 turns the test green and record that run as SC-003's
  evidence

**Checkpoint**: every difference between `main` and the pinned Bun is a failing test with a BC; the
conformance test stays red until US1's checkpoint

---

## Phase 4: User Story 4 - Every `bun.lock` form the resolver reads is pinned by a canary (Priority: P2)

**Goal**: Each new access L23–L30 of research Part 4 has a canary with a red mode (FR-005,
FR-006), before the carry-over reads it (constitution V).

**Independent Test**: `bazel test //bun/tests/canary/npm/...` passes, and with
`--test_env=RULES_BUN_CANARY_RED=1` each new canary fails naming its reader (Q5).

### Tests for User Story 4 (the canaries are the tests)

Each canary uses `bun/tests/canary/npm/support.ts` (`runInstall`, `red`, `canaryFail`,
`LOCKFILE_SOURCE`), asserts the form the pinned Bun writes, and names in `canaryFail` the reader it
protects as the `bun/private/bun_lockfile.bzl` (or `lockfile.bzl`) function of research R1 that
reads it.

- [X] T019 [P] [US4] `bun/tests/canary/npm/c_unresolved.test.ts` (C-UNRESOLVED, L23 info
  `unresolved` and L24 workspace `unresolved`): a list of strings naming the optional dependency on
  a package entry and on a workspace; reader `parse_append_dependencies`
- [X] T020 [P] [US4] `bun/tests/canary/npm/c_unlinked.test.ts` (C-UNLINKED, L25): a workspace named
  like a package the root aliases gets keys `./<name>/<dep>` (unscoped and scoped); reader of
  workspace dependencies' resolutions (S2)
- [X] T021 [P] [US4] `bun/tests/canary/npm/c_bundled.test.ts` (C-BUNDLED, L26): an entry of a
  bundled dependency carries info `bundled: true`; record the lockfile it observed as research Part
  7 evidence
- [X] T022 [P] [US4] `bun/tests/canary/npm/c_pkgext.test.ts` (C-PKGEXT, L27): whether the package
  rows already carry the dependencies a top-level `packageExtensions` adds; if they do, the canary
  asserts that and research Part 4 records L27 as not read, with the evidence
- [X] T023 [P] [US4] `bun/tests/canary/npm/c_wsversion.test.ts` (C-WSVERSION, L28): a workspace's
  `version` is written in `workspaces` and a peer on that name with a matching range binds to the
  workspace
- [X] T024 [P] [US4] `bun/tests/canary/npm/c_roworder.test.ts` (C-ROWORDER, L29): the pinned Bun
  writes `packages` keys sorted as the loader's "later row wins" (LOCK L2993) assumes
- [X] T025 [P] [US4] Extend `bun/tests/canary/npm/c_infodeps.test.ts` and
  `bun/tests/canary/npm/c_peers.test.ts` (L30): the `dependencies`, `optionalDependencies` and
  `peerDependencies` values are npm range strings as written in `package.json` (`^`, `~`, `||`,
  hyphen, x-range), the form `bun_semver.bzl` parses
- [X] T026 [US4] Add a `bun_test` target for each new canary in
  `bun/tests/canary/npm/BUILD.bazel` as the existing ones are declared; run `bazel run //:gazelle`

### Evidence for User Story 4

- [X] T027 [US4] Run `bazel test //bun/tests/canary/npm/...` (record green) and each new or extended
  canary with `--test_env=RULES_BUN_CANARY_RED=1` (record that each fails naming its reader); fill
  research Part 4's "Evidence" and "Canary" columns for L23–L30 and add the Part 7 evidence rows
  (`E5`…) for what each canary observed

**Checkpoint**: every field the carry-over will read is pinned

---

## Phase 5: User Story 1 - A consumer's build links what `bun install` links (Priority: P1)

**Goal**: The resolver is a carry-over of Bun 1.4.4's pipeline in Bun's order (research S0–S8,
R1–R5), and `resolve.bzl` adapts it to today's output (R4), so every project links what the pinned
Bun links.

**Independent Test**: `bazel test //bun/tests/npm/conformance:conformance_test` reports
`0 differences` (Q1), every BC-n difference recorded at T017 is gone, and the generated targets of
projects without a BC are unchanged (Q7, T064).

### Tests for User Story 1 (write first, see red)

- [X] T028 [P] [US1] Write `bun/tests/npm/bun_semver_test.bzl`: version parse and order
  (prerelease and build), npm range parse and `satisfies` (`||`, hyphen, x-ranges, `~`, `^`,
  comparators, the prerelease rule), each case taken from `SRC/test/cli/install/semver.test.ts` and
  commented with its line at the tag (research R5)
- [X] T029 [P] [US1] Write `bun/tests/npm/bun_install_types_test.bzl`: `Behavior` bits and
  `is_placed` (HOOKS L271), `Libc::for_dependency` (HOOKS L884–890: `libc` applies to optional
  dependencies only), `is_disabled` (META L72–74) with Bun's `OperatingSystem`/`Architecture`/`Libc`
  `is_match` including negated entries (`!win32`), and `DepSorter` order (LOCKFILE)
- [X] T030 [P] [US1] Add cases to `bun/tests/npm/lockfile_test.bzl` for the accesses L23–L30 of
  `bun/private/lockfile.bzl`: `unresolved` not a list, or holding a non-string, fails naming the
  `bun.lock` label, the entry and the field without printing the value (spec Edge Cases); a name
  under `unresolved` that is no optional dependency is accepted (ignored later, as Bun does);
  `bundled` not a boolean; a workspace `version` not a string
- [X] T031 [P] [US1] Write `bun/tests/npm/bun_lockfile_test.bzl` on `@npm_fixture_results`
  lockfiles and inline texts: one package per `name@resolution` (`append_package_dedupe`:
  `dependency_conflict`'s `x@1.0.0` keys are one package); workspaces under their names first;
  `./lib/<dep>` and `./@scope/lib/<dep>` bind the workspace's dependencies
  (`conformance_alias_workspace`); `unresolved` resets the binding (`conformance_unresolved`); an
  optional or peer dependency without a key stays unresolved, any other fails
  (`may_stay_unresolved` L3298, `dependency_resolution_failure` L3302); row evidence binds
  `dependency_conflict`'s `x@1.0.0 → b@1.0.0` (research E2); version-based peers (S3) and
  `shared_version` (S5) on `conformance_shared_peer`; a `packages` key equal to a workspace's name
  holding a `file:` folder returns Bun's "Duplicate package path" error naming the file and the key
  (FR-004); and the spec's edge cases: a peer provided only through an `unresolved` optional edge
  stays as Bun binds it; a `./<name>/...` key of a linked workspace is loaded and never bound; a
  name under `unresolved` that is not an optional dependency changes no binding
- [X] T032 [P] [US1] Write `bun/tests/npm/bun_tree_test.bzl`: hoisting places rows as Bun's
  `process_subtree`/`hoist_dependency` do on `hoisted` and `conformance_nested`; `bind_served_peers`
  rebinds a peer unless it is placed; `is_filtered_dependency_or_workspace` skips a disabled package
  whether or not optional (BC-7), an unplaced behavior, an omitted optional peer, a pruned workspace,
  an unresolved non-peer; `is_unlinked_member`
- [X] T033 [P] [US1] Write `bun/tests/npm/bun_isolated_store_test.bzl`: `leaking_peers` fixpoint;
  one entry for one package reached under one peer provider, two under two
  (`conformance_peer_contexts`); a peer nothing provides and without resolution is not linked
  (`conformance_unprovided_peer`, BC-5); workspace dependencies owned once; cycles; an entry's
  dependencies are its children's entries
- [X] T034 [P] [US1] Add cases to `bun/tests/npm/platforms_test.bzl` for platform classes
  (research R3): a lockfile without a restricted package has one class; `conformance_platform`'s
  tuples group by the set of packages `is_disabled` leaves out; Linux `unconstrained` uses
  `Libc::ALL`; "unmapped" is a class
- [X] T035 [P] [US1] Add a case to `bun/tests/integration/lockfile_errors.test.ts` (with its project
  under `bun/tests/integration/lockfile_errors/`, written as the existing cases are, since Bun
  writes no lockfile it refuses): a `packages` key equal to a workspace's name holding a `file:`
  folder fails extension evaluation with an English message naming the `bun.lock` label and the key,
  and the remedy where Bun's message has one (FR-004, spec Edge Cases)
- [X] T036 [US1] Register the new suites in `bun/tests/npm/BUILD.bazel` (as `resolve_test_suite` is
  registered); run `bazel run //:gazelle` and `bazel test //bun/tests/npm/...
  //bun/tests/integration:lockfile_errors_test --keep_going`; record red for each new suite and
  case (depends on T028–T035)

### Implementation for User Story 1 (in Bun's order, research R2)

- [X] T037 [US1] Carry over SEMVER into `bun/private/bun_semver.bzl` (version parse and
  `Resolution::order`-relevant order, npm query parse, `satisfies`; only the parts S3, S5 and TREE
  L659, L716, L1717, L1876 call); cite each function; record green for `bun_semver_test`
- [X] T038 [P] [US1] Carry over HOOKS `Behavior`, `is_placed`, `Libc::for_dependency`, META
  `is_disabled` with Bun's `os`/`arch`/`libc` `is_match`, and LOCKFILE `DepSorter` into
  `bun/private/bun_install_types.bzl`; cite each function; record green for
  `bun_install_types_test`
- [X] T039 [P] [US1] In `bun/private/lockfile.bzl` add the checked accesses L23–L30, each tagged
  `# L<n>` as L1–L22 are, with the diagnostics of T030 (an `unresolved` value is never printed);
  record green for `lockfile_test`
- [X] T040 [US1] Carry over S1 into `bun/private/bun_lockfile.bzl`: LOCK
  `parse_into_binary_lockfile` L1797–2711 (top-level fields L1815–2099, `workspaces` L2100–2304 with
  each workspace in the key map under its name L2302, `packages` rows L2308– with `bundled` L2351 and
  `os`/`cpu`/`libc` L2594–2602, the key forms of PRIOR S3 including "Duplicate package path" and
  unlinked workspaces), LOCKFILE `append_package_dedupe` L2685–2711, and `parse_append_dependencies`
  L3347–3543 (`optionalPeers`/`unresolved` L3372–3400, sort L3531); Packages, Dependencies and the
  key map as data-model "Loaded lockfile" states; errors returned as `struct(value = None, error =
  …)` as `resolve.bzl` returns them; cite each function. List every load error of LOCK
  L1797–2711 in research Part 4 with its line; each is tested in T031 or recorded there as not
  produced by any supported Bun (FR-004) (depends on T037, T038, T039)
- [X] T041 [US1] Carry over S2 into `bun/private/bun_lockfile.bzl`: `resolutions` L2765–3031 (root
  dependencies, `workspace` dependencies by name, peers by `linked_member`/`peer_by_version`
  L2793–2855; workspace dependencies by `<name>/<dep>`, `./<name>/<dep>`, then `<dep>` L2859–2921;
  rows by `PkgMap::find_resolution` L1580–1662 with `RowEvidence` L1524–1542 and "later row of equal
  evidence wins" L2993; the `unresolved` reset L3027–3031), `may_stay_unresolved` L3298 and
  `dependency_resolution_failure` L3302; cite each function (depends on T040)
- [X] T042 [US1] Carry over S3 and S5 into `bun/private/bun_lockfile.bzl`:
  `resolve_peer_dep_version_based` L3067–3089, `version_based_peer_range` L3174–3208 (catalogs and
  overrides), `PeerRanges::shared_version` L3091–3172, and REACH `packages_without_peer_provider`,
  with the package index by name ordered by `Resolution::order`; cite each function (depends on
  T041)
- [X] T043 [US1] Carry over S4's hoister and S7's filters into `bun/private/bun_tree.bzl`: TREE
  `process_subtree` L1412, `hoist_dependency` L1782, `bind_served_peers` L816–834, `bind_peer` and
  `peer_by_version` L851–878, `is_filtered_dependency_or_workspace` L1313–1405 (with L1324–1326),
  `is_unlinked_member` (L379–388 for unlinked workspaces), and PRUNED
  `skips_link_to_pruned_workspace`; Trees and served peers as data-model "Hoisted trees"; cite each
  function; record green for `bun_tree_test` (depends on T042)
- [X] T044 [US1] Carry over LOCKFILE `Lockfile::resolve` L1618–1625 (hoist repeated while a peer is
  bound late, then LOCK `rebind_peers_to_printed_packages` L3244) and `clean_with_logger` L1236
  (`Package::clone` resetting optional peers, hoisting again) into `bun/private/bun_lockfile.bzl`,
  after reading S6 in full in `SRC`; if a step of `clean` provably changes no binding of a frozen,
  unchanged lockfile, record that in research Part 2 "Not carried over" with its lines instead of
  carrying it (R2); cite each function; record green for `bun_lockfile_test` (depends on T043)
- [X] T045 [US1] Carry over ISO `build_store` L510–1470 into `bun/private/bun_isolated_store.bzl`:
  `leaking_peers` L573–672; the first pass L728–1240 (cycles L730–776, workspace dependencies owned
  once L779–799, early dedupe by `(pkg_id, ctx)` L801–937 with `ctx` the exact list of
  `(peer name, ancestor resolution)` instead of its `Wyhash`, non-peer dependencies queued
  L1032–1072 with `is_unlinked_member` L711–720, peers resolved up the node chain L1074–1224, an
  unprovided unresolved peer unlinked L1183–1186); the second pass L1251–1470 (entries by package
  and peer set, an entry's dependencies its children's entries L1307–1346, L1430–1455); ISO
  `contained_folders`; Nodes and Entries as data-model "Isolated store"; skip only the steps of
  research Part 2 "Not carried over"; cite each function; record green for
  `bun_isolated_store_test` (depends on T044)
- [X] T046 [US1] In `bun/private/platforms.bzl` add the platform tuples and their grouping into
  classes by the set of packages `bun_install_types.bzl`'s `is_disabled` leaves out (research R3);
  `check_list` stays for the toolchain; record green for `platforms_test` (depends on T038)
- [X] T047 [US1] Rewrite `bun/private/resolve.bzl` as the adapter of research R4, keeping
  `resolve(lockfile, file = "bun.lock", hash_fn = hash)` and its output
  `struct(instances, links, members)` as consumed by `npm_extension.bzl`, `npm_repositories.bzl` and
  `run.bzl`: load (T040–T042) → `resolve` and `clean` (T044) → `build_store` per platform class
  (T045, T046) → entries merged over classes by `(package, peer bindings)` into instances (`id`
  `name@version__<h>[__<n>]`, `name`, `version`, `store_name`, `key`, `edges`, `dependency_keys`,
  `peers`, `status`) → `links[path][alias]` with `closure` (reached in every class) and `optional`
  (ID → the classes' `[os, cpu, libc]` requirements) → `members`; an unfetched entry's dependencies
  are followed (BC-8) while its `status` keeps failing analysis and tagging links `manual` as on
  `main`; remove every function of `main`'s resolver this replaces; each remaining function cites
  the Bun lines it adapts or states it is the adapter (depends on T045, T046)
- [X] T048 [US1] Change the existing tests that assert behavior Bun does not have (research R14,
  FR-016), each listed in `tdd-log.md` as "FR-016 change" with the BC it follows:
  `bun/tests/npm/resolve_test.bzl` cases on per-key instances of one `name@version` (BC-6) and on
  `missing_peer` (BC-5: resolves, `state` not linked); the test of
  `bun/tests/npm/fixtures/missing_peer/` that expects evaluation to fail; and every other test that
  `grep -rn "lists no entry for\|missing_peer\|whatever its" bun/tests e2e` finds asserting BC-3,
  BC-5 or BC-7's old behavior (for example `bun/tests/integration/restricted.test.ts`); no other
  assertion changes (depends on T047)
- [X] T049 [US1] Audit the key walks of `bun/private/lockfile.bzl`, `bun/private/workspaces.bzl`
  and `bun/private/npm_extension.bzl` (PRIOR's audit of key walks, research Part 1): each walk or
  binding decision made outside the carry-over is replaced by `resolve.bzl`'s output or recorded in
  research Part 2 with its lines and the reason it decides no link (depends on T047)
- [X] T050 [US1] Close research Part 4: every `root.get(...)`/`info.get(...)` of LOCK L1797–3543 in
  `SRC` is an access L1–L30 or listed as read by Bun and deciding no binding
  (`trustedDependencies` L1872, `hasInstallScript` L2606, `configVersion` L1861, …); any access the
  carry-over reads without a canary: stop and report (constitution V). The user approved canaries
  with red modes for L31 (the info object of a non-npm row), L32 (a row's `devDependencies`) and
  L33 (a workspace's `optionalPeers`) on 2026-11-21: add them, red first, as T019–T027 added theirs
  (depends on T044)
- [X] T051 [US1] Run `bazel test //bun/tests/npm/conformance:conformance_test --test_output=errors`
  (Q1: `0 differences`), `//bun/tests/npm/...`, `//bun/tests/canary/npm/...`,
  `//bun/tests/integration/...` and `//...`; record green, and for each BC-n of T017 one row
  "difference gone" naming the project (SC-003). A remaining difference is fixed in the carry-over
  by following Bun's cited lines, never by a case rule (P1) (depends on T047–T050)
- [X] T052 [US1] Run `bazel test //bun/tests/integration:scale_test --test_output=all` (Q9) and
  record the printed evaluation time next to T005's; if the 10,000 ms bound fails, record
  `--starlark_cpu_profile` output and stop and report; no shortcut departing from Bun's structure
  (research R13)

**Checkpoint**: the conformance test is green; US1 and US2 hold together

---

## Phase 6: User Story 3 - Each step of the resolver can be traced to Bun's source (Priority: P2)

**Goal**: Every function of the rebuilt resolver cites Bun's lines at `bun-v1.4.4`, and research
maps every binding-relevant Bun step (FR-002, SC-004).

**Independent Test**: `bazel test //bun/tests/npm/conformance:citations_test` passes, fails in red
mode, and research Part 2 lists 0 unaccounted Bun steps (Q6).

- [X] T053 [P] [US3] Write `bun/tests/npm/conformance/citations.test.ts` and its `bun_test` target
  `citations_test` in `bun/tests/npm/conformance/BUILD.bazel` (`data` = `bun/private/bun_*.bzl` and
  `bun/private/resolve.bzl`): every `def` has a docstring with at least one line matching
  `Bun: (src/install|src/install_types|src/semver)/\S+ L\d+–L\d+ @ bun-v1\.4\.4` naming a file of
  research Part 1, or, in `resolve.bzl` only, a line stating it is the adapter;
  `RULES_BUN_CITATIONS_RED=1` (its own variable, so Q2 does not flip it) adds an uncited `def` to
  the checked text and the test must fail;
  record green and red
- [X] T054 [US3] Re-read every cited range in `SRC` against its Starlark function (same steps, same
  order); correct any citation or carry-over that differs, then re-run T051's conformance test;
  record the review in `tdd-log.md` (one row per `bun/private/bun_*.bzl` file). The user approved
  ID-6 on 2026-11-21 (research Part 6): `linkWorkspacePackages` binds as Bun's default and no
  `bunfig.toml` is read; T078 names ID-6 in the docs
- [X] T055 [US3] Write research Part 2's function-level map: each Bun function of S1–S8 → the
  ruleset function that carries it over; complete "Not carried over" with T044's `clean` decision
  and T049's audit; state that 0 binding-relevant Bun steps are unaccounted (SC-004) in
  `specs/006-bun-conformant-resolution/research.md`

**Checkpoint**: conformance holds by construction, traceably

---

## Phase 7: User Story 5 - A consumer on Bun 1.4.2 keeps the links 1.4.2 gives (Priority: P3)

**Goal**: Lockfiles Bun 1.4.2 writes resolve as Bun 1.4.2's own isolated install links them, the
oracle being a registered 1.4.2 toolchain (FR-013, research R10).

**Independent Test**: `bazel test //bun/tests/npm/conformance:conformance_1_4_2_test
--platforms=//bun/tests/npm/conformance:host_bun_1_4_2` passes and lists the not-applicable projects
with reasons (Q4).

- [X] T056 [P] [US5] In `MODULE.bazel` add `bun_dev.toolchain(name = "bun_1_4_2", bun_version =
  "1.4.2")` (fetched with `bun/private/versions.bzl`'s integrity), `use_repo` its archive
  repositories, and `register_toolchains("//bun/tests/npm/conformance:all", dev_dependency = True)`
  **before** the `@bun_toolchains//:all` registration; if the `bun` extension does not accept a
  second dev toolchain tag of another version, stop and report
- [X] T057 [US5] In `bun/tests/npm/conformance/BUILD.bazel` add `constraint_setting(name =
  "bun_version")`, `constraint_value(name = "bun_1_4_2")`, `platform(name = "host_bun_1_4_2",
  parents = ["@platforms//host"], constraint_values = [":bun_1_4_2"])`, and one `toolchain()` per
  1.4.2 archive for `//bun/toolchain:target_type` with that archive's OS/CPU (and libc) constraints
  plus `:bun_1_4_2` in `target_compatible_with`, as `@bun_toolchains` declares its own (depends on
  T056)
- [X] T058 [US5] Add `--bun-1-4-2` to `bun/tests/npm/registry/write_lockfiles.ts`: it writes
  `bun/tests/npm/conformance/bun_1_4_2/<project>/` (`bun.lock`, `package.json`, workspace
  `package.json` files, a `BUILD.bazel` exporting them) for every corpus project, and keeps an
  exported `NOT_APPLICABLE_1_4_2` map with the reason for each project 1.4.2 cannot write or install
  (unlinked workspace: SRC142 LOCK L2479–2490 rejects it; `unresolved`: 1.4.2 does not write it),
  after re-reading those lines in `SRC142`; run it with the 1.4.2 Bun of T056's repository
  (`$(bazel info output_base)/external/<its repository>/bun`, `--version` = `1.4.2`); run
  `bazel run //:gazelle`; `conformance_test` (1.4.4) now compares these lockfiles too (T010, R10)
  (depends on T056)
- [X] T059 [US5] In `bun/tests/npm/conformance/conformance.test.ts` add the 1.4.2 mode, selected
  when `Bun.version` is `1.4.2` (asserted to be `1.4.2` or `1.4.4`): projects are exactly the
  directories under `bun/tests/npm/conformance/bun_1_4_2/`, the not-applicable list is
  `NOT_APPLICABLE_1_4_2` printed with reasons, and a difference fails with the contract's "1.4.2
  extra failure" text (`<project>: Bun 1.4.2 links this lockfile differently from Bun 1.4.4, which
  the ruleset follows (<first difference>); the ruleset cannot follow both (constitution V)`), which
  holds because `conformance_test` asserts the ruleset equals Bun 1.4.4 on the same lockfiles; add
  the `bun_test` target `conformance_1_4_2_test` with `target_compatible_with =
  [":bun_1_4_2"]` so `bazel test //...` skips it (depends on T057, T058)
- [X] T060 [US5] Run Q4 on Linux and record the result per project; `conformance_test` must stay
  green with the 1.4.2 lockfiles. A "Bun 1.4.2 links this lockfile differently" failure is the
  spec's stop condition: stop and report, change neither side. If Bun 1.4.4's `--frozen-lockfile`
  install refuses a 1.4.2-written lockfile (it would rewrite it), stop and report the same way
  (depends on T059, T051)
- [X] T061 [US5] In `.github/workflows/ci.yaml` add to the `test` job, `if: matrix.folder == '.'`,
  a step `bazel test //bun/tests/npm/conformance:conformance_1_4_2_test
  --platforms=//bun/tests/npm/conformance:host_bun_1_4_2` so it runs on `ubuntu-latest`,
  `macos-latest` and `windows-latest` (FR-013)

**Checkpoint**: all user stories hold

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Documentation that claims only what the tests cover, the completion gates, the PR.

- [X] T062 [P] Rewrite the resolution part of `_NPM_DOC` in `bun/private/npm_extension.bzl`
  (FR-017): the ruleset links what the pinned Bun 1.4.4's isolated install links, as the
  conformance test checks; the Intentional Differences ID-1, ID-2, ID-3; remove the statements of
  the old rules (BC-7's "A non-optional dependency is carried whatever its `os`, `cpu` and `libc`
  say", BC-3's and BC-5's failures); name only CI runner labels whose jobs ran these tests (filled at
  T067)
- [X] T063 [P] In `specs/004-bun-1-4-4-upgrade/research.md` mark G1 and G2 resolved by feature 006,
  with a link to this feature's research Part 4 (L23, L25)
- [X] T064 Q7: on `main` and on the branch, list the targets of every root fixture hub
  (`bazel query '@<hub>//...'`) and, in `e2e/smoke/`, `bazel mod show_extension
  @rules_bun//bun:extensions.bzl%npm`; the `:node_modules/...` names and every public symbol must be
  equal except where a BC lists a change (SC-005); record the comparison, and that links are
  compared by inference (both `main`'s and the branch's links equal Bun's in `conformance_test` for
  projects without a BC); any other change: stop and report
- [X] T065 Completion gates (Q8, FR-018): in the root `bazel run //:gazelle`,
  `prek run --all-files`, `bazel test //...`, `bazel test //... --noenable_runfiles
  --spawn_strategy=local`; in `e2e/smoke/` `bazel test //...`; record each; report a failure, do not
  widen the task (AGENTS.md)
- [ ] T066 Commit the remaining work, push `006-bun-conformant-resolution` and open one PR to `main`
  with `gh pr create`: the BC table of `contracts/public-api.md`, each BC with its T017 difference
  and its T051 "difference gone" row, the FR-016 list of changed tests (T048), the Intentional
  Differences, `scale_test` times on `main` and on the branch (T005, T052), and the 1.4.2 results
  per platform (T060), and the speckit overlay as outside feature 006's scope (T083); end the body
  with the attribution line the session specifies
- [ ] T067 Watch the PR's CI run (`gh pr checks --watch`); for each job on `ubuntu-latest`,
  `macos-latest`, `windows-latest` (including the 1.4.2 step) record the result in `tdd-log.md`; on a
  failure, report it with its log, do not widen the task; when every job passes, fill `_NPM_DOC`'s
  runner labels (T062) with exactly the labels that ran, and commit as
  `docs: record PR #<n>'s CI run for feature 006`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none. T002 before any task that cites ID-3, BC-6, BC-7 or BC-8.
- **Foundational (Phase 2)**: after Setup; blocks every story (corpus and `graphs.json`).
- **US2 (Phase 3)**: after Foundational; its red run (T017) is taken on `main`'s resolver, so it
  MUST finish before T047 replaces that resolver.
- **US4 (Phase 4)**: after Foundational (canaries reuse corpus layouts); before T039–T041, which
  read the fields the canaries pin (constitution V). Independent of US2; can run alongside it.
- **US1 (Phase 5)**: after US2 (T017, T018) and US4 (T027); verified by US2's test.
- **US3 (Phase 6)**: after US1's implementation (T047); T053 can be written as soon as one
  `bun/private/bun_*.bzl` exists.
- **US5 (Phase 7)**: T056–T058 after Foundational, in parallel with US1; T060 after T051.
- **Polish (Phase 8)**: after every story; T066 after T065; T067 after T066.

### User Story Dependencies

- **US2 (P1)**: Foundational only. MVP: makes every difference a failing test.
- **US4 (P2)**: Foundational only.
- **US1 (P1)**: US2 (its verification) and US4 (canaries before reads).
- **US3 (P2)**: US1 (the code it checks).
- **US5 (P3)**: US1 for its green run; its infrastructure is independent.

### Within User Story 1

Tests T028–T035 → T036 (red) → T037, T038, T039 → T040 → T041 → T042 → T043 → T044 → T045;
T046 after T038; T047 after T045 and T046; T048, T049 after T047; T050 after T044; T051 after
T047–T050; T052 after T051.

### Parallel Opportunities

- Setup: T003, T004, T005.
- Foundational: T006 with T008 (archives and the graph converter's test).
- US2: T012, T013 together; T014 after T012.
- US4: T019–T025 together (one file each), then T026.
- US1 tests: T028–T035 together (one file each). Implementation: T037, T038, T039 together.
- US5: T056 while US1 runs.
- Polish: T062, T063 together.

---

## Parallel Example: User Story 4

```bash
Task: "C-UNRESOLVED canary in bun/tests/canary/npm/c_unresolved.test.ts"
Task: "C-UNLINKED canary in bun/tests/canary/npm/c_unlinked.test.ts"
Task: "C-BUNDLED canary in bun/tests/canary/npm/c_bundled.test.ts"
Task: "C-PKGEXT canary in bun/tests/canary/npm/c_pkgext.test.ts"
Task: "C-WSVERSION canary in bun/tests/canary/npm/c_wsversion.test.ts"
Task: "C-ROWORDER canary in bun/tests/canary/npm/c_roworder.test.ts"
```

## Parallel Example: User Story 1 (tests first)

```bash
Task: "bun/tests/npm/bun_semver_test.bzl from Bun's semver.test.ts"
Task: "bun/tests/npm/bun_install_types_test.bzl"
Task: "bun/tests/npm/bun_lockfile_test.bzl"
Task: "bun/tests/npm/bun_tree_test.bzl"
Task: "bun/tests/npm/bun_isolated_store_test.bzl"
Task: "platform-class cases in bun/tests/npm/platforms_test.bzl"
```

---

## Implementation Strategy

### MVP First (User Story 2)

1. Phase 1 and Phase 2: corpus and the ruleset's graphs.
2. Phase 3 (US2): the conformance test, red on `main` with exactly BC-1…BC-8.
3. **STOP and VALIDATE**: every difference is a failing, named test (Q2, Q3).

### Incremental Delivery (one PR at the end)

1. US2 → every difference visible.
2. US4 → every field the carry-over reads is pinned.
3. US1 → the carry-over, stage by stage in Bun's order; conformance green.
4. US3 → citations checked and mapped.
5. US5 → Bun 1.4.2 as a second oracle.
6. Polish → docs, gates, PR, CI on Linux, macOS and Windows.

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks.
- `conformance_test` is red from T017 to T051 on this branch by design; nothing merges before T067.
- A difference is fixed only by following Bun's cited lines; a case rule fitted to a fixture is the
  approach this feature replaces (P1).
- Commit after each task or logical group, in English, with the session's attribution line.

---

## Phase 9: Convergence

- [X] T068 The user approved BC-9 (optional peers linked as Bun links them:
  `conformance_peer_contexts`, `bun/tests/integration/workspaces/fetch`) and BC-10
  (`bundleDependencies` not linked: `conformance_bundled`) on 2026-10-30 (research Part 6). Add both
  rows to `contracts/public-api.md` and name them in T017's `tdd-log.md` rows, before any carry-over
  task fixes them
- [X] T069 Add the corpus project `conformance_unfetched` (research "T017 findings": a patched
  package with a dependency) to `bun/tests/npm/registry/write_lockfiles.ts` with a `check` asserting
  that form, write it with `$B` into `bun/tests/npm/fixtures/conformance_unfetched/` (archives only by
  `pack.ts`), and record its BC-8 difference red in `tdd-log.md` on `main`'s resolver before T047,
  per SC-003 / BC-8 (missing)
- [X] T070 Keep the red mode on `workspace`, not T018's `basic` (which shows BC-6): record the
  deviation and its reason in `tdd-log.md`; T018's second Q2 run after T051 uses `workspace`, per
  FR-011 (partial)

---

## Phase 10: Convergence

- [X] T071 Make an instance whose `status` fails analysis visible to the conformance test: in
  `bun/tests/npm/conformance/graph.bzl` carry each reached instance's non-`ok` `status` into the
  Graph JSON (and `bun/tests/npm/conformance/graph.ts`'s `compare` report it as a difference, with
  a `graph_test`/`graph_test_ts` case written red first), so `missing_peer`, whose evaluation fails
  on `main` while Bun installs it, shows BC-5 instead of passing (T017 row "`missing_peer` shows no
  graph difference"); the unfetched status BC-8 keeps is not one of ID-1–ID-3, so stop and report
  for the user to decide whether it becomes a listed Intentional Difference before excluding it;
  record red on `main`'s resolver before T047, per FR-007 / FR-011 / US1/AC5 (partial)

---

## Phase 11: Convergence

- [X] T072 The user approved ID-4 on 2026-11-21 (research Part 6). Treat the differences T071 reported with no ID or BC: an
  unfetched entry fails analysis in the ruleset while Bun installs it (`unsupported`: tarball URL;
  `restricted` and `integration/workspaces/multi_nointegrity/two`: no integrity, constitution III;
  `conformance_unfetched`'s patched entry once BC-8 lands). Until decided, T051's `0 differences`
  cannot hold. If the user approves it as **ID-4** (unfetched entries fail analysis), add ID-4 to
  spec "Intentional Differences", the Exclusions of `contracts/conformance-graph.md`, `data-model.md`
  "Intentional difference" and `quickstart.md` Q1; then, writing a `graph_test_ts` case red first,
  make `bun/tests/npm/conformance/graph.ts`'s `compare` skip only an unfetched entry's `status`, by
  the name ID-4, so `missing_peer`'s BC-5 status stays a difference; name ID-4 in
  `conformance.test.ts`'s header and its "excluded by name" line; record red and green in
  `tdd-log.md`, before T051, per FR-011 / SC-001 (contradicts)
- [X] T073 After T068 and T072 are answered, bring `plan.md` (Summary, Constitution Check VII,
  Phases: "BC-1…BC-8") and research Part 6 "T017 findings" (`missing_peer` shows BC-5 in the
  conformance test since T071, not only through T048) into line with the spec's Behavior Changes and
  Intentional Differences, per spec P3 / FR-017 (partial)

---

## Phase 12: Convergence

- [X] T074 Add the corpus project `conformance_unresolved_peer` for the spec edge case "a peer that
  some package provides only through an `unresolved` optional edge": a package whose peer's only
  provider in the tree is an optional dependency another package lists under `unresolved`; add it to
  `projects` in `bun/tests/npm/registry/write_lockfiles.ts` with a `check` asserting that form
  (archives only by `pack.ts`), write it with `$B` into
  `bun/tests/npm/fixtures/conformance_unresolved_peer/`, and run `conformance_test` on `main`'s
  resolver before T047, recording in `tdd-log.md` its difference (with its BC, or stop and report
  if none explains it) or that it shows none, so the oracle, not T031's hand-reasoned case, decides
  the binding; if the pinned Bun cannot write the layout, stop and report, per spec Edge Cases / P2
  / FR-009 (partial)

---

## Phase 13: Convergence

- [X] T075 CRITICAL: pin with canaries the three `bun.lock` accesses the carry-over already reads
  without one (research Part 4 "none yet"): L31 the info object in slot 1 of a row that is not an
  npm version (`bun/private/lockfile.bzl` `# L31`), L32 a row's `devDependencies` (`# L32`), L33 a
  workspace's `optionalPeers` (`# L33`). Add `bun/tests/canary/npm/c_rowinfo.test.ts` (C-ROWINFO: a
  `file:` and a tarball-URL row carry their `dependencies` in slot 1),
  `bun/tests/canary/npm/c_rowdevdeps.test.ts` (C-ROWDEVDEPS: a folder package's row carries
  `devDependencies`) and `bun/tests/canary/npm/c_wsoptpeers.test.ts` (C-WSOPTPEERS: a workspace
  with an optional peer carries `optionalPeers`), each through `support.ts` with a red mode and a
  `canaryFail` naming its reader in `bun/private/lockfile.bzl` / `bun/private/bun_lockfile.bzl`;
  register them in `bun/tests/canary/npm/BUILD.bazel`, run `bazel run //:gazelle`, record green and
  `RULES_BUN_CANARY_RED=1` red in `tdd-log.md`, and fill research Part 4's Evidence and Canary
  columns with Part 7 evidence rows. If the pinned Bun does not write a form, stop and report
  (the read is then removed or the user decides), per Constitution V (contradicts)
- [X] T076 The user approved BC-11 on 2026-11-21 (research Part 6). Carry both store entries of one
  `name@version` with different peer bindings into a target that reaches both. Bun's isolated
  install links both (spec Edge Cases; `conformance_peer_contexts`: `p@1.0.0` with the root's
  `q@1.0.0` and through `q2-user` with `q@2.0.0`), but `bun/private/run.bzl` `_check_unique` fails
  analysis of such a target ("a target holds one instance of each package version"), and
  `bun/tests/npm/uniqueness_test.bzl` `_peer_test` and `_peer_chain_test` assert that failure.
  `bun/tests/npm/conformance/graph.bzl` does not model it, so `conformance_test` cannot see it.
  Before anything changes, make the conformance test report it: a `graph_test` / `graph_test_ts`
  case, red first, for a holder whose links reach two entries of one `name@version`, recorded red in
  `tdd-log.md`. Then lay out each entry by its peer bindings in `run.bzl`, in a store directory
  named as Bun's isolated store names it (`<name>@<version>+<peer hash>`, Store.rs L450–L466,
  cited), and change the two tests as FR-016 changes; record green, per spec BC-11 / P3 / FR-016 /
  US1 (contradicts)
- [X] T077 The user approved BC-12 on 2026-11-21 (research Part 6). Settle the adapter's two
  failures that neither the spec lists nor a test covers:
  `bun/private/resolve.bzl` "the store links \"<alias>\" of <package> to different packages on
  different platforms" and "\"<alias>\" of the workspace \"<path>\" links different packages on
  different platforms, which rules_bun cannot express". Determine from Bun's cited lines (S7, S8)
  whether the pinned Bun can write a lockfile whose store binds one alias of an entry or holder
  to different packages on different platform classes. If it can, add a corpus project through
  `bun/tests/npm/registry/write_lockfiles.ts` with a `check`, record its difference red, and express
  it: a per-class binding the hub turns into `select()` on the `[os, cpu, libc]` classes it already
  selects optional links by (BC-12). If it cannot, record why in research R4 with the Bun
  lines. In either case add a `bun/tests/npm/resolve_test.bzl` case for each error path, per spec
  P3 / BC-12 / FR-015 / Constitution II (partial)
- [X] T073 BC-4 in builds (user decision 2026-11-21, research Part 6): the hub links a registry
  package's dependency on a workspace member by path only (no target dependency, so no Bazel
  dependency cycle), and the rule that builds the copy tree (`bun/private/run.bzl`) fails analysis
  when a target's closure holds such an edge and the member's target is not among the target's
  transitive deps, naming the package, the dependency and the member's target and telling the user
  to add it to `deps`. Write the failing analysis tests first (member declared: the link resolves
  and a program imports the member through the package; member not declared: the failure text),
  then implement; record red and green in `tdd-log.md`; update US1 scenario 4 and the `_NPM_DOC`
  text to this behavior

---

## Phase 14: Convergence

- [X] T078 CRITICAL: make the documentation claim only what `conformance_test` passes on. Today
  `_NPM_DOC`'s Resolution paragraph in `bun/private/npm_extension.bzl` ("the hub links what the
  pinned Bun 1.4.4's isolated install links … a package reached under different peers is one package
  per set of peers") and `bun_binary`'s doc in `bun/private/run.bzl` ("Peers resolve as the pinned
  Bun's isolated install resolves them") hold unconditionally, while `conformance_test` reports
  T076's layouts (`basic`, `conformance_peer_contexts`, `integration/workspaces/fetch`: one target
  reaching two entries of `p@1.0.0` fails analysis) and T077's (`conformance_platform_peer`,
  `conformance_platform_peer_workspace`: evaluation fails, "rules_bun cannot express"). The user
  decided T076 (BC-11) and T077 (BC-12) on 2026-11-21; after both land and before T065: name in both
  docs ID-5 and ID-6 with what a consumer sees, bring `plan.md`, `contracts/public-api.md` (BC-11
  and BC-12 rows), `data-model.md` and `quickstart.md` to BC-1…BC-12 and ID-1…ID-6, keep the
  unconditional claim only for layouts Q1 shows conformant, and confirm with a green Q1 run recorded
  in `tdd-log.md`, per Constitution II / FR-017 (contradicts)
- [X] T079 Complete T040's inventory in research Part 4: every refusal of Bun's loader at
  `bun-v1.4.4`, LOCK L1797–L3543 (the 48 `fail!` sites from L1819 "Missing lockfile version" to
  L2710 "Invalid git dependency tag", `UnknownLockfileVersion` L1855, `UnexpectedResolution` L2427,
  `InvalidPackageInfo` L2536 and L2888, `InvalidPackagesObject` L2933, `parse_append_dependencies`'
  refusals, `dependency_resolution_failure` L2843, L2908, L3010), each with its line and either the
  `bun/tests/npm/bun_lockfile_test.bzl` / `lockfile_test.bzl` /
  `bun/tests/integration/lockfile_errors.test.ts` case where the ruleset fails evaluation naming the
  `bun.lock` label and the key or field (written red first), or the reason no supported Bun writes
  it. Settle L2667 explicitly ("Missing integrity hash for npm package resolved to a tarball URL
  outside the configured registry", lockfile v2+): the ruleset now treats such a row as ID-4 (fails
  analysis of a target that needs it) where Bun refuses the lockfile. The user approved ID-5 on
  2026-11-21 (research Part 6): keep the row ID-4 and record ID-5 against L2652–L2669 in the
  inventory, per FR-004 / T040 (partial)
- [X] T080 In `bun/private/lockfile.bzl`, check the dependency maps the carry-over reads before
  `dict(...)`: an entry's `dependencies`, `optionalDependencies`, `peerDependencies` (L13, L14) and
  `devDependencies` (L32), and a workspace's dependency kinds (L3, L6), each an object whose values
  are strings, as Bun refuses otherwise ("Expected an object" / "Expected a string", LOCK
  L3405–L3426); fail naming the `bun.lock` label, the entry or workspace and the field, in English,
  without printing the value; write the `bun/tests/npm/lockfile_test.bzl` cases red first and record
  red and green in `tdd-log.md`, per spec Edge Cases (malformed value) / FR-004 (partial)
- [X] T081 Settle BC-4 for package executables: `npm_bin` (`bun/private/run.bzl`, mode `bin`) lays
  out `deps = [package]`, and a registry `npm_link` carries no `BunDeclaredTargetsInfo`, so
  `:node_modules/<package>/bin/<bin>` of a package whose closure links a workspace member always
  fails `_member_links` with "add … to its deps", which a bin target has no attribute for. Write the
  analysis test first (a bin of `member-user`-like package in
  `bun/tests/npm/fixtures/conformance_registry_to_workspace/`, through `pack.ts` and
  `write_lockfiles.ts`) and record it red; then make the bin link the member as Bun links it without
  a Bazel dependency cycle, or, if no supported way exists, stop and report so the user decides
  (spec BC-4 wording, an Intentional Difference); update `_NPM_DOC`'s BC-4 sentence to name bins;
  record green, per BC-4 / US1/AC4 (partial)
- [X] T082 Extend `bun/tests/npm/conformance/citations.test.ts` (`MODULES`) to the resolver functions
  `bun/private/platforms.bzl` added (`platform_tuples`, `platform_bits`, `platform_classes`), letting
  a function there state that it is the adapter of research R3 (ID-2) as `resolve.bzl` may; cite or
  mark `platform_tuples`; record green and the existing `RULES_BUN_CITATIONS_RED=1` red in
  `tdd-log.md`, per FR-002 / SC-004 (partial)
- [X] T083 The user decided on 2026-11-21 (research Part 6) that
  `.specify/workflows/overlays/speckit/rules-bun.yml` (commit 57a1326, called for by neither spec
  nor plan) ships in this feature's PR; T066's PR body lists it as outside feature 006's scope, per
  FR-018 (unrequested)

---

## Phase 15: Convergence

- [X] T084 CRITICAL: make `_NPM_DOC`'s "Packages" paragraph in `bun/private/npm_extension.bzl`
  (L501–L513) state the rule the resolver applies. It says a dependency's `os`, `cpu` and `libc` are
  matched "by npm's rule (npm-install-checks `checkList`: a sole `any` matches every platform, `!`
  negations included)", while platform classes come from Bun's `Meta::is_disabled` with
  `OperatingSystem`/`Architecture`/`Libc` `is_match` (`bun/private/bun_install_types.bzl`
  `negatable_from_json_value`, `meta_is_disabled`; HOOKS L884–L890: `libc` applies to optional
  dependencies only), which differs from `checkList` (for example `os: ["linux", "any"]` matches
  every OS in Bun, only Linux in npm). Name Bun's rule with its lines, and for each case the
  paragraph states (a sole `any`, `!` negations, a value without an `@platforms` constraint, `libc`
  off Linux), add a `bun/tests/npm/bun_install_types_test.bzl` or `bun/tests/npm/platforms_test.bzl`
  case on `meta_is_disabled` / `platform_classes`, written red first where it covers new behavior;
  record in `tdd-log.md`, per Constitution II / FR-017 / P1 (contradicts)
- [X] T085 Bring `specs/006-bun-conformant-resolution/contracts/public-api.md` in line with spec BC-4
  (user, 2026-11-21): its BC-4 row still reads "not linked → linked to the member". Make it state the
  link by path, the analysis failure of a target whose closure holds such a link without the
  member's target among its transitive `deps` (naming the package, the dependency and the member's
  target), and the bin target receiving the members from the hub (T081). In "Diagnostics added",
  list BC-4's analysis failure and the refusals T079 and T080 added (a container or a dependency map
  that is not an object of strings), and remove "No other diagnostic changes text, except those of
  BC-3 and BC-5" (once T076 lands, also BC-11's removed "a target holds one instance of each package
  version"), per spec BC-4 / FR-015 / P4 (partial)
- [X] T086 Review `libc_matches` (`bun/private/npm_repositories.bzl` L260) and `check_list`
  (`bun/private/platforms.bzl` L80), `main`'s npm-rule package selection: since T046/T047 the hub
  selects by the resolver's platform tuples (`conditions_hold`), and only
  `bun/tests/npm/libc_test.bzl` and `bun/tests/npm/platforms_test.bzl` `_check_list_test` call them
  (plan's "`check_list` stays for the toolchain": no toolchain file calls it). Remove them, their
  tests and their registration, as T047 removes every function of `main`'s resolver it replaces, or
  record in research Part 2 the non-test use that keeps them; run `bazel run //:gazelle` and
  `bazel test //bun/tests/npm/...`, per T047 / plan Source Code (unrequested)
- [X] T087 Exhausting `_LIMIT` falls through silently in every carried-over loop
  (`bun/private/bun_lockfile.bzl` L1170, L1212, L1231, L1437; `bun/private/bun_tree.bzl` L701;
  `bun/private/bun_isolated_store.bzl` L127, L252, L443; `bun/private/resolve.bzl` L123), against the
  "Carry over" convention ("exhausting `_LIMIT` returns an English error naming the stage, as
  `resolve.bzl` does on `main`"); T054's review left them without the user's decision. Make each
  return that error, or stop and report so the user decides to keep them (T054: unreachable within
  an evaluation) and record the decision in research Part 6, per tasks.md Conventions / T054
  (contradicts). The user decided on 2026-11-21 to keep the loops as they are; the convention above
  now says so (research Part 6)

---

## Phase 16: Convergence

- [X] T088 After T087 changes `bun/private/bun_lockfile.bzl`, `bun/private/bun_tree.bzl`,
  `bun/private/bun_isolated_store.bzl` and `bun/private/resolve.bzl`, run the completion gates
  again on the final code before T066 (T065's records predate it): in the root
  `bazel run //:gazelle`, `prek run --all-files`, `bazel test //...`, `bazel test //...
  --noenable_runfiles --spawn_strategy=local`, and Q1 (`conformance_test`, `0 differences`); in
  `e2e/smoke/` `bazel test //...`; record each in `tdd-log.md`; report a failure, do not widen the
  task (AGENTS.md), per FR-018 / SC-006 (partial)

---

## Phase 17: Final review (2026-11-21)

The workflow's Claude review before the final gate found these; the user rejected the gate on
2026-11-21 to fix them first (research Part 6). Each is written red first and recorded in
`tdd-log.md`.

- [X] T089 BC-4 for bins with a private member: `bun/private/npm_repositories.bzl` (about L490) gives
  `npm_bin` the members as `members = [Label(m) …]`, so Bazel checks the visibility of each member's
  `bun_library` from the hub, and a member at the default private visibility makes
  `:node_modules/<package>/bin/<bin>` fail analysis; the only fixture
  (`bun/tests/npm/fixtures/conformance_registry_to_workspace/packages/member-lib/BUILD.bazel`) is
  public. Add a test with a private member, red first; then make the bin link the member without
  requiring a visibility the consumer did not grant, or, if Bazel offers no supported way, fail with
  an English message naming the member target and the visibility to add, and state it in
  `_NPM_DOC` and spec BC-4; record green, per BC-4 / US1 (contradicts)
- [X] T090 `bun/private/resolve.bzl` (about L234 and L273) merges workspace-member links of the
  platform classes with `merged.members.update(...)` without the conflict check ordinary edges get
  (L231–L233): a member bound on only some classes applies on every platform, and an alias bound to a
  member on one class and a package on another is both, so `run.bzl` declares one
  `.store/<dir>/node_modules/<alias>` link twice. Add `bun/tests/npm/resolve_test.bzl` cases, red
  first, then treat member links per class as BC-12 treats edges (selected by platform, or the
  existing English error where R4 shows the pinned Bun cannot write the layout); record green, per
  BC-12 / FR-015 (contradicts)
- [X] T091 Research R10 (`research.md` about L570) says projects Bun 1.4.2 cannot write are listed
  (example: an unlinked workspace), but `bun/tests/npm/conformance/not_applicable_1_4_2.ts` is empty
  and `tdd-log.md` (about L110) records that 1.4.2 wrote `conformance_alias_workspace`. Establish
  with the 1.4.2 oracle which corpus projects 1.4.2 refuses or links differently; if some exist,
  list them with their reasons so US5 acceptance scenario 2 is exercised, otherwise correct R10 and
  state in `tdd-log.md` that no project is not applicable; per US5 / FR-014 (contradicts). Decided
  (the lead, under the user's delegation, 2026-11-21, research Part 6): no project is not
  applicable; correct R10, keep the committed lockfile, and settle the other one at T093
- [X] T092 `MODULE.bazel` L293–L294: move the comment "Excludes files that rules_bun renames, by their
  archive names (FR-033)" back above the `npm_renamed` tag it describes, below the inserted
  `npm_conformance_platform_peer` block (unrequested)

---

## Phase 18: Convergence

- [X] T093 Decided (the lead, under the user's delegation, 2026-11-21, research Part 6): keep the
  error as ID-7 and pin it with the Bun-written `4a5419e2` lockfile, committed as the fixture of the
  analysis test that today uses a hand-written one (`platform_entry_error_test`). Settle the
  Bun-written lockfile T091 found reaching the entry error: Bun 1.4.2 writes
  `conformance_platform_peer` in 5 of 6 runs as the `4a5419e2` lockfile (no `plat-peer-host/q` row),
  which Bun 1.4.4's and Bun 1.4.2's frozen isolated installs both accept, while the ruleset fails
  evaluation with `the store links "p" of plat-peer-host@1.0.0 to different packages on different
  platforms, which rules_bun cannot express` (`tdd-log.md` T091 rows). Research R4 "An entry's
  alias" ("No Bun-written lockfile reaching it was found") and `_NPM_DOC`'s Resolution paragraph in
  `bun/private/npm_extension.bzl` ("no lockfile the pinned Bun writes is known to reach either") no
  longer describe what a 1.4.2 consumer sees (US5). Then correct R4, `_NPM_DOC`, spec BC-12 /
  `contracts/public-api.md` to the outcome, and record it in `tdd-log.md` before T088, per US5 /
  BC-12 / FR-017 / Constitution II (contradicts)

---

## Phase 19: Second final review (2026-11-21)

The second Claude review before the final gate found these; the lead rejected the gate to fix them
(the lead, under the user's delegation, 2026-11-21, research Part 6). Each is written red first and
recorded in `tdd-log.md`.

- [X] T094 BC-4's member check counts only targets carrying the private `BunDeclaredTargetsInfo`
  (`bun/private/run.bzl` about L342–L344, `bun/private/library.bzl` about L51–L54), while
  `BunLibraryInfo` is public and a consumer's rule may return it (`bun/defs.bzl` about L70,
  `bun/private/providers.bzl` about L17–L19, `bun/tests/npm/layout_test.bzl` about L72): a member
  built by a consumer's rule, or such a rule between the program and the member, is not counted,
  and analysis asks to "add" a member already in `deps`; bins go through the same check (`run.bzl`
  about L536). Add analysis tests for both, red first; count every declared target that reaches the
  member's `BunLibraryInfo`; record green, per BC-4 / US1 scenario 4 (contradicts)
- [X] T095 The Bun 1.4.2 run takes its projects from `bun_1_4_2/` only
  (`bun/tests/npm/conformance/conformance.test.ts` about L118–L131): nothing checks that each
  `fixtures/conformance_*` project has a 1.4.2 lockfile or is listed in `NOT_APPLICABLE_1_4_2`, nor
  that a listed one has none. Fail the test on either, with an English message naming the project;
  show it red (a project without a 1.4.2 lockfile), then green, per US5 scenario 2 / FR-013
  (contradicts)
- [X] T096 BC-13 and BC-14 have no red record (`tdd-log.md` about L150: "green on the first run"),
  and no corpus project exercises them (every `libc` row has `os: linux`; no `["linux", "any"]`).
  Add tests that pin Bun's reading (`os: ["linux", "any"]` and its reverse; an optional package
  with `libc` on a darwin class), run them on `main`'s code in a worktree to record red, then green
  on the branch; add a corpus project for what the Linux host class can compare, per FR-015 /
  SC-003 (contradicts)
- [X] T097 `bun/private/npm_extension.bzl` (about L354–L358) takes a per-platform link's bins and
  fetch status from its first per-platform target, assuming all are one package. Write the
  reviewer's case red first (workspace `w` with peer `p: ^1`; the root's optional `p: 2.0.0`
  limited to darwin; `w`'s `p` is `p@2` on darwin and `p@1` elsewhere, through
  `write_lockfiles.ts`); if it reproduces, take bins and status per platform target (`select()`),
  otherwise record with Bun's lines why the pinned Bun cannot write it, per BC-12 (partial)
- [X] T098 `_NPM_DOC` (`bun/private/npm_extension.bzl` about L497) says the conformance test covers
  "every lockfile of rules_bun's tests", but `e2e/smoke/bun.lock` is not compared
  (`conformance.test.ts` about L74–L92). Compare it, or state exactly which lockfiles are
  compared, per Constitution II / FR-017 (contradicts)
- [X] T099 For a not-applicable project the test checks only that Bun refuses it
  (`conformance.test.ts` about L138–L141), not that the ruleset refuses it too, as the spec requires
  ("never link a graph for a lockfile Bun does not install"); `stale_link` passes only because its
  template is not valid JSON. Check the ruleset's refusal as well, red first with a lockfile Bun
  refuses that is valid JSON, per FR-004 / spec Edge Cases (partial)
- [X] T100 `scale_test` measures one platform class only: `resolve.bzl` (about L264–L268) builds the
  store once per class, and the scale fixture has no `os`, `cpu` or `libc`. Add a scale variant
  with platform-specific packages (an esbuild-like set of about 20 per-platform optional packages
  under many dependents) so every class builds its store, keep the 10 s bound (plan R13), and
  record the times in `tdd-log.md`, per SC / plan R13 (partial)
- [X] T101 Codex's branch review (high): `bun/private/resolve.bzl` (about L275–L280) keeps an edge
  when any platform class has it, so platform conditions on edges are lost. Example: root
  dependencies `a` and `b`, `a` optionally depending on `b`, `b` declaring `libc: ["musl"]`; on
  glibc the carried-over store omits `a → b` but keeps the root's required `root → b`; after the
  merge `a`'s edges hold `b`, and `run.bzl` (about L407–L414) links it whenever `b` is among the
  target's instances, so declaring `b` changes what `a` sees, against the graph equality. The
  conformance graph (`bun/tests/npm/conformance/graph.bzl` about L103) hides it by requiring both
  ends in one link's closure, while a run combines closures. Write the glibc regression red first
  (an analysis or integration test combining `a` and `b`), make the conformance graph reflect the
  combined closure a run sees, then carry each edge's platform classes and select edges for the
  target platform before layout (as BC-12 selects roots); record green, per P1 / FR-008 / BC-12
  (contradicts)

---

## Phase 20: Convergence

- [X] T102 Bring spec "Behavior Changes" BC-12 and "Intentional Differences" ID-7 in line with the
  outcome of T090 and T097, which `contracts/public-api.md` ("Diagnostics added") and research R4
  ("A holder's alias", "A member link") already state: BC-12 selects by target platform an alias of
  the root or a workspace that the store binds to different store entries of one package (other
  peer bindings), while `bun/private/resolve.bzl` (about L362–L368, T097) fails evaluation where
  those roots are different packages and `class_member_conflict` (T090) fails it where a
  workspace-member link differs by platform class, neither reached by a lockfile Bun writes. Today
  BC-12 says "different packages … is linked per target platform" and ID-7's "(not of the root or a
  workspace, which BC-12 links per platform)" says the same, so the spec lists neither failure. State
  both in the spec with R4's reason, per spec P3 / BC-12 / FR-015 (contradicts)

---

## Phase 21: Convergence

- [X] T103 CRITICAL: compare `bun/tests/npm/scale/platform/` (T100's variant, whose `bun.lock` the
  pinned Bun writes through `bun/tests/npm/scale/generate.ts --platform` and `scale_test` resolves
  across 22 platform classes) in `conformance_test`. `_NPM_DOC`'s Resolution paragraph
  (`bun/private/npm_extension.bzl`: "for every `bun.lock` under … `bun/tests/npm/scale/`") and
  `bun/tests/npm/fixture_results.bzl`'s docstring claim it is compared, but `_projects` adds only
  `bun/tests/npm/scale`. Add the project to `_projects`, serve its archives with
  `writeArchives(dir, true)` in `bun/tests/npm/conformance/conformance.test.ts` `archivesFor`, add
  its files to the test's `data`, and record the run in `tdd-log.md` (a difference no BC explains:
  stop and report), per spec P2 / Constitution II / FR-017 (contradicts)
- [X] T104 In `bun_binary`'s doc (`bun/private/run.bzl` L95), change "That paragraph names where
  rules_bun links differently on purpose (ID-1 to ID-6)" to ID-1 to ID-7, as `_NPM_DOC`'s
  Resolution paragraph has listed ID-7 since T093, per FR-017 / spec Intentional Differences
  (partial)
- [X] T105 Bring `plan.md`'s Constitution Check row VII ("BC-1…BC-12 change no released behavior",
  L86) and "Phases after this plan" step 1 ("Q1 must fail exactly with BC-1…BC-14", L147) to
  BC-1…BC-15, as its Summary (L34) and the spec state, per spec Behavior Changes / FR-017 (partial)
- [X] T106 In T066's PR body, give each Behavior Change the test that showed it before and after
  (spec "Behavior Changes": "listed again in the PR with the test that shows it"), not only T017 and
  T051 rows: BC-1…BC-10 their T017 red and T051 "difference gone" rows; BC-11 and BC-12 T076's and
  T077's red rows and their T051 rows; BC-13 and BC-14 T096's red on `main` and green on the branch
  (`platform_rule_test.bzl`, `conformance_platform_rule`); BC-15 T101's red and green
  `conformance_test` rows, per spec Behavior Changes / SC-003 (partial)

---

## Phase 21: Third final review (2026-11-21)

The third Claude review before the final gate found these; the lead rejected the gate to fix them
(the lead, under the user's delegation, 2026-11-21, research Part 6). Its finding that `_NPM_DOC`
names CI runners before a CI run is left to T067: the PR merges only once that run passes. Each is
written red first and recorded in `tdd-log.md`.

- [X] T107 ID-7 describes another case than the one rejected: `bun/private/resolve.bzl` (about
  L301–L302) fails any package dependency whose store entry differs by platform class, including
  one package under different peer bindings, and its only known trigger (`id_7`,
  `bun/tests/npm/resolve_test.bzl` about L306–L311) is `p@1.0.0` with peer `q` on darwin and
  without it elsewhere, one package, while the error, spec ID-7 and `_NPM_DOC` (about L527–L532)
  say "different packages … cannot express". BC-12 links that case per platform for the root and
  workspaces, and `_edge_fields` already selects package edges by platform (BC-15). Express a
  package dependency whose entry differs by platform class through the same per-platform selection
  (red first with the `4a5419e2` lockfile), and keep an error only for what still cannot be
  expressed; bring the error text, spec ID-7 (or remove it and list the change as a BC), research
  R4, `_NPM_DOC` and `contracts/public-api.md` to the outcome, per P1 / P3 (contradicts)
- [X] T108 Two canaries name readers that moved: `bun/tests/canary/npm/c_peers.test.ts` (about L9,
  "the peer rules in bun/private/resolve.bzl", now in `bun_lockfile.bzl` / `bun_isolated_store.bzl`)
  and `bun/tests/canary/npm/c_keypath.test.ts` (about L9, "the key walk in bun/private/resolve.bzl",
  now `_find_resolution` in `bun_lockfile.bzl`). Name the current readers; check every canary's
  `canaryFail` text against the reader it protects, per US4 scenario 1 (contradicts)
- [X] T109 The not-applicable check accepts any failure: `bun/tests/npm/conformance/conformance.test.ts`
  (about L171) uses `rejects.toThrow()` (a missing archive, a port conflict or a registry error
  pass), and the ruleset side (about L173–L175) accepts any `error`. Assert Bun's loader refusal
  by its message and the ruleset's by the English error that names the `bun.lock` label; show red
  with a project whose install fails for another reason, per spec Edge Cases / FR-004 (partial)
- [X] T110 `bun/tests/npm/platform_rule_raw/bun.lock` (BC-13's hand-written lockfile, resolved by
  `bun/tests/npm/fixture_results.bzl` about L52) is outside every directory the conformance test
  scans, so its `["linux", "any"]` claim is checked only against the ruleset's own reading. Compare
  it with the pinned Bun (add it to the scanned projects, or move it under the corpus), or record
  why Bun cannot install it and list it as not applicable, per P2 (partial)

---

## Phase 22: Fourth final review (2026-11-21)

The fourth Claude review before the final gate found these; the lead rejected the gate to fix them
(the lead, under the user's delegation, 2026-11-21, research Part 6). Each is written red first and
recorded in `tdd-log.md`.

- [X] T111 CRITICAL: a declared dependency the store links on no platform class gets no
  `:node_modules/<package>` target (`bun/private/resolve.bzl` about L366–L394 builds links only from
  the store's holder edges), against the naming rule (`bun/private/npm_extension.bzl` about
  L468–L470: one target "for each package that workspace package declares"), P4, FR-014 and SC-005.
  `main` generated the target; on the branch `deps = ["//:node_modules/x"]` fails with "no such
  target" for: a root or workspace optional dependency matching no platform the hub selects on
  (`os: ["sunos"]`, `cpu: ["ppc64"]`), a non-optional dependency BC-7 disables everywhere, an
  optional dependency under `unresolved` (BC-1, `conformance_unresolved` `packages/w` → `q`), and
  the BC-3 and BC-5 cases. Write analysis tests red first (each case: the target exists and carries
  nothing where Bun links nothing), then generate the target for every declared dependency, empty
  on the platform classes where the store links nothing, as `main`'s empty optional targets are;
  check every generated target name of `main` against the branch for the fixtures (SC-005), per
  P4 / FR-014 / SC-005 (contradicts)
- [X] T112 A package restricted to an `os` or `cpu` Bun does not name (`cpu: ["riscv64"]`,
  `@esbuild/linux-riscv64`; `os: ["netbsd"]`) is disabled on every class, including a
  linux/riscv64 or netbsd target: `bun/private/bun_install_types.bzl` (about L358) maps such a
  target value to `_UNNAMED`, and about L394–L398 read such a package value as matching nothing,
  while `NPM_CPU` / `NPM_OS` (`bun/private/platforms.bzl` about L22, L31) still map them and
  research (about L165) records npm's rule for these values, as on `main`'s `check_list`. Write
  `bun/tests/npm/platforms_test.bzl` cases red first, then match a package value Bun does not name
  as npm's rule does on the target that names it; align `_NPM_DOC`'s list of values that match no
  platform, per research R3 / FR-015 (contradicts)
- [X] T113 `e2e/smoke/bun.lock` is resolved by the ruleset's tests but not compared with the pinned
  Bun (search roots in `bun/tests/npm/conformance/conformance.test.ts` about L93 and
  `bun/tests/npm/fixture_results.bzl` `_projects`; the exclusion stated at `_NPM_DOC` about L503),
  against spec P2 ("every project the ruleset's tests resolve"). Compare it (a copy or a reference
  the root module's tests can read), or record in the spec why it cannot be and narrow P2's
  wording, per P2 (partial)

---

## Phase 23: Convergence

- [X] T114 In T066's PR body, also give the tests that showed each change found after T106 was
  written: BC-16 its T107 rows (red on `main`'s resolver in a worktree with the `4a5419e2`
  lockfile; green `resolve`, `platforms`, `graph` and `conformance_test`); BC-13's extension to
  `netbsd` and `riscv64` its T112 rows (`platforms_bun_rule_test` red and green); the kept
  `:node_modules/<package>` target of a declared dependency the store links on no platform its
  T111 rows (`declared_test.bzl` red and green, and the SC-005 comparison of `main`'s names); and
  `scale_test`'s time for T100's platform variant next to T005's and T052's. T106 lists only
  BC-1…BC-15, per spec "Behavior Changes" / SC-003 / FR-015 (partial)
- [X] T115 Cite Bun's lines in, or state that it is the adapter (research R3, ID-2) in, the docstring
  of `_npm_only` in `bun/private/platforms.bzl` (T112: the bits for `netbsd` and `riscv64` that
  `platform_bits` and `package_platforms` read), and add it to `ONLY.platforms` in
  `bun/tests/npm/conformance/citations.test.ts`, which skips it today; record the
  `citations_test` run in `tdd-log.md`, per FR-002 / SC-004 (partial)
- [X] T116 Bring the design documents and `_NPM_DOC` to the code: `data-model.md` "Ruleset output"
  ("unchanged shape") names a link `struct(alias, root, closure, optional)`, while
  `bun/private/resolve.bzl` `resolve` returns `struct(alias, root, roots, closure, optional, key)`
  (`roots`: BC-12; `key` and the empty link of a dependency the store links nowhere: T111) and
  instances with `peer_hash` (BC-11), `members` (BC-4) and `unfetched` (ID-4);
  `contracts/conformance-graph.md` "Projects" and `quickstart.md` Q1 omit `e2e/smoke` (T113), Q1
  also `bun/tests/npm/conformance/refused/`, and the contract's "Oracle files" row omits the
  archives served to `e2e/smoke` (`bun/tests/npm/fixtures/jsx/archives`) and to the scale projects
  (`writeArchives`); `_NPM_DOC`'s list of compared directories in `bun/private/npm_extension.bzl`
  omits `refused/`, where the ruleset's refusal of `patch_path` is checked, per plan (data model,
  contracts) / FR-017 (partial)

---

## Phase 24: Convergence

- [X] T117 CRITICAL: test and document BC-7's effect on bins. Since BC-7, a declared non-optional
  package whose `os` or `cpu` exclude some target platforms is a link whose root the hub selects
  by platform, so `_compatible` (`bun/private/npm_repositories.bzl` about L471–L489) makes its
  `:node_modules/<package>/bin/<bin>` incompatible there; on `main` the root was in `closure` and
  the bin compatible with every platform. No test covers it (`bun/tests/integration/restricted.test.ts`
  covers optional packages only, `bun/tests/npm/declared_test.bzl` only packages no platform
  matches), and `_NPM_DOC` in `bun/private/npm_extension.bzl` ("The bins of a declared optional
  package with `os`, `cpu` or `libc` are compatible only with the platforms it matches") and the
  BC-7 row of `contracts/public-api.md` state it for optional packages only. Write an analysis test
  (a declared non-optional package with `os` or `cpu` and a `bin`, through `pack.ts` and
  `write_lockfiles.ts`: its bin incompatible on an excluded platform, buildable on a matched one),
  run it on `main`'s code in a worktree to record red, then green on the branch, recorded in
  `tdd-log.md`; state the rule for non-optional packages in `_NPM_DOC` and the BC-7 row, per
  Constitution II / BC-7 / FR-017 (partial)
- [X] T118 Complete research Part 2's "Function-level map (T055)" in
  `specs/006-bun-conformant-resolution/research.md`, which says it lists each function of the
  rebuilt resolver as its docstring cites it: add `platforms.bzl` `platform_tuples`,
  `platform_bits` (`src/install/PackageManager/PackageManagerOptions.rs` L1174–L1176),
  `platform_classes` (`src/install/lockfile/Package/Meta.rs` L70–L74), `package_platforms`,
  `npm_only_names`, `_npm_only`, `_check_list`, and `resolve.bzl` `_hex16`, `_declared_key`,
  `_differing_member`, `class_member_conflict`, `_mask`, `_conditions`; give `_ids` its citations
  (Store.rs L450–L466, ISO L1353–L1386) instead of "the adapter", and narrow the "Not carried
  over" row `peer_hash` (ISO L1353–L1386, "directory names only") to what `_ids` does not carry
  (Bun's Wyhash, a tarball's integrity, ID-4); in "Walks outside the carry-over" make `run.bzl`
  `_check_unique` read one copy per store directory (BC-11). Check the map against every `def`
  `citations_test` checks (none missing, none extra), per US3/AC2 / SC-004 / FR-002 (partial)

---

## Phase 25: Convergence

- [X] T119 In T066's PR body, also give BC-7's effect on bins, found after T106 and T114 were
  written, its T117 rows: `//bun/tests/integration:restricted_test` red on `main`'s code in a
  worktree (`//:node_modules/bin-darwin/bin/dbin` builds for `//:linux_x64`) and green on the
  branch (incompatible on `//:linux_x64`, buildable on `//:darwin_arm64`), next to BC-7's T017 and
  T051 rows, per spec "Behavior Changes" (BC-7: "bins: T117") / SC-003 (partial)
- [X] T120 Bring the docstring of `_compatible` in `bun/private/npm_repositories.bzl` (about
  L472–L476, "A declared optional package with `os`, `cpu` or `libc` is absent elsewhere") to
  BC-7 as T117 stated it in `_NPM_DOC`: a declared package with `os` or `cpu`, optional or not, and
  a declared optional package with `libc`, per BC-7 / FR-017 (partial)
- [X] T121 Bring quickstart Q6 to the check that holds: it names only `bun/private/bun_*.bzl` and
  expects `grep -c "@ bun-v1.4.4"` to give one per `def` (today 67 citations for 53 `def`s in
  `bun_install_types.bzl`, 63 for 54 in `bun_lockfile.bzl`), while `citations.test.ts` checks every
  `def` of `bun_*.bzl` and `resolve.bzl` and `ONLY.platforms` of `platforms.bzl`, where a function
  may state that it is the adapter; give `bazel test //bun/tests/npm/conformance:citations_test`
  and its expected output (`204 functions checked in 7 modules`), per plan (quickstart) / US3 /
  SC-004 (partial)

---

## Phase 26: Convergence

- [X] T122 Bring quickstart Q7 to SC-005 and the check T111 made: its expected result ("names of
  `:node_modules/...` targets are equal for every project without a BC; differences are only those
  the BCs list") lets a Behavior Change remove or rename a target, while spec P4, FR-014, SC-005 and
  `contracts/public-api.md` ("adds, removes and renames nothing") allow none, and since T111 every
  declared dependency keeps its target. State that every `:node_modules/...` name of `main` exists
  on the branch for every project, the branch only adding names (new fixtures and packages, and hubs
  whose evaluation fails on `main`, BC-3), and give T111's procedure (a worktree of `main` with the
  new fixtures, their hubs, `files.bzl` and archives copied in; `bazel query '//bun/tests/...' |
  grep ':node_modules/'` on both; `diff` shows only `>` lines), per plan (quickstart) / SC-005
  (partial)

---

## Phase 26: Fifth final review (2026-11-21)

The fifth review before the final gate (Claude and Codex, branch-wide) found these; the lead
rejected the gate to fix them (the lead, under the user's delegation, 2026-11-21). Each is written
red first and recorded in `tdd-log.md`.

- [X] T123 Codex: a bin's workspace members are collected across the first workspace boundary only
  (`bun/private/npm_repositories.bzl` about L428–L429): for `cli → W1 → helper → W2` (W1 declares
  the registry package `helper`, which depends on member W2) only W1 is collected, so
  `_member_links` fails for W2 and the bin has no `deps` to supply it. Add the bin integration test
  red first, then collect members to a fixed point across package and member links, per BC-4
  (contradicts)
- [X] T124 Codex: the member aspect (`bun/private/library.bzl` about L43–L54) collects member labels
  through every attribute, including `data` and tools, without checking that the member's
  `BunLibraryInfo` reaches the program, so a member reached only through a wrapper's `data` passes
  the declaration check while its `package.json` and npm dependencies are missing from the copy
  tree. Add the regression red first, then count a member only where its `BunLibraryInfo` is
  carried into the layout, else fail with the existing "add … to its deps" message, per BC-4
  (contradicts)
- [X] T125 `bun/private/lockfile.bzl` (about L211) does not check `configVersion` (a number, Bun
  LOCK L1861–L1869) or `trustedDependencies` (an array of strings, L1871–L1888), which Bun refuses
  ("failed to parse lockfile"), so the ruleset links a graph for a lockfile Bun does not install.
  Add `lockfile_test.bzl` cases red first and fail naming the `bun.lock` label and the field;
  update research Part 4's refusal inventory (about L811–L833), per FR-004 / spec Edge Cases
  (contradicts)
- [X] T126 `_NPM_DOC` (`bun/private/npm_extension.bzl` about L509–L513) names `ubuntu-latest`,
  `macos-latest` and `windows-latest` before any CI run; every recorded run is Linux x64 (WSL).
  Name only where the test ran and state the rest as unverified until T067 fills it from the PR's
  CI run, per Constitution II / FR-017 (contradicts)
- [X] T127 `bun/tests/npm/conformance/graph.ts` (about L132, L185) gives every entry of a name the
  same label once any entry of it has a non-registry version, so a wrong link between a `file:`
  `foo` and registry `foo@1.0.0` entries compares equal. Add a `graph_test_ts` case red first
  (the root's `foo: "file:./vendor/foo"`, two dependents of `foo@1.0.0`, one misbound), then label
  each entry by its own resolution, per P2 / FR-008 (contradicts)
- [X] T128 `bun/tests/npm/conformance/citations.test.ts` (about L67) checks top-level `def`s only;
  18 nested functions (`resolve.bzl` about L392 `conditions`, `bun_isolated_store.bzl` about L236
  `resolve_up`, `bun_tree.bzl`, `bun_lockfile.bzl` …) are neither counted nor checked. Show red,
  then check nested functions (citing Bun's lines or marked as the adapter) and fill research Part
  2's map, per FR-002 / SC-004 (partial)
- [X] T129 `bun/private/BUILD.bazel`: `:resolve` (about L78–L87) lacks `:lockfile`, which
  `resolve.bzl` loads, and `:bun_lockfile` (about L163–L169) lacks `:platforms`, which
  `bun_lockfile.bzl` loads; add them and check every `bzl_library` against its file's `load`s
  (unrequested)

---

## Phase 27: Convergence

- [X] T130 CRITICAL: pin by canary the two `bun.lock` fields T125 made the ruleset read.
  `read_lockfile` in `bun/private/lockfile.bzl` (about L209–L219) now reads the values of
  `configVersion` and `trustedDependencies` to refuse a form Bun refuses, but neither field is in
  the format material bun.com links (feature 003 research: the blog post names `lockfileVersion`,
  `workspaces` and `packages` only), no canary in `bun/tests/canary/npm` pins the form the pinned
  Bun writes, and research Part 4's closed list (about L796–L797) still says each "decides no
  binding" without an access ID. Add a canary through `support.ts` that asserts the pinned Bun
  writes `configVersion` as a whole number ≥ 0 and `trustedDependencies` as an array of strings,
  names `read_lockfile in bun/private/lockfile.bzl`, and has a red mode; give both an access row
  in Part 4 with the writer lines (LOCK L373, L510–L527), the reader lines and the evidence; record
  red and green in `tdd-log.md`, per Constitution V / FR-005 / FR-006 (contradicts)
- [X] T131 Cover the rest of `_bin_members`' walk (`bun/private/npm_repositories.bzl` about
  L365–L420, T123): `bins_test`'s T123 case reaches one member through another member's package
  (`chain-w1` → `chain-helper` → `chain-w2`), but no test reaches a member through a member's
  `workspace:` link (the Bazel package `_member_edges` adds for it) or through more than one
  further member, while `_NPM_DOC`, spec BC-4 and the BC-4 row of `contracts/public-api.md` state
  "through any number of members". Add a case (a member that declares another by `workspace:`,
  whose package links a third member), red first with `_member_edges` ignoring `workspace:` links,
  then green; or narrow the three statements to what the test covers, per BC-4 / FR-017 (partial)
- [X] T132 Bring the T124 statements to `declared_targets_aspect` and test the attributes they
  name: `_FILE_ATTRIBUTES` (`bun/private/library.bzl` about L41–L44) skips `srcs`, `data`,
  `tools`, `entry_point` and `preload`, while `_NPM_DOC` (`bun/private/npm_extension.bzl` about
  L478–L480), spec BC-4 and the BC-4 row of `contracts/public-api.md` name `srcs`, `data` and
  `tools` only, and `bun/tests/npm/workspace_member_test.bzl` covers `data` (`through_data`) and a
  target without `BunLibraryInfo` (`through_carrier`) only. Name all five in the three statements,
  and add `workspace_member_test` cases for a member reached through `srcs`, `entry_point` and
  `preload` (and `tools` through a rule in `bun/tests/npm/consumer_rules.bzl`), each failing with
  the "add … to its deps" message, per BC-4 / FR-017 (partial)
- [X] T133 In T066's PR body, also give BC-4's extensions found after T106, T114 and T119 were
  written, their T123 and T124 rows: `//bun/tests/integration:bins_test`'s T123 case red ("the hub
  gives the bin `chain-w1` only") and green, with `conformance_member_chain` compared in both
  conformance runs; `//bun/tests/npm:workspace_member` `through_data` and `through_carrier` red
  and green; next to BC-4's T017 and T051 rows, per spec "Behavior Changes" (BC-4: T123, T124) /
  SC-003 (partial)
- [X] T134 Add T125's refusals to `contracts/public-api.md` "Diagnostics added": a `configVersion`
  that is not a whole number ≥ 0 and a `trustedDependencies` that is not an array of strings, each
  naming the `bun.lock` label and the field without its value, next to T079's and T080's, per plan
  (contracts) / FR-004 (partial)

---

## Phase 28: Convergence

- [X] T135 Run the unsandboxed gate on the final code, `bazel test //... --noenable_runfiles
  --spawn_strategy=local --keep_going` in the root: T130–T132 added `c_rootfields_test`, a
  `bins_test` case, four `workspace_member` cases and the corpus project
  `conformance_member_workspace_chain` that `conformance_test` compares, and T130–T134's gate rows
  in `tdd-log.md` record the sandboxed `bazel test //...` only (the last unsandboxed row is
  T123–T129's); record the run in `tdd-log.md`; report a failure, do not widen the task (AGENTS.md),
  per FR-018 / SC-006 (partial)
- [X] T136 Complete research R11's corpus table in `specs/006-bun-conformant-resolution/research.md`:
  it lists 11 of the 22 `bun/tests/npm/fixtures/conformance_*` projects. Add a row (layout, the BC
  or edge case it exercises, the task that added it) for `conformance_bundled` (BC-10, T006),
  `conformance_unfetched` (BC-8, T069), `conformance_unresolved_peer` (spec Edge Cases, T074),
  `conformance_platform_peer` and `conformance_platform_peer_workspace` (BC-12, T077),
  `conformance_platform_root_package` (T097), `conformance_platform_rule` (BC-13, BC-14, T096),
  `conformance_platform_edge` (BC-15, T101), `conformance_declared_nowhere` (T111),
  `conformance_member_chain` (BC-4, T123) and `conformance_member_workspace_chain` (BC-4, T131),
  each checked against its `write_lockfiles.ts` entry, per plan (research R11) / FR-009 (partial)

---

## Phase 29: Convergence

- [X] T137 In T066's PR body, give every test change `tdd-log.md` records as "FR-016 change", not
  only T048's: also T039's (`bun/tests/npm/lockfile_test.bzl` `kinds_test`, BC-8), T076's
  (`bun/tests/npm/uniqueness_test.bzl` `peer`, `peer_chain`, BC-11) and T077's
  (`bun/tests/npm/resolve_test.bzl` `platform_holder_error_test`, now `platform_holder_test`,
  BC-12), each with the BC it follows; T066 names "the FR-016 list of changed tests (T048)" only,
  per FR-016 (partial)
- [X] T138 In T066's PR body, also give the BC-4 tests T131 and T132 added after T133 was written,
  next to T133's rows: `//bun/tests/integration:bins_test`'s T131 case (red with `_member_edges`
  ignoring `workspace:` links, green restored) and `conformance_member_workspace_chain` compared in
  both conformance runs, which show "through any number of members"; and
  `//bun/tests/npm:workspace_member` `through_srcs`, `through_entry_point`, `through_preload` and
  `through_tools` (red with `_FILE_ATTRIBUTES` set to `["data"]`, green restored), which spec BC-4
  cites as T132, per spec "Behavior Changes" (BC-4) / SC-003 (partial)

---

## Phase 28: Sixth final review (2026-11-21)

The sixth review before the final gate (Claude and Codex, branch-wide) found these; the lead
rejected the gate to fix them (the lead, under the user's delegation, 2026-11-21). Each is written
red first and recorded in `tdd-log.md`.

- [X] T139 `bun/private/lockfile.bzl` reads JSON `null` as a missing field: for dependency maps,
  `optionalPeers`, `unresolved`, a workspace's `version`, `configVersion` and
  `trustedDependencies` it loads a lockfile Bun refuses, and for `overrides`, `catalog`,
  `catalogs`, `patchedDependencies` and `packages` evaluation crashes with a bare Starlark error
  (`in dict, got NoneType`) naming no file. Add `lockfile_test.bzl` cases red first (each field
  set to `null`, checked against the pinned Bun's refusal), then tell a present `null` from an
  absent key and fail naming the `bun.lock` label and the field, per FR-004 / spec Edge Cases
  (contradicts)
- [X] T140 Codex: the member check still accepts a member whose files never reach the program
  (`bun/private/library.bzl` about L59–L64): it assumes a target returning `BunLibraryInfo`
  forwards every dependency outside the excluded attributes, but `consumer_library(extras =
  [member])` returns none of the member's files, so a `bun_test` on that wrapper and
  `node_modules/member-user` passes `_member_links` and gets a link to an uncopied directory. Add
  that negative test red first, then accept a member only where its files and package record are
  actually in the layout the run rule builds (from what `BunLibraryInfo` carries, not from which
  attributes an aspect walks), else fail with the existing "add … to its deps" message; keep
  T123/T124's tests green, per BC-4 (contradicts)
- [X] T141 `bun/tests/npm/fixtures/dependency_conflict/BUILD.bazel` and a comment in
  `bun/tests/npm/registry/write_lockfiles.ts` still say the ruleset must reject that lockfile;
  since BC-6 it accepts it (`uniqueness_test.bzl`). Correct both comments (unrequested)

---

## Phase 30: Convergence

- [X] T142 In T066's PR body, also give the tests of the spec's "Behavior Changes" that no PR-body
  task names yet (T066, T106, T114, T119, T133, T137, T138), each with its `tdd-log.md` rows next to
  its BC: BC-4 T081 (`//bun/tests/npm:workspace_member` `bin_test` red and green,
  `//bun/tests/integration:bins_test`), T089 (`bins_test` "a bin whose member is not visible to the
  linking package fails with Bazel's visibility error") and T140 (`workspace_member`
  `through_extras` red and green); BC-12 T090 (`//bun/tests/npm:resolve` `platform_member_test`,
  red with `class_member_conflict` stubbed) and T097 (`platform_root_package_test`,
  `conformance_platform_root_package`); BC-13 T110 (`platform_rule_raw` under
  `bun/tests/npm/conformance/accepted/`, compared with both oracles). Then check that every task ID
  the spec's "Behavior Changes" cites has its rows in the body, per spec "Behavior Changes" ("listed
  again in the PR with the test that shows it") / SC-003 (partial)

---

## Phase 31: Convergence

- [X] T143 Bring spec P2 ("For every project the ruleset's tests resolve, the pinned Bun installs
  the same lockfile") and research R9 "Coverage" to the projects the conformance test compares: the
  inner workspaces that `bun/tests/integration/conflict.test.ts`, `registries.test.ts`,
  `credentials.test.ts`, `rename.test.ts` and `lockfile_errors.test.ts` write with hand-written
  `bun.lock` texts (two entries of one `name@version`, per-test registries, credentials, renamed
  files, refusals) are resolved by the ruleset's tests, but neither conformance run compares them and
  R9 neither lists nor excludes them. Compare those Bun installs, or record each in R9 with the
  reason it is not compared and narrow P2's wording to R9's projects, as T113 settled `e2e/smoke`,
  per spec P2 / FR-009 (partial)

---

## Phase 31: Seventh final review (2026-11-22)

The seventh Claude review before the final gate found these; the lead rejected the gate, fixed the
spec and research text directly (US5 scenario 2 and the 1.4.2 assumption, the Intentional
Differences ID-8 and ID-9, research Part 4's split table) and left the rest here (the lead, under the user's delegation, 2026-11-22).
`_NPM_DOC`'s runner labels stay with T067. Each is written red first and recorded in
`tdd-log.md`.

- [ ] T144 `bun/private/lockfile.bzl` (about L113) crashes evaluation with a bare Starlark error
  (`dict(value)`) when a row's `bin` is neither `null`, a string nor an object (`5`, `["x"]`),
  while research Part 4 (about L926–L928) records that Bun skips such a value and loads the
  lockfile. Confirm Bun's reading against `Bin.rs` at `bun-v1.4.4` and the pinned Bun, add
  `lockfile_test.bzl` cases red first, then read such a `bin` as Bun does (cited), per FR-004 /
  spec Edge Cases (contradicts)
- [ ] T145 Bring the docs to ID-1…ID-9 (ID-7 withdrawn): `plan.md`, `data-model.md`,
  `quickstart.md`, `contracts/public-api.md`, `contracts/conformance-graph.md`, `_NPM_DOC` and
  `bun_binary`'s doc in `bun/private/run.bzl` name ID-8 (declared workspace members, BC-4) and
  ID-9 (BC-12's two evaluation failures) where they list the Intentional Differences, and T066's PR
  body lists them, per P3 / Constitution II (partial)
