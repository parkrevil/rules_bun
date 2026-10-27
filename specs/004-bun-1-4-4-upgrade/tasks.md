---

description: "Task list for feature 004: upgrade the pinned Bun to 1.4.4"
---

# Tasks: Upgrade the Pinned Bun to 1.4.4

**Input**: Design documents from `specs/004-bun-1-4-4-upgrade/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/public-api.md,
quickstart.md

**Tests**: no new test file. Existing suites are run against 1.4.4 (FR-005, FR-009); one assertion
is added to `versions_test` (FR-003, research R2); C-TD is removed if it goes red as research R6
predicts (FR-006).

**Organization**: Tasks are grouped by user story. Paths are relative to the repository root.

**Conventions used in every task**:

- Work and commit on branch `003-npm-dependencies` (research R10). Branch `004-bun-1-4-4-upgrade`
  gets no commits.
- `B` is the development toolchain's Bun:
  `B="$(bazel info output_base)/external/+bun+bun_linux-x64/bun"` (valid once T005 is done).
- Downloaded or scratch data goes in a new, empty directory under `/tmp/bun144*`, never next to a
  script.
- "Record in research" means: add the result, the command and the platform it ran on to
  `specs/004-bun-1-4-4-upgrade/research.md` Part 3 under the named evidence item (E7, E8, E9).
- "Stop and report" means: end the task, change nothing more for that item, and tell the user what
  was observed (constitution V; spec Edge Cases).
- Strings containing `1.4.2` that do not refer to Bun stay unchanged (FR-010): `bazel_skylib`
  1.4.2 in `MODULE.bazel.lock`, `e2e/smoke/MODULE.bazel.lock`,
  `bun/tests/integration/registry/modules/bazel_skylib/`, `.../rules_pkg/1.0.1/MODULE.bazel`;
  `rules_python` 1.4.2 in `.../modules/rules_python/metadata.json`; every string in
  `bun/tests/semver_test.bzl`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US4)

---

## Phase 1: Setup

**Purpose**: Confirm the branch and the upstream facts the plan rests on.

- [X] T001 Confirm `git branch --show-current` prints `003-npm-dependencies` and that
  `git status --short` shows only `specs/004-bun-1-4-4-upgrade/` as untracked (research R10: the
  spec directory is already on the implementation branch); leave branch `004-bun-1-4-4-upgrade`
  untouched
- [X] T002 [P] Re-verify research R1 against the official release: `gh release view bun-v1.4.4 -R
  oven-sh/bun` lists `bun-linux-x64.zip`, `bun-linux-aarch64.zip`, `bun-darwin-x64.zip`,
  `bun-darwin-aarch64.zip`, `bun-windows-x64.zip` and `SHASUMS256.txt`; download only
  `SHASUMS256.txt` into a new empty `/tmp/bun144-shasums/`; for each of the five lines compute
  `echo -n <hex> | xxd -r -p | base64` and confirm `sha256-<result>` equals the SRI column of
  research R1 in `specs/004-bun-1-4-4-upgrade/research.md`. If an archive or a line is missing, or
  a value differs, stop and report; never compute an integrity from a downloaded archive
  (constitution III)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Make 1.4.4 known and make it the Bun every root test runs with. Every story depends
on this phase.

- [X] T003 Add a `"1.4.4"` entry to `TOOL_VERSIONS` in `bun/private/versions.bzl`, after the
  unchanged `"1.4.2"` entry and in the same key order and formatting, with exactly these values
  (research R1): `linux-x64` = `sha256-v4zL+ysLgBWeD5ptFcVTF63YB3U028YTCj7bUvzLOVw=`,
  `linux-aarch64` = `sha256-uqa7NvUdblhWHgK76oJQOKnfRU9nPW13bou/hvjHhQ4=`, `darwin-x64` =
  `sha256-UKNJH3Orwv6BZzFxqFdi07wswWgMzsrdmD3pmt93l34=`, `darwin-aarch64` =
  `sha256-wkDX8My5DCY6hJ/NsJt+5iYw2SE0jtaq/ahrnVd7xRA=`, `windows-x64` =
  `sha256-zSwPzMePPt4fUMqCehXwY+2hPU0VCj0GdPT24yPYZKU=`. Do not add 1.4.3 (spec Assumptions)
- [X] T004 [P] Add the FR-003 assertion to `bun/tests/versions_test.bzl`: a test case (registered
  in the file's existing test suite) asserting that both `"1.4.2"` and `"1.4.4"` are keys of
  `TOOL_VERSIONS`, so removing either fails the test; the existing loops already check every
  version's five platforms and SRI form
- [X] T005 Set `bun_dev.toolchain(bun_version = "1.4.4")` at `MODULE.bazel` line 20 (leave the
  `update.ts` `http_file` region for T035). Run `bazel test //bun/tests:versions`; run
  `"$B" --version` and confirm it prints `1.4.4`; record both in research E9. Keep any
  `MODULE.bazel.lock` change Bazel writes (only Bun-related entries may change; report any other)

**Checkpoint**: the root module builds and tests with Bun 1.4.4.

---

## Phase 3: User Story 1 - The ruleset's own tests pass unsandboxed (Priority: P1) 🎯 MVP

**Goal**: C-PATCHED passes without a sandbox because Bun 1.4.4 runs `bun patch --commit`'s
`git diff --no-index` with `GIT_DIR` set to the null device (research R3), with no test-side
workaround (FR-009).

**Independent Test**: C-PATCHED passes sandboxed and with the `manifest-only` flags
(`--noenable_runfiles --spawn_strategy=local`) on Linux; the `windows-symlinks` job passes in CI
(after the final gate, quickstart).

- [X] T006 [US1] Run `bazel test //bun/tests/canary/npm:c_patched_test --nocache_test_results`
  and `bazel test //bun/tests/canary/npm:c_patched_test --noenable_runfiles
  --spawn_strategy=local --nocache_test_results`; both must pass with no edit to
  `bun/tests/canary/npm/c_patched.test.ts` or `.github/workflows/ci.yaml`. Record in research E7.
  If the unsandboxed run still fails on `.gitattributes`, stop and report (research R3 refuted)
- [X] T007 [US1] Confirm no test-side `.gitattributes` workaround exists: `git grep -n -i
  gitattributes -- . ':!specs'` finds nothing in `bun/`, `e2e/` or `.github/workflows/ci.yaml`
  (FR-009); if one is found, remove it and rerun T006

**Checkpoint**: the defect that blocks PR #5 is gone locally; CI confirmation comes after the final gate (quickstart).

---

## Phase 4: User Story 2 - A consumer gets Bun 1.4.4 without supplying integrity (Priority: P1)

**Goal**: `bun.toolchain(bun_version = "1.4.4")` without `integrity` fetches and verifies 1.4.4 on
all five platforms; docs and examples name 1.4.4.

**Independent Test**: `cd e2e/smoke && bazel test //:version_test` passes, asserting the
registered Bun reports `1.4.4`.

- [X] T008 [P] [US2] In `e2e/smoke/MODULE.bazel` line 9 set `bun.toolchain(bun_version =
  "1.4.4")`; in `e2e/smoke/BUILD.bazel` line 20 set the expected version `"1.4.4"`. Leave
  `e2e/smoke/MODULE.bazel.lock`'s `bazel_skylib` 1.4.2 line unchanged (FR-010); keep any Bun
  entry Bazel rewrites in it
- [X] T009 [P] [US2] Change the version-string examples to `1.4.4`: `bun/extensions.bzl` line 8
  (module docstring `bun.toolchain(bun_version = "1.4.4")`), `bun/private/extensions.bzl` line 16
  (`bun_version` doc "such as `1.4.4`"), `bun/private/providers.bzl` line 7 (`version` field doc
  "such as `1.4.4`"), `bun/private/toolchain.bzl` line 77 (`bun_target_toolchain` example
  `version = "1.4.4"`)
- [X] T010 [US2] Run `cd e2e/smoke && bazel test //:version_test`; it must pass. Record in
  research E9

**Checkpoint**: US2 is complete and independently verified through the consumer workspace.

---

## Phase 5: User Story 3 - Every claim about Bun behavior is true of the pinned Bun (Priority: P2)

**Goal**: every canary runs against 1.4.4 and passes or is resolved per FR-006; every statement
that names 1.4.2 behavior names 1.4.4 and is true of it; every fixture the pinned Bun wrote is
regenerated by 1.4.4.

**Independent Test**: `bazel test //bun/tests/canary/...` passes; the red mode fails every
`bun.lock` canary naming its reader; `git grep -n '1\.4\.2' -- . ':!specs'` finds only the
FR-003 entry and the FR-010 strings; rerunning every writer of research R8 leaves
`git status --short` clean.

### Canaries (before any fixture changes, plan step 3)

- [X] T011 [US3] Run every canary against 1.4.4 on the unchanged fixtures:
  `bazel test //bun/tests/canary/... --nocache_test_results` and the same with
  `--noenable_runfiles --spawn_strategy=local`. Record each canary's result (pass, red with its
  message, or skipped as Windows-only on Linux) per run in research E7. Expected (research R6):
  all pass except `//bun/tests/canary/npm:c_td_test`, red in its first test (`"trustedDependencies"
  in lock` for a manifest with `trustedDependencies: []`)
- [X] T012 [US3] Run the red mode: `bazel test //bun/tests/canary/npm/...
  --test_env=RULES_BUN_CANARY_RED=1 --nocache_test_results`; every `bun.lock` canary must fail with
  a message naming its reader or workaround. Record in research E7; a canary whose red mode
  passes is reported to the user
- [X] T013 [US3] Resolve C-TD per research R6, depending on T011:
  if C-TD went red because 1.4.4 writes `"trustedDependencies": []`, delete
  `bun/tests/canary/npm/c_td.test.ts`, remove the `c_td_test` target (line 82) and its
  `":c_td_test"` entry in the test suite (line 196) from `bun/tests/canary/npm/BUILD.bazel`, and in
  `bun/private/run.bzl` (lines 90–93) remove only the clause "and Bun 1.4.2 writes no empty
  `trustedDependencies` to `bun.lock`", keeping the sentence that no lifecycle script runs
  whatever `trustedDependencies` says; then run
  `bazel test //bun/tests/npm/fixtures/basic:scripted_test` (must pass) and record the resolution
  with its evidence in research R6 and E7. If C-TD passed instead, keep it, change its header
  (line 1) to name 1.4.4 and record the finding in research R6. If it went red for another
  reason, stop and report
- [x] T014 **Superseded by T047 (research R11).** [US3] For any canary other than C-TD that went red in T011: apply research R6's "If
  red" column (update the named reader to the canary-pinned 1.4.4 form, or remove a workaround
  1.4.4 no longer needs together with its canary), record the change and evidence in research
  Part 1 and E7, and add or update the test that covers it (FR-006). If the resolution needs a new
  `bun.lock` access or a design change (C1, C2), stop and report. Skip if T011 found no other red
- [X] T015 [P] [US3] Change the canary headers that name 1.4.2 to 1.4.4, only for canaries that
  passed in T011: `bun/tests/canary/c13_regexp_limit.test.ts` line 1,
  `bun/tests/canary/npm/c_catalog.test.ts` line 1, `bun/tests/canary/npm/c_integrity.test.ts`
  lines 2 and 15, `bun/tests/canary/npm/c_overrides.test.ts` line 1,
  `bun/tests/canary/npm/c_url1.test.ts` line 1, `bun/tests/canary/npm/c_url2.test.ts` line 2,
  `bun/tests/canary/npm/c_ver.test.ts` line 1, `bun/tests/canary/npm/c_ver1.test.ts` line 2

### Behaviors without a canary of their own (research R7)

- [X] T016 [US3] Observe research E8: in a new empty `/tmp/bun144-e8/` write `main.js` containing
  `console.log(JSON.stringify(process.argv.slice(2)))`, run `"$B" /tmp/bun144-e8/main.js -- x`
  and record the printed array in research E8. If `--` is still dropped (`["x"]`), T018 and T020
  rename the version. If `--` is kept (`["--","x"]`), stop and report before changing
  `bun/private/launcher.js`'s `--` error (removing it changes `bun_binary` behavior, FR-008)
- [X] T017 [US3] Run `bazel test //bun/tests/run/isolation:install_test
  //bun/tests/npm/workspaces:glob_compare_test //bun/tests/run/protocol/coverage/...
  --nocache_test_results`, then the `coverage` CI job's commands from `.github/workflows/ci.yaml`
  lines 137–138. Record each result in research E7. If `install_test` fails, stop and report
  (auto-install changed). If `glob_compare_test` fails, update `bun/private/workspaces.bzl` and
  `bun/tests/npm/workspaces/glob_cases.bzl` to the semantics 1.4.4 shows and record them. If a
  coverage test fails on `SF:` paths, update the coverage handling to the observed 1.4.4 form and
  record it

### Statements that name 1.4.2 (research R9, after T013, T016, T017)

- [X] T018 [P] [US3] In `bun/private/launcher.js` change line 73 (comment: longest guard pattern
  Bun 1.4.4 compiles), line 274 (`(Bun 1.4.4)` in the guard-limit error; keep `MAX_GUARD_PATTERN`
  at 1,048,576 unless C13 measured otherwise in T011/T014) and line 285 (`because Bun 1.4.4 drops
  a "--" directly after the entry point`, only if T016 observed the drop)
- [X] T019 [US3] In `bun/private/run.bzl` change line 46 (guard limit "with Bun 1.4.4"), line 537
  (`bun_binary` doc "because Bun 1.4.4 drops a `--` directly after the entry point", per T016) and
  line 595 (`bun_test` doc "1.4.4 does not install a missing package under `bun test`", per T017);
  line 93 is handled by T013, which must be done first (same file)
- [X] T020 [P] [US3] In `bun/tests/run/args/args.test.ts` line 20 expect `"Bun 1.4.4 drops"`
  (matches T018); in `bun/tests/run/protocol/coverage/chdir.test.ts` line 6 name Bun 1.4.4 (per
  T017)
- [X] T021 [P] [US3] In `bun/private/lockfile.bzl` line 153 make the FR-007 diagnostic read "the
  versions Bun 1.4.4 writes: run `bun install` with Bun 1.4.4 and commit bun.lock"; in
  `bun/tests/integration/lockfile_errors.test.ts` lines 26–27 expect "run `bun install` with Bun
  1.4.4 and commit bun.lock" (contracts/public-api.md; spec US3-4). `SUPPORTED_VERSIONS` stays
  1, 2, 3 (research R5.1)
- [X] T022 [P] [US3] Name 1.4.4 in the integrity-form statements (C-INTEGRITY passed in T011):
  `bun/private/check_integrity.js` line 8, `bun/private/npm_extension.bzl` line 73,
  `bun/tests/integration/fetch_algorithms.test.ts` line 2
- [X] T023 [P] [US3] Name 1.4.4 in the workspace-glob statements (`glob_compare_test` passed in
  T017): `bun/private/workspaces.bzl` lines 4 and 209, `bun/tests/npm/workspaces/glob_cases.bzl`
  line 1, `bun/tests/npm/workspaces/glob_compare.test.ts` line 1,
  `bun/tests/npm/workspaces_test.bzl` line 3
- [X] T024 [P] [US3] In `bun/tests/npm/registry/write_lockfiles.ts` line 243 name Bun 1.4.4 in the
  catalog comment (C-CATALOG passed in T011); must precede T027 (same file is run there)

### Fixtures written by the pinned Bun (research R8, in this order)

- [X] T025 [US3] Re-pack the run-test archive: in a new empty `/tmp/bun144-pack/` copy
  `bun/tests/run/isolation/registry/rules-bun-fixture-pkg/`, run `"$B" pm pack` there and copy the
  resulting `rules-bun-fixture-pkg-1.0.0.tgz` over
  `bun/tests/run/isolation/registry/rules-bun-fixture-pkg-1.0.0.tgz`; run
  `bazel test //bun/tests/run/isolation:install_test`. Record the byte diff (same or changed) in
  research E9
- [X] T026 [US3] From the repository root run `"$B" bun/tests/npm/registry/pack.ts`; commit
  `bun/tests/npm/registry/archives/*.tgz` as written. Record in research E9 which archives
  changed and the printed SRIs; if any SRI changed, every fixture hub or test that names it is
  updated by T027–T031 output only
- [X] T027 [US3] From the repository root run `"$B" bun/tests/npm/registry/write_lockfiles.ts`
  (no arguments); it must finish with its own key assertions passing. Commit
  `bun/tests/npm/fixtures/*/bun.lock` and every file it copied back exactly as written (FR-007).
  If an assertion fails because 1.4.4 writes a key differently, apply T014's rule (canary-pinned
  form, or stop and report). Record in research E9 the `lockfileVersion` printed per project and
  a diff summary (`git diff --stat bun/tests/npm/fixtures/`)
- [X] T028 [US3] From the repository root run `"$B" bun/tests/npm/scale/generate.ts`; commit
  `bun/tests/npm/scale/bun.lock` and `bun/tests/npm/scale/package.json` as written. Record the
  diff summary in research E9
- [X] T029 [US3] Regenerate the inline lockfiles of `bun/tests/integration/credentials.test.ts`
  and `bun/tests/integration/registries.test.ts` (research R8 step 5): for each, write the test's
  `package.json` into a new empty `/tmp/bun144-<test>/`, start the loopback registry with a scratch
  script outside the repository that imports `startRegistry` from
  `bun/tests/support/npm_registry.ts` and serves the archives the test serves (the same
  `startRegistry` options the test passes), run `"$B" install` there against that registry, paste the resulting `bun.lock` into the test with the URL slots
  replaced by the same `${urls.*}` placeholders the current text uses, and change the comment at
  line 26 of each file to "The lockfile the pinned Bun 1.4.4 wrote …". Run
  `bazel test //bun/tests/integration:credentials_test //bun/tests/integration:registries_test`
- [X] T030 [US3] In `e2e/smoke/` run `"$B" install --lockfile-only` on the existing
  `e2e/smoke/bun.lock` (re-save, not a fresh install, research R8 step 6); commit the result as
  written; run `cd e2e/smoke && bazel test //...` far enough to confirm the hub loads
  (`--frozen-lockfile` semantics hold)
- [x] T031 **Remaining part superseded by T048 (research R12).** [US3] Where the regenerated content differs from what the unit tests expect, update
  only those expectations to what 1.4.4 wrote, in `bun/tests/npm/lockfile_test.bzl` and
  `bun/tests/npm/fixture_results.bzl`; run `bazel test //bun/tests/npm/...`
- [x] T032 **Superseded by T050 (research R13).** [US3] Prove the fixtures are what 1.4.4 writes (quickstart Q4): rerun T025–T028's
  writers and confirm `git status --short` shows no further change (T029 and T030 are checked by
  their tests); if a writer's output is not byte-reproducible (for example `bun pm pack`), stop
  and report it instead of committing; run
  `bazel test //bun/tests/npm/... //bun/tests/run/... //bun/tests/canary/... --nocache_test_results`
  (all pass). Record in research E9

**Checkpoint**: canaries, statements and fixtures all evidence Bun 1.4.4.

---

## Phase 6: User Story 4 - Bazel-in-Bazel tests stay offline (Priority: P2)

**Goal**: the nested workspaces request 1.4.4 and the loopback registry serves the 1.4.4 archives,
verified with the `versions.bzl` integrities.

**Independent Test**: `bazel test //bun/tests/integration:integration_tests
--nosandbox_default_allow_network` passes; the `network-denied` CI job passes (after the final gate, quickstart).

- [X] T033 [P] [US4] Set `bun.toolchain(bun_version = "1.4.4")` in the nine nested workspaces:
  `bun/tests/integration/workspaces/fetch/MODULE.bazel` line 4, `multi_root/MODULE.bazel` line 4,
  `replace/MODULE.bazel` line 4, `restricted/MODULE.bazel` line 5, `scale/MODULE.bazel` line 4,
  `source_nm/MODULE.bazel` line 4, `stale_link/MODULE.bazel` line 4, `toolchain/MODULE.bazel`
  line 4, `winname/MODULE.bazel` line 4 (all under `bun/tests/integration/workspaces/`)
- [X] T034 [P] [US4] Fix `bun/tests/integration/registry/update.ts` (research R4): replace the
  loop at lines 233–236, which keys every `"<platform>": "sha256-…"` pair of `versions.bzl` to a
  hard-coded `bun-v1.4.2` URL, with code that takes the version the nested workspaces request
  (one constant, `"1.4.4"`, next to `BAZEL_VERSION`), extracts only that version's block of
  `bun/private/versions.bzl`, and keys each of its five platform integrities to
  `https://github.com/oven-sh/bun/releases/download/bun-v<version>/bun-<platform>.zip`; fail with
  an English error if the block or a platform is missing
- [X] T035 [US4] With network, from the repository root run
  `"$B" bun/tests/integration/registry/update.ts` (after T033, T034). It rewrites
  `bun/tests/integration/registry/archives.bzl` and the `# BEGIN integration archives` region of
  `MODULE.bazel`. The diff must be exactly the five Bun URLs (`bun-v1.4.4`) in `archives.bzl`
  lines 47–51 and the five `integration_bun-*.zip` `http_file` URLs and integrities in
  `MODULE.bazel` (each integrity equal to T003's value); if anything else changes (registry
  modules, other archives), do not commit those lines and report them
- [X] T036 [US4] Run `bazel fetch //...` then `bazel test //bun/tests/integration:integration_tests
  --nosandbox_default_allow_network --nocache_test_results` (quickstart Q5); all pass and the
  loopback log shows the five `bun-v1.4.4` paths and no external request

**Checkpoint**: integration tests run offline against 1.4.4.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: the AGENTS.md gates, the SC-004 search, the evidence log and CI.

- [X] T037 Run `bazel run //:gazelle` in the root; commit any BUILD change it makes (expected: the
  removed `c_td_test` stays removed)
- [X] T038 Run `prek run --all-files` in the root; fix only formatting it reports in files this
  feature changed; report other failures
- [X] T039 Run `bazel test //...` in the root; all pass (SC-001). Report a failure; do not widen
  the task to fix unrelated ones (AGENTS.md)
- [X] T040 Run `bazel test //... --noenable_runfiles --spawn_strategy=local --nocache_test_results`
  in the root (quickstart Q3, the `manifest-only` flags); all pass, C-PATCHED included
- [X] T041 Run `bazel test //...` in `e2e/smoke/`; all pass (SC-001)
- [X] T042 Run `git grep -n '1\.4\.2' -- . ':!specs'`; the only hits are the `"1.4.2"` key in
  `bun/private/versions.bzl` (FR-003) and the FR-010 strings listed under Conventions (SC-004).
  Fix any other hit by the matching T009/T015/T018–T024 rule. Then check FR-008: `git diff
  054c413 -- bun/*.bzl bun/private/*.bzl` changes docstrings, `doc =` strings, diagnostics and
  `versions.bzl` entries only, no attribute, tag, rule or symbol
- [X] T043 [P] Complete `specs/004-bun-1-4-4-upgrade/research.md`: Part 3 E7 (every canary,
  sandboxed and unsandboxed, red mode), E8, E9; R6 and R7 outcomes; any finding that refuted the
  static reading. E7 holds the local Linux results only; the macOS and Windows results come from
  CI after the workflow and go in the PR #5 description (constitution II)
- [X] T044 [P] Update `specs/004-bun-1-4-4-upgrade/contracts/public-api.md` if T016 or T011/T014
  changed an outcome the "After" column predicts; set the plan's **Status** line in
  `specs/004-bun-1-4-4-upgrade/plan.md` to implemented
- [x] T045 Moved out of the implement step: committing, pushing PR #5 and watching its CI happen
  after the workflow's final gate, in the session that runs the workflow (see quickstart
  "After the final gate")

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)**: none.
- **Foundational (Phase 2)**: after Setup; blocks every story (all root tests use the dev
  toolchain set in T005).
- **US1 (Phase 3)**: after Phase 2. Independent of US2–US4.
- **US2 (Phase 4)**: after Phase 2 (needs T003). Independent of US1, US3, US4.
- **US3 (Phase 5)**: after Phase 2. T011–T012 must run before T025–T031 (canaries against unchanged
  fixtures, plan step 3). T030 touches `e2e/smoke/bun.lock`, so run it after T008.
- **US4 (Phase 6)**: after Phase 2 (needs T003's integrities). T033 and T034 before T035; T035
  rewrites the `MODULE.bazel` region, so do not edit `MODULE.bazel` concurrently.
- **Polish (Phase 7)**: after all stories; the commit, push and CI follow the final gate (T045).

### Within US3

T011 → T012 → T013/T014 → T015; T016, T017 (independent of the canaries) → T018–T024;
T013 → T019; T024 → T027; T025 → T026 → T027 → T028 → T029 → T030 → T031 → T032.

### Parallel opportunities

- T002 with T001; T004 with T003.
- After Phase 2: US1, US2 and US4's T033/T034 can run alongside US3's canary runs, as long as only
  one `bazel` command runs per output base at a time (Bazel serializes them anyway).
- T008 and T009; T015 with T016/T017; T018, T020, T021, T022, T023, T024 (different files);
  T033 and T034; T043 and T044.

## Parallel Example: User Story 3 statements

```text
T018 bun/private/launcher.js
T020 bun/tests/run/args/args.test.ts, bun/tests/run/protocol/coverage/chdir.test.ts
T021 bun/private/lockfile.bzl, bun/tests/integration/lockfile_errors.test.ts
T022 bun/private/check_integrity.js, bun/private/npm_extension.bzl, bun/tests/integration/fetch_algorithms.test.ts
T023 bun/private/workspaces.bzl, bun/tests/npm/workspaces/glob_cases.bzl, glob_compare.test.ts, bun/tests/npm/workspaces_test.bzl
T024 bun/tests/npm/registry/write_lockfiles.ts
```

## Implementation Strategy

### MVP (US1)

Phase 1 → Phase 2 → Phase 3: with T003 and T005 the dev toolchain is 1.4.4 and C-PATCHED passes
unsandboxed locally. This alone does not make PR #5's CI green: the nested workspaces (US4), the
1.4.2-specific canaries and messages (US3) and `e2e/smoke` (US2) must follow before pushing.

### Incremental delivery

1. Setup + Foundational → 1.4.4 known and in use.
2. US1 → the blocking defect is gone locally.
3. US2 → consumers verified through `e2e/smoke`.
4. US3 → canaries, statements and fixtures evidence 1.4.4.
5. US4 → integration tests offline on 1.4.4.
6. Polish → gates, SC-004 search, evidence log, one push, CI on all three OSes.

Push only once, after the final gate and all local gates, so PR #5's CI runs the complete change.

---

## Phase 8: Convergence

- [x] T046 CRITICAL: Rewrite the statements that `bun.lock` records no `libc` (`bun/private/npm_extension.bzl` lines 366–367, the comment at `bun/tests/npm/platforms_test.bzl` line 16, the header of `bun/tests/canary/npm/c_oscpu.test.ts` lines 1–2) to what 1.4.4 writes and what the ruleset now does with it (research R11), and document FR-014 in the npm extension's docs (how to set `@rules_bun//bun/platforms/libc:glibc` on a platform, what `:unconstrained` does)
- [x] T047 Implement research R11 test-first (FR-011–FR-013, SC-006): (a) add `bun/platforms/libc/BUILD.bazel` with `constraint_setting(name = "libc", default_constraint_value = ":unconstrained")` and the values `unconstrained`, `glibc`, `musl`, public visibility, as rules_js's `platforms/libc`; (b) add Linux platforms with `:glibc` and `:musl` to `bun/tests/platforms/BUILD.bazel`; (c) write the SC-006 analysis tests first (glibc → glibc variant only, musl → musl only, unconstrained → both, macOS/Windows → neither) over the `basic` fixture's libc variants and watch them fail; (d) read `libc` in `bun/private/lockfile.bzl` beside `os`/`cpu`; (e) extend the restriction condition in `bun/private/resolve.bzl` and the generated select in `bun/private/npm_extension.bzl` to `[os, cpu, libc]` with npm-install-checks' `checkList` semantics (`!` negation, `any`, no libc off Linux, `:unconstrained` accepts); (f) add canary C-LIBC in `bun/tests/canary/npm/` pinning the form 1.4.4 writes, with a red mode; (g) change C-OSCPU to pin `os`/`cpu` as 1.4.4 writes them beside `libc`; record evidence in research E7. Run `bazel test //bun/tests/npm/... //bun/tests/canary/npm/... --nocache_test_results` (all pass)
- [x] T048 Implement research R12: the `dependency_conflict` fixture project (the 1.4.4 lockfile with its `y/x/b` line removed, asserted by `write_lockfiles.ts`), its hub `npm_dependency_conflict` in `MODULE.bazel`, and `uniqueness_dependency_test` pointed at it; evidence in research R12. `bazel test //bun/tests/npm:all` passes
- [x] T049 Rerun the AGENTS.md gates after T046–T048 and T050: root `bazel run //:gazelle`, `prek run --all-files`, `bazel test //...` and `bazel test //... --noenable_runfiles --spawn_strategy=local --nocache_test_results`; `e2e/smoke` `bazel test //...`; all pass with zero failures ; update the gate line of research E9 and the plan's **Status** line per SC-001 (partial)
- [x] T050 Implement research R13: add an optional `port` to `startRegistry` in `bun/tests/support/npm_registry.ts` (default 0) with a test in `npm_registry.test.ts`; pass one fixed loopback port from `bun/tests/npm/registry/write_lockfiles.ts` and `bun/tests/npm/scale/generate.ts`; regenerate every lockfile they write (all projects, then the scale fixture) and commit them as written; rerun both and confirm `git status --short` shows no change; make quickstart Q4 say so without "modulo the port"; run `bazel test //bun/tests/npm/... //bun/tests/run/... //bun/tests/canary/... --nocache_test_results`; record in research E9
