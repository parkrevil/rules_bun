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
  queue, and exhausting `_LIMIT` returns an English error naming the stage, as `resolve.bzl` does
  on `main`.
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
- [ ] T018 [US2] Make `RULES_BUN_CONFORMANCE_RED=1` redirect one edge of `basic` (a project with no
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
- [ ] T051 [US1] Run `bazel test //bun/tests/npm/conformance:conformance_test --test_output=errors`
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
- [ ] T054 [US3] Re-read every cited range in `SRC` against its Starlark function (same steps, same
  order); correct any citation or carry-over that differs, then re-run T051's conformance test;
  record the review in `tdd-log.md` (one row per `bun/private/bun_*.bzl` file)
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
- [ ] T060 [US5] Run Q4 on Linux and record the result per project; `conformance_test` must stay
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

- [ ] T062 [P] Rewrite the resolution part of `_NPM_DOC` in `bun/private/npm_extension.bzl`
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
- [ ] T065 Completion gates (Q8, FR-018): in the root `bazel run //:gazelle`,
  `prek run --all-files`, `bazel test //...`, `bazel test //... --noenable_runfiles
  --spawn_strategy=local`; in `e2e/smoke/` `bazel test //...`; record each; report a failure, do not
  widen the task (AGENTS.md)
- [ ] T066 Commit the remaining work, push `006-bun-conformant-resolution` and open one PR to `main`
  with `gh pr create`: the BC table of `contracts/public-api.md`, each BC with its T017 difference
  and its T051 "difference gone" row, the FR-016 list of changed tests (T048), the Intentional
  Differences, `scale_test` times on `main` and on the branch (T005, T052), and the 1.4.2 results
  per platform (T060); end the body with the attribution line the session specifies
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
- [ ] T076 Ask the user to decide how to treat a target that reaches two store entries of one
  `name@version` with different peer bindings. Bun's isolated install links both (spec Edge Cases;
  `conformance_peer_contexts`: `p@1.0.0` with the root's `q@1.0.0` and through `q2-user` with
  `q@2.0.0`), but `bun/private/run.bzl` `_check_unique` fails analysis of such a target ("a target
  holds one instance of each package version"), and `bun/tests/npm/uniqueness_test.bzl`
  `_peer_test` and `_peer_chain_test` assert that failure. `bun/tests/npm/conformance/graph.bzl`
  does not model it, so `conformance_test` cannot see it. Before anything changes, make the
  conformance test report it: a `graph_test` / `graph_test_ts` case, red first, for a holder whose
  links reach two entries of one `name@version`, recorded red in `tdd-log.md`. Then, as the user
  decides, either list it as a new Intentional Difference (spec, the Exclusions of
  `contracts/conformance-graph.md`, `data-model.md`, `quickstart.md` Q1, `conformance.test.ts`'s
  "excluded by name" line, `_NPM_DOC`), or lay out each entry by its peer bindings in `run.bzl` and
  change the two tests as FR-016 changes; record green, per spec P3 / FR-016 / US1 (contradicts)
- [ ] T077 Settle the adapter's two failures that neither the spec lists nor a test covers:
  `bun/private/resolve.bzl` "the store links \"<alias>\" of <package> to different packages on
  different platforms" and "\"<alias>\" of the workspace \"<path>\" links different packages on
  different platforms, which rules_bun cannot express". Determine from Bun's cited lines (S7, S8)
  whether the pinned Bun can write a lockfile whose store binds one alias of an entry or holder
  to different packages on different platform classes. If it can, add a corpus project through
  `bun/tests/npm/registry/write_lockfiles.ts` with a `check`, record its difference red, and either
  express it (a per-class binding the hub turns into `select()`) or stop and report so the user can
  list it as an Intentional Difference. If it cannot, record why in research R4 with the Bun
  lines. In either case add a `bun/tests/npm/resolve_test.bzl` case for each error path, per spec
  P3 / FR-015 / Constitution II (partial)
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

- [ ] T078 CRITICAL: make the documentation claim only what `conformance_test` passes on. Today
  `_NPM_DOC`'s Resolution paragraph in `bun/private/npm_extension.bzl` ("the hub links what the
  pinned Bun 1.4.4's isolated install links … a package reached under different peers is one
  package per set of peers") and `bun_binary`'s doc in `bun/private/run.bzl` ("Peers resolve as the
  pinned Bun's isolated install resolves them") hold unconditionally, while `conformance_test`
  reports T076's layouts (`basic`, `conformance_peer_contexts`, `integration/workspaces/fetch`: one
  target reaching two entries of `p@1.0.0` fails analysis) and T077's (`conformance_platform_peer`,
  `conformance_platform_peer_workspace`: evaluation fails, "rules_bun cannot express"). After the
  user decides T076 and T077, and before T065: name in both docs each layout left as an Intentional
  Difference by its ID with the diagnostic a consumer sees, keep the unconditional claim only for
  layouts Q1 shows conformant, and confirm with a green Q1 run recorded in `tdd-log.md`, per
  Constitution II / FR-017 (contradicts)
- [ ] T079 Complete T040's inventory in research Part 4: every refusal of Bun's loader at
  `bun-v1.4.4`, LOCK L1797–L3543 (the 48 `fail!` sites from L1819 "Missing lockfile version" to
  L2710 "Invalid git dependency tag", `UnknownLockfileVersion` L1855, `UnexpectedResolution` L2427,
  `InvalidPackageInfo` L2536 and L2888, `InvalidPackagesObject` L2933, `parse_append_dependencies`'
  refusals, `dependency_resolution_failure` L2843, L2908, L3010), each with its line and either the
  `bun/tests/npm/bun_lockfile_test.bzl` / `lockfile_test.bzl` /
  `bun/tests/integration/lockfile_errors.test.ts` case where the ruleset fails evaluation naming the
  `bun.lock` label and the key or field (written red first), or the reason no supported Bun writes
  it. Settle L2667 explicitly ("Missing integrity hash for npm package resolved to a tarball URL
  outside the configured registry", lockfile v2+): the ruleset now treats such a row as ID-4 (fails
  analysis of a target that needs it) where Bun refuses the lockfile; follow Bun's
  `npm_url_needs_integrity` lines, or stop and report if the configured registry cannot be known from
  what the ruleset reads (FR-003), per FR-004 / T040 (partial)
- [X] T080 In `bun/private/lockfile.bzl`, check the dependency maps the carry-over reads before
  `dict(...)`: an entry's `dependencies`, `optionalDependencies`, `peerDependencies` (L13, L14) and
  `devDependencies` (L32), and a workspace's dependency kinds (L3, L6), each an object whose values
  are strings, as Bun refuses otherwise ("Expected an object" / "Expected a string", LOCK
  L3405–L3426); fail naming the `bun.lock` label, the entry or workspace and the field, in English,
  without printing the value; write the `bun/tests/npm/lockfile_test.bzl` cases red first and record
  red and green in `tdd-log.md`, per spec Edge Cases (malformed value) / FR-004 (partial)
- [ ] T081 Settle BC-4 for package executables: `npm_bin` (`bun/private/run.bzl`, mode `bin`) lays
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
- [ ] T083 Ask the user whether `.specify/workflows/overlays/speckit/rules-bun.yml` (commit 57a1326,
  called for by neither spec nor plan) ships in this feature's PR or separately; if it ships, list it
  in T066's PR body as outside feature 006's scope, per FR-018 (unrequested)
