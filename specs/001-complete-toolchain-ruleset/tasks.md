---

description: "Task list for completing the Bun toolchain ruleset"
---

# Tasks: Complete the Bun Toolchain Ruleset

**Input**: Design documents from `specs/001-complete-toolchain-ruleset/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/public-api.md,
quickstart.md

**Tests**: Requested (TDD, FR-009). Every behavior task writes or changes a test first, runs it,
and records in `specs/001-complete-toolchain-ruleset/tdd-log.md` that it fails for the expected
reason, then implements until it passes. Tests that guard existing behavior record a reverted
mutation as their red. Deletion and refactor tasks record the existing tests that still pass.
Documentation tasks record no test.

**Organization**: Grouped by user story. Phases run in the order written: US3 runs before US2
because FR-003 requires the replacement selection tests to land before `cross_*_test` and
`action_fixture` are deleted.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1–US4 from spec.md

## Conventions for every task

- **Record**: append one entry to `specs/001-complete-toolchain-ruleset/tdd-log.md` with the
  fields of data-model.md "Test-first record": Task ID, Kind (behavior · deletion/refactor ·
  documentation), Red (command, exit code, failure line; mark mutation runs), Green (command,
  result), Platforms (Linux locally; macOS/Windows only from a named CI run).
- **Messages**: every `asserts.*` `msg` and every `diff_test` `failure_message` added here is
  English (FR-012, research R0), like docstrings, `doc =` strings and comments.
- **Red first**: if a new test passes before implementation and the task is not a
  guard-existing-behavior task, the test is wrong; change it until it fails for the expected
  reason (spec Edge Cases).
- **Stop rule**: if a step needs an undocumented or deprecated API, stop and report the gap
  (constitution V). Do not widen a task to fix an unrelated failure; report it (AGENTS.md).

---

## Phase 1: Setup

**Purpose**: Create the record file and capture the starting state.

- [X] T001 Create `specs/001-complete-toolchain-ruleset/tdd-log.md` with a title, a one-paragraph
  purpose referencing FR-009, and a Markdown table header with the columns
  `Task | Kind | Red | Green | Platforms` from data-model.md "Test-first record".
- [X] T002 Record the starting state in `specs/001-complete-toolchain-ruleset/tdd-log.md` (Kind:
  baseline): run `(cd e2e/smoke && bazel test //...)` and record exit code 4 and the line
  "No test targets were found"; run `bazel test //...` in the root and record the result and the
  list of test targets (it includes `hardening_test`, `hardening_emitted_test`, `cross_*_test`,
  `semver`, `//tools:preset.update_test`). This is the module's starting state, not a red of any
  test (research R1).

---

## Phase 2: Foundational (test fixtures shared by US3 and US4)

**Purpose**: Test platforms and repository visibility that the selection (R5), exec-cfg (R6) and
`BUN_BIN` (R7) tests all need.

**⚠️ CRITICAL**: US3 and US4 cannot start until this phase is complete. US1 does not depend on it.

- [X] T003 [P] Add `platform(name = "linux_x64", constraint_values = ["@platforms//os:linux", "@platforms//cpu:x86_64"])`
  and `platform(name = "darwin_x64", constraint_values = ["@platforms//os:macos", "@platforms//cpu:x86_64"])`
  to `bun/tests/platforms/BUILD.bazel`, next to the existing `darwin_aarch64`, `linux_aarch64`,
  `windows_x64`. They MUST be hand-written literals and MUST NOT load or derive from
  `PLATFORMS` (research R5). Record (refactor): root `bazel test //...` still passes.
- [X] T004 [P] In the root `MODULE.bazel`, extend the dev `use_repo(bun_dev, "bun_toolchains")`
  to `use_repo(bun_dev, "bun_toolchains", "bun_darwin-aarch64", "bun_darwin-x64", "bun_linux-aarch64", "bun_linux-x64", "bun_windows-x64")`
  so tests can write `Label("@bun_<platform>//:bun<exe>")` (research R5). Run
  Do not run `bazel mod tidy`; refresh only `MODULE.bazel.lock`. Record
  (refactor): root `bazel test //...` still passes.

**Checkpoint**: five literal test platforms exist; the five platform repositories are visible to
the root module.

---

## Phase 3: User Story 1 - The consumer test module passes everywhere (Priority: P1) 🎯 MVP

**Goal**: `e2e/smoke` has tests that run the registered toolchain's Bun in a build action with
`toolchain = BUN_TOOLCHAIN_TYPE` and compare the reported version with the literal `1.4.2`.

**Independent Test**: `(cd e2e/smoke && bazel test //...)` runs at least two tests and passes on
Linux, macOS and Windows; changing the literal to `0.0.0` makes it fail.

- [X] T005 [US1] In `e2e/smoke/MODULE.bazel`, add
  `bazel_dep(name = "bazel_skylib", version = "1.9.2", dev_dependency = True)` and refresh
  `e2e/smoke/MODULE.bazel.lock` with `(cd e2e/smoke && bazel mod deps --lockfile_mode=update)`.
  Confirm with `(cd e2e/smoke && bazel mod graph)` that `platforms` stays 1.0.0 and
  `package_metadata` 0.0.6 (FR-013, research R1). Record (refactor): the run still reports
  "No test targets were found" (nothing else changed).
- [X] T006 [US1] Write the red test for FR-008 (research R2): create `e2e/smoke/verify_test.bzl`
  with a module docstring and an `analysistest.make` rule `toolchain_param_test` whose
  `config_settings = {"//command_line_option:incompatible_auto_exec_groups": True}` and whose
  implementation asserts, with an English `msg`, that the target under test registers exactly one
  action with mnemonic `BunVersion`. In `e2e/smoke/BUILD.bazel` load it and add
  `toolchain_param_test(name = "toolchain_param_test", target_under_test = ":verify")`. Run
  `(cd e2e/smoke && bazel test //:toolchain_param_test)`; record the red: analysis fails with
  "Couldn't identify if tools are from implicit dependencies or a toolchain. Please set the
  toolchain parameter" (FR-009 allows an analysis error that names the missing behavior).
- [X] T007 [US1] Make T006 green: in `e2e/smoke/verify.bzl`, read
  `buninfo = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo` and call
  `ctx.actions.run(executable = buninfo.bun, tools = buninfo.tool_files, toolchain = BUN_TOOLCHAIN_TYPE, ...)`
  as contracts/public-api.md shows; keep the existing arguments, outputs, mnemonic and
  `progress_message`. Run `(cd e2e/smoke && bazel test //:toolchain_param_test)`; record green.
  Also record, per research R2, that the test would pass with `toolchain = None`, so the value
  is covered only by `git grep -n 'toolchain = BUN_TOOLCHAIN_TYPE' -- e2e` (not by a test).
- [X] T008 [US1] Add the version comparison (FR-002, research R1) to `e2e/smoke/BUILD.bazel`:
  load `@bazel_skylib//rules:write_file.bzl` and `@bazel_skylib//rules:diff_test.bzl`; add
  `write_file(name = "expected_version", out = "expected_version.txt", content = ["1.4.2", ""], newline = "unix")`
  and `diff_test(name = "version_test", file1 = ":verify", file2 = ":expected_version", failure_message = "<English>")`.
  The `failure_message` MUST NOT contain any of `( ) ! % ^ & | < >` (research R1 Windows
  constraints). This guards existing behavior, so its red is a mutation: set the literal to
  `"0.0.0"`, run `(cd e2e/smoke && bazel test //:version_test)`, record the failure and the
  message (marked as mutation), revert to `"1.4.2"`, run `(cd e2e/smoke && bazel test //...)`
  and record green with both tests listed.
- [X] T009 [P] [US1] Update the `BUN_TOOLCHAIN_TYPE` docstring in `bun/defs.bzl` (English) to
  show a consumer rule that declares `toolchains = [BUN_TOOLCHAIN_TYPE]`, reads
  `ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo`, and calls
  `ctx.actions.run(executable = buninfo.bun, tools = buninfo.tool_files, toolchain = BUN_TOOLCHAIN_TYPE, ...)`
  (FR-008, contracts/public-api.md). Record (documentation): no test; root `bazel test //...`
  still passes.

**Checkpoint**: `(cd e2e/smoke && bazel test //...)` passes locally with
`toolchain_param_test` and `version_test` (SC-001 still needs CI, POST-2).

---

## Phase 4: User Story 3 - Toolchain tests prove what they claim (Priority: P3)

**Goal**: selection tests vary the **execution** platform; `bun_toolchain.bun` is built in the
exec configuration. Runs before US2 (FR-003).

**Independent Test**: `bazel test //bun/tests/...` passes; swapping two entries'
`compatible_with` in `PLATFORMS` makes exactly those two selection tests fail; removing
`cfg = "exec"` makes `exec_cfg_test` fail.

- [X] T011 [US3] Create `bun/tests/toolchain_test.bzl` (module docstring in English) with:
  a test-local provider `ResolvedBunInfo(buninfo)`; a fixture rule `resolved_bun` with
  `toolchains = [BUN_TOOLCHAIN_TYPE]` (loaded from `//bun:defs.bzl`) that returns
  `ResolvedBunInfo(buninfo = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo)`; and five
  `analysistest.make` rules, one per Bun platform, each with
  `config_settings = {"//command_line_option:extra_execution_platforms": [str(Label("//bun/tests/platforms:<p>"))]}`
  (`<p>` ∈ `linux_x64`, `linux_aarch64`, `darwin_x64`, `darwin_aarch64`, `windows_x64`) and one
  shared implementation asserting, with an English `msg`, that
  `target[ResolvedBunInfo].buninfo.bun.owner == Label("@bun_<platform>//:bun<exe>")`
  (`<exe>` is `.exe` only for `windows-x64`). Add a macro
  `toolchain_selection_test_suite(name)` that declares `resolved_bun(name = name + "_fixture")`,
  the five tests (`<name>_<p>_test`) and a `test_suite`. In `bun/tests/BUILD.bazel` call
  `toolchain_selection_test_suite(name = "selection")`. Run `bazel test //bun/tests:all` and
  confirm all five pass. This guards existing behavior (research R5), so record the red as a
  mutation: in `bun/private/platforms.bzl` swap the `compatible_with` lists of `linux-aarch64`
  and `darwin-aarch64`, run `bazel test //bun/tests:all`, record that exactly
  `selection_linux_aarch64_test` and `selection_darwin_aarch64_test` fail, revert, and record
  green.
- [X] T012 [US3] Write the red test for FR-008a (research R6) in `bun/tests/toolchain_test.bzl`:
  a fixture rule `os_named_file` with a string attribute `os` that writes an empty file
  `<os>/bun` with `ctx.actions.write` (no shell); an `analysistest.make` rule `exec_cfg_test`
  with `config_settings = {"//command_line_option:platforms": str(Label("//bun/tests/platforms:windows_x64")), "//command_line_option:extra_execution_platforms": [str(Label("//bun/tests/platforms:linux_aarch64"))]}`
  asserting, with an English `msg`, that
  `target[platform_common.ToolchainInfo].buninfo.bun.short_path.endswith("linux/bun")`; and a
  macro `exec_cfg_test_suite(name)` that declares
  `os_named_file(name = name + "_bun", os = select({"@platforms//os:linux": "linux", "@platforms//os:macos": "macos", "@platforms//os:windows": "windows"}))`,
  `bun_toolchain(name = name + "_toolchain", bun = ":" + name + "_bun", version = "0.0.0")`
  (loaded from `//bun:toolchain.bzl`) and `exec_cfg_test(name = name + "_test", target_under_test = ...)`.
  Call it from `bun/tests/BUILD.bazel` as `exec_cfg_test_suite(name = "exec_cfg")`. Run
  `bazel test //bun/tests:exec_cfg_test`; record the red: the path ends with `windows/bun`.
- [X] T013 [US3] Make T012 green: add `cfg = "exec"` to the `bun` attribute of `bun_toolchain` in
  `bun/toolchain.bzl` (research R6, data-model.md). Run `bazel test //bun/tests/...` and record
  green, including the five selection tests.

**Checkpoint**: selection and exec-cfg tests pass; `cross_*_test` still exist and pass.

---

## Phase 5: User Story 2 - The ruleset holds only the toolchain (Priority: P2)

**Goal**: delete the unreachable hardening helper and every authored shell action or launcher.

**Independent Test**: `git grep -n run_shell -- bun e2e` and
`git grep -n 'is_executable = True' -- bun e2e` print nothing, and root `bazel test //...` passes.

- [X] T014 [US2] Delete `bun/private/action.bzl`, `bun/private/hardening.bzl`,
  `bun/private/paths.bzl`, `bun/tests/action_test.bzl`, `bun/tests/hardening_test.bzl` and
  `bun/tests/platform_transition.bzl` (FR-003, research R3). In `bun/private/BUILD.bazel` remove
  the `bzl_library` targets `action`, `hardening` and `paths`. In `bun/tests/BUILD.bazel` remove
  the loads of `action_test.bzl`, `hardening_test.bzl`, `platform_transition.bzl` and
  `build_test.bzl`, and the targets `action_fixture`, `hardening_emitted_test`, `hardening_test`,
  `fixture_darwin_aarch64`, `fixture_linux_aarch64`, `fixture_windows_x64`,
  `cross_darwin_aarch64_test`, `cross_linux_aarch64_test`, `cross_windows_x64_test`. Keep
  every target in `bun/tests/platforms/BUILD.bazel`: the selection and exec-cfg tests reference
  them through `config_settings` label strings, which `rdeps` does not see.
  Run `bazel run //:gazelle`.
- [X] T015 [US2] Record (deletion) in `specs/001-complete-toolchain-ruleset/tdd-log.md`: root
  `bazel test //...` passes and lists no `hardening_*` or `cross_*` test;
  `git grep -n run_shell -- bun e2e` and `git grep -n 'is_executable = True' -- bun e2e` print
  nothing (SC-003); `git grep -n -e 'action.bzl' -e 'hardening.bzl' -e 'paths.bzl' -e 'platform_transition' -- bun e2e MODULE.bazel`
  prints nothing.

**Checkpoint**: no authored shell action remains; root tests pass without the deleted files.

---

## Phase 6: User Story 4 - Structure matches the reference baseline (Priority: P4)

**Goal**: close the divergences research.md marks **closed** (R4, R7, R9, R10, rows 30, 37,
41) and keep every intentional one recorded.

**Independent Test**: root and `e2e/smoke` `bazel test //...` pass; each closed row of
research.md Part 2 names a passing test or refactor record.

### Refactors (no behavior change)

- [X] T016 [US4] Remove the `hasattr(repository_ctx, "repo_metadata")` guard and its
  `return None` from `bun/repositories.bzl` and `bun/private/toolchains_repo.bzl`; each
  implementation ends with `return repository_ctx.repo_metadata(reproducible = True)` (FR-005,
  research R4). Record (refactor): root and `(cd e2e/smoke && bazel test //...)` pass;
  `git grep -n hasattr -- bun` prints nothing (SC-004).
- [X] T017 [US4] Replace `stripPrefix = "bun-" + platform` with `strip_prefix = "bun-" + platform`
  in the `download_and_extract` call in `bun/repositories.bzl` (research R9). Record (refactor):
  root and `e2e/smoke` tests pass; `git grep -n stripPrefix -- bun` prints nothing.
- [X] T018 [US4] Move implementation to `bun/private/` (research R10, constitution I): create
  `bun/private/toolchain.bzl` (`bun_toolchain` rule and impl, from `bun/toolchain.bzl`),
  `bun/private/repositories.bzl` (`bun_repositories`, `bun_register_toolchains`, `_ATTRS`, impl,
  from `bun/repositories.bzl`) and `bun/private/extensions.bzl` (tag class `bun_toolchain`,
  `_toolchain_extension`, `bun`, from `bun/extensions.bzl`; it loads
  `//bun/private:repositories.bzl`). Each public file keeps its module docstring and only
  re-exports the same names (`load("//bun/private:toolchain.bzl", _bun_toolchain = "bun_toolchain")`
  then `bun_toolchain = _bun_toolchain`; likewise `bun_repositories`, `bun_register_toolchains`,
  `bun` and the tag class `bun_toolchain` in `bun/extensions.bzl`). The generated platform
  repository keeps loading `@rules_bun//bun:toolchain.bzl`. Run `bazel run //:gazelle` to update
  `bun/BUILD.bazel` and `bun/private/BUILD.bazel`. Record (refactor): root and `e2e/smoke` tests
  pass; `bazel build $(bazel query 'kind(starlark_doc_extract, //bun/...)')` succeeds.
- [X] T019 [US4] Move `PLATFORMS` from `bun/private/platforms.bzl` into
  `bun/private/toolchains_repo.bzl` (research Part 2 row 37), make
  `bun/private/repositories.bzl` load it from `//bun/private:toolchains_repo.bzl`, delete
  `bun/private/platforms.bzl` and its `bzl_library`, and run `bazel run //:gazelle`. Record
  (refactor): root tests pass, including all five selection tests; repeat the T011 mutation
  (swap `linux-aarch64`/`darwin-aarch64` `compatible_with` in `bun/private/toolchains_repo.bzl`),
  record that the same two tests fail, revert (quickstart step 4).
- [X] T020 [US4] Align `e2e/smoke/MODULE.bazel` with the baseline (research Part 2 row 30):
  remove `module(name = "rules_bun_e2e_smoke")`, add `dev_dependency = True` to the `rules_bun`
  `bazel_dep`; leave `local_path_override`, `use_extension`, `bun.toolchain`, `use_repo` and
  `register_toolchains` as a consumer writes them. Refresh `e2e/smoke/MODULE.bazel.lock`. Record
  (refactor): `(cd e2e/smoke && bazel test //...)` passes with the declared versions (FR-013).

### `TemplateVariableInfo` with `BUN_BIN` (FR-007, research R7)

- [X] T021 [US4] Write the red value test in `bun/tests/toolchain_test.bzl`: an
  `analysistest.make` rule `bun_bin_value_test` (no config change) asserting, with English `msg`s,
  that `platform_common.TemplateVariableInfo in target` (returning `analysistest.end(env)` right
  after that assertion fails, so the red is the assertion, not a Starlark error) and that
  `target[platform_common.TemplateVariableInfo].variables["BUN_BIN"] == target[platform_common.ToolchainInfo].buninfo.bun.path`.
  In `bun/tests/BUILD.bazel` add `bun_toolchain(name = "bun_bin_toolchain", bun = "@bun_linux-x64//:bun", version = "0.0.0")`
  and `bun_bin_value_test(name = "bun_bin_value_test", target_under_test = ":bun_bin_toolchain")`.
  Run `bazel test //bun/tests:bun_bin_value_test`; record the red: the provider-presence
  assertion fails with its message.
- [X] T022 [US4] Write the red genrule test: in `bun/tests/BUILD.bazel` add
  `genrule(name = "bun_bin_genrule", outs = ["bun_bin_genrule.txt"], cmd = "$(BUN_BIN) --version > $@", cmd_bat = "$(BUN_BIN) --version > $@", toolchains = ["//bun/toolchain:execution_type"], tags = ["manual"])`
  and a `resolved_bun(name = "bun_bin_resolved")` fixture. In `bun/tests/toolchain_test.bzl` add an
  `analysistest.make` rule `bun_bin_genrule_test` (no config change) with an extra attribute
  `resolved = attr.label(providers = [ResolvedBunInfo])` that asserts, with an English `msg`, that
  some argument of the genrule's single action, with `\` replaced by `/`, contains
  `ctx.attr.resolved[ResolvedBunInfo].buninfo.bun.path` (on Windows `cmd_bat` expands paths with
  backslashes, per the genrule page; research R7). It MUST NOT assert anything about the
  action's inputs (research R7 gap). Add
  `bun_bin_genrule_test(name = "bun_bin_genrule_test", target_under_test = ":bun_bin_genrule", resolved = ":bun_bin_resolved")`.
  Run `bazel test //bun/tests:bun_bin_genrule_test`; record the red: analysis error
  "$(BUN_BIN) not defined" (verified on Bazel 9.2.0, research R7).
- [X] T023 [US4] Make T021 and T022 green: in `bun/private/toolchain.bzl`, return
  `platform_common.TemplateVariableInfo({"BUN_BIN": bun.path})` alongside `DefaultInfo` and
  `ToolchainInfo`, and document in the `bun_toolchain` `doc` (English) that it provides
  `BUN_BIN`, the execution-root-relative path, and that only the expansion is promised
  (contracts/public-api.md). Run `bazel test //bun/tests/...`; record green.

### Versions test (research Part 2 row 41)

- [X] T024 [P] [US4] Create `bun/tests/versions_test.bzl` with a skylib `unittest` that asserts,
  with English `msg`s, for every entry of `TOOL_VERSIONS` (`//bun/private:versions.bzl`) that
  `sorted(entry.keys()) == sorted(PLATFORMS.keys())` (`//bun/private:toolchains_repo.bzl`) and
  that every value starts with `sha256-`; expose `versions_test_suite(name)` and call
  `versions_test_suite(name = "versions")` in `bun/tests/BUILD.bazel`. It guards existing data,
  so record the red as a mutation: delete the `"windows-x64"` key from `"1.4.2"` in
  `bun/private/versions.bzl`, run `bazel test //bun/tests:versions` (the suite) alone (running
  `//bun/tests:all` would stop earlier at the `bun_windows-x64` repository's integrity `fail()`),
  record the versions test's own failure, revert,
  record green.

### Divergence register

- [X] T025 [US4] Update `specs/001-complete-toolchain-ruleset/research.md` Part 2 so every
  **closed** row names the test or refactor record that closed it (T006–T008 row 29, T020 row
  30, T019 row 37, T017 row 39b, T011–T015/T021–T024 row 40, T024 row 41, T021–T023 row 42, T012–T013
  row 42c) and every row still has a source and a status (SC-005). Record (documentation).

**Checkpoint**: all divergences in research.md are closed with a test or recorded with a status.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T026 Run the AGENTS.md hand-back checks: in the root `bazel run //:gazelle`,
  `prek run --all-files`, `bazel test //...`; in `e2e/smoke/` `bazel test //...`. Record each
  result in `specs/001-complete-toolchain-ruleset/tdd-log.md`. Report a failure; do not widen the
  task to fix it.
- [X] T027 Run quickstart.md step 3 static checks and record the output in
  `specs/001-complete-toolchain-ruleset/tdd-log.md`: `run_shell`, `is_executable = True`,
  `hasattr`, `stripPrefix` print nothing; `toolchain = BUN_TOOLCHAIN_TYPE` appears only in
  `bun/defs.bzl` and `e2e/smoke/verify.bzl`. Also confirm FR-011: no new public target and no
  rule that runs Bun programs, runs Bun tests or installs packages
  (`bazel query 'attr(visibility, "//visibility:public", //bun/...)'` MUST print the same set as
  the same query on `main`: the public `bzl_library` targets of `bun/BUILD.bazel`, any targets they
  generate, and `//bun/toolchain:execution_type`).



## Post-workflow (run by the operator after the `review-final` gate, not by `speckit.implement`)

The user authorized pushing on 2026-09-30. The Windows check of a Korean `failure_message`
(was T010) was dropped on 2026-10-01: messages are English and ASCII, so the codepage risk it
checked no longer exists. They run after the workflow because a commit
before the workflow's review steps would leave them an empty working-tree diff. Their results are
appended to `tdd-log.md` then.

- POST-0 (was T028) Adversarial review by a subagent and by Codex: done by the workflow's
  `review-claude` and `review-codex` steps after `verify`; the operator fixes confirmed findings
  within this feature and records each finding and its outcome in `tdd-log.md`.
- POST-2 (was T029) Commit, push `001-complete-toolchain-ruleset`, open a pull request to `main`, and
  record the `CI` run ID with per-OS, per-folder results (`ubuntu-latest`, `macos-latest`,
  `windows-latest` × `.`, `e2e/smoke`) in `tdd-log.md` (SC-001, SC-002). Report any OS that did not
  run or failed as unverified (FR-014).

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T002)**: first.
- **Foundational (T003–T004)**: after Setup; blocks US3 and US4.
- **US1 (T005–T009)**: after Setup; independent of Foundational.
- **US3 (T011–T013)**: after Foundational. T012 before T013.
- **US2 (T014–T015)**: after US3 (FR-003: replacement tests land before `cross_*_test` and
  `action_fixture` are deleted).
- **US4 (T016–T025)**: after US2. T016 → T017 → T018 → T019 (same files). T021–T022 need T018
  (implementation lives in `bun/private/toolchain.bzl`) and T011 (`resolved_bun`); T023 after
  both. T024 after T019 (`PLATFORMS` location). T020 after US1. T025 last.
- **Polish (T026–T027)**, then POST-0, POST-2: after all stories.

### Story completion order

US1 → (Foundational) → US3 → US2 → US4 → Polish. US1 and Foundational can run in parallel.

### Parallel opportunities

- T003 and T004 (different files).
- T009 alongside T005–T008 (`bun/defs.bzl` vs `e2e/smoke/`).
- US1 (T005–T009) alongside Foundational and US3, since `e2e/smoke/` and `bun/` do not overlap;
  T013 edits `bun/toolchain.bzl`, which `e2e/smoke` loads, so rerun `e2e/smoke` tests after it.
- T024 alongside T021–T023 (different files: `versions_test.bzl` vs `toolchain_test.bzl`,
  but both add a line to `bun/tests/BUILD.bazel`; merge that line last).

### Parallel example: User Story 1

```text
Task T005–T008: e2e/smoke/MODULE.bazel, verify_test.bzl, verify.bzl, BUILD.bazel (sequential)
Task T009:      bun/defs.bzl docstring (parallel)
```

### Parallel example: User Story 4

```text
Task T021–T023: bun/tests/toolchain_test.bzl, bun/private/toolchain.bzl (sequential)
Task T024:      bun/tests/versions_test.bzl (parallel)
```

---

## Implementation Strategy

### MVP (User Story 1)

1. T001–T002, then T005–T009.
2. Validate: `(cd e2e/smoke && bazel test //...)` passes locally; Windows is covered by CI in POST-2.
3. This alone unblocks the BCR presubmit's `//...` in `e2e/smoke`.

### Incremental delivery

1. Setup + Foundational.
2. US1 → e2e has tests (MVP).
3. US3 → selection and exec-cfg are proven per execution platform.
4. US2 → shell-free, toolchain-only ruleset.
5. US4 → baseline alignment, `BUN_BIN`, versions test, register updated.
6. Polish → hand-back checks, review, CI on three OSes.
