# Feature Specification: Complete the Bun Toolchain Ruleset

**Feature Branch**: `001-complete-toolchain-ruleset`

**Created**: 2026-09-29

**Status**: Draft (revised after adversarial review)

**Input**: User description: "Complete rules_bun as a Bun toolchain ruleset that follows bazel.build documentation and the bazel-contrib/rules-template baseline exactly, with no workarounds, and develop it test-first (TDD): every task writes or changes a test, runs it and records that it fails for the expected reason, then implements until it passes. Scope stays a toolchain ruleset as AGENTS.md defines it; no bun_binary/bun_test/install rules. Known gaps to close: (1) e2e/smoke has no test target, so 'bazel test //...' fails there on every OS and in the BCR presubmit; it needs a test that runs the registered toolchain's Bun as an external consumer would. (2) bun/tests/hardening_test.bzl uses ctx.actions.run_shell and a generated .sh launcher, which constitution principle VI forbids and which cannot run on Windows. (3) bun/repositories.bzl and bun/private/toolchains_repo.bzl feature-detect repository_ctx.repo_metadata with hasattr although every Bazel in bazel_compatibility (>=9.2.0) provides it, which principle V forbids. (4) Compare every file against bazel-contrib/rules-template and the bazel.build toolchain, module-extension and repository-rule documentation, and close each remaining divergence the plan's research.md can source (for example the toolchain rule's TemplateVariableInfo and a resolved_toolchain target, if the baseline defines them). Tests must pass on linux, macos and windows as CI and .bcr/presubmit.yml run them."

**Revision (2026-09-29, after review)**: The user decided that the hardening machinery in
`bun/private/` (`action.bzl`, `hardening.bzl`, `paths.bzl`) and its tests are deleted, because no
consumer can reach them and the ruleset's scope is the toolchain only. The baseline removed its
resolved-toolchain target (rules-template PR #188, "remove resolved toolchain for genrules
workaround", merged 2026-06-21), so none is added. The baseline is
`bazel-contrib/rules-template@cb8787e74153b061b473a7bac92ac11aa2cca346`.

## User Scenarios & Testing *(mandatory)*

Actors:

- **Consumer**: a Bazel module that depends on `rules_bun`, registers its toolchain, and writes rules
  that run Bun.
- **Maintainer**: a person who changes `rules_bun` and must know, from test results alone, whether
  the change is correct on every supported platform.
- **Registry**: the Bazel Central Registry presubmit, which accepts a release only if the test
  module passes on every platform it runs.

### User Story 1 - The consumer test module passes everywhere (Priority: P1)

A consumer adds `rules_bun`, registers the toolchain, and runs the tests of the example consumer
module (`e2e/smoke`). Today that module declares no test, so its test run fails on every OS (CI
run 36447818686: "No test targets were found") and the registry would reject every release. After
this feature, the module contains a test that runs Bun from the registered toolchain in a build
action, exactly as the bazel.build toolchain documentation tells a consumer rule to, and checks
the version Bun reports against the version the module requested.

**Why this priority**: Without it no release can be published, and nothing proves the toolchain
works for anyone other than the ruleset itself.

**Independent Test**: Run the consumer module's full test set on Linux, macOS and Windows; it
passes, and it fails if the requested version and the version Bun reports differ.

**Acceptance Scenarios**:

1. **Given** the consumer module as checked in, **When** its full test set runs on Linux, macOS or
   Windows, **Then** at least one test runs and all tests pass.
2. **Given** the consumer module requests Bun version X in `MODULE.bazel`, **When** the test runs,
   **Then** it compares Bun's reported version with the literal X written in the test's BUILD
   file, not with a value derived from the toolchain, and passes only if they are equal.
3. **Given** the consumer rule's action, **When** it runs Bun, **Then** the action names the Bun
   toolchain type as its `toolchain`, as `ctx.actions.run` documents for tools that come from a
   toolchain.

---

### User Story 2 - The ruleset holds only the toolchain (Priority: P2)

A maintainer finds no code in the ruleset that no consumer can use. The private hardening helper
(`bun_action`, `hardening_args`, `empty_bunfig`, `runfiles_path`) and its tests are removed, which
also removes the only shell action and shell launcher the repository authored.

**Why this priority**: Unreachable code makes claims (constitution II) about behavior no consumer
gets, and its test is the one that cannot run on Windows (CI: `hardening_test.sh ... %1 is not a
valid Win32 application`).

**Independent Test**: Search the repository for `run_shell`, for generated scripts written by its
own rules, and for loads of the deleted files; none remain, and the root test set passes.

**Acceptance Scenarios**:

1. **Given** the repository after this feature, **When** it is searched, **Then** no rule or test
   authored in it calls `ctx.actions.run_shell` or writes a shell script or launcher. Launchers
   generated by bazel-skylib rules are allowed (constitution VI).
2. **Given** the root module, **When** its full test set runs, **Then** it passes without the
   deleted files.

---

### User Story 3 - Toolchain tests prove what they claim (Priority: P3)

The existing `cross_*_test` targets transition only the **target** platform, but the Bun toolchain
is an execution toolchain, so those tests do not prove Bun is selected per execution platform.
After this feature, every test that claims toolchain selection varies the platform the toolchain
is actually selected by, or they are replaced. The documented way is an `analysistest` whose
`config_settings` sets `//command_line_option:extra_execution_platforms`
(https://bazel.build/rules/testing), as bazel-contrib/rules_python
(`tests/base_rules/py_executable_base_tests.bzl`) and bazelbuild/rules_rust
(`test/unit/lint_tests/lint_tests.bzl`) do.

**Why this priority**: A test that passes for the wrong reason is worse than no test.

**Independent Test**: Each remaining toolchain-selection test fails when the matching
`exec_compatible_with` in the generated toolchain hub is wrong.

**Acceptance Scenarios**:

1. **Given** a selection test for platform P, **When** the hub's toolchain for P declares the wrong
   constraints, **Then** the test fails.
2. **Given** an analysis test whose extra execution platform is P, **When** it analyzes a rule that
   declares the Bun toolchain type, **Then** the resolved Bun comes from the repository for P
   (for example `bun_darwin-aarch64`), not from the host's.

---

### User Story 4 - Structure matches the reference baseline (Priority: P4)

A maintainer compares each file with the baseline and with the bazel.build documentation for
toolchains, module extensions and repository rules. Each divergence is closed, or recorded in
`research.md` with a source URL and a reason.

**Why this priority**: Following the baseline keeps the ruleset familiar and maintainable; it
builds on stories 1–3.

**Independent Test**: Every closed divergence has a test; every other divergence has a status and
a reason in `research.md`.

**Acceptance Scenarios**:

1. **Given** the baseline's toolchain rule returns `platform_common.TemplateVariableInfo`
   (`mylang/toolchain.bzl`), **When** a `genrule` lists the Bun toolchain type in `toolchains` and
   uses `$(BUN_BIN)` in `cmd`, **Then** analysis expands it to the `File.path` of the resolved Bun. The test inspects the action with
   `analysistest`; the genrule is tagged `manual`, so `bazel test //...` never builds it and no
   shell runs.
2. **Given** a divergence that the constitution or AGENTS.md mandates, **When** `research.md` is
   written, **Then** it is recorded as intentional with the principle it follows.

### Edge Cases

- Windows: Bun is `bun.exe`; the consumer test must work without a shell, and any file compared
  byte-for-byte must be written with LF endings.
- The execution platform differs from the target platform: the consumer test runs Bun in a build
  action, so it must use the execution toolchain, not a runfiles or target-platform Bun.
- A test written first passes before implementation: the test is wrong and must be changed until it
  fails for the expected reason. This does not apply to refactors and deletions that change no
  observable behavior, nor to tests that guard existing behavior, whose red is a recorded,
  reverted mutation (see FR-009).
- A divergence cannot be closed without an undocumented or deprecated API: work on it stops and the
  gap is reported (constitution V).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The consumer test module MUST contain at least one test, so that running all of its
  tests succeeds on Linux, macOS and Windows.
- **FR-002**: That test MUST obtain Bun only through the public API (`BUN_TOOLCHAIN_TYPE`,
  `BunInfo`), run it in a build action with `ctx.actions.run` and `toolchain = BUN_TOOLCHAIN_TYPE`,
  and compare the reported version with a literal version written in the test's BUILD file.
  The comparison MUST use bazel-skylib's `diff_test` against a `write_file` with
  `newline = "unix"`; the consumer module adds `bazel_skylib` as a `dev_dependency` and its
  `MODULE.bazel.lock` is updated.
- **FR-003**: `bun/private/action.bzl`, `bun/private/hardening.bzl`, `bun/private/paths.bzl`,
  `bun/tests/action_test.bzl`, `bun/tests/hardening_test.bzl` and their BUILD targets MUST be
  removed. `action_fixture` is used by the `cross_*_test` targets, so FR-010's replacement tests
  MUST land first, and the deletion MUST also remove `with_platform`,
  `bun/tests/platform_transition.bzl` and any other target left unused.
- **FR-004**: No rule or test authored in this repository MAY call `ctx.actions.run_shell` or write
  a shell script or shell launcher; launchers generated by bazel-skylib rules are allowed, and so is
  a `manual`-tagged genrule that is only analyzed, never built (FR-007).
- **FR-005**: Repository rules MUST NOT feature-detect `repository_ctx.repo_metadata`, which every
  Bazel in `bazel_compatibility` provides (added in Bazel 8.3.0). The baseline keeps this guard
  for Bazel <8.3.0, so `research.md` MUST record the divergence as intentional (constitution V).
- **FR-006**: Every path in the baseline tree at the pinned commit, and every file of this
  repository, MUST be compared with each other and with the bazel.build pages for toolchains
  (https://bazel.build/extending/toolchains), module extensions
  (https://bazel.build/external/extension) and repository rules
  (https://bazel.build/external/repo). `research.md` MUST list that path set, which is the
  denominator of SC-005. Each divergence MUST be recorded in
  `research.md` with a source URL and one status: **closed** (with its test), **intentional** (with
  the constitution principle or AGENTS.md rule it follows), **out of scope** (with the excluded
  scope), **equivalent** (the form differs but a cited source shows the behavior is identical,
  such as removed comments or two documented spellings of the same setting), or **gap** (no
  supported API exists). A path with no divergence is recorded as **equal**. Known divergences to record include: the
  baseline's `target_type` toolchain type and target toolchains, its `target_tool_path` for
  host-installed tools, its self-registration of toolchains, its `hasattr` guard, its
  `.bazelignore` listing `e2e/`, its `toolchains_repo` returning no `repo_metadata`, its
  presubmit testing Bazel `9.*` and `8.*`, its non-dev `bazel_skylib`, and its
  `mylang/tests/versions_test.bzl`.
- **FR-007**: `bun_toolchain` MUST return `platform_common.TemplateVariableInfo` with `BUN_BIN`, as
  the baseline does. `BUN_BIN` MUST hold the executable's `File.path`, because a genrule `cmd` runs
  from the execution root (https://bazel.build/reference/be/make-variables#custom_variables);
  this differs from the baseline's runfiles-style path, which is recorded as intentional. An
  `analysistest` MUST check the expanded command. Bun being an input of the genrule's action is
  not documented by Bazel, so it MUST NOT be asserted or promised, and is reported as a gap
  (constitution V).
- **FR-008**: Every `ctx.actions.run` in this repository that runs Bun MUST pass
  `toolchain = BUN_TOOLCHAIN_TYPE`, and the `BUN_TOOLCHAIN_TYPE` docstring in `bun/defs.bzl` MUST
  show a consumer doing so.
- **FR-008a**: The `bun` attribute of `bun_toolchain` MUST use `cfg = "exec"`, because an attribute
  without it is built for the target platform
  (https://bazel.build/extending/toolchains#toolchains-and-configurations). A test MUST give the
  toolchain a generated file and check that it is built for the execution platform while the
  target platform differs.
- **FR-009**: A task that changes observable behavior MUST first add or change a test, run it and
  record that it fails for the expected reason, then implement until it passes. A red state MAY be an
  analysis or build error when the missing behavior makes the target unanalyzable, as long as the
  error names the missing behavior. A test that guards behavior which already exists
  (so no implementation is missing) MUST record its red by a mutation that breaks that behavior,
  marked as a mutation and reverted. A task that only deletes or refactors MUST record the existing
  tests that still pass after it. A research or documentation task records no test. The records
  MUST be kept with the feature.
- **FR-010**: Toolchain-selection tests MUST vary the execution platform with `analysistest`
  `config_settings` on `//command_line_option:extra_execution_platforms`, for every platform in
  `PLATFORMS` other than the host's, and replace the `cross_*_test` targets
  (User Story 3).
- **FR-011**: The ruleset MUST NOT add rules that run Bun programs, run Bun tests, or install
  packages, and MUST NOT add public targets other than `//bun/toolchain:execution_type`
  (constitution I).
- **FR-012**: Build diagnostics added or changed by this feature (`fail()`, progress messages,
  test failure messages) MUST be in English, like all other text in the repository (AGENTS.md,
  revised 2026-10-01 at the user's direction; the ruleset is not for Korean speakers only).
- **FR-013**: Non-dev `bazel_dep` minimum versions MUST NOT be raised unless a change needs it, and
  the consumer module MUST keep passing with exactly the declared versions (constitution IV).
- **FR-014**: Documentation and reports MUST claim only behavior a test covers and MUST name the
  platforms each test actually ran on; platforms not run are reported as unverified.

### Key Entities

- **Consumer test module** (`e2e/smoke`): an independent Bazel module that uses `rules_bun` only
  through its public API; the registry runs it.
- **Bun toolchain**: the registered execution toolchain that gives a rule the Bun executable, its
  version and its files, and exposes `BUN_BIN` to make-variable expansion.
- **Divergence record**: an entry in `research.md` naming a file, the baseline or documentation it
  differs from, the source URL, and its status (closed, intentional, out of scope, gap).
- **Test-first record**: per task, the failing run before implementation, or for deletions and
  refactors, the passing existing tests after it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Running all tests of the consumer module succeeds on 3 of 3 CI platforms (Linux,
  macOS, Windows).
- **SC-002**: Running all tests of the root module succeeds on 3 of 3 CI platforms.
- **SC-003**: Zero `run_shell` calls and zero shell scripts or launchers written by this
  repository's own rules and tests.
- **SC-004**: Zero feature-detection branches remain for APIs every supported Bazel version provides.
- **SC-005**: 100% of divergences in `research.md` carry a source URL and a status, and every
  closed one is covered by a test.
- **SC-006**: 100% of behavior-changing, deletion and refactor tasks have the record FR-009
  requires.

## Assumptions

- Local verification runs on Linux only (WSL); macOS and Windows results come from CI and are
  reported as unverified until CI succeeds there.
- The registry presubmit runs only on a registry pull request after a release tag, so it is not a
  criterion of this feature. CI covers the same three OSes. The presubmit uses `bazel: 9.x` while
  `e2e/smoke/.bazelversion` pins 9.2.0; that difference is recorded, not changed here.
- The supported Bazel range stays `>=9.2.0`; this feature does not change `bazel_compatibility`.
- Release automation from the baseline (tag creation, version tooling) is out of scope, per the
  existing release-tooling decision.
- The public names `BUN_TOOLCHAIN_TYPE`, `BunInfo`, `bun_toolchain` and the `bun` module extension
  remain. The deleted files are in `bun/private/` and `bun/tests/`, which constitution I says may
  change in any release.
