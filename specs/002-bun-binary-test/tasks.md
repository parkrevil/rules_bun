---

description: "Task list for bun_binary, bun_test and bun_library"
---

# Tasks: Run Bun Programs and Bun Tests (`bun_binary`, `bun_test`)

**Input**: Design documents from `specs/002-bun-binary-test/`

**Prerequisites**: plan.md (updated for spec Revision 13), spec.md (Revisions 1–13, FR-028),
research.md (Part 1 G1–G15, G-impl-1, "Plan for spec Revision 10" through "Plan for spec
Revision 13", Part 2 R1–R14), data-model.md, contracts/public-api.md, quickstart.md

**Tests**: Requested (test-first, FR-020). Every behavior task writes or changes a test first,
runs it, and records in `specs/002-bun-binary-test/tdd-log.md` that it fails for the expected
reason, then implements until it passes. A test that guards behavior which already exists records
a reverted mutation as its red. A canary's red is a mutation of its pinned expectation, recorded
and reverted (data-model "Upstream canaries"). Refactor and dependency tasks record the existing
tests that still pass. Documentation and research tasks record no test.

**Organization**: Grouped by user story, in the order of plan "Implementation Order", which
tasks.md refines. The target-platform toolchain, `bun_library` and a launch skeleton are
Foundational because every story needs them. The copy tree is in US1 (it delivers US1-3,
generated data) and also covers US3-4; the load guard is in US3. Three changes to the plan's
order or wording:

1. Exit-code propagation is added in the skeleton (T011–T012), before any spawn test, because a
   spawn test is itself a `bun_test` and can report a failure to Bazel only once the launcher
   passes on Bun's exit code; the US1 non-zero-exit spawn test (T019) therefore records a mutation
   as its red.
2. The CI workflow task (T081) is in Polish, after US5, because its jobs run the `e2e/smoke`
   targets of T078 (analysis finding O1).
3. Coverage (T048) matches each of Bun's `SF:` values against the declared copies by two readings
   (G15): the value joined to the real path of the working directory the launcher gives the
   second process, and the value itself when it is absolute. That working directory is the
   copy-tree root data-model names once T054 moves it there; before T054 it is the launcher's own,
   so the matching is correct at both steps.

Withdrawn by spec Revision 10 and absent here: the `--config` of `bun test` (G3, canary C3),
`--pass-with-no-tests` (G8, canary C5), the inserted `--` (G13, canary C6), the other-drive test
(G9), canaries C8–C12. C14 (an empty shard passes) and C15 (manifest escaping) are ordinary
assertions in T041 and T029.

Changed by spec Revision 11 (research Part 1 "Plan for spec Revision 11"), with the task IDs kept:
T053 and T054 (a `bun_test` gets no configuration file: the rule writes no `bunfig.toml` into the
copy tree, and the test checks only the Bazel side, that the second process runs at the copy-tree
root and that this root holds no file; `isolated_bunfig.toml` is passed to `bun_binary` from
runfiles, not copied; test files are passed as `./<tree path>`, finding A1 of 2026-10-08); T055
(canary C4 pins the runtime `bun --config <path> <file>` and `bun -c <path> <file>`); T056 (no
`.env` fixture at the copy-tree root, which must hold no file); T057 (FR-001 step 1: the stub
embeds `--no-env-file`, the static launcher and the launch configuration, no `--config=`); T083
(the undocumented `bun test` lookup and the accepted-but-untested allowlisted options, finding U2
of 2026-10-08).

Changed by spec Revision 12 (research Part 1 "Plan for spec Revision 12"). New tasks take IDs after
T087 so that every existing ID stays stable; they sit in their phase in execution order:
T048 (each `SF:` value is matched against the declared copies by two readings, G15; a record that
matches no copy or several is still dropped until T089, and the launcher's own record is removed by
the same comparison); T088 and T089 (the G15 error: a coverage spawn test whose test calls
`process.chdir`, red while unmatched records are dropped, then the English error and no `.dat`);
T054 (it also re-runs T088); T090 (the `e2e/smoke` root `bunfig.toml`, `smoke_preload.ts` and
`.env`, declared by no target, asserted by the consumer `bun_test`; the result is recorded per OS,
and a failure is a gap, not worked around); T081 (after T090); T083 (the reach of the
parent-directory lookup, which includes `execroot/_main`, and the `process.chdir` coverage
limitation); POST-1 (the per-OS result of T090).

Changed by spec Revision 13 (research Part 1 "Plan for spec Revision 13", plan step 11). On Linux
and macOS the executable becomes a shell launcher generated from `bun/private/launcher.sh.tpl` that
finds its files with the Bash runfiles library of `rules_shell` 0.6.1; Windows keeps the
hermetic-launcher stub. Completed task IDs and their records stay as they are; what Revision 13
changes in their expectations is done by new tasks T102–T114 (Phase 13):
- the stub's embedded arguments (T009 as changed by T056) and the 256-byte limit (T017–T018) are
  asserted for a Windows target only (T104), and a long name analyzes on Linux (T105);
- `copy_tree_test_suite`'s T053 assertion that a `bun_test`'s runfiles lack
  `isolated_bunfig.toml` is inverted for Linux and macOS (T105);
- the `no_stub` platform of T075 moves to Windows, and a FreeBSD target analyzes with the shell
  launcher (T106);
- the first-process `bunfig.toml` limitation of FR-018a (G4) is tested as absent on Linux and
  macOS (T109); canary C4 keeps running on every OS and names the Windows limitation (T113).

Withdrawn by Revision 13, with their needs carried by Phase 13: T092 (implement the G-impl-1
decision) → T103–T111; T095 (the `--spawn_strategy=local` run and the CI step) → T111, T112; T097
(align quickstart and the `bun_test` `doc`) → T113 (quickstart already carries Revision 13); T099
(hand option 1 to the user) → withdrawn, the user decided by Revision 13, and T102 hands over the
one open item, O-13; T100 (the G-impl-1 canary) → withdrawn, G-impl-1 is resolved, not worked
around, so it has no canary (plan "Upstream canaries"). T101's draft report is completed and is
not filed (research G-impl-1 "Resolution"). Plan step 11's precondition is O-13: spec FR-022 and
SC-005 still forbid shell launchers, so no Phase 13 task after T102 starts until a spec revision
settles it (constitution, Governance).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1–US5 from spec.md

## Conventions for every task

- **Record**: append one row to `specs/002-bun-binary-test/tdd-log.md` with the columns
  `Task | Kind | Red | Green | Platforms` (data-model "Test-first record"). Kind is one of
  baseline, behavior, mutation, canary, refactor, dependency, research, documentation,
  verification. Red: command, exit code, the failure line naming the missing behavior (mark
  mutation runs and say what was mutated and that it was reverted). Green: command and result.
  Platforms: Linux (WSL) for local runs; macOS and Windows only with a named CI run (FR-026).
- **Genuine red**: behavior is added only after its test has failed against code without it
  (FR-020, research R12 "Red order"). Write each implementation step minimal: it MUST NOT already
  contain the behavior a later task tests (no isolation option, no leading-`--` rejection, no
  allowlist, no sharded-filter rejection, no guard, no length check, no declared-file limit, no
  G15 coverage error before their tasks). If a new test passes before its implementation and the task is not marked as a
  mutation task, the test is wrong; change it until it fails for the expected reason (spec Edge
  Cases).
- **Parallel marker and mutations** (analysis finding P1): [P] is set only on a task that edits
  none of `bun/private/launcher.js`, `bun/private/run.bzl` and (Revision 13)
  `bun/private/launcher.sh.tpl`, not even temporarily. A task whose red is a mutation of one of
  them is sequential: apply the mutation, run, record, revert, while no other task edits that
  file.
- **Windows-only behavior** (G1, canary C7): local runs are Linux only (spec Assumptions). Record
  the red as "not run locally (Windows only)" and the result from the CI run in POST-1; report it
  unverified until then (constitution II). Since Revision 13 this covers everything the
  hermetic-launcher stub does (embedded arguments, the 256-byte limit, G1, G4). Analysis tests of
  the stub run under `--platforms=//bun/tests/platforms:windows_x64` (or another Windows platform)
  for `bun_binary` only, because a Windows `bun_test` does not analyze on a Linux host (T093).
- **macOS** (Revision 13): the shell launcher runs on macOS only in CI; analysis tests under the
  `darwin_*` platforms are local, and every run result on macOS comes from POST-1.
- **Symlinks** (analysis finding U2): a test that creates a symlink (canary C1; C11, which also
  did, is withdrawn by Revision 10) first checks that it can. If the runner lacks the privilege
  (Windows), the test logs that and passes without asserting, and the canary is reported
  unverified on that OS in POST-1 (plan Risks), never skipped silently.
- **English**: every `fail()` message, `doc =` string, docstring, comment, `asserts.*` `msg`,
  thrown `Error` and test name is English (FR-025). Each new rule, attribute and provider gets an
  English `doc` when it is created; T083 completes the limitation lists.
- **No shell** (constitution VI, FR-022): actions only through `ctx.actions.run` (with `Args`),
  `ctx.actions.write` and, for the Linux and macOS launcher only (Revision 13, once O-13 is
  settled by T102), `ctx.actions.expand_template` of `bun/private/launcher.sh.tpl`; no
  `run_shell`, no `.sh`, `.bat`, `.cmd` or `.ps1` file; no test writes or runs a shell script;
  fixtures that need a directory or many files are written by test-only Starlark rules with
  `ctx.actions.write`, or with `ctx.actions.run` of the execution-platform Bun
  (`BUN_TOOLCHAIN_TYPE`).
- **Spawn tests** (FR-021): a passing `bun_test` lists the `manual` target in `data`, resolves its
  executable with the support helper of T013, starts it with `Bun.spawn`, and asserts exit code
  and output. Expected-failure targets are tagged `manual`.
- **JUnit assertions**: "the JUnit report holds N `<testcase>`" counts `<testcase` elements in the
  file the spawn test named in `XML_OUTPUT_FILE`; a report that was not written counts as zero.
- **Canaries** (FR-028; C1, C2, C4, C7, C13 only): a `bun_test` in `bun/tests/canary/` unless
  stated; it runs the toolchain's Bun (`process.execPath`) on fixtures under `TEST_TMPDIR`; when
  its assertion fails it fails with an English message naming the workaround to remove or revisit
  and the upstream link from data-model "Upstream canaries". Canary tasks are marked [P]: their
  mutation edits only the canary's own expectation. Each adds one target to
  `bun/tests/canary/BUILD.bazel`, so merge that line last.
- **BUILD hygiene**: after adding a `.bzl` file, run `bazel run //:gazelle` so `bzl_library`
  targets exist (`bun/BUILD.bazel`, `bun/private/BUILD.bazel`); add a dependency on the
  `hermetic_launcher` or `bazel_lib` `bzl_library` where a file loads from them.
- **Stop rule**: if a step needs an undocumented or deprecated API, or a Bun option bun.com does
  not document for the command it is passed to, that research.md does not already record as
  decided, stop and report the gap (constitution V, FR-004). Do not widen a task to fix an
  unrelated failure; report it (AGENTS.md).

---

## Phase 1: Setup

**Purpose**: Create the record file, capture the starting state, add the dependencies.

- [X] T001 Create `specs/002-bun-binary-test/tdd-log.md` with a title, a one-paragraph purpose
  citing FR-020 and FR-028, a note that local runs are Linux (WSL2, Bazel 9.2.0) and macOS and
  Windows appear only with a named CI run, and a Markdown table header
  `| Task | Kind | Red | Green | Platforms |`.
- [X] T002 Record the starting state in `specs/002-bun-binary-test/tdd-log.md` (Kind: baseline):
  run `bazel test //...` in the root and `(cd e2e/smoke && bazel test //...)`; record exit codes
  and the list of test targets of each. This is not a red of any test.
- [X] T003 Update `MODULE.bazel` (Kind: dependency; research R1, R6, "Revision 8 fixes", G14):
  add `bazel_dep(name = "hermetic_launcher", version = "0.0.16")` (non-dev) with the comment
  `# On any hermetic_launcher bump, check hermetic-launcher#81 (G4) and #80 (G1).` on the line
  above (FR-028, G14); raise `bazel_dep(name = "platforms", version = "1.0.0")` to `"1.1.0"`;
  change `bazel_dep(name = "bazel_lib", version = "3.7.2", dev_dependency = True)` to a non-dev
  `bazel_dep(name = "bazel_lib", version = "3.7.2")` (the floor is fixed in T082). Refresh
  `MODULE.bazel.lock` and `e2e/smoke/MODULE.bazel.lock` with
  `bazel mod deps --lockfile_mode=update` in each module. Check from `@hermetic_launcher`'s
  `MODULE.bazel` (0.0.16) that it registers its own template and finalizer toolchains; if a
  consumer would have to register them, stop and report (the contract promises no extra
  registration). Record: root `bazel test //...` and `(cd e2e/smoke && bazel test //...)` pass
  with feature 001's tests unchanged (FR-010), and `bazel mod graph` shows `platforms` 1.1.0 in
  both modules (quickstart 7a).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The target-platform toolchain (R3), `bun_library` (R4), the launch skeleton (R1, R2)
with exit-code propagation, and the spawn helper every spawn test uses (FR-021).

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T004 Write the red selection test for `//bun/toolchain:target_type` (R3, FR-009, SC-007):
  create `bun/tests/target_toolchain_test.bzl` with a module docstring, a test-only rule
  `resolved_target_bun` (declares `toolchains = ["//bun/toolchain:target_type"]` and returns
  `DefaultInfo(files = depset([ctx.toolchains[...].buninfo.bun]))`), and a macro
  `target_toolchain_selection_test_suite(name)` that, for each of the five literal platforms in
  `bun/tests/platforms/BUILD.bazel` (`linux_x64`, `linux_aarch64`, `darwin_x64`,
  `darwin_aarch64`, `windows_x64`), declares a `manual` `resolved_target_bun` and an
  `analysistest` with `config_settings = {"//command_line_option:platforms": [<platform>]}`
  asserting, with an English `msg`, that the resolved file's owner is
  `Label("@bun_<platform>//:bun")` (`bun.exe` target for Windows, as feature 001's selection suite
  names it). Register the suite as `target_selection` in `bun/tests/BUILD.bazel`. Run
  `bazel test //bun/tests:target_selection`; record the red: "no such target
  '//bun/toolchain:target_type'".
- [X] T005 Make T004 green (R3): add `toolchain_type(name = "target_type", visibility =
  ["//visibility:public"])` to `bun/toolchain/BUILD.bazel`; add `bun_target_toolchain` to
  `bun/private/toolchain.bzl` (`bun` attribute `attr.label(mandatory = True, allow_single_file =
  True)` with no `cfg`, `version` `attr.string(mandatory = True)`; returns `DefaultInfo` and
  `platform_common.ToolchainInfo(buninfo = BunInfo(bun, version, tool_files = [bun]))`, no
  `TemplateVariableInfo`); export it from `bun/toolchain.bzl`; add
  `BUN_TARGET_TOOLCHAIN_TYPE = Label("//bun/toolchain:target_type")` to `bun/defs.bzl`; in
  `bun/private/repositories.bzl` add `bun_target_toolchain(name = "bun_target_toolchain", bun =
  ":bun", version = …)` next to `bun_toolchain` in each platform repository's BUILD; in
  `bun/private/toolchains_repo.bzl` add, per platform, `toolchain(name =
  "<platform>_target_toolchain", target_compatible_with = <constraints>, toolchain =
  "@<name>_<platform>//:bun_target_toolchain", toolchain_type =
  "@rules_bun//bun/toolchain:target_type")` with no `exec_compatible_with` (data-model "Generated
  repositories"). `bun_toolchain`, `execution_type` and their toolchains stay unchanged. Record
  green: `bazel test //bun/tests:target_selection` passes, and feature 001's suites pass unchanged
  (US4-5, FR-010).
- [X] T006 Add the target-configuration test (US4-3, R3) to `bun/tests/target_toolchain_test.bzl`:
  a `bun_target_toolchain` whose `bun` is a generated file (bazel-skylib `write_file`), wrapped by
  `resolved_target_bun` with a registered test-only `toolchain()` (via `config_settings`
  `"//command_line_option:extra_toolchains"`), asserting the generated Bun is built in the target
  configuration (its output path contains no `-exec` segment). This guards T005: record the red
  as a mutation (set `cfg = "exec"` on `bun_target_toolchain.bun` in `bun/private/toolchain.bzl`),
  revert, record green.
- [X] T007 Write the red `bun_library` test (R4, FR-006): create `bun/tests/run_test.bzl` with a
  module docstring and a macro `library_test_suite(name)` declaring `manual` fixtures (two
  `bun_library` targets, the outer one with `deps` on the inner one, each with one `.ts` source
  and one data file) and `analysistest`s asserting: `BunLibraryInfo.srcs` is the transitive
  sources; `BunLibraryInfo.data` is the transitive data files (`DefaultInfo.files` of `data`);
  `DefaultInfo.files` is the own `srcs`; runfiles hold the sources, the data files and the
  `default_runfiles` of `data` and `deps`; under `"//command_line_option:collect_code_coverage":
  True` with an `instrumentation_filter` covering the fixtures, `InstrumentedFilesInfo` names the
  sources. Register it in `bun/tests/BUILD.bazel`. Record the red: loading fails because
  `bun_library` and `BunLibraryInfo` are not in `bun/defs.bzl`.
- [X] T008 Make T007 green: add `BunLibraryInfo` (fields `srcs: depset[File]` "transitive
  TypeScript/JavaScript sources", `data: depset[File]` "transitive files of `data` targets
  (`DefaultInfo.files`)", data-model "Providers") to `bun/private/providers.bzl`; create
  `bun/private/library.bzl` with `bun_library` (`srcs`: `allow_files = [".ts", ".tsx", ".mts",
  ".cts", ".js", ".jsx", ".mjs", ".cjs"]`; `data`: any; `deps`: `providers = [BunLibraryInfo]`)
  returning `BunLibraryInfo`, `DefaultInfo` and
  `coverage_common.instrumented_files_info(ctx, source_attributes = ["srcs"],
  dependency_attributes = ["deps", "data"])`; export `bun_library` and `BunLibraryInfo` from
  `bun/defs.bzl`. Record green.
- [X] T009 Write the red launch-skeleton tests (R1, R2, FR-005, FR-001): create
  `bun/tests/run/BUILD.bazel` with `bun_test(name = "skeleton_test", srcs = ["skeleton.test.ts"])`
  (a test asserting `typeof Bun.version === "string"`) and `bun_binary(name = "hello", entry_point =
  "hello.ts", tags = ["manual"])` (prints `hello`); add to `bun/tests/run_test.bzl` a macro
  `skeleton_test_suite(name)`, registered as `skeleton` in `bun/tests/BUILD.bazel`, whose
  `analysistest`s assert, for `//bun/tests/run:hello`:
  (a) the executable is not a source file;
  (b) runfiles hold the Bun of the target toolchain for the host platform,
  `bun/private/launcher.js` and `hello.launch.json`;
  (c) the `FileWrite` action of `hello.launch.json` writes JSON with `mode` `"binary"`, `label`
  and `entry_point` (an rlocation path, data-model "Launch configuration");
  (d) the embedded stub arguments (analysis finding D3) are, in order, the rlocation path of that
  Bun, of `bun/private/launcher.js` and of `hello.launch.json` — three of hermetic-launcher's 10.
  Read `@hermetic_launcher//launcher:lib.bzl` at 0.0.16 first to see how `compile_stub` hands the
  embedded arguments to its action (the action's `argv`, or a file it writes with
  `ctx.actions.write`), find that action in `analysistest.target_actions(env)` by its output
  being the executable, and assert there; if `lib.bzl` exposes them in neither place, stop and
  report (Stop rule). T056 changes this expectation to four arguments.
  Record the red: loading fails because `bun_binary` and `bun_test` are not in `bun/defs.bzl`.
- [X] T010 Make T009 green with a minimal launch chain (R1, R2): create `bun/private/run.bzl`
  with one shared implementation for `bun_binary` (`entry_point`: `attr.label(allow_files =
  True)`; `srcs`; `data`) and `bun_test` (`srcs`, `data`; `test = True`), declaring the toolchains
  `//bun/toolchain:target_type`, hermetic-launcher's `launcher.template_toolchain_type` and
  `launcher.finalizer_toolchain_type` (all mandatory for now; T076 makes two optional); write
  `<name>.launch.json` with `ctx.actions.write(json.encode(...))` holding `mode`, `label`,
  `entry_point` (binary) or `tests` (test) as rlocation paths (`_main/…` or `<canonical repo>/…`,
  R5); build the stub with `launcher.compile_stub(..., cfg = "target")` from
  `@hermetic_launcher//launcher:lib.bzl` with the embedded arguments `[bun, launcher.js,
  <name>.launch.json]` as runfiles; return `DefaultInfo(executable = stub, runfiles = …)` holding
  the Bun tool files, the stub's inputs, `launcher.js`, `launch.json`, `srcs`, the entry point and
  `data`. Create `bun/private/launcher.js`: as main module (`import.meta.main`) it locates
  runfiles from `RUNFILES_MANIFEST_FILE` (plain `<link> <target>` lines, no unescaping yet) or
  `RUNFILES_DIR`, exits 1 with an English error when neither is set or a path is missing, reads
  `launch.json`, and starts `process.execPath` with `Bun.spawn` (`stdout` and `stderr`
  `"inherit"`, no `stdin` option, the launcher's working directory) on
  `[<real path of the entry point>, ...process.argv.slice(3)]` (binary) or
  `["test", ...process.argv.slice(3), ...<real paths of the test files>]` (test; a POSIX real path
  starts with `/`, which `bun test` treats as a file, BUN-discovery; T054 replaces these with
  `./`-relative paths), waits, and exits 0 (exit-code propagation is T012). Export `launcher.js`
  from `bun/private/BUILD.bazel` with `exports_files(["launcher.js"], visibility =
  ["//bun/tests:__subpackages__"])`; export `bun_binary` and `bun_test` from `bun/defs.bzl`
  directly (no wrapper macros). Record green: `bazel test //bun/tests/run:skeleton_test
  //bun/tests:skeleton` passes and `bazel run //bun/tests/run:hello` prints `hello`.
- [X] T011 Write the red exit-code test (US1-1, US2-2, FR-015): add
  `bun_test(name = "failing_test", srcs = ["failing.test.ts"])` to `bun/tests/run/BUILD.bazel`,
  not `manual`, with `test("fails on purpose", () => expect(1).toBe(2))`. Run
  `bazel test //bun/tests/run:failing_test`; record the red: Bazel reports PASSED although the
  test log names "fails on purpose" (the launcher exits 0).
- [X] T012 Make T011 green in `bun/private/launcher.js`: exit with the child's exit code; when the
  child ends by signal `n`, exit with `128 + n` (R2; unverified on Windows). Record green:
  `bazel test //bun/tests/run:failing_test` fails. Then tag `failing_test` `manual` and record that
  root `bazel test //...` passes.
- [X] T013 Add the spawn helper and its first spawn test (FR-021): create
  `bun/tests/support/BUILD.bazel` with `bun_library(name = "spawn", srcs = ["spawn.ts"],
  visibility = ["//bun/tests:__subpackages__"])`. `bun/tests/support/spawn.ts` exports
  `rlocation(path)` (resolves through `RUNFILES_DIR` or `RUNFILES_MANIFEST_FILE` as Bazel's runfiles
  libraries do, including BZ-manifest escaping of lines that start with a space: `\s`, `\n`, `\b`
  in the link, `\n`, `\b` in the target), `executable(rlocationPath)` (appends `.exe` when
  `process.platform === "win32"`), and `spawnTarget(rlocationPath, {args, env, cwd, stdin})`, which
  starts the target with `Bun.spawn` after removing `XML_OUTPUT_FILE`, `TEST_TOTAL_SHARDS`,
  `TEST_SHARD_INDEX`, `TEST_SHARD_STATUS_FILE`, `TESTBRIDGE_TEST_ONLY` and `COVERAGE_DIR` from the
  child's environment unless the caller sets them, keeps `RUNFILES_DIR` and
  `RUNFILES_MANIFEST_FILE`, and returns `{exitCode, stdout, stderr}`. Add
  `bun/tests/run/failing_spawn.test.ts` and `bun_test(name = "failing_spawn_test", srcs =
  ["failing_spawn.test.ts"], data = [":failing_test"], deps = ["//bun/tests/support:spawn"])`
  asserting a non-zero exit and that the output names "fails on purpose" (US2-2). This guards
  T012: record the red as a mutation (`bun/private/launcher.js` exits 0 again), revert, record
  green.

**Checkpoint**: `bazel test //...` passes; programs and tests run through the stub with the target
platform's Bun; spawn tests can observe expected failures.

---

## Phase 3: User Story 1 - Run a Bun program (Priority: P1) 🎯 MVP

**Goal**: `bazel run` runs a program's entry point as Bun's main module with its sources, data,
arguments, environment, exit code and standard streams; Bun runs per-target copies (FR-003).

**Independent Test**: `bazel run //bun/tests/run/app:main -- extra` exits 0, and exits non-zero
naming the wrong item when one argument changes (quickstart 3–4);
`bazel run //bun/tests/run/args:echo -- -- x` exits 1 naming the leading `--` (quickstart 4a); the
spawn tests in `bun/tests/run/{exit,args,stdin,tree,spaces}` pass under `bazel test //...`, also
with `--noenable_runfiles`.

### Program, library dependencies, environment

- [X] T014 [US1] Write the red self-checking program (US1-2…6, FR-012, FR-013, FR-014): create
  `bun/tests/run/lib/BUILD.bazel` with `bun_library(name = "greet", srcs = ["greet.ts"],
  visibility = ["//bun/tests:__subpackages__"])` (`greet(name)` returns `` `hello, ${name}` ``)
  and `bun/tests/run/app/` with `main.ts`, `message.txt` and `BUILD.bazel`:
  `bun_binary(name = "main", entry_point = "main.ts", data = ["message.txt"], deps =
  ["//bun/tests/run/lib:greet"], args = ["--name=world", "$(rlocationpath message.txt)",
  "split 'a b'"], env = {"GREETING": "hello"})` and a comment giving the command line
  `bazel run //bun/tests/run/app:main -- extra`. The third `args` value is the one Bazel's
  Bourne-shell tokenization splits (analysis finding G3; BZ-common): it MUST arrive as two
  arguments, `split` and `a b`. `main.ts` checks, and on the first mismatch prints an English
  message naming the item and exits 1: the import from the other package; the content of
  `join(import.meta.dir, "message.txt")`; `process.argv.slice(2)` equals `["--name=world",
  "_main/bun/tests/run/app/message.txt", "split", "a b", "extra"]`; the original data file read
  through `RUNFILES_DIR`/`RUNFILES_MANIFEST_FILE` at the second argument (contract "Locating
  data"); `process.env.GREETING === "hello"`; `import.meta.main === true`. Run
  `bazel run //bun/tests/run/app:main -- extra`; record the red: analysis fails because
  `bun_binary` has no attribute `deps` and no attribute `env`.
- [X] T015 [US1] Make T014 green in `bun/private/run.bzl`: add `deps` (`providers =
  [BunLibraryInfo]`) and `env` (`attr.string_dict`) to both rules; return `BunLibraryInfo`
  (transitive `srcs` and `data`) from `bun_binary` and `bun_test`; merge the `default_runfiles`
  of `deps` and `data`; return `RunEnvironmentInfo(environment = {k: ctx.expand_location(v,
  targets = data + deps + srcs)})` (R9; `$(location)` and `$(locations)` only, no
  `ctx.expand_make_variables`). Record green: the run prints nothing and exits 0; with one
  argument changed it exits 1 naming the argument (quickstart 3–4).
- [X] T016 [US1] Add `binary_test_suite(name)` to `bun/tests/run_test.bzl` (FR-014, SC-004):
  `analysistest`s asserting `RunEnvironmentInfo.environment` of a fixture with
  `env = {"ONE": "$(location :data_a)", "MANY": "$(locations :data_group)"}` holds the expanded
  paths, and that `bun_binary` returns `BunLibraryInfo` with its transitive files. Register it in
  `bun/tests/BUILD.bazel`. This guards T015: record the red as a mutation (drop
  `ctx.expand_location` in `bun/private/run.bzl`), revert, record green.
- [X] T017 [US1] Write the red analysis-failure tests (FR-007, FR-001 limit) in
  `bun/tests/run_test.bzl`: `analysistest`s with `expect_failure = True` asserting the failure
  message names `entry_point` for a `bun_binary` with no `entry_point`, with a `filegroup` of two
  `.ts` files, and with a `.txt` file; and one asserting the message names the path and the limit
  of 256 bytes for a `bun_binary` whose name is 240 characters long, so the rlocation path of
  `<name>.launch.json` exceeds 256 bytes (data-model: "Each must be ≤ 256 bytes, else analysis
  fails naming the path"). Record the red: the four targets analyze successfully.
- [X] T018 [US1] Make T017 green in `bun/private/run.bzl`: `fail()` naming `entry_point` unless it
  yields exactly one file with an extension in `.ts .tsx .mts .cts .js .jsx .mjs .cjs`; `fail()`
  naming the path and 256 bytes when an embedded stub argument's rlocation path is longer than 256
  bytes (HL-readme limit). Record green.

### Exit code, arguments, standard input

- [X] T019 [US1] Add the non-zero-exit spawn test (US1-1, spec Revision 9): create
  `bun/tests/run/exit/` with a `manual` `bun_binary(name = "exit3")` whose entry point calls
  `process.exit(3)` and a `bun_test(name = "exit_test")` that spawns it and asserts exit code 3.
  This guards T012 (see Organization): record the red as a mutation (`bun/private/launcher.js`
  exits 0), revert, record green.
- [X] T020 [US1] Add the argument spawn tests (US1-4, US1-6, FR-013): create `bun/tests/run/args/`
  with a `manual` `bun_binary(name = "echo", visibility = ["//bun/tests:__subpackages__"])`
  printing `JSON.stringify({argv: process.argv.slice(2), main: import.meta.main})`, and
  `bun_test(name = "args_test")` asserting each spawned argument list arrives unchanged with
  `main: true`: `[""]`, `["a b"]`, `["", "a b", ""]`, `["--config=z"]`, `["--config=z", "x"]`
  (Revision 10: a first argument `--config=z` is the program's); and
  `bun_test(name = "args_quotes_test")` with `['"q"', 'a"b', "a\\\"b"]`, marked
  `target_compatible_with = select({"@platforms//os:windows": ["@platforms//:incompatible"],
  "//conditions:default": []})` because the Windows stub splits quoted arguments (G1; the Windows
  test waits for a hermetic-launcher release that fixes #80). These guard the skeleton's
  forwarding: record the red as a mutation (`bun/private/launcher.js` drops empty arguments),
  revert, record green.
- [X] T021 [P] [US1] Add canary C7 (G1) as `bun/tests/canary/c7_windows_args.test.ts` with its
  target in `bun/tests/canary/BUILD.bazel`: a `bun_test` with `target_compatible_with =
  ["@platforms//os:windows"]` and `//bun/tests/run/args:echo` in `data` that spawns it with an
  argument containing `"` and with 130 runtime arguments and asserts today's behavior (the
  argument is split; arguments past 128 are dropped); on failure the message names "the
  documented Windows argument limitation and the waiting Windows quote test (G1)" and
  hermeticbuild/hermetic-launcher#80. Red: mutation expecting the arguments unchanged — Windows
  only (see Conventions).
- [X] T022 [US1] Write the red standard-input test (FR-015): create `bun/tests/run/stdin/` with a
  `manual` `bun_binary(name = "cat")` that writes `await Bun.stdin.text()` to stdout and a
  `bun_test(name = "stdin_test")` that spawns it with `stdin` `"ping\n"` and asserts stdout
  `"ping\n"`. Record the red: stdout is empty.
- [X] T023 [US1] Make T022 green: `Bun.spawn` in `bun/private/launcher.js` gets `stdin:
  "inherit"`. Record green.
- [X] T024 [US1] Write the red leading-`--` cases (FR-013, spec Revision 10, G13 withdrawn): add to
  `bun/tests/run/args/args_test.ts` the cases `["--", "x"]` and `["--"]`, each asserting exit 1,
  no program output on stdout, and stderr holding an English error that names `--` as the first
  program argument and says Bun 1.4.2 drops it. Record the red: exit 0, and the program prints
  `["x"]` and `[]`.
- [X] T025 [US1] Make T024 green in `bun/private/launcher.js`: in binary mode, when the first user
  argument is `--`, exit 1 with that error before starting the second process; insert nothing
  into the argv (R2). Record green, and quickstart 4a: `bazel run //bun/tests/run/args:echo -- -- x`
  exits 1 naming `--`.

### Per-target copy tree (FR-003, R6; also US3-4)

- [X] T026 [US1] Write the red copy-tree tests: create `bun/tests/run/tree/` with
  (a) checked-in `undeclared.ts` and a `manual` `bun_binary(name = "sibling")` whose entry point
  imports `./undeclared.ts` without declaring it, plus a spawn test asserting a non-zero exit and
  Bun's module-not-found error (US3-4);
  (b) a bazel-skylib `write_file` producing `generated.txt` and a `bun_test(name =
  "generated_data_test", data = [":generated"])` that reads `join(import.meta.dir,
  "generated.txt")` (US1-3, FR-012; generated data is in scope);
  (c) in `bun/tests/run_test.bzl`, `copy_tree_test_suite(name)` asserting that a fixture
  `bun_binary` with an entry point, `srcs`, `data` and `deps` (a `bun_library` with its own data)
  declares one copy per file at `<package>/<name>.bun/<rlocation path>`, written by actions with
  mnemonic `CopyFile`, deduplicated by rlocation path, that `launch.json` names the copies and
  holds `copies` as `[[<rlocation path of the copy>, <File.path of the original>], …]`, and that
  runfiles hold the copies, the original data files and Bun (data-model "Per-target copy tree");
  (d) `expect_failure` tests: a `bun_library` and a `bun_binary` whose `data` holds a directory (a
  test-only rule in `bun/tests/run_test.bzl` that `declare_directory`s and fills it with
  `ctx.actions.run` of the execution-platform Bun) fail naming `data` and the directory (G12).
  Record the reds: (a) the import succeeds; (b) ENOENT; (c) no copies are declared; (d) analysis
  succeeds.
- [X] T027 [US1] Make T026 green: in `bun/private/run.bzl` collect the entry point or test files,
  own `srcs`, `BunLibraryInfo.srcs` and `.data` of `deps` and the files of own `data` targets,
  dedupe by rlocation path, and copy each to `ctx.actions.declare_file("<name>.bun/<rlocation
  path>")` with `copy_file_action` from `@bazel_lib//lib:copy_file.bzl`, declaring
  `toolchains = COPY_FILE_TOOLCHAINS` (BL-copy); write the copies' rlocation paths to
  `launch.json` (`entry_point`, `tests`, `copies`); keep the originals of data files and the
  `default_runfiles` of `data` and `deps` uncopied in runfiles. `fail()` naming `data` and the
  directory when a file to copy is a directory (`File.is_directory`), in `bun/private/run.bzl`
  and `bun/private/library.bzl`. Record green: all four T026 parts pass, and every earlier test
  still passes.
- [X] T028 [P] [US1] Add canary C1 (copy tree and load guard) as
  `bun/tests/canary/c1_preserve_symlinks.test.ts` with its target in
  `bun/tests/canary/BUILD.bazel`: under `TEST_TMPDIR`, `a.ts` imports `./b.ts`; a symlink to `a.ts`
  in another directory that has its own `b.ts`; `bun --preserve-symlinks --preserve-symlinks-main
  <link>` resolves `./b.ts` from the link target's directory; on failure the message names "the
  per-target copy tree and the load guard" and oven-sh/bun#43689 and PR #36757. Red: mutation
  expecting the import beside the link. Follow the Symlinks convention when the runner cannot
  create a symlink.

### Runfiles paths with spaces

- [X] T029 [US1] Write the red spaces test (spec Edge Cases, FR-011): create
  `bun/tests/run/spaces/` with `with space.ts`, `with space.txt` and `with space.test.ts` and a
  `bun_library` plus `bun_test(name = "spaces_test")` whose test imports `./with space.ts` and
  reads `join(import.meta.dir, "with space.txt")`; when `RUNFILES_MANIFEST_FILE` is set and names
  a readable file, the test also asserts that the manifest line for `with space.txt` starts with a
  space and escapes the space as `\s` (BZ-manifest, `SourceManifestAction.java` at Bazel 9.2.0;
  formerly canary C15), and otherwise logs that this assertion did not apply. Run
  `bazel test //bun/tests/run/spaces:all` and `bazel test //bun/tests/run/spaces:all
  --noenable_runfiles`; record the red: with the manifest only, the launcher fails to find the
  escaped path (English error naming it).
- [X] T030 [US1] Make T029 green: the manifest parser in `bun/private/launcher.js` unescapes lines
  that start with a space (`\s`, `\n`, `\b` in the link; `\n`, `\b` in the target; BZ-manifest,
  RPY `runfiles.py` `_LoadRunfiles`). Record green with and without `--noenable_runfiles`, and
  that the manifest assertion ran in the second run.

**Checkpoint**: US1 works locally on Linux with and without a runfiles tree.

---

## Phase 4: User Story 2 - Run Bun tests (Priority: P1)

**Goal**: `bazel test` runs exactly the declared test files with `bun test`, with `env`,
`env_inherit`, the `args` allowlist, filter, sharding, JUnit XML, preloads and coverage.

**Independent Test**: `bazel test //bun/tests/run/protocol/... //bun/tests/run/length/...` passes;
`RULES_BUN_INHERITED=set RULES_BUN_BOTH=inherited bazel test
//bun/tests/run/protocol/env:env_inherit_set_test` passes (quickstart 5); quickstart 6 passes.

- [X] T031 [US2] Write the red `bun_test` analysis and environment tests (FR-007, FR-014, FR-016,
  US2-4, US2-5): add `test_rule_test_suite(name)` to `bun/tests/run_test.bzl` with an
  `expect_failure` test asserting a `bun_test` with no `srcs` fails naming `srcs`, and an
  `analysistest` asserting `RunEnvironmentInfo.inherited_environment` equals `env_inherit`; create
  `bun/tests/run/protocol/env/` with `bun_test(name = "env_test", env = {"RULES_BUN_DECLARED":
  "declared", "RULES_BUN_BOTH": "declared"}, env_inherit = ["RULES_BUN_UNSET", "RULES_BUN_BOTH"])`
  asserting `RULES_BUN_DECLARED === "declared"`, `RULES_BUN_UNSET` undefined, `RULES_BUN_BOTH ===
  "declared"` (not set by the invoking environment), a file written under `TEST_TMPDIR` reads
  back, and `TEST_SRCDIR`, `TEST_WORKSPACE`, `TEST_TMPDIR` are set (FR-016: left unchanged); and a
  `manual` `bun_test(name = "env_inherit_set_test")` with `env_inherit = ["RULES_BUN_INHERITED",
  "RULES_BUN_BOTH"]`, `env = {"RULES_BUN_BOTH": "declared"}` asserting `RULES_BUN_INHERITED ===
  "set"` and `RULES_BUN_BOTH === "inherited"` (BZ-runenv precedence). Record the red: analysis
  fails, `bun_test` has no attribute `env_inherit`; the empty-`srcs` target analyzes.
- [X] T032 [US2] Make T031 green in `bun/private/run.bzl`: `env_inherit` (`attr.string_list`) on
  `bun_test`, returned as `RunEnvironmentInfo.inherited_environment`; `fail()` naming `srcs` when
  `bun_test` has no test file; `srcs` of `bun_test` accept the extensions of T008. Record green,
  and quickstart 5 locally.
- [X] T033 [US2] Add the declared-arguments test (US2-6, FR-013): create
  `bun/tests/run/protocol/args/` with a test awaiting 200 ms, a `manual` `bun_test(name =
  "slow_test")` and a `manual` `bun_test(name = "slow_declared_test", args = ["--timeout=50"])`,
  and a spawn test asserting: `slow_declared_test` fails by timeout; `slow_test` with runtime
  argument `--timeout=50` (what `--test_arg` appends) fails by timeout; `slow_test` alone passes.
  This guards the skeleton's forwarding: record the red as a mutation (`bun/private/launcher.js`
  drops test-mode arguments), revert, record green.
- [X] T034 [US2] Add the undeclared-test-file test (US2-3, FR-007): create
  `bun/tests/run/protocol/declared/` with `declared.test.ts` (passes) and `undeclared.test.ts`
  (fails on purpose, not declared) and `bun_test(name = "declared_test", srcs =
  ["declared.test.ts"])`. This guards T027: record the red as a mutation (`bun/private/launcher.js`
  passes the test file's directory instead of the file), revert, record green.
- [X] T035 [US2] Write the red allowlist tests (FR-013, R8, spec Revision 9): create
  `bun/tests/run/protocol/allowlist/` with a passing `manual` `bun_test(name = "target_test")` and
  a spawn test that runs it once per allowed form — `--timeout=5000`, `--rerun-each=1`,
  `--retry=0`, `--concurrent`, `--randomize`, `--seed=1`, `--bail`, `--bail=1`,
  `--max-concurrency=2`, `--todo`, `--isolate`, `--smol`, `--conditions=x`, `--prefer-offline`,
  `--frozen-lockfile` — asserting exit 0, and once per rejected argument — `x.test.ts`, `--`,
  `-talpha`, `-uts`, `-r./x.ts`, `--path-ignore-patterns=x`, `--changed`, `--test-name-pattern=x`,
  `--reporter=junit`, `--dots`, `--coverage`, `--shard=1/1`, `-u`, `--update-snapshots`,
  `--env-file=x`, `--preload=x`, `--config=x`, `--parallel`, `--no-isolate`, `--watch`,
  `--inspect`, `--define=a:b`, `--loader=.js:text`, `--tsconfig-override=x`, `--timings` —
  asserting exit 1 and an English error naming the argument. Record the red: rejected arguments
  run or fail without that error.
- [X] T036 [US2] Make T035 green in `bun/private/launcher.js`: in test mode every user argument
  must equal an allowlisted form of research R8 "Arguments" (`<n>` a decimal integer, `<value>`
  non-empty), else exit 1 with an English error naming the argument and pointing to the allowed
  list. Record green.
- [X] T037 [US2] Write the red JUnit test (US2-9, FR-016): create `bun/tests/run/protocol/junit/`
  with a `manual` `bun_test(name = "math_test", visibility = ["//bun/tests:__subpackages__"])`
  holding `describe("Math ops")` with `test("adds")` and `test("subtracts")`, and a top-level
  `test("other")`; a spawn test sets `XML_OUTPUT_FILE` to a path under `TEST_TMPDIR` and asserts
  the report holds a `<testcase>` for each of the three. Record the red: no file.
- [X] T038 [US2] Make T037 green: when `XML_OUTPUT_FILE` is set `bun/private/launcher.js` adds
  `--reporter=junit --reporter-outfile=<XML_OUTPUT_FILE>` (BUN-reporters). Record green.
- [X] T039 [US2] Write the red filter tests (US2-7, FR-016, BUN-discovery, spec Revision 10) in
  `bun/tests/run/protocol/filter/`: spawn tests against `//bun/tests/run/protocol/junit:math_test`,
  each with `XML_OUTPUT_FILE` set, asserting: `TESTBRIDGE_TEST_ONLY="Math ops adds"` exits 0 and
  the JUnit report holds exactly one `<testcase>`, named `adds` (describe-label match);
  `TESTBRIDGE_TEST_ONLY="nomatch"` exits 1 and the JUnit report holds zero `<testcase>` (analysis
  finding G2: the count is what makes this case red before T040, because without the mapping all
  three tests run and pass). Record the red: both runs exit 0 with three `<testcase>` elements.
- [X] T040 [US2] Make T039 green: when `TESTBRIDGE_TEST_ONLY` is set `bun/private/launcher.js`
  adds `--test-name-pattern=<value>` and nothing else (R8; no `--pass-with-no-tests`). Record
  green: the `nomatch` run exits 1 with Bun's own exit code.
- [X] T041 [US2] Write the red sharding tests (US2-8, FR-016): create
  `bun/tests/run/protocol/shard/` with test files `a.test.ts`, `b.test.ts`, `c.test.ts`, a
  `bun_test(name = "sharded_test", shard_count = 2)` over them (in `//...`), a `manual`
  `bun_test(name = "shard_target_test")` over the same files, and a spawn test asserting, through
  JUnit reports: shards `0/2` and `1/2` together run every test exactly once and each creates
  `TEST_SHARD_STATUS_FILE`; with 4 shards over 3 files the shard with no file exits 0 (formerly
  canary C14; R8 "a shard with no file exits 0"). Record the red: each shard runs every file, and
  no status file is written.
- [X] T042 [US2] Make T041 green: `bun/private/launcher.js` creates or touches
  `TEST_SHARD_STATUS_FILE` when set and maps `TEST_TOTAL_SHARDS`/`TEST_SHARD_INDEX` to
  `--shard=<index + 1>/<total>` (R8, BUN-parallel). Record green.
- [X] T043 [US2] Write the red filter-with-shards test (FR-016, spec Revision 10, G8 withdrawn):
  add to the T041 spawn test, for `TEST_TOTAL_SHARDS=2` and each `TEST_SHARD_INDEX` of `0` and
  `1`, with `TESTBRIDGE_TEST_ONLY` matching one test in `a.test.ts` and `XML_OUTPUT_FILE` set:
  exit 1, stderr holding an English error that filtering a sharded `bun_test` is not supported,
  zero `<testcase>` in the JUnit report, and no `TEST_SHARD_STATUS_FILE` created. Record the red:
  the shards run tests (Bun's exit code, a report with test cases) without that error.
- [X] T044 [US2] Make T043 green: when `TESTBRIDGE_TEST_ONLY` is set and `TEST_TOTAL_SHARDS` is
  greater than 1, `bun/private/launcher.js` exits 1 with that error before touching the shard
  status file or starting the second process (R8 "Filter"). Record green.
- [X] T045 [US2] Write the red preload test (FR-016c): create `bun/tests/run/protocol/preload/`
  with `setup.ts` setting `globalThis.__RULES_BUN_PRELOAD = "loaded"` and `bun_test(name =
  "preload_test", srcs = ["preload.test.ts"], preload = ["setup.ts"])` asserting it. Record the
  red: `bun_test` has no attribute `preload`.
- [X] T046 [US2] Make T045 green: `preload` (`allow_files` as T008) on `bun_test` in
  `bun/private/run.bzl`; preloads are copied (R6) and written to `launch.json` `preload`;
  `bun/private/launcher.js` passes `--preload=<copy>` for each, in order, after the protocol
  options and before the user arguments (R8 "Command"). Record green.
- [X] T047 [US2] Write the red coverage tests (FR-016a, G7 re-based): add to
  `bun/tests/run_test.bzl` an `analysistest` asserting `InstrumentedFilesInfo` of a `bun_test`
  under `collect_code_coverage` names its `srcs` and those of its `deps`; create
  `bun/tests/run/protocol/coverage/` with a `bun_library(name = "covered", srcs = ["covered.ts"])`,
  a `bun_test(name = "coverage_test", srcs = ["covered.test.ts"], deps = [":covered"])`, a `manual`
  `bun_test(name = "coverage_target_test")` with the same `srcs` and `deps`, and a spawn test that
  sets `COVERAGE_DIR` to an empty directory under `TEST_TMPDIR` for `coverage_target_test` and
  asserts: exactly one file in it, named to match `^bunlcov_[0-9a-f-]{36}\.dat$`; it holds the
  record `SF:bun/tests/run/protocol/coverage/covered.ts` (the original's `File.path`); and no
  record for `launcher.js` or for a path containing `.bun/`. Record the reds: no instrumented
  files; no `.dat` file.
- [X] T048 [US2] Make T047 green: `bun_test` in `bun/private/run.bzl` declares `_lcov_merger` =
  `attr.label(default = configuration_field(fragment = "coverage", name = "output_generator"),
  executable = True, cfg = config.exec(exec_group = "test"))` and returns
  `coverage_common.instrumented_files_info(ctx, source_attributes = ["srcs"],
  dependency_attributes = ["deps", "data"])`; when `COVERAGE_DIR` is set
  `bun/private/launcher.js` adds `--coverage --coverage-reporter=lcov --coverage-dir=<a new
  directory under TEST_TMPDIR>` and, after the child exits, reads `<that directory>/lcov.info` as
  LCOV (LCOV-format) and, for each `SF:` value, forms two readings (G15, Organization item 3): the
  value joined to `fs.realpathSync` of the working directory the launcher gave the second
  process, and the value itself when `path.isAbsolute` holds for it on the running OS; it compares
  both, after `path.normalize`, with the real paths of the copies in `launch.json` `copies`
  (data-model "Launch configuration": "the set each coverage `SF:` value must match exactly
  once"). A record whose reading equals the real path of `launcher.js` itself is removed (the
  rule's file, not a declared copy). Exactly one matching copy: the value is rewritten to that
  copy's original `File.path`. No copy or several: the record is dropped for now (T089 replaces
  this with the G15 error; Genuine red). The result is written to
  `$COVERAGE_DIR/bunlcov_<crypto.randomUUID()>.dat` (RPY-cov `pylcov_<uuid4>.dat`, BUN-webapis).
  Assume no `SF:` form beyond these two readings (constitution V). Record green.
- [X] T049 [US2] Add the coverage check program (FR-016a, quickstart 6): in
  `bun/tests/run/protocol/coverage/` add `bun_binary(name = "coverage_check", entry_point =
  "check.ts")` that resolves its first argument against `BUILD_WORKING_DIRECTORY`, reads the
  merged report, and exits 1 with an English message naming "the `bunlcov_<uuid>.dat` file and
  the `SF:` rewrite (G7)" unless it holds a record `SF:bun/tests/run/protocol/coverage/covered.ts`.
  Run quickstart 6 locally on Linux: `bazel coverage --combined_report=lcov
  //bun/tests/run/protocol/coverage:coverage_test`, then `bazel run
  //bun/tests/run/protocol/coverage:coverage_check --
  bazel-out/_coverage/_coverage_report.dat`. This guards T048: record the red as a mutation
  (`bun/private/launcher.js` writes `SF:` lines unchanged), revert, record green.
- [X] T088 [US2] Write the red G15 coverage-error test (FR-016a, G15, spec Revision 12): in
  `bun/tests/run/protocol/coverage/` add `chdir.test.ts`, which imports `./covered.ts`, calls it,
  creates a new directory with `fs.mkdtempSync(join(process.env.TEST_TMPDIR, "chdir-"))` and calls
  `process.chdir` to it (Bun 1.4.2 then writes `SF:` values relative to that directory, research
  Part 1 "Plan for spec Revision 12", G15 "Observed"); a `manual` `bun_test(name =
  "coverage_chdir_target_test", srcs = ["chdir.test.ts"], deps = [":covered"])`; and
  `chdir_spawn.test.ts` with `bun_test(name = "coverage_chdir_test", srcs =
  ["chdir_spawn.test.ts"], data = [":coverage_chdir_target_test"], deps =
  ["//bun/tests/support:spawn"])`, which sets `COVERAGE_DIR` to an empty directory under
  `TEST_TMPDIR` for `coverage_chdir_target_test` and asserts: exit 1; stderr holds the target's
  label and an English error of the form `<label>: coverage record SF:<value> names no declared
  file` with a non-empty `<value>`; `COVERAGE_DIR` holds no file (no `.dat`). Record the red: exit
  0 and one `bunlcov_*.dat` file, because T048 drops the unmatched records.
- [X] T089 [US2] Make T088 green in `bun/private/launcher.js` (G15, research Part 1 "Plan for spec
  Revision 12"): after the launcher's own record is removed, a record whose readings match no copy
  makes the launcher write no `.dat` file and exit 1, whatever Bun's exit code, with
  `<label>: coverage record SF:<value> names no declared file`; one whose readings match several
  copies does the same with `<label>: coverage record SF:<value> names several declared files`.
  Record green: `coverage_chdir_test`, the T047 coverage spawn test and T049 pass. Record, in the
  same row, that the several-matches branch has no fixture (no tree builds a value whose two
  readings both name declared copies) and is unverified (FR-026, plan Constitution Check II).
- [X] T050 [P] [US2] Add canary C2 (G2) as `bun/tests/canary/c2_snapshot.test.ts` with its target
  in `bun/tests/canary/BUILD.bazel`: with `CI=true`, `bun test` of a file with a new
  `toMatchSnapshot()` fails and creates a header-only `__snapshots__/<file>.snap`; on failure the
  message names "snapshot tests unsupported (FR-016b, G2)" and oven-sh/bun#44531. Red: mutation
  expecting no `.snap` file.
- [X] T051 [US2] Write the red command-line length test (R2, spec Revisions 8–9): create
  `bun/tests/run/length/many_tests.bzl` with a test-only rule writing 400 test files with
  90-character base names (each a passing `test()`) by `ctx.actions.write`, a `manual`
  `bun_test(name = "long_cmdline_test", srcs = [":many_tests"])`, and a spawn test asserting exit
  1 and an English error naming the measured length and the limit 32,767. Premise (analysis
  finding U3): the red relies on Bun running these generated test files, while spec "Proposed
  boundaries" leaves generated sources out of scope and unverified; they are fixture input only.
  Record the red — on Linux the run starts and passes (exit 0) — together with that premise, and
  claim nothing about generated sources from it (FR-026). After T052 they are never started.
- [X] T052 [US2] Make T051 green in `bun/private/launcher.js`: before `Bun.spawn`, measure the
  command line as the running OS builds it — on Windows each argument quoted by the WIN-argv rules,
  joined by spaces, plus the terminating null; on Linux and macOS the unquoted arguments joined by
  single spaces plus the terminating null — in UTF-16 code units, and exit 1 with an English error
  naming the length and the limit when it exceeds 32,767 (WIN-create), on every OS. Record green.

**Checkpoint**: US1 and US2 pass under `bazel test //...` and with `--noenable_runfiles`.

---

## Phase 5: User Story 3 - Bun ignores undeclared configuration, `.env` files and does not install (Priority: P2)

**Goal**: A `bun_binary`'s second process reads only the rule's configuration; a `bun_test`'s
second process gets no configuration option and runs at the copy-tree root, which holds no file
(Revision 11); neither loads an undeclared `.env` or installs; the launcher rejects `BUN_OPTIONS`
and disables the transpiler cache; a load guard rejects every module outside the declared files
(FR-018, FR-018a, R7, R13).

**Independent Test**: `bazel test //bun/tests/run/isolation/... //bun/tests/run/guard/...` passes,
with and without `--noenable_runfiles`; every isolation fixture was first shown on Linux to change
the result (SC-006).

### Isolation of the second process

- [X] T053 [US3] Write the red `bunfig.toml` and working-directory tests (US3-1, FR-018, spec
  Revisions 10–11): create `bun/tests/run/isolation/` with a `manual` `bun_binary(name = "probe")`
  printing `JSON.stringify({bunfig: globalThis.__RULES_BUN_BUNFIG ?? null, dotenv:
  process.env.RULES_BUN_DOTENV ?? null})`; a `manual` `bun_test(name = "probe_test")` asserting
  `globalThis.__RULES_BUN_BUNFIG` is unset, `process.cwd()` equals `fs.realpathSync` of the
  ancestor of `import.meta.dir` named `probe_test.bun` (the copy-tree root), and every entry of
  `fs.readdirSync(process.cwd(), {withFileTypes: true})` is a directory (the root holds no file:
  no `bunfig.toml`, no `.env`; data-model "Per-target copy tree"); and a spawn test that writes
  under `TEST_TMPDIR` a directory with `bunfig.toml` (`preload = ["./set.ts"]` and
  `[test] preload = ["./set.ts"]`) and `set.ts` (sets `globalThis.__RULES_BUN_BUNFIG = "read"`)
  and spawns both targets with that directory as `cwd`, asserting `probe` prints `bunfig: null`
  and `probe_test` exits 0. The `probe_test` green is an observation on Bun 1.4.2, not a claim
  about where `bun test` looks for `bunfig.toml` (oven-sh/bun#45331, FR-026). Extend
  `copy_tree_test_suite` in `bun/tests/run_test.bzl` (data-model "Launch configuration",
  "Per-target copy tree"): a `bun_binary` fixture's runfiles hold `bun/private/isolated_bunfig.toml`
  (the original, not a copy) and its `launch.json` holds `bunfig` with that file's rlocation path;
  a `bun_test` fixture's runfiles do not hold it and its `launch.json` has no `bunfig`; no copy of
  either fixture is declared directly at `<name>.bun/` (each path below `<name>.bun/` has at least
  two segments); a `bun_test` fixture's `launch.json` `tests` is `[[<rlocation path of the copy>,
  <tree path>]]` per test file, the tree path being the original's rlocation path (finding A1 of
  2026-10-08). Record the reds: the global is set in both; `probe_test`'s working directory is the
  fixture directory; the analysis tests find no `bunfig` field, no `isolated_bunfig.toml` and
  `tests` as plain rlocation paths.
- [X] T054 [US3] Make T053 green (R6, R7, R8): create `bun/private/isolated_bunfig.toml` holding
  only an English comment naming FR-018 and `bun_binary` (its settings come in T057 and T059) and
  export it like `launcher.js`; in `bun/private/run.bzl` add the implicit `_bunfig` to `bun_binary`
  only (`bun_test` has no `_bunfig`, data-model "`bun_test`"), put the file uncopied in
  `bun_binary`'s runfiles (not in the copy tree, not in `copies`, not in the guard's set), write
  its rlocation path to `launch.json` `bunfig` for `bun_binary` only, and write `tests` as
  `[[<rlocation path of the copy>, <tree path>]]`. The rule writes nothing at the root of
  `<name>.bun/`. In `bun/private/launcher.js`: binary mode passes `--config=<real path of the
  runfile named by bunfig>` (the `=` form, G4) before the entry point and keeps its working
  directory; test mode passes no configuration option, starts the second process with `cwd` = the
  copy-tree root (the real path of the first test file's copy with its tree path removed), and
  passes each test file as `./<tree path>` (R8 "Command"). Record green, and that every earlier
  test still passes, including the T047 and T088 coverage spawn tests (the first reading of each
  `SF:` value is now joined to the copy-tree root).
- [X] T055 [P] [US3] Add canary C4 (G4, Bun's side of the runtime command; Revision 11) as
  `bun/tests/canary/c4_config_form.test.ts` with its target in `bun/tests/canary/BUILD.bazel`:
  under `TEST_TMPDIR`, in a directory holding no `bunfig.toml`, write `config.toml` whose `preload`
  names `marker.ts` (prints `CONFIG_PRELOAD`) and `main.ts` (prints `MAIN`), and run the
  toolchain's Bun as `bun --config <config.toml> main.ts` and as `bun -c <config.toml> main.ts`
  (the runtime command of the first process, not `bun test`), asserting neither output holds
  `CONFIG_PRELOAD` or `MAIN`, because Bun runs `<config.toml>` as the entry point (data-model
  "Upstream canaries"; the exit code is not asserted). On failure the message names "the
  first-process limitation (FR-018a, G4); hermetic-launcher's side is the MODULE.bazel comment
  (G14)" and hermeticbuild/hermetic-launcher#81. Red: mutation expecting `MAIN` in the output.
- [X] T056 [US3] Write the red `.env` test (US3-2): add to the T053 spawn test a fixture directory
  with `.env` defining `RULES_BUN_DOTENV=leaked`, spawn both targets with it as `cwd`, and assert
  `probe` prints `dotenv: null` and `probe_test` sees `RULES_BUN_DOTENV` unset. No fixture writes
  into `probe_test.bun/`: its root must hold no file (T053, Revision 11). Also change T009's
  embedded-argument assertion to the four arguments `[<Bun>, "--no-env-file", <launcher.js>,
  <hello.launch.json>]` (FR-001 step 1, data-model "Embedded stub arguments"). Record the reds:
  the variable is set in both (the first process loads the fixture's `.env` and the second
  inherits it; `probe`'s second process also runs in the fixture directory), and the T009
  assertion finds three arguments.
- [X] T057 [US3] Make T056 green: `env = false` in `bun/private/isolated_bunfig.toml`;
  `--no-env-file` as the stub's second embedded argument in `bun/private/run.bzl` (FR-001 step 1:
  the stub embeds `--no-env-file`, the static launcher and the launch configuration, and no
  `--config=`, G4), and after `--config=` in the binary argv in `bun/private/launcher.js`
  (BUN-env); nothing added to the test argv (Revisions 10–11). Record green.
- [X] T058 [US3] Write the red install test (US3-3, SC-006): in `bun/tests/run/isolation/` add a
  `manual` `bun_binary(name = "imports_package")` importing `rules-bun-fixture-pkg`, a matching
  `manual` `bun_test`, a checked-in package tarball `registry/rules-bun-fixture-pkg-1.0.0.tgz`
  (made once with `bun pm pack` from a fixture directory kept next to it; record the command), and
  a spawn test that serves the package metadata and tarball from a local `Bun.serve` registry,
  sets `BUN_CONFIG_REGISTRY` to it and `BUN_INSTALL_CACHE_DIR` to an empty directory under
  `TEST_TMPDIR`, spawns from a directory without `node_modules`, and asserts Bun's
  module-not-found error and an empty cache directory. Record the red for `bun_binary`: the package
  installs into the cache. For `bun_test` record the observation that it does not auto-install
  even without the protection (G5; replaces its red, SC-006).
- [X] T059 [US3] Make T058 green: `[install] auto = "disable"` in
  `bun/private/isolated_bunfig.toml` and `--no-install` after `--no-env-file` in the binary argv
  in `bun/private/launcher.js` (BUN-bunfig, BUN-run). Record green.
- [X] T060 [US3] Write the red `BUN_OPTIONS` test (FR-018a): a spawn test in
  `bun/tests/run/isolation/` of `probe` with `BUN_OPTIONS="--define=X:1"` asserting exit 1, an
  English error naming `BUN_OPTIONS`, and no program output. Record the red: the program runs.
- [X] T061 [US3] Make T060 green: `bun/private/launcher.js` exits 1 with that error before
  starting the child when `BUN_OPTIONS` is set, and deletes it from the child's environment (R7).
  Record green.
- [X] T062 [US3] Write the red transpiler-cache test (FR-018, BUN-cache): in
  `bun/tests/run/isolation/` add `manual` `bun_binary` targets `cache_probe` (a declared source
  over 4 KB; prints `process.env.BUN_RUNTIME_TRANSPILER_CACHE_PATH`) and `tiny` (one line), and a
  spawn test that sets `BUN_RUNTIME_TRANSPILER_CACHE_PATH` to an empty directory, removes
  `BUN_INSPECT_CONNECT_TO`, runs `tiny` then `cache_probe`, and asserts `cache_probe` prints `0`
  and the directory holds no more `.pile` files than after `tiny`. Record the red: it prints the
  directory and a `.pile` file is added.
- [X] T063 [US3] Make T062 green: the child's environment gets
  `BUN_RUNTIME_TRANSPILER_CACHE_PATH=0` in `bun/private/launcher.js` (R7). Record green.

### Load guard (R13; G10, G11)

- [X] T064 [US3] Write the red guard tests: create `bun/tests/run/guard/` with
  `bun/tests/run/guard/undeclared.bzl`, a test-only rule declaring, by `ctx.actions.write`,
  undeclared outputs at the paths of R13 "Tests": a stale copy inside the `manual` target
  `guarded`'s tree (`guarded.bun/_main/bun/tests/run/guard/stale.ts`), a file reached by a `../`
  climb out of the tree, an ancestor `package.json` with `"imports"` mapping `#undeclared` to an
  undeclared file, and an ancestor `node_modules/undeclared-pkg` package; a `manual`
  `bun_binary(name = "guarded")` whose entry point takes a case name and, without `try`/`catch`,
  imports: `declared` (declared ESM, CommonJS and JSON files), `stale`, `climb`, `imports`,
  `node_modules`, `cjs` (`require` of an undeclared file), `json` (an undeclared `.json`),
  `original` (the original of a declared data file, located through runfiles); a `manual`
  `bun_binary(name = "static_stale")` with a static import of the stale file; a `manual`
  `bun_test` whose preload imports an undeclared file; and a `manual` `bun_test` with two files,
  the second importing an undeclared file, run with `--isolate`. A spawn test (with the test-only
  rule in `data`) asserts `declared` exits 0 and every other case exits non-zero with
  `<label>: <path> is not declared by this target`. Record the red: the undeclared imports
  succeed.
- [X] T065 [US3] Make T064 green with the guard (R13), using only the documented API of research
  Part 1 "Plan for spec Revision 10", item 5: `bun/private/launcher.js` sets
  `RULES_BUN_LAUNCH_CONFIG` to the real path of `launch.json` in the child's environment and
  passes `--preload=<real path of launcher.js>` before any other preload in both modes (binary
  argv `[--config=…, --no-env-file, --no-install, --preload=<launcher.js>, <entry>, ...user args]`;
  test argv `[test, --preload=<launcher.js>, <protocol options>, --preload=<copy>…, ...user args,
  ./<test>…]`, R2, R8); `launcher.js`, when not the main module, reads that file without deleting
  the variable or the file, resolves the real paths of `copies`, and registers
  `Bun.plugin({setup(build) { build.onLoad({filter, namespace: "file"}, …) }})` with
  `filter = ^(?!(?:<escaped declared real paths joined by |>)$).*$` (one alternation; the trie is
  T069) and a callback that throws `Error("<label>: <path> is not declared by this target")`.
  With no configuration it registers nothing yet (fail closed is T067). Record green with and
  without `--noenable_runfiles`.
- [X] T066 [US3] Write the red fail-closed test (spec Revision 9): in `bun/tests/run/guard/`, a
  spawn test with `//bun/private:launcher.js` in `data` that starts the toolchain's Bun
  (`process.execPath`) with `--preload=<launcher.js, resolved through runfiles>` and a declared
  entry point that prints a marker, once with `RULES_BUN_LAUNCH_CONFIG` unset and once naming a
  missing file, asserting a non-zero exit, the guard's English error naming the reason, and no
  marker. Record the red: the entry point runs.
- [X] T067 [US3] Make T066 green in `bun/private/launcher.js`: when the variable is unset, the file
  cannot be read or parsed, or a declared path cannot be resolved, the guard registers an `onLoad`
  whose filter matches every path and whose callback throws an English error naming the reason
  (R13 "Fail closed"). Record green.
- [X] T068 [US3] Write the red large-set test (spec Revision 8): create
  `bun/tests/run/guard/many_files.bzl`, a test-only rule writing N `.json` data files by
  `ctx.actions.write` (generated data is in scope), and a `manual` `bun_binary(name =
  "large_set")` whose `data` holds 10,000 such files; a spawn test asserts a declared one imports
  and an undeclared one fails naming it. Record the red: "regular expression too large" from the
  single alternation.
- [X] T069 [US3] Make T068 green in `bun/private/launcher.js`: build the guard filter as a prefix
  trie of the declared real paths (each character escaped, shared prefixes emitted once, branches
  as non-capturing groups) inside `^(?!(?:…)$).*$` (R13). Record green.
- [X] T070 [US3] Write the red declared-file-limit test (spec Revision 9): a `manual`
  `bun_binary(name = "over_limit")` whose `data` holds 22,000 files with 50-character names drawn
  from a deterministic pseudo-random sequence (fixed seed in `many_files.bzl`), and a spawn test
  asserting exit 1 and an English error naming the label, the declared-file count and the limit
  1,048,576. Record the red: Bun's "regular expression too large" from the preload.
- [X] T071 [US3] Make T070 green: `bun/private/launcher.js` builds the guard pattern before
  `Bun.spawn` and, when the pattern string is longer than 1,048,576 characters (a named constant,
  the limit measured on Bun 1.4.2), exits 1 with that error (R2, R13). Record green.
- [X] T072 [P] [US3] Add canary C13 as `bun/tests/canary/c13_regexp_limit.test.ts` with its target
  in `bun/tests/canary/BUILD.bazel`: `new RegExp` compiles a 1,048,576-character pattern string,
  `Bun.plugin` accepts it as an `onLoad` filter, and a 1,048,577-character one fails with "regular
  expression too large"; on failure the message names "the prefix trie and the declared-file
  limit (R13)" and PR #36757. Red: mutation expecting the longer pattern to compile.
- [X] T073 [US3] Pin the caught-error limitation (R13, R14): in `bun/tests/run/guard/`, a `manual`
  `bun_binary(name = "caught")` running `try { await import(<undeclared>) } catch {}` and a spawn
  test asserting exit 0. Record the red as a mutation (the guard callback in
  `bun/private/launcher.js` calls `process.exit(1)` before throwing), revert, record green.

**Checkpoint**: isolation and the guard pass locally with and without a runfiles tree.

---

## Phase 6: User Story 4 - Same behavior on Linux, macOS and Windows (Priority: P2)

**Goal**: Bun for the target platform on every platform, analysis failures instead of a shell
fallback, `.exe` on Windows, and the manifest-only path. macOS and Windows runs come from the CI
workflow of T081 (Polish) and POST-1.

**Independent Test**: `bazel test //bun/tests:all` passes the per-platform and failure suites;
`bazel test //... --noenable_runfiles` and `bazel run --noenable_runfiles
//bun/tests/run/app:main -- extra` pass on Linux.

- [X] T074 [US4] Add per-platform tests for the rules (US4-3, SC-007, spec boundary "Use as a
  build-action tool"): in `bun/tests/target_toolchain_test.bzl`, for each of the five platforms,
  `analysistest`s asserting that the runfiles of a `bun_binary` and of a `bun_test` hold
  `@bun_<platform>//:bun` (or `bun.exe`) and no other platform's Bun; and an `analysistest` over a
  test-only rule with a `cfg = "exec"` attribute holding a `bun_binary` under
  `--platforms=//bun/tests/platforms:windows_x64`, asserting the executable carries the Bun that
  `BUN_TOOLCHAIN_TYPE` resolves for the execution platform (compare with feature 001's
  `resolved_bun`). This guards T010: record the red as a mutation (`bun/private/run.bzl` resolves
  `BUN_TOOLCHAIN_TYPE` instead of `target_type`), revert, record green.
- [X] T075 [US4] Write the red platform-failure and `.exe` tests (US4-4, FR-001): in
  `bun/tests/platforms/BUILD.bazel` add test-only platforms `no_bun` (constraints for which
  `hermetic_launcher` 0.0.16 registers a template toolchain but rules_bun registers no
  `target_type` toolchain; pick them from `@hermetic_launcher` `launcher/private/toolchains.bzl`)
  and `no_stub` (constraints with no hermetic-launcher template toolchain), plus a test-only
  `bun_target_toolchain` and `toolchain()` for `no_stub`, registered through
  `config_settings = {"//command_line_option:extra_toolchains": [...]}`; in
  `bun/tests/target_toolchain_test.bzl` add `expect_failure` tests for a `bun_binary` and a
  `bun_test` under each platform asserting the message names the missing toolchain type
  (`//bun/toolchain:target_type`, or the template toolchain type) and the target platform, and an
  `analysistest` asserting the executable under `windows_x64` ends in `.exe` and under
  `linux_x64` does not. Record the reds: `bazel test` aborts with "No matching toolchains found"
  (mandatory toolchains, R1), and the Windows executable has no `.exe`.
- [X] T076 [US4] Make T075 green in `bun/private/run.bzl`: declare `//bun/toolchain:target_type`
  and `launcher.template_toolchain_type` with `config_common.toolchain_type(..., mandatory =
  False)`, `fail()` in English naming the type and the target platform when either is `None` (R1,
  BZ-toolchains "Optional toolchains"); keep `launcher.finalizer_toolchain_type` mandatory; add the
  implicit `_windows_constraint = "@platforms//os:windows"` and name the stub `<name>.exe` when
  `ctx.target_platform_has_constraint` holds. Record green.
- [X] T077 [US4] Run the root module with the manifest only (US4-2, SC-003, quickstart 2 and 2a;
  Kind: verification): `bazel test //... --noenable_runfiles` and `bazel run --noenable_runfiles
  //bun/tests/run/app:main -- extra`; record both results in
  `specs/002-bun-binary-test/tdd-log.md`, and that the manifest assertion of
  `//bun/tests/run/spaces:spaces_test` ran (its log does not say it did not apply).

**Checkpoint**: analysis proves per-platform behavior; the manifest-only path passes on Linux.

---

## Phase 7: User Story 5 - The consumer module uses both rules (Priority: P3)

**Goal**: `e2e/smoke` declares one program and one test through the public API only, and its test
observes that a workspace-root `bunfig.toml` and `.env`, declared by no target, take no effect
(Revision 12).

**Independent Test**: `(cd e2e/smoke && bazel test //... && bazel run //app:main)` passes with
Bazel's defaults, including the root-fixture assertion of `//app:greet_test`;
`git grep -n 'bun/private' -- e2e` prints nothing.

- [X] T078 [US5] Add the consumer targets (US5-1, US5-2, FR-023): create `e2e/smoke/app/` with
  `greet.ts`, `greet.test.ts`, `main.ts`, `message.txt` and `BUILD.bazel` loading only
  `@rules_bun//bun:defs.bzl`: `bun_library(name = "greet", srcs = ["greet.ts"])`,
  `bun_test(name = "greet_test", srcs = ["greet.test.ts"], deps = [":greet"])`, and a
  self-checking `bun_binary(name = "main", entry_point = "main.ts", data = ["message.txt"], deps =
  [":greet"], args = ["--name=world"], env = {"GREETING": "hello"})` that checks the import,
  `join(import.meta.dir, "message.txt")`, its arguments and `GREETING`, and exits 1 naming the
  wrong item. The rules exist, so these guard existing behavior: record two mutation reds (a wrong
  expected argument in `main.ts` makes `bazel run //app:main` exit 1 naming it; a wrong
  expectation in `greet.test.ts` makes `bazel test //app:greet_test` fail), revert, record green
  for `(cd e2e/smoke && bazel test //...)` and `(cd e2e/smoke && bazel run //app:main)`.
- [X] T090 [US5] Add the `e2e/smoke` root fixture (FR-018, US5-1, spec Revision 12; research Part 1
  "Plan for spec Revision 12", item 2): create, at the root of `e2e/smoke/` and named in no
  target's `srcs`, `data`, `deps` or `preload`: `smoke_preload.ts` (sets
  `globalThis.__RULES_BUN_SMOKE_PRELOAD = "loaded"`), `bunfig.toml` (`preload =
  ["./smoke_preload.ts"]` and `[test]` `preload = ["./smoke_preload.ts"]`, with an English comment
  that the file is a fixture declared by no target) and `.env` (`RULES_BUN_SMOKE_DOTENV=leaked`,
  with an English comment saying the same). Add to `e2e/smoke/app/greet.test.ts` a test asserting
  `globalThis.__RULES_BUN_SMOKE_PRELOAD` and `process.env.RULES_BUN_SMOKE_DOTENV` are both
  `undefined`, with English messages naming the root `bunfig.toml` and `.env`. This guards
  existing behavior (FR-020): record the red as a reverted mutation inverting the expectation
  (assert `"loaded"` and `"leaked"`; `(cd e2e/smoke && bazel test //app:greet_test)` fails), revert,
  record green for `(cd e2e/smoke && bazel test //...)` with Platforms "Linux (WSL)"; macOS and
  Windows come from POST-1. Record that `git grep --untracked -l -e smoke_preload -e
  RULES_BUN_SMOKE_DOTENV -- e2e/smoke` lists only `e2e/smoke/bunfig.toml`, `e2e/smoke/.env` and
  `e2e/smoke/app/greet.test.ts` (no `BUILD.bazel` names them). If the unmutated assertion fails
  on Linux (Bun reads either file), stop and report it to the user as a gap (FR-004); do not move,
  rename or exclude the fixture.
- [X] T079 [US5] Run `(cd e2e/smoke && bazel test //... --noenable_runfiles)` and
  `(cd e2e/smoke && bazel run --noenable_runfiles //app:main)` and record both results in
  `specs/002-bun-binary-test/tdd-log.md` (quickstart 10; Kind: verification).
- [X] T080 [US5] Run `git grep -n 'bun/private' -- e2e` from the root and record its (empty) output
  in `specs/002-bun-binary-test/tdd-log.md` (US5-3, quickstart 11; Kind: verification).

**Checkpoint**: every story works locally on Linux.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T081 Extend `.github/workflows/ci.yaml` (FR-024, R11, US4-1, SC-002, SC-003; steps call only
  `bazel`; placed after US5 because the jobs run T078's targets and T090's root fixture, analysis
  finding O1): in the
  matrix job, after `bazel test //...`, a `bazel run` step of the self-checking program
  (`//bun/tests/run/app:main -- extra` for `.`, `//app:main` for `e2e/smoke`) and, for `.`, a step
  `bazel test //bun/tests/run/protocol/env:env_inherit_set_test` with `env:`
  `RULES_BUN_INHERITED: set` and `RULES_BUN_BOTH: inherited`; a Linux job running, in `.` and
  `e2e/smoke`, `bazel test //...` and the `bazel run` step with `--noenable_runfiles`; a Linux job
  running `bazel coverage --combined_report=lcov //bun/tests/run/protocol/coverage:coverage_test`
  and then `bazel run //bun/tests/run/protocol/coverage:coverage_check --
  bazel-out/_coverage/_coverage_report.dat`; a Windows job running the root and `e2e/smoke` test
  sets and the `bazel run` step with `bazel --output_user_root="C:/bazel root"` (BZ-startup); add
  the new jobs to `conclusion.needs`. Record (Kind: verification): `prek run --all-files` passes
  locally; CI results come from POST-1.
- [X] T082 Fix the `bazel_lib` floor (constitution IV, research R6; Kind: research): for each stable
  `bazel_lib` release from `3.0.0` upward, set it in `MODULE.bazel`, refresh `MODULE.bazel.lock`
  and `e2e/smoke/MODULE.bazel.lock`, run root `bazel test //...` and `(cd e2e/smoke && bazel test
  //...)`, and record each failure line; keep the lowest version with which both pass, and record
  the resulting `bazel mod graph` of `e2e/smoke`.
- [X] T083 [P] Complete the documentation in `bun/defs.bzl`, `bun/private/run.bzl`,
  `bun/private/library.bzl`, `bun/private/providers.bzl` and `bun/private/toolchain.bzl` (FR-026,
  research R14, contracts/public-api.md; Kind: documentation): English `doc` strings for
  `bun_binary`, `bun_test`, `bun_library`, `BunLibraryInfo`, `bun_target_toolchain` and their
  attributes, and the `bun/defs.bzl` module docstring with the contract's usage example; the rule
  docs list every known limitation of the contract (Windows quotes and 128 arguments, snapshots,
  first-process `bunfig.toml` and transpiler cache, guard limits including a caught error and JSX,
  the declared-file limit, the `bun_test` allowlist of research R8 (accepted and passed unchanged;
  their effect is Bun's, and only `--timeout` and `--isolate` have a test of it, finding U2 of
  2026-10-08), the `bun_test` working directory (the copy-tree root, which holds no file), that
  bun.com documents no `bunfig.toml` lookup for `bun test` (oven-sh/bun#45331) so `bun_test`
  offers no `bunfig.toml` (use `preload`, FR-016c) and whether Bun searches parent directories of
  the copy-tree root is unverified, with its reach stated (those parent directories include
  `execroot/_main`, which links every top-level entry of the main repository, so a workspace-root
  `bunfig.toml` or `.env` is within reach; `e2e/smoke` holds both, declared by no target, and its
  `bun_test` checks per OS that neither takes effect, Revision 12), that under `bazel coverage` a
  test that calls `process.chdir` fails with the G15 error naming an `SF:` value, a filter that
  matches nothing and filtering a sharded
  `bun_test`, a leading `--`, directories in `data`, another repository's data, the
  32,767-character command line) and claim only behavior a test covers. Record: root
  `bazel test //...` still passes.
- [X] T084 [P] Draft the bazel-lib request for G12 (export the copy-directory toolchain type and a
  documented way to reach its tool; research G12 option 1) in English, with the sources research
  cites, and add it to `specs/002-bun-binary-test/tdd-log.md` (Kind: documentation). Filing it is
  outward-facing: hand the text to the user, who files it or approves filing.
- [X] T085 Run the static checks and record their output in `specs/002-bun-binary-test/tdd-log.md`
  (SC-005, FR-022, constitution V, I; Kind: verification): `git grep -n run_shell -- bun e2e` and
  `git grep -n expand_make_variables -- bun` print nothing; `git grep -n -e
  'pass-with-no-tests' -- bun` prints nothing (Revision 10); `git ls-files '*.sh' '*.bat' '*.cmd'
  '*.ps1'` lists no file this feature added; `bazel query 'attr(visibility,
  "//visibility:public", //bun/...)'` differs from the same query on `main` only by
  `//bun/toolchain:target_type` and `bzl_library` targets for the new public files.
- [X] T086 Run the quickstart validation on Linux (quickstart 1–11) and record each row's result in
  `specs/002-bun-binary-test/tdd-log.md`; rows that need macOS or Windows are left to POST-1.
- [X] T087 Run the AGENTS.md hand-back checks: in the root `bazel run //:gazelle`,
  `prek run --all-files`, `bazel test //...`; in `e2e/smoke/` `bazel test //...`. Record each
  result in `specs/002-bun-binary-test/tdd-log.md`. Report a failure; do not widen the task to
  fix it.

---

## Post-workflow (run by the operator after the `review-final` gate, not by `speckit.implement`)

They run after the workflow because a commit before its review steps would leave them an empty
working-tree diff. Results are appended to `tdd-log.md`.

- POST-0 Adversarial review by a subagent and by Codex: done by the workflow's `review-claude` and
  `review-codex` steps; the operator fixes confirmed findings within this feature and records each
  finding and its outcome.
- POST-1 Commit, push `002-bun-binary-test` and open a pull request to `main` only when the user
  authorizes it; record the `CI` run ID with per-OS, per-folder results, the `--noenable_runfiles`
  (test and run), coverage and `C:/bazel root` jobs, the Windows-only red and green of canary C7
  (T021), canary C1 on Windows if the runner could not create a symlink, and, per OS, the result
  of T090's root-fixture assertion in `e2e/smoke` (a failure on any OS is reported to the user as a
  gap, FR-004, not worked around). For Revision 13 also record: the macOS matrix results (the
  first runs of the shell launcher on macOS), the `manifest-only` job's `bazel run` step and the
  `--spawn_strategy=local` step of T112 (G-impl-1 verified on Linux CI), and per OS the results of
  T107's manifest-only spawn test and T109's first-process assertion (made on Linux and macOS,
  logged as not applicable on Windows). Then mark G-impl-1 in `research.md` verified for each OS
  that passed. Report every OS or job that did not run or failed as unverified (FR-026).

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T003)**: first.
- **Foundational (T004–T013)**: after Setup; blocks every story. T004 → T005 → T006; T007 → T008;
  T009 → T010 → T011 → T012 → T013 (T009 needs T005 and T008).
- **US1 (T014–T030)**: after Foundational. T014 → T015 → T016 → T017 → T018 → T019 → T020 → T022
  → T023 → T024 → T025 → T026 → T027 → T029 → T030; T021 after T020; T028 after T027.
- **US2 (T031–T052, T088–T089)**: after US1 (needs the copy tree, T027). T031 → T032 → T033 →
  T034 → T035 → T036 → T037 → T038 → T039 → T040 → T041 → T042 → T043 → T044 → T045 → T046 →
  T047 → T048 → T049 → T088 → T089 → T051 → T052; T050 after T032.
- **US3 (T053–T073)**: after US2 (the guard's first-preload order needs T046; T054 moves the test
  working directory under T048's coverage matching and T089's error). Isolation T053 → T054 → T056 → T057 → T058 →
  T059 → T060 → T061 → T062 → T063, then guard T064 → T065 → T066 → T067 → T068 → T069 → T070 →
  T071 → T073; T055 after T054; T072 after T071.
- **US4 (T074–T077)**: T074–T076 need only Foundational but edit `bun/private/run.bzl`, so they
  run between, not alongside, other tasks that edit it; T077 after US3.
- **US5 (T078–T080, T090)**: after US1–US3 (the consumer must get the final launcher). T078 →
  T090 → T079 → T080.
- **Polish (T081–T087)**: after all stories; T081 after T049, T078 and T090; T082 before T086 and
  T087.
- **Convergence (T091–T101)**: done; T092, T095, T097, T099 and T100 are withdrawn (see
  Organization).
- **Revision 13 (T102–T114)**: after T101. T102 (O-13, the user's decision) blocks every later
  task. T103 → T104 → T105 → T106; T107 and T109 after T103, alongside T104–T106 and each other;
  T108 after T103; T110 after T104–T109 (every red recorded); T111 after T110; T112 after T111;
  T113 after T110; T114 last.
  POST-0, POST-1 last.

### Story completion order

Foundational → US1 → US2 → US3 → US4 → US5 → Polish. US4's analysis tasks (T074–T076) may move
earlier, between tasks, because they need only Foundational. Almost every behavior task edits
`bun/private/launcher.js` or `bun/private/run.bzl`, so implementation steps are sequential.

### Within each story

- The test task runs red and is recorded before its implementation task.
- A canary follows the implementation of its workaround.
- Each checkpoint re-runs root `bazel test //...` before the next phase.

### Parallel opportunities

Only tasks that edit neither `bun/private/launcher.js` nor `bun/private/run.bzl`, even for a
mutation (analysis finding P1):

- Canaries C7, C1, C2, C4, C13 (T021, T028, T050, T055, T072): separate test files; merge their
  `bun/tests/canary/BUILD.bazel` lines last.
- T083 and T084 (documentation in `.bzl` files and the request text) alongside each other, after
  T082.

- T107 and T109 (Revision 13 reds in `bun/tests/run/manifest/` and
  `bun/tests/run/isolation/isolation.test.ts`), alongside each other and T104–T106.

Not parallel, because their red mutates `launcher.js` or `run.bzl`: T013, T016, T019, T020, T033,
T034, T049, T073, T074, T104. T090 edits only `e2e/smoke/` but follows T078, whose `greet.test.ts`
it changes, and precedes T079, which runs it; it is sequential. T105 and T106 both edit
`bun/tests/target_toolchain_test.bzl`, so they are sequential.

---

## Parallel Example: User Story 1

```text
Task T021: bun/tests/canary/c7_windows_args.test.ts (after T020; Windows only)
Task T028: bun/tests/canary/c1_preserve_symlinks.test.ts (after T027)
```

## Parallel Example: User Story 2

```text
Task T050: bun/tests/canary/c2_snapshot.test.ts (after T032), alongside any of T033–T052, T088–T089
```

## Parallel Example: User Story 3

```text
Task T055: bun/tests/canary/c4_config_form.test.ts (after T054), alongside T056–T071
Task T072: bun/tests/canary/c13_regexp_limit.test.ts (after T071), alongside T073
```

## Parallel Example: Revision 13

```text
Task T107: bun/tests/run/manifest/ (after T103), alongside T104–T106 and T109
Task T109: bun/tests/run/isolation/isolation.test.ts (after T103), alongside T104–T107
```

---

## Implementation Strategy

### MVP (User Story 1)

1. Setup (T001–T003), Foundational (T004–T013).
2. US1 (T014–T030).
3. Validate: quickstart 3–4a and `bazel test //...` with and without `--noenable_runfiles` on
   Linux. Not releasable alone: isolation (US3) and the test protocol (US2) are mandatory, and
   macOS and Windows are unverified until POST-1.

### Incremental delivery

1. Foundational → programs and tests run through the stub with the target platform's Bun.
2. US1 → programs, arguments (with the leading-`--` rejection), stdin, copies, spaces.
3. US2 → the Bazel test protocol, with coverage records matched to declared files or failing (G15).
4. US3 → isolation, the `bun_test` working directory and the load guard.
5. US4 → per-platform analysis and the manifest-only path.
6. US5 → consumer module, with the root `bunfig.toml`/`.env` fixture observed per OS.
7. Polish → CI, dependency floor, documentation, checks.
8. Revision 13 → after O-13, the Linux and macOS shell launcher, the manifest-only path without a
   staged tree (`bazel run`, local strategy), the first process without `$cwd/bunfig.toml`; then
   POST-0, POST-1.

---

## Notes

- [P] tasks = different files, no dependency on an incomplete task, and no edit of
  `bun/private/launcher.js` or `bun/private/run.bzl`.
- [Story] label maps a task to its user story for traceability.
- Verify each test fails for the expected reason before implementing (FR-020).
- Stop at any checkpoint to validate the stories so far.

---

## Phase 9: Convergence

- [X] T091 Record gap G-impl-1 in `specs/002-bun-binary-test/research.md` Part 1 and hand it to the user for a decision per FR-004, SC-009 (missing): `bazel run --noenable_runfiles //bun/tests/run/app:main -- extra` and `(cd e2e/smoke && bazel run --noenable_runfiles //app:main)` exit 1 with "ERROR: execve failed with code -2" (tdd-log T077, T079, T086; reproduced 2026-10-16), because the `bazel run` script drops `RUNFILES_MANIFEST_FILE` and the hermetic-launcher 0.0.16 stub takes `<name>.runfiles/`, which then holds only the manifest, as its runfiles source; give the sources (Bazel's `bazel run` script, hermetic-launcher 0.0.16 `runfiles.rs` `select_source`), the options, and the CI `manifest-only` job's expected failure; do not implement before the user decides
- [X] T093 Record in `specs/002-bun-binary-test/research.md` that the `windows_x64` `bun_test` case of `bun/tests/target_toolchain_test.bzl` is absent (Bazel's Windows test wrapper `@bazel_tools//src/tools/launcher` finds no C++ toolchain on a Linux host, tdd-log T074), so a `bun_test` carrying the Windows Bun is unverified by analysis, per SC-007, US4-3 (partial)

## Phase 10: Convergence

- [X] T094 Extend gap G-impl-1 in `specs/002-bun-binary-test/research.md` Part 1 with its reach beyond `bazel run` and hand it to the user together with T092's decision per FR-011, US4-2 (partial): `bazel test //bun/tests/run:skeleton_test --noenable_runfiles --spawn_strategy=local --nocache_test_results` fails with "ERROR: execve failed with code -2", while the same command with `--spawn_strategy=processwrapper-sandbox` passes (observed 2026-10-16, Linux), because sandboxed strategies stage a runfiles tree and the local strategy does not; correct the statement "`bazel test //... --noenable_runfiles` passes in both" to name the sandboxed strategy it ran under, state remote execution as not run, and make T092's resolution cover `bazel test` as well as `bazel run`
- [X] T096 [US3] Add the `bun_test` case of the undeclared-sibling import per US3-4 (partial): in `bun/tests/run/tree/` a checked-in `undeclared_sibling.test.ts` importing `./undeclared.ts`, a `manual` `bun_test(name = "sibling_test")` over it, and a case in `sibling_spawn.test.ts` asserting a non-zero exit and Bun's "Cannot find module" error; this guards T027, so record the red as a reverted mutation (the copy tree in `bun/private/run.bzl` also copies `undeclared.ts`, or the launcher runs the original test file), then green with and without `--noenable_runfiles` in `specs/002-bun-binary-test/tdd-log.md`

## Phase 11: Convergence

- [X] T098 Append the missing `Task | Kind | Red | Green | Platforms` rows for T091 and T093 (Kind: research; Red and Green "—"; the `research.md` section each wrote, G-impl-1 and the `windows_x64` `bun_test` record; Platforms Linux (WSL)) to `specs/002-bun-binary-test/tdd-log.md`, per tasks.md Conventions "Record", FR-020 (partial)

## Phase 12: Convergence

- [X] T101 [P] Draft the hermetic-launcher report for G-impl-1 in English and add it to `specs/002-bun-binary-test/tdd-log.md`, as T084 did for G12, per research G-impl-1 option 1 (missing): keep the directory preference of hermetic-launcher#59 and ask to honour `RUNFILES_MANIFEST_ONLY=1` and to fall back to `<executable>.runfiles_manifest` when a path resolved through the directory does not exist, with the sources research cites (HL-readme "Runfiles discovery", `runfiles.rs` `select_source`, `PREFER_DIRECTORY_SOURCE`, BZ-run, BZ-testrunner, BZ-testsetup); filing it is outward-facing and is the user's decision

---

## Phase 13: Revision 13 - Shell launcher on Linux and macOS (US3, US4)

**Goal**: On Linux and macOS a `bun_binary` or `bun_test` starts from a generated shell launcher
that finds its files with the Bash runfiles library of `rules_shell` 0.6.1 and execs the target
platform's Bun with `--config=<isolated_bunfig.toml>`, `--no-env-file`, `launcher.js` and
`<name>.launch.json`; Windows keeps the hermetic-launcher stub (FR-001 as restated by Revision 13;
research Part 1 "Plan for spec Revision 13" items 1–6; data-model "Executable"). G-impl-1 is
resolved: a manifest without a staged runfiles tree works for `bazel run` and for `bazel test`
without a sandbox (US4-2, SC-003, FR-024). The first process no longer reads `$cwd/bunfig.toml` on
Linux and macOS (FR-018a, G4 Windows only).

**Independent Test**: `bazel test //bun/tests:launcher_platform //bun/tests:platform_failure
//bun/tests/run/manifest/... //bun/tests/run/isolation/...` passes; quickstart rows 2, 2a, 2b, 2c
and 10 pass on Linux; every earlier test passes unchanged with and without `--noenable_runfiles`.

- [X] T102 Hand O-13 to the user and wait for the decision (constitution, Governance; research Part
  1 "Plan for spec Revision 13" item 6; plan Constitution Check VI; Kind: research): spec FR-022
  ("MUST NOT … write shell scripts or shell launchers") and SC-005 ("Zero shell scripts, shell
  launchers …") contradict FR-001 as restated by Revision 13 and constitution v2.0.0 VI, and
  Revision 13 did not restate them. Present both statements, the restated FR-001 and the
  constitution text, with no proposed wording beyond naming the conflict; the spec revision is the
  user's, through `specify workflow run speckit` (AGENTS.md). Also report the plan's finding that
  rules_python's `py_binary` bootstrap does not use the Bash runfiles library and the design follows
  `interpreter_binary` (research item 2), for the user to decide whether the constitution's pointer
  needs an amendment; the design does not wait for that answer. Append a row to
  `specs/002-bun-binary-test/tdd-log.md` with the spec revision number and date that settles O-13.
  Do not start T103 before that revision exists in `specs/002-bun-binary-test/spec.md`.
- [X] T103 Add the launcher's dependencies to `MODULE.bazel` (Kind: dependency; research Part 1
  "Plan for spec Revision 13" item 5, constitution IV): add `bazel_dep(name = "rules_shell",
  version = "0.6.1")` (non-dev) and replace `bazel_dep(name = "bazel_skylib", version = "1.9.2",
  dev_dependency = True)` with the non-dev `bazel_dep(name = "bazel_skylib", version = "1.9.0")`,
  keeping alphabetical order with the other non-dev `bazel_dep` lines; leave
  `bazel_skylib_gazelle_plugin` 1.9.2 (dev) unchanged. Refresh `MODULE.bazel.lock` and
  `e2e/smoke/MODULE.bazel.lock` with `bazel mod deps --lockfile_mode=update` in each module.
  Record: root `bazel test //...` and `(cd e2e/smoke && bazel test //...)` pass unchanged, and
  `bazel mod explain rules_shell` shows `rules_shell@0.6.1` in both modules.
- [X] T104 [US4] Pin the stub's expectations to a Windows target (FR-001 Windows; data-model
  "Executable", Windows row; Kind: mutation): in `bun/tests/run_test.bzl`, move assertion (d) of
  `skeleton_test` (the stub's embedded arguments `[<Bun>, "--no-env-file",
  "_main/bun/private/launcher.js", "_main/bun/tests/run/hello.launch.json"]`) out of the host
  test into a new `analysistest` of `//bun/tests/run:hello` with `config_settings =
  {"//command_line_option:platforms": [str(Label("//bun/tests/platforms:windows_x64"))]}`, where
  `<Bun>` is the rlocation path of the runfile whose owner is `Label("@bun_windows_x64//:bun.exe")`
  and the executable is `hello.exe`; add it to `skeleton_test_suite`. Set the same
  `config_settings` on the T017 test that expects `_main/bun/tests/<long name>.launch.json is longer
  than 256 bytes`. The host `skeleton_test` keeps (a)–(c). This guards existing behavior: record
  the red as a mutation (drop `.embedded_args("--no-env-file")` in `bun/private/run.bzl`; the
  Windows test fails), revert, record green for `bazel test //bun/tests:all`.
- [X] T105 [US4] Write the red launcher-per-platform tests (FR-001, Revision 13; data-model "Test
  fixtures", "launcher per platform"; research R12 "Revision 13 cases"): in
  `bun/tests/target_toolchain_test.bzl` add `launcher_platform_test_suite(name)`, registered as
  `launcher_platform` in `bun/tests/BUILD.bazel`, with `analysistest`s of a fixture `bun_binary`
  and a fixture `bun_test` under each of `linux_x64`, `linux_aarch64`, `darwin_x64` and
  `darwin_aarch64` (via `config_settings` `"//command_line_option:platforms"`) asserting, with
  English `msg`s:
  (a) the executable's basename is the target name (no `.exe`);
  (b) the action whose outputs hold the executable has mnemonic `TemplateExpand`, and its
  `content` starts with `#!/usr/bin/env bash` and holds, each as `shell.quote` from
  `@bazel_skylib//lib:shell.bzl` renders it, the rlocation paths of that platform's Bun, of
  `_main/bun/private/isolated_bunfig.toml`, of `_main/bun/private/launcher.js` and of the
  fixture's `<package>/<name>.launch.json`;
  (c) the runfiles hold `bazel_tools/tools/bash/runfiles/runfiles.bash` (an entry of
  `default_runfiles.root_symlinks` with that `path`, or a file with that rlocation path) and
  `isolated_bunfig.toml`;
  (d) a fixture `bun_binary` whose name is 240 characters long, so that its `<name>.launch.json`
  path exceeds 256 bytes, analyzes (the embedded-argument limit is Windows only).
  Add one `analysistest` under `windows_x64` for the fixture `bun_binary` asserting the executable
  ends in `.exe`, is not the output of a `TemplateExpand` action, and its runfiles do not hold
  `runfiles.bash` (existing behavior; it passes before T110 and is recorded as such). In
  `bun/tests/run_test.bzl`, change the T053 assertion of `copy_tree_test_suite` that a `bun_test`
  fixture's runfiles do not hold `bun/private/isolated_bunfig.toml` to assert that they hold it
  (the host is Linux), while its `launch.json` still has no `bunfig`. Record the reds: (a)–(c)
  find the stub (mnemonic of hermetic-launcher's finalizer, no `runfiles.bash`, no
  `isolated_bunfig.toml` for `bun_test`); (d) fails analysis naming 256 bytes; the T053 assertion
  finds no `isolated_bunfig.toml`.
- [X] T106 [US4] Move the no-stub test to Windows and write the red FreeBSD test (US4-4, FR-001;
  research Part 1 "Plan for spec Revision 13" item 6, HL-toolchains; data-model "no-stub
  platform"): in `bun/tests/platforms/BUILD.bazel` change `no_stub` to `@platforms//os:windows` and
  `@platforms//cpu:aarch64` (hermetic_launcher 0.0.16 registers a Windows template for x86_64
  only) and update its comment; in `bun/tests/target_toolchain_test.bzl` change the
  `platform_failure_test_suite` test-only toolchain's `target_compatible_with` to the same
  constraints, keep `no_stub_binary_test` (it must still fail naming `template_toolchain_type` and
  the platform), and remove `no_stub_test_test`, because a Windows `bun_test` does not analyze on
  a Linux host (T093); record that absence in `specs/002-bun-binary-test/research.md` next to the
  T093 record. Add to the same suite a test-only `bun_target_toolchain` and `toolchain()` for
  `//bun/tests/platforms:freebsd_x64`, registered through `"//command_line_option:extra_toolchains"`,
  and `analysistest`s asserting that a `bun_binary` and a `bun_test` analyze under `freebsd_x64` and
  that the executable is the output of a `TemplateExpand` action (a non-Windows platform with no
  hermetic-launcher toolchain gets the shell launcher; research item 4 "Other non-Windows OSes";
  nothing is claimed about running on FreeBSD, FR-026). Record: `no_stub_binary_test` still passes
  under the Windows platform (re-pointed, existing behavior); the red of the FreeBSD tests is the
  analysis failure naming the template toolchain type.
- [X] T107 [P] [US4] Write the red manifest-only spawn test without a staged tree (G-impl-1, US4-2,
  SC-003, FR-011; research Part 1 "Plan for spec Revision 13" item 3, the local-strategy row):
  create `bun/tests/run/manifest/BUILD.bazel` with `runfiles_manifest` targets (from
  `//bun/tests/support:runfiles_manifest.bzl`, `testonly = True`) for `//bun/tests/run:hello` and
  `//bun/tests/run:skeleton_test`, and `bun_test(name = "manifest_only_test", srcs =
  ["manifest_only.test.ts"], data = [both targets, both manifests], deps =
  ["//bun/tests/support:spawn"])`. `bun/tests/run/manifest/manifest_only.test.ts` spawns each
  target with `RUNFILES_DIR` naming a new empty directory under `TEST_TMPDIR`,
  `RUNFILES_MANIFEST_FILE` naming that target's manifest and `RUNFILES_MANIFEST_ONLY=1` (what
  `bazel test --spawn_strategy=local --noenable_runfiles` gives a test), asserting: (a) `hello`
  exits 0 and prints `hello`; (b) `skeleton_test` exits 0; (c) with a copy of `hello`'s manifest
  written under `TEST_TMPDIR` without the line of `_main/bun/tests/run/hello.launch.json`, `hello`
  exits 1 and stderr holds an English error naming `_main/bun/tests/run/hello.launch.json` (data-model
  "Executable": "an empty or missing result → English error naming the path, exit 1"). Case (c)
  runs only when `process.platform !== "win32"` and otherwise logs that it does not apply (the
  Windows stub reports a missing runfile its own way). Cases (a) and (b) run on every OS (the
  Windows stub prefers the manifest, Revision 13; Windows result from POST-1). Record the reds on
  Linux: (a) and (b) exit non-zero with "execve failed with code -2" (G-impl-1); (c) does not name
  the launch configuration. If a red differs, record what it is and check the test before going on
  (Genuine red).
- [X] T108 [US4] Record the command-line reds of G-impl-1 (quickstart 2a, 2b, 10; Kind: behavior,
  red only; green in T111): from the root `bazel run --noenable_runfiles //bun/tests/run/app:main --
  extra` and `bazel test //bun/tests/run:skeleton_test --noenable_runfiles --spawn_strategy=local
  --nocache_test_results`, and `(cd e2e/smoke && bazel run --noenable_runfiles //app:main)`; record
  each exit code and failure line ("ERROR: execve failed with code -2") in
  `specs/002-bun-binary-test/tdd-log.md`. These commands cannot be `bazel test` targets; T112 runs
  them in CI.
- [X] T109 [P] [US3] Write the red first-process `bunfig.toml` assertion (FR-018a as restated by
  Revision 13, G4 Windows only; data-model "isolation × 3"; research R12 "Revision 13 cases"): in
  `bun/tests/run/isolation/isolation.test.ts`, make `set.ts` of `bunfigDirectory()` also write
  `RULES_BUN_CWD_BUNFIG_PRELOAD` to stderr with `console.error` (stdout stays `probe`'s JSON), and
  in both "does not read a bunfig.toml in the working directory" tests assert, when
  `process.platform !== "win32"`, that `result.stdout + result.stderr` does not contain
  `RULES_BUN_CWD_BUNFIG_PRELOAD`, with an English message naming the first process and
  `$cwd/bunfig.toml`; on Windows log that the assertion does not apply (FR-018a). Record the red
  on Linux: both tests find the marker, because the stub's first process runs `bun --no-env-file
  launcher.js …` in the fixture directory and Bun reads its `bunfig.toml` (G4).
- [X] T110 [US4] Make T105–T109 green with the shell launcher (FR-001; research Part 1 "Plan for
  spec Revision 13" items 1, 3, 4; data-model "Executable", "`bun_binary`" and "`bun_test`"
  attributes):
  - create `bun/private/launcher.sh.tpl`: `#!/usr/bin/env bash`, then the "runfiles.bash
    initialization v3" block copied verbatim from the header of `shell/runfiles/runfiles.bash` of
    `rules_shell` 0.6.1, then an English comment naming FR-001, then for each of four placeholders
    (Bun, `isolated_bunfig.toml`, `launcher.js`, `<name>.launch.json`) a variable set with
    `rlocation`, which, when empty or not a file, prints `<rlocation path> is not in the runfiles`
    (English, naming the path) to stderr and exits 1, as rules_python's `interpreter_tmpl.sh` does;
    then `runfiles_export_envvars`; then `exec "$bun" "--config=$bunfig" --no-env-file "$launcher"
    "$launch_config" "$@"`. Export it from `bun/private/BUILD.bazel` like `launcher.js`.
  - in `bun/private/run.bzl`: add the implicit `_launcher_template`
    (`//bun/private:launcher.sh.tpl`, `allow_single_file = True`) and `_bash_runfiles`
    (`@rules_shell//shell/runfiles`) to both rules, and move `_bunfig` to both rules; declare
    `launcher.finalizer_toolchain_type` with `config_common.toolchain_type(..., mandatory =
    False)`. When the target platform has `@platforms//os:windows` (`_windows_constraint`), keep
    today's path: require both hermetic-launcher toolchain types (English `fail()` naming the type
    and the target platform, R1), check the embedded arguments against 256 bytes, compile the stub
    to `<name>.exe`. Otherwise declare `<name>` and write it with `ctx.actions.expand_template(
    template = ctx.file._launcher_template, output = …, substitutions = {…}, is_executable = True)`,
    substituting each placeholder with `shell.quote(<rlocation path>)` (`load("@bazel_skylib//lib:
    shell.bzl", "shell")`; rlocation paths as `_rlocation_path` already computes them, rules_python
    `runfiles_root_path`), merge `ctx.attr._bash_runfiles[DefaultInfo].default_runfiles`, and put
    `isolated_bunfig.toml` in the runfiles of both rules; resolve no hermetic-launcher toolchain.
    `launch.json` is unchanged (`bunfig` for `bun_binary` only); `bun/private/launcher.js` is not
    changed.
  - run `bazel run //:gazelle` so the `bzl_library` of `run.bzl` depends on
    `@bazel_skylib//lib:shell`.
  Record green: T105, T106, T107 and T109 pass; root `bazel test //...` and `bazel test //...
  --noenable_runfiles` pass, including the unchanged argument, standard-input, exit-code,
  spaces-in-paths, isolation, guard, coverage and length spawn tests; `(cd e2e/smoke && bazel test
  //...)` passes. Record in the same row that the optional finalizer toolchain on a non-Windows
  target has no test of its own (hermetic-launcher registers it for every execution platform) and
  is unverified (FR-026).
- [X] T111 [US4] Verify G-impl-1's resolution on Linux (quickstart 2, 2a, 2b, 2c, 10; Kind:
  verification; replaces T095): run, and record each exit code in
  `specs/002-bun-binary-test/tdd-log.md` as the green of T108: `bazel run --noenable_runfiles
  //bun/tests/run/app:main -- extra`; `bazel test //bun/tests/run:skeleton_test --noenable_runfiles
  --spawn_strategy=local --nocache_test_results`; `bazel build //bun/tests/run/app:main && head -n1
  bazel-bin/bun/tests/run/app/main` (prints `#!/usr/bin/env bash`); `(cd e2e/smoke && bazel test
  //... --noenable_runfiles && bazel run --noenable_runfiles //app:main)`; and root and `e2e/smoke`
  `bazel test //... --noenable_runfiles --spawn_strategy=local --nocache_test_results`. Then add
  to G-impl-1 in `specs/002-bun-binary-test/research.md` that these local Linux runs pass (cite the
  tdd-log rows) while macOS, Windows and remote execution are unverified until POST-1, and that the
  stale-tree case (plan Risks) is not tested. A failure is recorded and reported to the user, not
  worked around (AGENTS.md).
- [X] T112 Extend the CI `manifest-only` job in `.github/workflows/ci.yaml` (FR-024, SC-003,
  quickstart 13; Kind: verification; replaces T095's CI part): keep its `bazel test //...
  --noenable_runfiles` and `bazel run --noenable_runfiles` steps, which are now expected to pass,
  and add a step `bazel test //... --noenable_runfiles --spawn_strategy=local` if both modules'
  local-strategy runs passed in T111; otherwise add only `bazel test //bun/tests/run:skeleton_test
  --noenable_runfiles --spawn_strategy=local` with `if: matrix.folder == '.'` and report the
  failing targets to the user. Steps call only `bazel`. Record: `prek run --all-files` passes
  locally; CI results come from POST-1.
- [X] T113 Align the documentation with Revision 13 (FR-026, R14, contracts/public-api.md
  "Launching"; Kind: documentation; replaces T092's and T097's documentation parts): in
  `bun/private/run.bzl` and the `bun/defs.bzl` module docstring, state per OS how a target
  launches (shell launcher with `@rules_shell//shell/runfiles` on Linux and macOS; `<name>.exe`
  stub on Windows), the run-time requirement on Linux and macOS (`/usr/bin/env`, `bash`, and
  `grep`, `sed`, `cut`, `tr`, `wc`, `awk`, `uname`, `dirname`, `basename`), that a manifest
  without a runfiles tree works for `bazel run` and `bazel test`; remove any statement that
  `--noenable_runfiles` fails (G-impl-1); restrict to Windows the first-process `$cwd/bunfig.toml`
  limitation (G4, FR-018a), the 256-byte embedded-path limit and the quote and 128-argument
  limitation (G1); keep the first-process transpiler-cache entry on every OS (FR-018a). Change the
  comment of `bun/private/isolated_bunfig.toml` to say it configures the first process of both
  rules on Linux and macOS and the second process of `bun_binary` on every OS. Change the failure
  message of canary C4 in `bun/tests/canary/c4_config_form.test.ts` to name "the Windows
  first-process limitation (FR-018a, G4)", keeping its link and assertion. In
  `specs/002-bun-binary-test/tdd-log.md` add to the T101 draft a line that it is superseded by
  Revision 13 and not filed. Claim only behavior a test covers. Record: root `bazel test //...`
  passes, including canary C4.
- [X] T114 Run the static checks and the AGENTS.md hand-back checks again (SC-005 as revised by
  T102's spec revision, FR-022, constitution IV–VI; Kind: verification), and record each output in
  `specs/002-bun-binary-test/tdd-log.md`: `git grep -n run_shell -- bun e2e` and `git grep -n
  expand_make_variables -- bun` print nothing; `git ls-files '*.sh' '*.bat' '*.cmd' '*.ps1'` lists
  no file this feature added; `git grep -n -e 'expand_template' -- bun` lists only
  `bun/private/run.bzl`; `bazel query 'attr(visibility, "//visibility:public", //bun/...)'` differs
  from the same query on `main` only as T085 recorded; `git grep -n 'bun/private' -- e2e` prints
  nothing; then in the root `bazel run //:gazelle`, `prek run --all-files`, `bazel test //...`,
  and in `e2e/smoke/` `bazel test //...`. Report a failure; do not widen the task to fix it.

**Checkpoint**: on Linux every target launches through the shell launcher with and without a
runfiles tree, including `bazel run --noenable_runfiles` and the local strategy; Windows keeps the
stub; macOS and Windows results come from POST-1.

## Phase 14: Convergence

- [X] T115 CRITICAL: Make `e2e/smoke` resolve exactly the `bazel_skylib` version the ruleset declares per Constitution IV (contradicts): `e2e/smoke/MODULE.bazel` declares `bazel_dep(name = "bazel_skylib", version = "1.9.2", dev_dependency = True)`, so `bazel mod explain bazel_skylib --verbose` in `e2e/smoke` shows `rules_bun`'s non-dev `bazel_skylib` 1.9.0 (T103) lifted to 1.9.2 ("was 1.9.0, cause <root>"), and the declared floor is never exercised; lower that declaration to `1.9.0`, refresh `e2e/smoke/MODULE.bazel.lock` with `bazel mod deps --lockfile_mode=update`, and record in `specs/002-bun-binary-test/tdd-log.md` (Kind: dependency) that `bazel mod explain bazel_skylib --verbose` in `e2e/smoke` resolves 1.9.0 and that `(cd e2e/smoke && bazel test //... && bazel run //app:main)` passes; if another module in the graph requires a higher version, record which and report it to the user instead of raising the declaration
- [X] T116 Add a Windows CI job to `.github/workflows/ci.yaml` that runs, in `.` and `e2e/smoke`, `bazel test //...` and the `bazel run` step of the self-checking program with, in the job's bazelrc (G-impl-2 option 1, spec Revision 14), `--shell_executable` and `--repo_env=BAZEL_SH` set to a path that does not exist, `--action_env`, `--host_action_env`, `--test_env` and `--run_env` setting a `PATH` without any Bash directory, `--run_env==BAZEL_SH`, `--nocache_test_results` and no disk cache, add it to `conclusion.needs`, and record in `specs/002-bun-binary-test/tdd-log.md` (Kind: verification) that `prek run --all-files` passes locally and that the CI result comes from POST-1, per SC-005 and Constitution VI ("no Windows build or run requires Bash") (partial): no CI job removes Bash, yet `bun/defs.bzl` and `bun/private/run.bzl` state that the Windows stub "needs no Bash"; if the job cannot be built without a step other than `bazel`, or fails, report it to the user (FR-026: until it passes, the claim is unverified)
- [X] T117 Update the comments that still describe the hermetic-launcher stub as the launcher on every OS per FR-001 as restated by Revision 13 (contradicts): `bun/private/launcher.js` lines 1–4 ("The stub of the target starts Bun on this file"), and `bun/tests/run/spaces/BUILD.bazel` and `bun/tests/run/tree/BUILD.bazel` ("the stub prefers it on Linux and macOS"), which on Linux and macOS is now the shell launcher with the Bash runfiles library; comment-only change, record in `specs/002-bun-binary-test/tdd-log.md` (Kind: documentation) that root `bazel test //...` still passes

## Phase 15: Convergence

- [X] T118 CRITICAL: State macOS and Windows behavior as unverified until a named CI run passes, naming the platforms the tests ran on, per Constitution II and spec Revision 15 item 3 (contradicts): the shared doc in `bun/private/run.bzl` ("Launching", "Limits", "Windows only"), the module docstring of `bun/defs.bzl` and `contracts/public-api.md` state Windows and macOS behavior as fact (for example "On Windows the executable is `<name>.exe`, a hermetic-launcher stub, and needs no Bash") although local runs are Linux (WSL) only and no named macOS or Windows CI run has passed (T116: POST-1 pending); each such statement names the platforms its tests ran on (Linux (WSL) locally; macOS and Windows: unverified until the named CI run of POST-1 passes). Run it after T119–T124 so it also covers the text they add. Record in `specs/002-bun-binary-test/tdd-log.md` (Kind: documentation) that `prek run --all-files` and root `bazel test //...` pass
- [X] T119 [US4] Make the shell launcher export absolute `RUNFILES_DIR` and `RUNFILES_MANIFEST_FILE` before it execs Bun per FR-011, FR-012 and spec Revision 15 item 1 (missing): `bun/private/launcher.sh.tpl` passes on what `runfiles_export_envvars` exports, which is relative when the target is started by a relative path (`$0.runfiles`, or a relative `RUNFILES_DIR` / `RUNFILES_MANIFEST_FILE`), and the second process of a `bun_test` runs with its working directory at the copy-tree root, where a relative path no longer resolves. Test first: a spawn test in `bun/tests/run/` (Linux and macOS only, `target_compatible_with` excluding Windows) that starts a `bun_binary` fixture printing both variables and a passing `bun_test`, once with a relative `RUNFILES_DIR` (tree) and once with only a relative `RUNFILES_MANIFEST_FILE` (manifest), both relative to the spawn's working directory; assert exit 0 and that each exported variable is absolute; record its red. Then make the paths absolute in the template only. Record in `specs/002-bun-binary-test/tdd-log.md` (Kind: behavior) the red, the green, and root `bazel test //...`
- [X] T120 [US3] Test that the load guard's fail-closed rejection prints its English error under `bun test` per FR-018 (load guard, fail closed) and spec Revision 15 item 1 (partial): `bun/tests/run/guard/fail_closed.test.ts` starts the toolchain's Bun with the guard preloaded only on a program, never under `bun test`. Add the two cases (`RULES_BUN_LAUNCH_CONFIG` unset; a missing launch configuration) with `bun test` on a declared test file, asserting a non-zero exit, `rules_bun load guard: …` on standard error and that the test file's body did not run. If the cases fail, fix `bun/private/launcher.js` until the error is printed (Kind: behavior); if they pass against the current code, record the red by a mutation of the guard's error message in `launcher.js`, reverted (Kind: mutation). Record in `specs/002-bun-binary-test/tdd-log.md`, with root `bazel test //...`
- [X] T121 [US1] Take `env` values literally in both rules per FR-012 and spec Revision 15 item 2 (contradicts): `bun/private/run.bzl` expands `env` with `ctx.expand_location` and documents "values support `$(location)` and `$(locations)` only", and the analysis test in `bun/tests/run_test.bzl` (the `ONE` / `MANY` values) asserts the expansion, although the expanded path does not resolve from the copy tree or without a runfiles tree. Test first: change that analysis test to expect `RunEnvironmentInfo.environment` to hold `$(location …)` and `$(locations …)` unchanged and record its red; then remove the expansion and change the `env` attribute's `doc` to say values are taken literally and data is located through `import.meta.dir`. Align `contracts/public-api.md` (the `env` bullet), `data-model.md` (`RunEnvironmentInfo` row and the `env` attribute row) and the `expand_location` entries of `research.md`. Record in `specs/002-bun-binary-test/tdd-log.md` (Kind: behavior), with root `bazel test //...` and `(cd e2e/smoke && bazel test //...)`
- [X] T122 [US4] Add the analysis test that a `bun_test` built for `windows_x64` carries the Windows Bun per SC-007, US4-3 and spec Revision 15 item 4 (missing): `_RULE_PLATFORM_TESTS["test"]` in `bun/tests/target_toolchain_test.bzl` has no `windows_x64` case, because on a Linux host Bazel's Windows test wrapper (`@bazel_tools//src/tools/launcher`) finds no C++ toolchain (research "`bun_test` carrying the Windows Bun is not analyzed"). Add `test_platform_windows_x64_test` asserting that the target's runfiles hold `@bun_windows-x64//:bun.exe` and record its red (the analysis error); then make it analyze with a mechanism bazel.build documents, confined to the test's configuration and changing nothing consumers get, with its source recorded in `research.md`, and replace that research section's "no gap, unverified" with the result. If no documented mechanism exists, record it as a gap in `research.md` and report it to the user instead (SC-009). Record in `specs/002-bun-binary-test/tdd-log.md` (Kind: behavior), with root `bazel test //...`
- [X] T123 [US3] Reject `BUN_OPTIONS` in the Linux and macOS shell launcher before it starts Bun per FR-018a and spec Revision 15 item 5 (missing): `bun/private/launcher.sh.tpl` execs Bun with `BUN_OPTIONS` intact, and bun.com documents that it prepends arguments to any Bun execution, so `--eval` or `--preload` in it runs code in the first process before or instead of `launcher.js`, whose own check is then bypassed; `bun/tests/run/isolation/bun_options.test.ts` covers only `--define=X:1`. Test first: a spawn test in `bun/tests/run/isolation/` (Linux and macOS only) that starts the `probe` `bun_binary` and the `probe_test` `bun_test` with `BUN_OPTIONS` set to an `--eval` that prints a marker and to a `--preload` of a fixture that prints a marker, asserting exit 1, an English error naming `BUN_OPTIONS`, and no marker in the output; record its red. Then add the check to the template, before any Bun starts; keep the check in `launcher.js` (Windows). Record in `specs/002-bun-binary-test/tdd-log.md` (Kind: behavior), with root `bazel test //...`
- [X] T124 [US4] Pin and document the Windows `BUN_OPTIONS` limitation per FR-018a, FR-028 and spec Revision 15 item 5 (missing): the Windows stub cannot inspect or unset the environment (hermetic-launcher#78), so an inherited `BUN_OPTIONS` reaches the first Bun process and can replace the launcher, yet `bun/private/run.bzl` ("A set `BUN_OPTIONS` fails the run before the {code} starts") and `contracts/public-api.md` state the rejection for every OS. Add canary C16, `bun/tests/canary/c16_windows_bun_options.test.ts` with a `bun_test` compatible with `@platforms//os:windows` only, which spawns a Windows target with `BUN_OPTIONS` set to an `--eval` that prints a marker, asserts the marker is printed, and on failure names the limitation and https://github.com/hermeticbuild/hermetic-launcher/issues/78; add C16 to the canary list of `research.md` and to the fixtures of `data-model.md`; restate the docstring and the contract: rejected on Linux and macOS, a Windows limitation. Record in `specs/002-bun-binary-test/tdd-log.md` (Kind: canary) the red as "not run locally (Windows only)" with the result from the Windows CI job in POST-1, and that root `bazel test //...` passes on Linux with C16 skipped

## Phase 16: Convergence

- [X] T125 [US4] Keep every text file LF on checkout on every OS per SC-002, FR-024 and FR-011 (contradicts): `.gitattributes` holds only `export-ignore` rules, and CI run 39048525769 on PR #4 checks out with CRLF on Windows, so `bun/tests/run/spaces/with space.txt` reads `"data with space\r\n"` (`//bun/tests/run/spaces:spaces_test`), `e2e/smoke/app/message.txt` fails the `message === "message from app\n"` check of `bazel run //app:main` in all three Windows jobs, and `bun/private/launcher.sh.tpl` becomes a template whose content does not start with `#!/usr/bin/env bash\n`, the first assertion of `_shell_launcher_test_impl` in `bun/tests/target_toolchain_test.bzl` (the eight `//bun/tests:launcher_platform_{binary,test}_{linux,darwin}_*` tests, whose CI output is empty, so this cause is inferred until the reproduction below shows it). Test first: in a temporary clone made with `git clone -c core.autocrlf=true` of this branch on Linux, run `bazel test //bun/tests:launcher_platform //bun/tests/run/spaces:spaces_test` and `(cd e2e/smoke && bazel run //app:main)`, and record the red. Then add `* text=auto eol=lf` as the first rule of `.gitattributes`, keeping the `export-ignore` rules, run `git add --renormalize .` and confirm it changes no file, and repeat the clone run for the green. Record in `specs/002-bun-binary-test/tdd-log.md` (Kind: behavior) the red, the green and root `bazel test //...`; the Windows result comes from POST-1, and a launcher_platform test that still fails there is reported to the user as a separate cause
- [X] T126 [US4] Name the runfiles manifest by the executable's name in the manifest-only spawn tests per FR-011, FR-021 and SC-002 (contradicts): `bun/tests/run/tree/sibling_spawn.test.ts` (`manifestOnly`) and `bun/tests/run/spaces/manifest_spawn.test.ts` look up `_main/<package>/<name>.runfiles_manifest`, but on Windows the executable is `<name>.exe` and Bazel names its manifest `<name>.exe.runfiles_manifest`, so CI run 39048525769 fails with "`_main/bun/tests/run/tree/sibling.runfiles_manifest` is not in the runfiles manifest" (`//bun/tests/run/tree:sibling_spawn_test`, `//bun/tests/run/spaces:manifest_spawn_test`). The red is that CI run (it cannot be reproduced on Linux, where both names agree). Derive the path as `executable(<rlocation path>) + ".runfiles_manifest"` with `executable()` of `bun/tests/support/spawn.ts`, changing no assertion; record in `specs/002-bun-binary-test/tdd-log.md` (Kind: behavior) the red from CI run 39048525769 and root `bazel test //...` passing on Linux, with the Windows result from POST-1
- [X] T127 [US2] Pin `copy_tree_test_rule_test` to a Linux target platform per FR-021 and SC-007 (contradicts): `_copy_tree_test_rule_test_impl` in `bun/tests/run_test.bzl` asserts that a `bun_test` holds `bun/private/isolated_bunfig.toml` in its runfiles, which `bun/private/run.bzl` adds only for the shell launcher (Linux and macOS) and, on Windows, only for `bun_binary`, so with the host platform as the target the test fails on every Windows job of CI run 39048525769 (`//bun/tests:copy_tree_test_rule_test`). The red is that CI run. Give `copy_tree_test_rule_test` `config_settings` that set `//command_line_option:platforms` to `//bun/tests/platforms:linux_x64` and, as `_platform_config(..., test_rule = True)` in `bun/tests/target_toolchain_test.bzl` does, `//command_line_option:extra_execution_platforms` to `@platforms//host` and that platform; change no assertion. Record in `specs/002-bun-binary-test/tdd-log.md` (Kind: behavior) the red from CI run 39048525769 and root `bazel test //...` on Linux, with the Windows result from POST-1
- [X] T128 [US3] Give the large-set spawn tests a per-test timeout that fits a Windows launch per FR-018 (load guard) and SC-002 (partial): in CI run 39048525769, `//bun/tests/run/guard:large_set_test` fails on every Windows job with exit code 143 for `./large_files/f09999.json` and "Unhandled error between tests" after 10.4 s for its two tests, which matches Bun's default 5-second per-test timeout (spec Edge Cases) ending each test and its spawned target; the guard's result itself is not observed. The red is that CI run. Pass an explicit timeout to both tests of `bun/tests/run/guard/large_set.test.ts` (the third argument of `test`, bun.com "Test timeouts"), sized from the target's launch time and well below the Bazel `timeout` of the target, with a comment naming why; change no assertion. Record in `specs/002-bun-binary-test/tdd-log.md` (Kind: behavior) the red, the launch time measured on Linux, and root `bazel test //...`; if the Windows job of POST-1 still fails or exceeds the timeout, record the Windows launch time of 10,000 declared files as a gap in `research.md` and report it to the user instead of raising the timeout again
