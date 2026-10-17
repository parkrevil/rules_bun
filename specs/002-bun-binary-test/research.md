# Research: Run Bun Programs and Bun Tests (`bun_binary`, `bun_test`)

**Bazel**: 9.2.0 (`.bazelversion`). **Bun**: 1.4.2 (`MODULE.bazel`), tag `bun-v1.4.2` =
`744846f844374847c902b5e7fd59b4342a51ef99`. Bun documentation was read at that commit
(`docs/`); every page cited below is identical on `main` as of 2026-10-03, so bun.com shows the
same text. **hermetic-launcher**: `v0.0.16`; `main` has no commits after the tag (the Windows
launcher since spec Revision 13). **rules_shell**: `0.6.1`, the version Bazel 9.2.0's own
`MODULE.tools` requires; the Bash runfiles library of the Linux and macOS launcher (Part 1 "Plan
for spec Revision 13").

Sources (short names used below):

| Name | Source |
|---|---|
| BZ-toolchains | https://bazel.build/extending/toolchains ("Toolchains and configurations", "Toolchain resolution") |
| BZ-encyclopedia | https://bazel.build/reference/test-encyclopedia |
| BZ-coverage | https://bazel.build/extending/rules#code-coverage |
| BZ-common | https://bazel.build/reference/be/common-definitions (`args`, `env`, `env_inherit`) |
| BZ-ctx | https://bazel.build/rules/lib/builtins/ctx (`expand_location`, `expand_make_variables`, `target_platform_has_constraint`) |
| BZ-runenv | https://bazel.build/rules/lib/providers/RunEnvironmentInfo |
| BZ-platformfrag | https://bazel.build/rules/lib/fragments/platform (`platform`: "The current target platform"; named in the English failure of an unresolved optional toolchain, T076) |
| BZ-instrument | https://bazel.build/reference/command-line-reference (`--[no]instrument_test_targets`, default `false`: "specifies whether to consider instrumenting test rules"; set by the `InstrumentedFilesInfo` analysis test of T047) |
| BZ-flags | https://bazel.build/reference/command-line-reference#flag--enable_runfiles |
| BZ-manifest | `SourceManifestAction.java` at Bazel 9.2.0, lines 77–84, 381–403 (manifest line escaping) |
| BZ-repomap | https://github.com/bazelbuild/proposals/blob/main/designs/2022-07-21-locating-runfiles-with-bzlmod.md |
| BZ-run | `RunCommand.java` at Bazel 9.2.0: `ENV_VARIABLES_TO_CLEAR_UNCONDITIONALLY` (lines 214–223), `ensureRunfilesBuilt` (lines 996–1040) |
| BZ-testsetup | `tools/test/test-setup.sh` at Bazel 9.2.0 (the copy in the install base's `embedded_tools`), lines 81–87, 120, 135–140 |
| BZ-testrunner | `TestRunnerAction.java` at Bazel 9.2.0, lines 790–793 (`RUNFILES_MANIFEST_ONLY`) |
| BZ-teststrategy | `StandaloneTestStrategy.java` at Bazel 9.2.0, line 83 (`RUNFILES_DIR`) |
| BZ-lib-runfiles | bazel-contrib/bazel-lib `v3.7.2` `lib/BUILD.bazel` lines 36–39 (`config_setting(name = "enable_runfiles")`) |
| HL-pr59 | https://github.com/hermeticbuild/hermetic-launcher/pull/59 |
| HL-issue61 | https://github.com/hermeticbuild/hermetic-launcher/issues/61 |
| HL-readme | https://github.com/hermeticbuild/hermetic-launcher/blob/v0.0.16/README.md |
| HL-src | `runfiles-stub/src/windows.rs`, `linux.rs`, `macos.rs`, `common.rs`, `runfiles.rs`, `launcher/private/rules/lib.bzl`, `launcher/private/toolchains.bzl` at `v0.0.16` |
| RJS | aspect-build/rules_js `0a0b62de7d9b1b35077328ef1377a7439d50f20f`: `docs/hermetic_launcher.md`, `js/private/js_binary.bzl`, `js/private/js_binary.cjs.tpl`, `js/private/js_binary.sh.tpl`, `js/private/node-bootstrap/launcher.cjs` |
| RPY | bazel-contrib/rules_python `fc7dc414a2f4e1d9596dad13fabb2cded3a39a1a`: `python/private/py_toolchain_suite.bzl`, `python/private/py_runtime_rule.bzl`, `python/runfiles/runfiles.py` |
| RGO | bazel-contrib/rules_go `c18ec4766d81c57cb84f545ea2823d2bd9714766`: `go/tools/builders/generate_test_main.go`, `go/tools/bzltestutil/wrap.go` |
| BUN-run | `docs/snippets/cli/run.mdx` (CLI usage on https://bun.com/docs/runtime) |
| BUN-testcli | `docs/snippets/cli/test.mdx` (CLI usage on https://bun.com/docs/test) |
| BUN-bunfig | https://bun.com/docs/runtime/bunfig |
| BUN-env | https://bun.com/docs/runtime/environment-variables |
| BUN-autoinstall | https://bun.com/docs/runtime/auto-install |
| BUN-discovery | https://bun.com/docs/test/discovery |
| BUN-parallel | https://bun.com/docs/test/parallel |
| BUN-reporters | https://bun.com/docs/test/reporters |
| BUN-coverage | https://bun.com/docs/test/code-coverage |
| BUN-snapshots | https://bun.com/docs/test/snapshots |
| BUN-testruntime | https://bun.com/docs/test/runtime-behavior |
| BUN-resolution | https://bun.com/docs/runtime/module-resolution |

"Observed" below means run by the planner with the Bun 1.4.2 binary from
`@bun_linux-x64` in a scratch directory under `/tmp`, Linux (WSL), 2026-10-03. Observations are
not documentation; FR-017 counts a feature as supported only when bun.com documents it and a test
shows it working. macOS and Windows were not run.

## Part 1 — Gaps (FR-004, SC-009)

Each gap is a mandatory requirement no documented API satisfies on every platform. Work on it
stops until the user decides; no task for it may exist in `tasks.md` before that. Options are
listed with a recommendation; none is applied.

### G1. Windows stub does not forward every argument unchanged (FR-001, FR-013, US1-4)

- **Reach (spec Revision 13, 2026-10-17)**: Windows only. Linux and macOS launch through the
  shell launcher, not the stub (Part 1 "Plan for spec Revision 13").
- **Requirement**: the launch mechanism changes no argument boundary or value, including empty
  arguments and arguments containing spaces or quotes, on every OS.
- **Source**: HL-src `windows.rs`. The Windows stub takes its runtime arguments by re-parsing
  `GetCommandLineW()` in `parse_command_line` (lines 439–509): a quoted argument ends at the next
  `"`, and a backslash is never treated as an escape. Bazel and every caller that quotes with the
  documented `CommandLineToArgvW` rules write an embedded quote as `\"`, so an argument such as
  `say "hi"` arrives split and with stray backslashes. The output side (`append_arg`, lines
  537–570) quotes correctly, so only the input side is wrong. The same function stores at most
  128 runtime arguments (`argc < 128`, lines 441, 475, 646) and silently drops the rest, although
  HL-readme says "Runtime arguments are unrestricted". Linux and macOS take `argv` from the
  kernel and are not affected.
- **Status**: read from source, not run (no Windows host). No open issue upstream covers it
  (issues #9, #72, #76, #78 are the open ones).
- **Options**:
  1. *(recommended)* Report it upstream with a reproducer and a fix (parse with the
     `CommandLineToArgvW` rules, no fixed cap), then raise `hermetic_launcher` to the release
     that contains it. US1-4 on Windows waits for that release.
  2. Amend the specification: on Windows, arguments containing `"` and more than 128 runtime
     arguments are a documented limitation; the Windows test covers empty and space-containing
     arguments only.
  3. Choose a different launcher (would reopen the constitution V approval).

### G2. No documented way to stop `bun test` writing snapshot files (FR-016b)

- **Requirement**: a `bun_test` never writes snapshot files; a missing or outdated snapshot fails.
- **Source**: BUN-snapshots says only "In CI environments, Bun does not write new snapshots
  unless you pass this flag" (line 51). No page defines how Bun detects a CI environment, and
  BUN-testcli and BUN-bunfig have no option for it or for the snapshot directory.
- **Observed**: with `CI` unset, a new `toMatchSnapshot()` writes `__snapshots__/<file>.snap` and
  passes. With `CI=true` the test fails ("Snapshot creation is disabled in CI environments unless
  --update-snapshots is used"), **but Bun still creates `__snapshots__/<file>.snap`** holding the
  header line. Bun writes it next to the test file's real path (R6), which is the consumer's
  source tree.
- **Options**:
  1. *(recommended)* Drop FR-016b from this feature and document that snapshot tests are not
     supported by `bun_test`; ask Bun upstream for a documented read-only snapshot mode.
  2. Set `CI=true` (undocumented trigger) and document that a header-only file may still be
     created in the source tree.
  3. Keep FR-016b and block `bun_test` until Bun documents such a mode.

### G3. `--config`, `--no-env-file` and `--no-install` are not documented for `bun test` (FR-018, FR-017)

- **Status**: **withdrawn by spec Revision 10 (2026-10-08); restated by spec Revision 11
  (2026-10-15)**. `bun test` gets no `--config`. Revision 10 relied on `bun test` reading
  `$cwd/bunfig.toml`, which bun.com documents for the runtime only (BUN-run); BUN-bunfig and
  BUN-testconfig do not say how `bun test` finds the file. Revision 11 therefore makes no claim
  about Bun's lookup: the second process runs at the root of the copy tree, which holds only
  declared files, and the rule writes no `bunfig.toml` there (Part 1 "Plan for spec Revision 11").
  Asked upstream as oven-sh/bun#45331 (open, 2026-10-15): state the lookup rule for `bun test`
  and whether `--config` applies to it. The text below is kept as the record of the 2026-10-03
  decision.

- **Requirement**: the configuration file the rule supplies replaces `$cwd/bunfig.toml` for
  `bun test` as well; `.env` loading and auto-install are off.
- **Source**: `--config` ("Specify path to Bun config file. Default `$cwd/bunfig.toml`. Alias:
  `-c`") appears only in BUN-run, the CLI usage of `bun run`. BUN-testcli lists neither
  `--config` nor `--no-env-file` nor `--no-install`; BUN-testruntime lists the "CLI flags [that]
  also work with `bun test`" (`--smol`, `--inspect`, `--preload`, `--define`, `--loader`,
  `--tsconfig-override`, `--conditions`, `--env-file`, `--prefer-offline`,
  `--frozen-lockfile`), and none of the three is among them. BUN-env shows `--no-env-file` with
  `bun run` only. BUN-bunfig documents `env = false` and `install.auto = "disable"`, which take
  effect only if the file is read.
- **Observed**: `bun test --config=<file>` ignores a `bunfig.toml` in the working directory (its
  `preload` does not run) and applies `env = false` (a `.env` there is not loaded). For `bun run`,
  `--config=<file>` and `--no-env-file` behave the same way. `bun test` did not attempt an
  auto-install even without any protection (G5).
- **Options**:
  1. *(recommended)* Accept "documented for `bun run`, observed and pinned by a test for
     `bun test`" for `--config=` only, as an explicit, recorded exception to FR-017; ask Bun
     upstream to document it for `bun test`.
  2. Block FR-018 for `bun_test` until Bun documents it.

### G4. The stub cannot pass the configuration file to the first Bun process (FR-018a)

- **Reach (spec Revision 13, 2026-10-17)**: Windows only. On Linux and macOS the shell launcher
  passes `--config=<resolved path>` as one argument, so the first process reads only the rule's
  configuration file and the first-process `bunfig.toml` limitation of FR-018a does not apply
  there. The transpiler-cache entry the first process writes for the launcher stays a limitation
  on every OS (FR-018a; Revision 13 removes only the `bunfig.toml` part).
- **Requirement** (FR-018a): the first Bun process "gets the configuration file and
  `--no-env-file` from the stub's embedded arguments".
- **Source**: the stub resolves only whole arguments through runfiles (HL-readme
  "`transformed_args` … Indices of args to resolve through runfiles"; HL-src `lib.bzl`
  `_append_runfile`). BUN-run documents `--config` as a string option but not whether the value may
  be a separate argument.
- **Observed**: only `--config=<path>` works. `--config <path>` and `-c <path>` make `bun run`
  execute `<path>` as the entry point (the TOML file) and are ignored by `bun test`; `-c=<path>` is
  ignored. So the stub would have to embed `--config=` followed by a runfiles-resolved path in the
  same argument, which hermetic-launcher has no way to do. `--no-env-file` alone can be embedded.
  Consequence: a `bunfig.toml` in the working directory is read by the first process, and its
  `preload` runs before the rule's launcher (observed for `bun run`), so it can change the
  environment the launcher hands to the second process.
- **Options**:
  1. *(recommended)* Add this to the FR-018a known limitation: the first process gets
     `--no-env-file` but may read `$cwd/bunfig.toml`; under `bazel test` and `bazel run` the
     working directory is the runfiles root, which holds a `bunfig.toml` only when a target
     declares one at the root of the main repository. File an upstream request
     (hermetic-launcher: resolve the remainder of an argument after a literal prefix; or Bun:
     accept `--config <path>`), and remove the limitation when either ships.
  2. The launcher fails with an English error when `bunfig.toml` exists in its working directory.
     This turns a silent effect into a failure, but only after the preload has already run, and it
     also rejects a declared root `bunfig.toml`.
  3. Block FR-018a until upstream supports it.

### G5. `bun test` does not auto-install, so US3-3 has no red for `bun_test` (FR-020, SC-006)

- **Requirement**: each isolation fixture is first shown to change the result without the
  protection (the red record), then to change nothing with it.
- **Source**: BUN-autoinstall describes auto-install for executing scripts; BUN-testruntime says
  `--prefer-offline` and `--frozen-lockfile` "affect any network requests or auto-installs during
  test execution", which implies `bun test` can auto-install.
- **Observed**: with no `node_modules`, an empty `BUN_INSTALL_CACHE_DIR` and an unreachable
  registry (`BUN_CONFIG_REGISTRY`, documented in https://bun.com/docs/pm/npmrc), `bun <file>`
  tries to install (hangs until killed) while `bun test <file>` fails at once with "Cannot find
  package". So the install fixture shows no difference for `bun test`, and the red FR-020 asks for
  cannot be recorded there.
- **Options**:
  1. *(recommended)* Keep the install protection for `bun_test`, record the observation as its red
     substitute (no difference without the protection, quoted output), and count US3-3 as 2 of 3
     cases with a red for `bun_test` in SC-006.
  2. Drop the install case for `bun_test` from SC-006.

### Decisions (2026-10-03, user)

All five recommendations accepted.

- **G1**: reported upstream as hermeticbuild/hermetic-launcher#80 (verified at `v0.0.16`,
  `runfiles-stub/src/windows.rs` lines 439–509). The Windows quoted-argument test waits for a
  release with the fix; the limitation is documented until then.
- **G2**: snapshot tests unsupported in this feature; reported upstream as oven-sh/bun#44531
  (reproduced with Bun 1.4.2 on Linux).
- **G3**: `--config=` for `bun test` accepted as an exception to FR-017, pinned by a test.
- **G4**: added to the FR-018a limitation; requested upstream as
  hermeticbuild/hermetic-launcher#81 (reproduced: `--config <path>` and `-c <path>` do not apply
  the file, `--config=<path>` does). Narrowed to Windows by spec Revision 13.
- **G5**: the observation replaces the red for `bun_test` and package install (SC-006).

### Gaps from spec Revision 5 (G6–G9, decided 2026-10-03)

Spec Revision 5 made FR-003 a copy into the output tree and listed what the plan must address.
Checked against Bazel 9.2.0 sources (`site/en/...` and `tools/test/...` at tag `9.2.0`) and Bun
1.4.2 (`docs/` at `bun-v1.4.2`, and the binary from `@bun_linux-x64`, Linux, 2026-10-03). No task
for G6–G9 may exist before the user decides.

Sources added:

| Name | Source |
|---|---|
| BZ-outdirs | https://bazel.build/remote/output-directories ("Layout diagram") |
| BZ-covcmd | https://bazel.build/configure/coverage ("Running coverage") |
| BZ-merger | `tools/test/CoverageOutputGenerator/.../Main.java` (`getCoverageFilesInDir`, `getTracefiles`), `Constants.java` (`TRACEFILE_EXTENSION = ".dat"`), `Coverage.java` (`getOnlyTheseSources`), `tools/test/collect_coverage.sh` lines 248–254, at Bazel `9.2.0` |
| BZ-ctxapi | `StarlarkRuleContextApi.java` `expand_location` doc at Bazel `9.2.0` (the text of BZ-ctx) |
| BL-copy | bazel-contrib/bazel-lib 3.7.2 `lib/private/copy_file.bzl` (`copy_file_action`: `ctx.actions.run` of the coreutils toolchain's `cp`, "no shell is required"), `lib/copy_to_bin.bzl` (`copy_files_to_bin_actions`), `MODULE.bazel` (registers `@coreutils_toolchains//:all` itself) |

#### G6. Copies in the shared output tree still expose undeclared files (FR-003, US3-4)

- **Requirement**: FR-003 "an undeclared file is not there to import"; US3-4 an undeclared sibling
  fails to import "on every OS and with or without a runfiles tree".
- **Source**: BZ-outdirs: outputs of every target of package `foo/bar` go to
  `bazel-out/<config>/bin/foo/bar/`, and `execroot/_main` is the "root of symlink forest" where
  "packages … appear as if under a regular workspace".
- **Observed**: Bun resolves a relative import from the real path of the importing file: an entry
  point reached through a symlink imported `./b.ts` from the symlink target's directory although
  only the entry point was linked. So with copies in the shared `bin/<package>/` directory (the
  `copy_to_bin` layout), a sibling that another target of the package copied there is importable.
  In a directory tree laid out like the execroot, a copy under `bazel-out/<config>/bin/pkg/` also
  saw `tsconfig.json` `paths` and `node_modules` at the root (the symlink forest; this
  repository's execroot holds such links to every top-level entry).
- **Options**:
  1. *(recommended)* Each `bun_binary`/`bun_test` copies every transitive source, test file,
     preload and data file into its own tree, `bin/<package>/<name>.bun/<short_path>`
     (`ctx.actions.declare_file` is documented relative to the package; `File.short_path` keeps the
     relative layout). Only declared files exist in that tree, whether or not Bun resolves real
     paths. Cost: one copy per file per target. Root `tsconfig.json` and `node_modules` stay
     visible; they are already outside this feature (spec "Only the named isolation items") and
     are documented as a limitation.
  2. Shared `copy_to_bin` layout (bazel-lib); amend US3-4 to "not declared by any target
     of the package" and document the rest.
  3. Block FR-003 until Bun honors `--preserve-symlinks` (oven-sh/bun#43689).

#### G7. Coverage file name and `SF:` form are not documented (FR-016a)

- **Status**: **re-based by spec Revision 10 (2026-10-08)** on a ruleset pattern: the file is
  named `<prefix>_<unique>.dat` as bazel-contrib/rules_python writes `pylcov_{}.dat`, and `SF:`
  lines are rewritten from LCOV, a documented format, resolving each path against the copy-tree
  root, so no form of Bun's `SF:` is relied on (Part 1 "Plan for spec Revision 10"). **Matching
  restated by spec Revision 12 (G15)**: each `SF:` value is matched against the declared copies
  under two readings, and a value that matches none or several fails the test with an English
  error instead of being dropped (Part 1 "Plan for spec Revision 12"). The text below is kept as
  the record of the 2026-10-03 decision.

- **Requirement**: FR-016a; Revision 5: each undocumented step is a gap under FR-004.
- **Source**: BZ-coverage documents only "one or more LCOV files with unique names into the
  directory specified by the `COVERAGE_DIR` environment variable". BZ-merger: the merger reads only
  files ending in `.dat` (or gcov/profdata) under `COVERAGE_DIR`, and keeps only records whose
  `SF:` equals a line of the instrumented-file manifest (`--source_file_manifest=$COVERAGE_MANIFEST`,
  exact match). BZ-encyclopedia does not list `COVERAGE_MANIFEST`. Bun documents no `SF:` form;
  `--coverage-dir` writes `lcov.info` (R8), and `SF:` was relative to the working directory, so
  with FR-003 it names the copy, not the source.
- **Options**:
  1. *(recommended)* Exception to FR-004 like G3, pinned by the CI coverage check: the launcher
     points `--coverage-dir` at a directory under `TEST_TMPDIR`, then writes each report to
     `$COVERAGE_DIR/<unique>.dat` with every `SF:` rewritten from the copy to the source's
     `File.path` (the form of the manifest lines is verified only by that CI check).
  2. Drop FR-016a from this feature and document coverage as unsupported.
  3. Block FR-016a.
- **Not a gap**: reading the merged report. BZ-covcmd documents
  `bazel coverage --combined_report=lcov` and the report at
  `$(bazel info output_path)/_coverage/_coverage_report.dat`; BZ-outdirs documents the workspace
  symlink `bazel-out` → output path. A CI step `bazel run` of a checking `bun_binary` with
  `-- bazel-out/_coverage/_coverage_report.dat`, resolved against `BUILD_WORKING_DIRECTORY`, reads
  it as a command-line path, never from the cache.

#### G8. A shard whose files match no `--test_filter` fails (FR-016)

- **Status**: **withdrawn by spec Revision 10 (2026-10-08)**. No `--pass-with-no-tests`; filtering
  a sharded `bun_test` fails with an English error, and a filter that selects nothing fails as Bun
  reports (Part 1 "Plan for spec Revision 10"). The text below is kept as the record of the
  2026-10-03 decision.

- **Requirement**: Revision 5: define and test the result Bazel needs when `--test_filter` meets
  `shard_count > 1`; every shard of a passing filtered run must pass.
- **Observed**: two files, one test each, `-t alpha --shard=i/2`: shard 1 exits 0, shard 2 (no
  matching test) exits 1. `--pass-with-no-tests` ("Exit with code 0 when no tests are found")
  makes shard 2 and an unsharded no-match exit 0. It is listed by `bun test --help` of 1.4.2 but
  on no bun.com page (`docs/snippets/cli/test.mdx` at `bun-v1.4.2` lacks it), so FR-017 does not
  count it as supported.
- **Options**:
  1. *(recommended)* Exception to FR-017 like G3, pinned by a test: pass `--pass-with-no-tests`
     whenever `TESTBRIDGE_TEST_ONLY` is set, so a filter that selects nothing passes, sharded or
     not (changes the contract line "a filter that matches no test fails").
  2. Pass it only when both filter and sharding are set (an unsharded no-match still fails).
  3. No undocumented option: the launcher fails with an English error when both are set.
  4. Block the combination until Bun documents the option.

#### G9. Test file outside the working directory's drive (FR-013, R8)

- **Status**: the limitation is removed by spec Revision 10: test files are passed `./`-relative
  to the copy-tree root, which is the second process's working directory, so every test file is
  addressable. The text below is kept as the record of the 2026-10-03 decision.

- **Requirement**: Revision 5: no limitation the user has not approved.
- **Source**: BUN-discovery: a test file path must start with `./` or `/`; a Windows drive path
  (`C:\…`) is not documented. Under `bazel test` the working directory (runfiles) and the copies are
  both under the output base (BZ-outdirs), so a `./`-relative path always exists there. It does not
  when the launcher is started from another drive (running the `.exe` by hand, or `--test_tmpdir` on
  another drive for this repository's spawn tests).
- **Options**:
  1. *(recommended)* Fail with an English error naming the file and document the limitation.
  2. Change the second process's working directory to the copy tree for `bun_test` (contradicts
     spec "The rules do not change it").

#### Decisions on G6–G9 (2026-10-03, user)

All four recommendations (option 1 each) accepted; see spec Revision 6.

#### Other Revision 5 items (decisions, no gap)

- **Copy action**: `copy_files_to_bin_actions`/`copy_file_action` of bazel-lib (BL-copy) — a
  bazel-contrib ruleset, shell-free, with its own registered coreutils toolchain. Makes `bazel_lib`
  a non-dev dependency; its lowest working version is still to be determined (constitution IV).
  With G6 option 1 the copies go to the per-target tree via `copy_file_action`.
- **Runfiles**: `entry_point` and `preload` files (their copies) are added to runfiles, not only
  `srcs`.
- **`$(rlocationpath …)` in `env`**: BZ-ctxapi documents only `$(location …)` and
  `$(locations …)` for `ctx.expand_location`, so the contract offers only those in `env`;
  `$(rlocationpath …)` stays in `args`, which Bazel expands itself (BZ-common). Superseded by spec
  Revision 15 (T121): `env` values are taken literally (R9).
- **Tests the plan lacked**: an analysistest through a test-only rule with a `cfg = "exec"`
  attribute shows a `bun_binary` built for the execution configuration carries that platform's
  Bun; a test-only platform with a registered `bun_target_toolchain` but no hermetic-launcher
  template toolchain fails analysis (`expect_failure`); the inherited-and-set case of FR-014 is a
  `manual` `bun_test` with `env_inherit`, run by a CI step whose `env:` sets the variable (Bazel
  reads `inherited_environment` from the client environment, BZ-runenv).
- **R6 superseded**: R6 ("sources read from the source tree") is replaced by FR-003 and G6.

### Gaps from re-planning for spec Revisions 5 and 6 (G10–G11 decided 2026-10-04, G12 2026-10-05)

Found while re-planning the decided design (per-target copy tree, G6 option 1). Observed with Bazel
9.2.0 (Bazelisk, scratch modules under `/tmp`) and the Bun 1.4.2 binary from `@bun_linux-x64`,
Linux (WSL), 2026-10-03; macOS and Windows not run. Reviewed adversarially by a subagent; its
corrections were re-checked against the sources before being applied. G10 and G11 were decided by
the user on 2026-10-04 (spec Revision 7; see "Decisions on G10–G11" below). G12 was decided on
2026-10-05 (spec Revision 8; see "Plan review for spec Revision 8" below).

Sources added:

| Name | Source |
|---|---|
| BZ-sandbox | https://bazel.build/docs/sandboxing ("Sandboxing strategies"; `site/en/docs/sandboxing.md` at `9.2.0`) |
| BZ-hash | Starlark `hash` (`MethodLibrary.java` at `9.2.0`): "computed deterministically using the same algorithm as Java's `String.hashCode()` … Hashing of values besides strings is not currently supported" |
| BUN-plugins | https://bun.com/docs/runtime/plugins (`onLoad`, `onResolve`; registered through bunfig `preload`, BUN-bunfig) |
| BL-copydir | bazel-contrib/bazel-lib `lib/copy_directory.bzl` (exports `copy_directory`, `copy_directory_bin_action` only), `lib/private/copy_directory.bzl` (`copy_directory_bin_action(ctx, src, dst, copy_directory_bin, …)`), `lib/private/copy_directory_toolchain.bzl` (`ToolchainInfo(copy_directory_info = CopyToDirectoryInfo(bin), default = DefaultInfo)`; `_resolved_toolchain_impl` also returns `toolchain_info.template_variables`, a field that `ToolchainInfo` lacks), at `v3.0.0` and `v3.7.2` |
| BL-history | bazel-contrib/bazel-lib commits `01ca8f9432` (#622, 2023-11-14, `copy_file_action` runs coreutils `cp`), `b245c2f411` (#1123, module renamed `bazel_lib`; first tag `v3.0.0-beta.0`; `v2.22.5` is still `aspect_bazel_lib`), `cac2d78559` (`COPY_FILE_TOOLCHAINS` holds a `Label`; first tag `v3.2.2`), `2289bdd56e` (#1261, the action's `toolchain =` also a `Label`, because strings "are resolved in the consuming repository's mapping"; first tag `v3.5.0`) |
| RJS-data | aspect-build/rules_js `0a0b62de7d9b1b35077328ef1377a7439d50f20f` `js/private/js_helpers.bzl` `gather_runfiles` (copies only `data` files that are source files, through `copy_js_file_to_bin_action`; adds data targets' `DefaultInfo.files` and merges `default_runfiles` of `data` and `deps` uncopied) |

#### G10. A copy removed from a target stays importable (FR-003, US3-4)

- **Requirement**: FR-003 "an undeclared file is not there to import"; Revision 5: no limitation
  the user has not approved.
- **Source**: bazel.build documents no removal of outputs that a target no longer declares
  (BZ-outdirs describes the layout only). BZ-sandbox: `processwrapper-sandbox` links inputs as
  "symlinks that point to the original source files", and `linux-sandbox` "makes the entire
  filesystem read-only except for the sandbox directory" (readable); `darwin-sandbox` is "roughly
  the same". No sandbox strategy is documented to hide the rest of `bazel-out`.
- **Observed**: a rule declared `t.bun/a.ts` and `t.bun/b.ts` with `ctx.actions.declare_file`;
  after `b.ts` was removed from the rule and the target rebuilt, `bazel-bin/pkg/t.bun/b.ts` was
  still there. Bun run on a symlink to `a.ts` (as through a runfiles tree) imported `./b.ts` from
  the symlink target's directory and printed the stale file's export. So, in the same output base,
  a file removed from a target's inputs stays importable from its copy tree until `bazel clean`.
  A fresh output base (CI from a clean cache) has no such file. The whole chain under `bazel test`
  was not run, because the rules do not exist yet. On Windows the launcher passes the `bazel-out`
  path itself.
- **Options**:
  1. *(recommended)* Document it as a limitation next to the G6 one: after a file is removed from
     a target, an earlier copy may still be importable in local incremental builds until
     `bazel clean`; a clean output base is not affected. rules_js copies into the shared `bin`
     tree (RJS-data), where a stale copy would stay the same way (not run).
  2. Name the per-target tree after its input set, `<name>.bun/<h>/…`, where `<h>` is
     BZ-hash of the sorted destination paths joined into one string: a changed input set gets a
     new directory, so a removed file is never a sibling. Residual: 32-bit collisions, a full extra
     copy per input-set change left in `bazel-out`, and up to 12 more characters in every path.
  3. One TreeArtifact per target (`ctx.actions.declare_directory`), emptied and filled by one
     action. With bazel-lib's `copy_to_directory_bin_action` the tool is reachable only through a
     private provider (as in G12). An action of this ruleset that runs the execution platform's
     Bun (`BUN_TOOLCHAIN_TYPE`) with `node:fs` is shell-free and documented, but replaces the
     decided bazel-lib copy action, and how a manifest-only run resolves files inside a tree
     artifact is not researched.
  4. A Bun runtime plugin (BUN-plugins), preloaded through the rule's configuration file, whose
     `onLoad` rejects every path not on the target's list of copies. Observed: it rejected the
     stale sibling. **Defect, observed**: a CommonJS module (`require`, no ESM syntax) returned
     through `onLoad` `contents` is silently not executed and the run exits 0. Not usable as is.
     *Re-checked 2026-10-04: "not usable" is not reproduced; see "Decisions on G10–G11".*

#### G11. More of the workspace than G6 recorded is reachable from the copies (FR-003, G6)

- **Requirement**: Revision 5: no limitation the user has not approved. G6 approved
  "`node_modules` and `tsconfig.json` in ancestor directories of the output tree".
- **Source**: BUN-resolution: Bun "implements the Node.js module resolution algorithm" and
  supports "Node.js-style subpath imports in `package.json`" (`"imports"`, specifiers starting
  with `#`); it names no option that confines resolution (`NODE_PATH` and `--conditions` only add
  to it). BZ-outdirs: the execroot is the "root of symlink forest", and `bazel-out` is under it.
- **Observed**: a copy at `<dir>/bazel-out/bin/pkg/t.bun/_main/pkg/a.ts` imported `#u`, mapped by
  `"imports"` in `<dir>/package.json` to an undeclared `<dir>/undeclared.ts`, and
  `../../../../../../climb.ts`, an undeclared file reached by climbing out of the copy tree; both
  resolved. In the execroot, `<dir>` is the symlink forest of the main repository's top-level
  entries (G6 observation). With a `package.json` containing `{}` at `t.bun/`, `#u` failed
  ("Cannot find package '#u'"); the climb is unaffected.
- **Options**:
  1. *(recommended)* Widen the documented G6 limitation to: files in ancestor directories of the
     output tree are visible to Bun's lookups, including `package.json` (`"imports"`), and a
     relative import that climbs out of the per-target tree reaches the workspace; US3-4 covers
     only files next to the importing file.
  2. Option 1, plus the rule writes `{}` as `package.json` at the root of each per-target tree,
     which stops `"imports"` lookups above it (Node's package scope, which BUN-resolution links
     to). It changes the package scope of the copies (for example `"type"`), and does not stop
     `node_modules`, `tsconfig.json` or climbs.
  3. The plugin of G10 option 4 (same defect; re-checked 2026-10-04, see below).
  4. Block FR-003 until Bun offers a documented way to confine resolution.

#### Decisions on G10–G11 (2026-10-04, user, after a debate with Codex)

Spec Revision 7: keep the per-target copy tree (G6) and add a load guard. The launcher preloads a
Bun plugin (BUN-plugins) whose `onLoad` filter matches only absolute paths outside the target's
declared file set and throws an English error naming the file; declared files never reach the
callback. This closes G10 (a stale copy is not in the declared set) and G11 (files reached by
`../` climbs, `package.json` `"imports"` or `node_modules` are not in it). Design: Part 2 R13.

Evidence, Bun 1.4.2, Linux (WSL), 2026-10-04 (Codex experiments, re-run by the planner in a scratch
directory under `/tmp`; macOS and Windows not run):

- **The earlier defect claim, as a reason the plugin route is unusable, is not reproduced.**
  `onResolve` fires for relative imports in ESM and CommonJS: a trace plugin logged `./sib.ts`
  imported from a `.ts` entry and `./dep.cjs` required from a `.cjs` entry. A filtered `onLoad`
  throw works for CommonJS: with both files declared, `cjs.cjs` and its `require("./dep.cjs")` ran
  and exited 0; with only `cjs.cjs` declared, the run exited 1 with
  `Undeclared module: <real path of dep.cjs>`. The same held for an ESM import.
- What the earlier option observed is narrower and was reproduced: an `onLoad` that *returns* a
  CommonJS file's source as `contents` with loader `js` runs nothing and exits 0 (also when the
  `.cjs` file is imported from an ESM entry); loader `cjs` is rejected ("Expected loader to be one
  of …"). An `onLoad` returning `undefined`, `null` or `{}` throws (Codex). The guard never
  returns from `onLoad`, so neither affects it.
- `onResolve` is not usable as the guard: Bun 1.4.2 did not call it for bare specifiers, tsconfig
  `paths`, static imports under `bun test` or `import.meta.resolve`, and resolving specifiers in
  the plugin diverges from Bun (`./sibling.js` resolves to `sibling.ts`) (Codex).
- `bun test` with the guard as the first `--preload`: a declared test file, its declared import, a
  declared JSON import and a declared second preload ran (`1 pass`); an undeclared JSON import
  failed naming the file; an undeclared import of the second preload failed naming the file
  ("Unhandled error between tests"). With `--coverage`, Bun's LCOV also held a record for the
  guard file itself (`SF:` relative to the working directory).
- Not closed by the guard, and documented as limitations (spec Revision 7): modules loaded before
  the guard registers (a `bunfig.toml` preload of the first process, G4); code the program starts
  itself (Workers, child processes, `Bun.build`; Codex observed each bypass it); ancestor
  `tsconfig.json` and `package.json` still influence how a declared import resolves; plain file
  reads (`Bun.file`, `fs`). Not run: TSX (needs a JSX runtime package, out of scope, FR-008),
  `.node`, `.wasm`; filter performance with many paths; real-path spelling on macOS and Windows.
- What a throwing `onLoad` does is not documented on BUN-plugins, and the order of several
  `--preload` options is not documented on BUN-run; both are pinned by tests on every OS
  (Revision 7). The full fix is Bun honoring `--preserve-symlinks` (oven-sh/bun PR #36757).

#### G12. bazel-lib documents no way to copy a directory in `data` (FR-003, FR-006, US1-3)

- **Status**: decided 2026-10-05, option 1 (spec Revision 8).
- **Requirement**: FR-003 copies every data file with bazel-lib's copy action (decided); FR-006
  accepts data "checked in or generated", and a rule can produce a directory (TreeArtifact).
- **Source**: BL-copy `copy_file_action` fails on a TreeArtifact unless `dir_path` names one file
  inside it, which analysis cannot know. BL-copydir `copy_directory_bin_action` is public, but the
  caller must supply `copy_directory_bin`; its docstring says the tool is "typically the
  `@bazel_lib//tools/copy_directory` `go_binary` either built from source or provided by a
  toolchain". The toolchain exposes it only through undocumented `ToolchainInfo` fields
  (`copy_directory_info.bin`, `default`); bazel-lib exports no `COPY_DIRECTORY_TOOLCHAINS` the way
  it exports `COPY_FILE_TOOLCHAINS`; the generated `@copy_directory_toolchains//:resolved_toolchain`
  returns `toolchain_info.template_variables`, which its `ToolchainInfo` does not set (read from
  source; the reviewer saw its analysis fail at `3.7.2`). Building the tool from source needs
  rules_go, which bazel-lib's BCR `MODULE.bazel` declares only as a dev dependency (checked for
  `3.0.0` and `3.7.2`). rules_js copies only data files that are source files, so it never copies
  a directory (RJS-data).
- **Options**:
  1. *(recommended)* A directory among a target's data (direct or through `deps`) fails analysis
     with an English message naming `data` and the directory; directories are documented as not
     supported in this feature; ask bazel-lib upstream to export the copy-directory toolchain type
     and a documented way to reach its tool.
  2. Copy directories with an action of this ruleset that runs the execution platform's Bun with
     `node:fs` (shell-free, documented), next to bazel-lib's copy action for files.
  3. Read `ToolchainInfo.copy_directory_info.bin` and call `copy_directory_bin_action`;
     constitution V forbids relying on an undocumented field.
  4. Leave directories uncopied in runfiles, reachable only through the runfiles variables, and
     document that they are not next to the copies.

#### Findings for the re-plan (no gap)

- **Per-target tree path**: G6 option 1 writes `<name>.bun/<short_path>`. For a file of another
  repository `File.short_path` starts with `../<repo>/`; observed: `declare_file("u.bun/" +
  short_path)` for `@repo//:x.ts` produced `bazel-bin/pkg/repo+/x.ts`, outside the per-target
  tree. The tree path is therefore `<name>.bun/<rlocation path>` (`_main/…` for the main
  repository, `<canonical name>/…` otherwise), as the G11 observation already assumes; it keeps
  the relative layout inside each repository.
- **Lowest `bazel_lib`** (constitution IV): `copy_file_action` has run coreutils `cp` since #622,
  and the module is named `bazel_lib` from `3.0.0-beta.0` (BL-history), so `3.0.0` is the lowest
  stable candidate. Before `3.5.0` the action's toolchain label is a string resolved in the
  consuming repository's mapping (#1261), which may fail for `e2e/smoke`, whose module does not
  depend on `bazel_lib`. The lowest version is fixed by running the root and `e2e/smoke` test sets
  from `3.0.0` upward, recording each failure. Stable `bazel_lib` 3.x releases on BCR declare
  `bazel_features` 1.9.0, `bazel_skylib` 1.8.1, `platforms` 0.0.10 and `rules_shell` 0.4.1 and
  register their own coreutils toolchains (linux, darwin, windows; amd64 and arm64). Observed with
  `bazel mod graph` on a consumer of `package_metadata` 0.0.6, `platforms` 1.0.0 and
  `hermetic_launcher` 0.0.16: adding `bazel_lib` 3.0.0 adds `bazel_lib` 3.0.0, `bazel_features`
  1.42.1 and `rules_shell` 0.6.1 to what the consumer resolves.
- **Data runfiles**: the files a `data` target provides (`DefaultInfo.files`), source or
  generated, are copied; copying generated files is this design's choice (rules_js copies source
  files only, RJS-data). Each data target's `default_runfiles` is merged uncopied, as rules_js
  does, because it is laid out for that target (for example another executable's runfiles). The
  originals stay in runfiles too, so `$(rlocationpath …)` keeps locating data (FR-012).

### Plan review for spec Revision 8 (G12–G13 decided 2026-10-05)

Spec Revision 8 records two technical decisions by the implementer and the fixes the plan carries.
Re-checked by the planner with the Bun 1.4.2 binary from `@bun_linux-x64` and Bazel 9.2.0 in
scratch directories under `/tmp`, Linux (WSL), 2026-10-05; macOS and Windows not run.

Sources added:

| Name | Source |
|---|---|
| BUN-meta | https://bun.com/docs/runtime/module-resolution (`import.meta` table: `import.meta.dir`, "Absolute path to the directory containing the current file") |
| BUN-jsx | https://bun.com/docs/runtime/jsx (`jsxImportSource`: "Default value is `"react"`") |
| BUN-cache | https://bun.com/docs/runtime/environment-variables ("Runtime transpiler caching": "For files larger than 4 KB … Cached files use the `.pile` extension"; `BUN_RUNTIME_TRANSPILER_CACHE_PATH` "set to an empty string or the string "0", caching is disabled") |
| WIN-create | https://learn.microsoft.com/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw (`lpCommandLine`: "The maximum length of this string is 32,767 characters, including the Unicode terminating null character") |
| WIN-argv | https://learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-commandlinetoargvw and https://learn.microsoft.com/cpp/c-language/parsing-c-command-line-arguments (quoting rules) |

#### G12. Directories in `data` — decided

Option 1: a directory (TreeArtifact) among a target's data, direct or through `deps`, fails
analysis with an English message naming `data` and the directory; directories are documented as
unsupported; an upstream request goes to bazel-lib (export the copy-directory toolchain type and a
documented way to reach its tool). Design: R6.

#### G13. Bun drops a leading `--` from the program's arguments (FR-013, US1-4, US1-6) — withdrawn

- **Status**: **withdrawn by spec Revision 10 (2026-10-08)**. Nothing is inserted; a program
  argument list whose first argument is `--` fails with an English error (Part 1 "Plan for spec
  Revision 10"). The observations below stay valid; the decision is kept as the record of
  2026-10-05.

- **Requirement**: US1-4 and FR-013: the launch mechanism changes no argument boundary or value;
  US1-6: `process.argv.slice(2)` equals the program's own arguments.
- **Source**: BUN-run documents no handling of `--` after the entry point.
- **Observed** (`bun a.ts <args>`, printing `process.argv.slice(2)`): `-- x` → `["x"]`; `-- -- x`
  → `["--","x"]`; `-- --` → `["--"]`; `--` → `[]`; `-- --config=z` → `["--config=z"]`;
  `x -- y` → `["x","--","y"]`; `--config=z` without `--` → `["--config=z"]`. Bun removes
  exactly one `--` directly after the entry point and keeps every later one, so a program whose
  first argument is `--` loses it.
- **Observed for the test order**: `Bun.spawn` without a `stdin` option did not hand the
  parent's standard input to the child (it read `""`), so the FR-015 standard-input test is red
  against a launcher that does not set `stdin: "inherit"`.
- **Decision (2026-10-05, withdrawn)**: the launcher always inserts `--` directly after the entry point; then every
  program argument arrives unchanged (the `-- -- x` and `-- --config=z` rows). An exception to
  FR-017 like G3, pinned by a test: a program started with `--` as its first argument sees
  exactly its arguments; the same test keeps `--config=z` as a first argument, which already
  passes without the insertion, as a guard that an option after the entry point stays the
  program's. Design: R2.

#### Revision 8 fixes (decisions, no gap)

- **Guard filter as a prefix trie** (R13): one alternation over every escaped declared path fails
  to compile with Bun 1.4.2 ("Invalid regular expression: regular expression too large") at
  8,000 paths of about 160 characters, the length of real paths under a Bazel output base
  (observed: 1,000 compile, 8,000 do not). The same set built as a character trie, emitted as
  nested non-capturing groups, compiled and matched correctly at 8,000, 20,000, 50,000 and
  100,000 paths (pattern 0.09–1 M characters, compile 13–213 ms, one match under 0.001 ms), and
  `Bun.plugin` accepted it as an `onLoad` filter at 20,002 paths, rejecting an undeclared import
  and passing a declared one. Pinned by a test at 10,000 declared files (R13).
- **Data located through `import.meta.dir`** (R5, FR-012): BUN-meta documents `import.meta.dir`.
  Bun runs the copies by real path (R6), and the data copies sit in the same tree with the layout
  of their rlocation paths, so a path relative to `import.meta.dir` reaches a declared data file
  with a runfiles tree and with a manifest only. It is the FR-012 mechanism for `bun_test`, whose
  arguments must be options (FR-013) and so cannot carry `$(rlocationpath …)`.
- **`bun test --isolate` allowed** (R8): `bun test --help` 1.4.2 lists it ("Run each test file in a
  fresh global object"). Observed: with two test files, the guard preload ran once per file, found
  `RULES_BUN_LAUNCH_CONFIG` set each time although the previous run had deleted it, and rejected an
  undeclared import in the second file. It is not among the rejected options. `--parallel`, which
  implies it, stays rejected (R8). *Revision 9: BUN-parallel documents `--isolate` and the preload
  re-run, the guard no longer deletes the variable, and `bun_test` arguments are an allowlist
  ("Plan review for spec Revision 9").*
- **Caught guard error** (R13, R14): `try { await import("./undeclared.ts") } catch {}` caught the
  guard's error and the run exited 0 (observed). Documented limitation: the guard fails a run only
  when the consumer's code does not catch the error.
- **JSX** (R13, R14): BUN-jsx: the JSX transform imports from `react` by default; npm packages
  are a later feature (FR-008). Documented limitation: JSX needs the `react` package, which npm
  support provides; until then JSX is not supported, and TSX without JSX is reported unverified.
- **Command-line length** (R2): WIN-create limits a command line to 32,767 characters. Before
  starting the second process the launcher computes the length its command line has on Windows
  (each argument quoted by the WIN-argv rules, joined by spaces, plus the terminating null; string
  length in UTF-16 code units) and, above 32,767, exits 1 with an English error naming the length
  and the limit. *Revision 9: superseded; the launcher measures the command line as the running OS
  builds it (R2), and the fixture exceeds 32,767 characters on every OS.*
- **`platforms` 1.1.0** (constitution IV): `hermetic_launcher` 0.0.16 declares `platforms` 1.1.0,
  so the root `bazel_dep(name = "platforms")` is raised from 1.0.0 to 1.1.0, the version the
  ruleset then needs.
- **Missing fixtures** (data-model "Test fixtures"): standard input (FR-015), `BUN_OPTIONS`
  rejection (FR-018a), `BUN_RUNTIME_TRANSPILER_CACHE_PATH=0` (FR-018) and runfiles paths with
  spaces (spec Edge Cases). Observed for the cache fixture: a 16 KB source run with
  `BUN_RUNTIME_TRANSPILER_CACHE_PATH=<empty dir>` left one `.pile` file there, a one-line source
  none, and the 16 KB source with the variable `0` none; with `BUN_INSPECT_CONNECT_TO` set (as in
  some debugger sessions) Bun wrote no entry, so the fixture removes that variable from the
  child's environment. Bazel 9.2.0 built a `filegroup` of `with space.txt` and a rule output named
  `out file.txt` (observed), so the space fixture uses such files.
- **Genuine red ordering** (FR-020): each isolation option, the copy tree, the guard and its
  trie, `--` insertion, `BUN_OPTIONS` rejection and the length check are added only after their
  test has run red against the launcher without them (plan "Implementation Order"); a mutation is
  recorded only for behavior that existed before its test.

### Plan review for spec Revision 9 (2026-10-06, decisions, no gap)

Spec Revision 9 records six technical decisions by the implementer and adds FR-028. Re-checked by
the planner with the Bun 1.4.2 binary from `@bun_linux-x64` in scratch directories under `/tmp`,
Linux (WSL), 2026-10-06; macOS and Windows not run. Re-planning found one more gap, G14 (item 4 below, decided); otherwise each decision
has a documented way or is an observation pinned by a test and a canary.

Sources added:

| Name | Source |
|---|---|
| BZ-startup | https://bazel.build/reference/command-line-reference#startup_options-flag--output_user_root (`--output_user_root`) |
| BZ-covsrc | `tools/test/CoverageOutputGenerator/java/com/google/devtools/coverageoutputgenerator/Main.java` and `Constants.java` at Bazel `9.2.0` (the files of BZ-merger, named for canary messages) |

BUN-parallel (https://bun.com/docs/test/parallel, `docs/test/parallel.mdx` at `bun-v1.4.2`) now
also sources `--isolate`: "Runs each test file in a fresh JavaScript global object inside the same
process. Between files Bun: … re-runs `--preload` scripts in the new global." So the re-run of
the guard per file under `--isolate` is documented, not only listed by `bun test --help`.

#### 1. Declared-file limit of the guard filter (R13)

- **Observed** (2026-10-06): the limit is the length of the pattern. `new RegExp("a".repeat(n))`
  compiles for `n` = 1,048,576 and fails for 1,048,577 with `SyntaxError: Invalid regular
  expression: regular expression too large`; a pattern of `(?:ab)` groups fails at the same
  length, and `Bun.plugin` accepted a 1,048,576-character `onLoad` filter. The length is that of
  the pattern string (`RegExp.source` is longer, because it escapes `/`). The prefix trie of declared paths (a 160-character shared prefix plus a unique random suffix per
  file) compiled at 9,000 × 100, 16,000 × 50, 20,000 × 40 and 40,000 × 20 (pattern 0.88–0.99 M
  characters; `Bun.plugin` accepted each as an `onLoad` filter) and failed at 10,000 × 100,
  22,000 × 50 and 80,000 × 10 (1.05–1.21 M characters). The reviewer's figure (about 20,000 paths
  with 100-character suffixes) depends on how much the suffixes share; the pattern length is what
  decides. A single alternation of 10,000 such paths with short names (`f00001.txt`) is 2.2 M
  characters and fails, so the 10,000-file test stays red against it.
- **Decision**: the launcher builds the guard's pattern from the declared real paths before it
  starts the second process and, when the pattern is longer than 1,048,576 characters (the limit
  measured on Bun 1.4.2, a constant in `launcher.js`), exits 1 with an English error naming the
  target, the declared-file count and the limit. Documented as a limit (R14). Tested by a `manual`
  target whose 22,000 data files have 50-character random names (pattern about 1.2 M characters on
  every OS, because the shared prefix enters the trie once). A canary pins the constant: a pattern
  of 1,048,576 characters compiles and one of 1,048,577 does not (FR-028).

#### 2. Allowlist for `bun_test` arguments (R8)

- **Requirement**: Revision 9: allow only options that bun.com documents for `bun test` and that
  undo nothing the rules guarantee (FR-003 and the load guard of Revision 7, FR-007, FR-016,
  FR-016a, FR-016b, FR-018, FR-019); reject anything else with an English error naming it.
  `--define` and `--loader` are documented but excluded: with Bun 1.4.2, `--loader=.js:text`
  and `--define=Bun.plugin:console.log` each disabled a preloaded guard, and a `--define` of
  `process.env.<name>` can redirect the guard's configuration (verified 2026-10-06).
- **Sources**: BUN-testcli (`docs/snippets/cli/test.mdx` at `bun-v1.4.2`), BUN-parallel,
  BUN-testruntime ("CLI Flags Integration", "Installation-related Flags").
- **Observed** (2026-10-06): each allowed form below was accepted by `bun test --config=/dev/null
  <form> ./a.test.ts`; `--timeout=100` took effect.
- **Decision**: R8 "Arguments" lists the allowlist and the reason each documented option is not on
  it. No short option is on it (the documented short aliases `-t`, `-u` are owned or undo FR-016b),
  so attached and combined short options (`-talpha`, `-uts`, `-r./x.ts`) fail with the rest.

#### 3. Guard configuration from a file, fail closed (R13)

- **Decision**: the launcher passes the real path of `launch.json` to the second process in
  `RULES_BUN_LAUNCH_CONFIG`; the guard reads that file and never deletes the variable or the file.
  When the variable is unset, the file cannot be read or parsed, or a declared path cannot be
  resolved, the guard registers an `onLoad` whose filter matches every path and whose callback
  throws an English error naming the reason, so every module load is rejected. The guard no longer
  relies on Bun re-exposing a deleted variable under `--isolate` (Revision 8 observation);
  BUN-parallel documents the preload re-run.

#### 4. Canaries for every undocumented reliance (FR-028)

- **Decision**: the canaries are listed in data-model "Upstream canaries", one per reliance, each
  with what it pins, the workaround its message names, the upstream link and its red (a mutation of
  the pinned expectation, recorded and reverted, FR-020). Canaries run the toolchain's Bun directly
  (`process.execPath`) on fixtures under `TEST_TMPDIR` unless the reliance is Bazel's or the stub's.
  The G7 merger canary is part of the CI coverage check (Linux): the coverage test also writes an
  LCOV record with a marker line to `$COVERAGE_DIR/canary.info`, and the check asserts that the
  merged report holds the source's record under its workspace path and not the marker. For G4 the
  canary pins Bun's side (`--config <path>` is not applied); hermetic-launcher's side has no API a
  test could call, so FR-028 cannot be met for it by a test (decided 2026-10-06 by the
  implementer, G14): `MODULE.bazel` carries the comment "On any hermetic_launcher bump, check
  hermetic-launcher#81 (G4) and #80 (G1)" next to the `bazel_dep`, and the FR-018a limitation in the
  contract names #81, so the person raising the version sees it. *Revision 10 narrows the canary
  list to upstream defects and the regular-expression limit and moves G14 into the FR-028 text
  (Part 1 "Plan for spec Revision 10").*

#### 5. Command-line length on the running OS (R2)

- **Decision**: the launcher measures the command line it actually hands to the OS: on Windows the
  string `Bun.spawn` builds (each argument quoted by the WIN-argv rules, joined by spaces, plus the
  terminating null); on Linux and macOS the arguments joined by single spaces plus the terminating
  null, because `execve` receives them unquoted. Both are counted in UTF-16 code units and compared
  with 32,767 (WIN-create) on every OS. The fixture's 400 generated test files have 90-character
  base names, so the names alone exceed 32,767 characters on every OS whatever the path prefix,
  while each full path stays under Windows' 260-character `MAX_PATH` at the default output base of
  the GitHub runners (estimated, not run).

#### 6. Tests added

- **Describe-label filter** (FR-016, BUN-discovery): a `bun_test` with `describe("Math ops")`
  holding `test("adds")` and a sibling test; with `TESTBRIDGE_TEST_ONLY="Math ops adds"` only
  `adds` runs (JUnit report and exit code checked).
- **Non-zero exit** (US1-1): a `manual` `bun_binary` that exits 3 is spawned; the exit code is 3.
- **Output root with a space**: one CI job, Windows, runs the root and `e2e/smoke` test sets and the
  `bazel run` step with `bazel --output_user_root="C:/bazel root"` (BZ-startup), so every runfiles
  path contains a space. Windows is chosen because spaces in user directories are the case the
  spec's edge case names and the manifest-only path is Windows' default; the file-name fixture
  already covers spaces on Linux with a tree and with a manifest.

### Plan for spec Revision 10 (2026-10-08, analysis C1; decisions, no new gap)

Spec Revision 10 keeps constitution V unamended: every reliance on undocumented upstream behavior
is replaced by a documented mechanism, a pattern of a bazelbuild/bazel-contrib ruleset, or an
explicit English error. Re-checked by the planner with the Bun 1.4.2 binary from `@bun_linux-x64`
in a scratch directory under `/tmp`, Linux (WSL), 2026-10-08; macOS and Windows not run. Other
decided gaps (G1, G2, G4–G6, G10–G12) are unchanged.

Sources added:

| Name | Source |
|---|---|
| BUN-sveltetest | https://bun.com/docs/guides/test/svelte-test (`docs/guides/test/svelte-test.mdx` at `bun-v1.4.2`: an `onLoad` callback that does `throw new Error(…)`, preloaded before the tests) |
| BUN-onloadargs | https://bun.com/reference/bun/OnLoadArgs (`packages/bun-types/bun.d.ts` at `bun-v1.4.2`: `path`, "The resolved import specifier of the module being loaded") |
| BUN-webapis | https://bun.com/docs/runtime/web-apis (`crypto`, Web Crypto) |
| RPY-cov | bazel-contrib/rules_python `fc7dc414a2f4e1d9596dad13fabb2cded3a39a1a` `python/private/stage2_bootstrap_template.py` lines 367–415: `unique_id = uuid.uuid4()`, `os.path.join(coverage_dir, "pylcov_{}.dat".format(unique_id))` |
| LCOV-format | https://github.com/linux-test-project/lcov/blob/master/docs/man/geninfo.rst ("TRACEFILE FORMAT": `SF:<path to the source file>`) |

#### 1. `bun test` reads the rule's `bunfig.toml` from its working directory (G3 withdrawn)

*Superseded by "Plan for spec Revision 11", item 1: the `$cwd/bunfig.toml` default is documented
for the runtime only, and the BUN-bunfig sentence continues "alongside your `package.json`". The
working directory and the test-file paths below stand; the rule's `bunfig.toml` at the root does
not.*

- **Source**: BUN-run documents the default configuration file as `$cwd/bunfig.toml`; BUN-bunfig:
  "Put `bunfig.toml` in your project root".
- **Observed** (2026-10-08): in a directory holding `bunfig.toml` (`env = false`,
  `[install] auto = "disable"`), a `.env` defining a variable, and `_main/pkg/a.test.ts`,
  `bun test ./_main/pkg/a.test.ts` ran the test with that directory as `process.cwd()` and the
  variable unset; without the `bunfig.toml` the variable was set. An import of an absent package
  failed with "Cannot find package" and the install cache stayed empty (as G5 recorded, `bun test`
  shows no red for install).
- **Decision**: the rule copies `isolated_bunfig.toml` to `<name>.bun/bunfig.toml`, the root of
  the copy tree (R6); the second process of a `bun_test` runs with that root as its working
  directory and gets no `--config`, `--no-env-file` or `--no-install`, none of which bun.com
  documents for `bun test`. Each test file is passed as `./<tree path>`, where the tree path is its
  path inside the copy tree, which equals the original's rlocation path (`./_main/pkg/a.test.ts`;
  not the copy's own rlocation path, which also holds `<package>/<name>.bun/`). That root always
  exists, so the G9 limitation is gone. `bun_binary` keeps `--config=<real path>` (BUN-run)
  and its working directory. Design: R2, R7, R8; divergence from the encyclopedia's working
  directory: Part 3.

#### 2. Filter and shards (G8 withdrawn)

- **Observed** (2026-10-08): `bun test -t nomatch <file>` exits 1; `bun test --shard=2/2` with one
  test file exits 0.
- **Decision**: `TESTBRIDGE_TEST_ONLY` maps to `--test-name-pattern=<value>` only. When it is set
  and `TEST_TOTAL_SHARDS` is greater than 1, the launcher exits 1 with an English error that
  filtering a sharded `bun_test` is not supported, before it starts the second process. A filter
  that selects nothing fails with Bun's exit code. Both exit codes are pinned by tests (FR-016),
  not canaries.

#### 3. A leading `--` fails (G13 withdrawn)

- **Observed** (2026-10-08, unchanged from 2026-10-05): `bun e.ts -- x` gives `["x"]`.
- **Decision**: nothing is inserted after the entry point. When the program's first argument is
  `--`, the launcher exits 1 with an English error naming it, because Bun 1.4.2 would drop it. A
  first argument `--config=z` reaches the program unchanged (observed 2026-10-05); one spawn test
  pins both.

#### 4. Coverage on a ruleset pattern (G7 re-based)

*Matching superseded by "Plan for spec Revision 12", G15: a record that names no copy is no
longer dropped, and the base of a relative `SF:` path is no longer a reading the launcher relies
on. The file name and the `.dat` pattern below stand.*

- **Decision**: the launcher writes `$COVERAGE_DIR/bunlcov_<crypto.randomUUID()>.dat`, as RPY-cov
  writes `pylcov_<uuid4>.dat` into `COVERAGE_DIR` (unique per process, so shards and reruns never
  collide; BZ-coverage asks for "unique names"). It reads Bun's `lcov.info` as LCOV-format, resolves
  each `SF:` path against the copy-tree root (an absolute path stays as it is), maps the copy to
  the original's `File.path` through `launch.json`, and drops records that name no copy. Corrected
  by Revision 11 (finding A2 of 2026-10-08): LCOV-format does not state the base of a relative
  `SF:` path, and BUN-coverage does not say which form Bun writes. Taking the working directory
  of the process that wrote the file, the copy-tree root, as the base is the launcher's reading,
  matching what Bun 1.4.2 writes (observed 2026-10-04: paths relative to the working directory).
  It is not a workaround of an upstream defect, so it has no canary (FR-028); if Bun writes
  another form, every record is dropped, and the coverage spawn test (exactly one `.dat` file
  naming the source, every OS) and the CI coverage step (FR-016a) fail. Canary C9's marker record
  is not needed.

#### 5. Load guard on documented API

- **Decision**: unchanged design (R13), now sourced entirely: `Bun.plugin` and `onLoad`
  (BUN-plugins), throwing from `onLoad` (BUN-sveltetest), `args.path` as the resolved path
  (BUN-onloadargs), `--preload` importing the guard before other modules (BUN-run), the re-run
  under `--isolate` (BUN-parallel). Canaries C10–C12 are withdrawn; the guard tests on every OS
  (Revision 7) stay. The regular-expression limit stays an observation with canary C13.

#### 6. Canaries narrowed (FR-028)

- **Decision**: canaries remain for upstream defects the rules work around and for the
  regular-expression limit: C1 (oven-sh/bun#43689, PR #36757), C2 (G2), C4 (G4, Bun's side), C7
  (G1) and C13. Withdrawn: C3 (G3), C5 (G8), C6 (G13), C8, C9 (G7), C10–C12 (guard). C14 (empty
  shard exits 0) and C15 (manifest escaping, implemented as RPY `runfiles.py` does) become ordinary
  tests (FR-016; spaces-in-paths fixture). Numbers are not reused, so earlier references stay
  traceable. Spec Revision 15 adds C16 (T124): on Windows the stub passes an inherited
  `BUN_OPTIONS` on to the first Bun process, which then runs code before or instead of the
  launcher (hermeticbuild/hermetic-launcher#78, an open request for the stub to set environment
  variables; Windows only).

#### G14. hermetic-launcher's side of the G4 canary (FR-028) — decided 2026-10-06

- **Requirement**: FR-028, a canary for every upstream workaround.
- **Source**: HL-readme and HL-src offer no API a test could call to ask whether the stub can
  resolve the remainder of an argument after a literal prefix (hermetic-launcher#81).
- **Decision** (implementer, 2026-10-06; now in the FR-028 text): `MODULE.bazel` carries the
  comment "On any hermetic_launcher bump, check hermetic-launcher#81 (G4) and #80 (G1)" next to
  the `hermetic_launcher` `bazel_dep`, and the FR-018a limitation in the contract names #81. Bun's
  side of G4 keeps canary C4.

### Plan for spec Revision 11 (2026-10-15, findings C1, I1, I2 of the 2026-10-08 analysis; decisions, no new gap)

Finding IDs of an analysis (C1, I1, …) are its own and are cited with its date; they are not gap
(G) or canary (C) numbers. Other decided gaps are unchanged. Nothing was run for this revision;
the observations cited are those of 2026-10-03 to 2026-10-08 (Linux, WSL).

Sources added:

| Name | Source |
|---|---|
| BUN-testconfig | https://bun.com/docs/test/configuration (configures `bun test` through the `[test]` section of `bunfig.toml`; says nothing about where the file is looked up and does not mention `--config`; read on bun.com 2026-10-15, not compared with `docs/` at `bun-v1.4.2`) |
| BUN-45331 | https://github.com/oven-sh/bun/issues/45331 (open, 2026-10-15): asks bun.com to state where `bun test` looks for `bunfig.toml` (working directory only, or parent directories too) and whether `--config` applies to `bun test` |

#### 1. `bun_test` configuration: the Bazel side only (finding C1; FR-018)

- **Source**: BUN-run documents `--config` and its default `$cwd/bunfig.toml` for the runtime.
  BUN-testcli does not list `--config`; BUN-bunfig says "Put `bunfig.toml` in your project root,
  alongside your `package.json`"; BUN-testconfig names no lookup rule. BUN-45331 asks for one.
- **Decision**: the second process of a `bun_test` gets no configuration option and runs with its
  working directory at the root of the copy tree (R6), as in Revision 10. The rule writes no
  `bunfig.toml` into the tree; the copy-tree root holds only directories, because every copy is at
  `<name>.bun/<tree path>` and a tree path begins with a repository directory. The rules claim, and
  a test checks on every OS, only that: `process.cwd()` of the tests is the copy-tree root, and
  that root holds no file. A `bunfig.toml` or `.env` the target declares is a copy like any other,
  so if Bun reads it the run stays hermetic. Whether `bun test` also searches the parent
  directories of its working directory (under `bazel-out/<config>/bin/<package>/`) is undocumented
  and is a limitation reported as unverified (R14). *The reach of those parent directories is
  stated by "Plan for spec Revision 12", item 2: they include `execroot/_main`.*
- **Isolation fixtures** (US3-1, US3-2, SC-006): unchanged as outcome tests. A `bunfig.toml` whose
  `preload` sets a global, and a `.env`, in the directory the spawn test starts the launcher from,
  change the second process's result while the launcher leaves the working directory unchanged
  (red, Linux); once the second process runs at the copy-tree root, they do not (green, every OS).
  The green is an observation on the pinned Bun, not a claim about Bun's lookup rule (FR-026).
- **Install** (US3-3): bun.com documents no option that turns auto-install off for `bun test`
  (BUN-testcli, BUN-testruntime list no `--no-install`). Bun 1.4.2 does not auto-install under
  `bun test` (G5, observed 2026-10-03 and 2026-10-08); the install fixture checks on every OS that
  the install cache stays empty, and the G5 observation stands in for its red (SC-006). If a Bun
  version installs there, that test fails and FR-004 applies.
- **`bun_binary`**: unchanged in behavior: `--config=<real path>` of the rule's configuration
  file, `--no-env-file`, `--no-install` (BUN-run, BUN-env). Its configuration file is no longer
  copied into the tree: the launcher passes the real path of the static
  `bun/private/isolated_bunfig.toml`, which is in the target's runfiles (R6, R7).

#### 2. Canary C4 pins the runtime command (finding I1; FR-028)

- **Reliance**: G4 is a limitation of the first process, a runtime `bun … launcher.js`. The stub
  could embed the rule's configuration file as two arguments if Bun applied `--config <path>` or
  `-c <path>`; today it does not (G4, observed 2026-10-03: `bun run` executes `<path>` as the
  entry point).
- **Decision**: C4 runs `bun --config <path> <file>` and `bun -c <path> <file>`, where `<path>` is
  a TOML file whose `preload` prints a marker and `<file>` prints another, and asserts today's
  behavior: neither marker is printed, because Bun runs `<path>` as the entry point. When a Bun
  version applies the file or runs `<file>`, C4 fails naming the FR-018a limitation and
  hermetic-launcher#81. Red: the mutation expects `<file>`'s marker. The earlier C4 tested
  `bun test --config <path>`, which the rules no longer pass (Revision 10), so a change on the
  runtime side would not have failed it.

#### 3. FR-001 step 1 (finding I2)

The stub's embedded arguments are `[bun, "--no-env-file", launcher.js, <name>.launch.json]` (R1):
`launcher.js` is the static file `bun/private/launcher.js`, not generated, and no `--config=` is
embedded (G4). The spec text is corrected to match.

#### 4. Further findings of the 2026-10-08 analysis fixed here

- **A1**: a test file is passed as `./<tree path>`, its path inside the copy tree (the original's
  rlocation path), not `./` followed by the copy's rlocation path (Revision 10 item 1, R8).
- **A2**: the base of a relative `SF:` path is stated as the launcher's reading of an
  undocumented form (Revision 10 item 4, R8). *Superseded by G15 (spec Revision 12): no reading
  is relied on; a value either matches exactly one declared copy or fails the test.*
- **U2**: the allowlisted `bun test` options are claimed as accepted and passed unchanged; their
  effect is Bun's, and only `--timeout` and `--isolate` have a test of their effect (contract,
  R8).

### Plan for spec Revision 12 (2026-10-15, findings C1 and U1 of the analysis Revision 12 cites; decisions by the implementer)

Revision 12 decides G15 and states the reach of the unverified parent-directory lookup. Other
decided gaps are unchanged. "Observed" here means run by the planner with the Bun 1.4.2 binary
from `@bun_linux-x64` in a scratch directory under `/tmp`, Linux (WSL), 2026-10-15; macOS and
Windows not run.

#### G15. Coverage `SF:` values matched against the declared copies (FR-016a, constitution V) — decided 2026-10-15

- **Requirement**: FR-016a; constitution V: undocumented behavior MUST NOT be relied on.
- **Source**: LCOV-format defines `SF:<path to the source file>` and does not say what a relative
  path is relative to; BUN-coverage does not say which form Bun writes. Revision 11 (finding A2)
  took the working directory as the base, a reading of an undocumented form, and dropped records
  that named no copy, so a record Bun wrote in another form was lost without an error naming it.
- **Observed**: Bun 1.4.2 writes `SF:` relative to the working directory **at the time it writes
  the report**: a test that calls `process.chdir(<other>)` gets `SF:../root/_main/pkg/a.ts`
  instead of `SF:_main/pkg/a.ts`. A preload outside the working directory gets its own record
  (`SF:../other/guard.js`), as the launcher in its guard role will (observed 2026-10-04 inside the
  working directory).
- **Decision**: the launcher reads Bun's `lcov.info` as LCOV-format and, for each `SF:` value,
  forms two readings: the value joined to the working directory it gave the second process (the
  copy-tree root, a real path), and the value itself when `path.isAbsolute` holds for it on the
  running OS. It compares both, after `path.normalize`, with the real paths of the declared copies
  (`copies` of `launch.json`, R6):
  - exactly one copy matches: the value is rewritten to that copy's original `File.path`;
  - no copy or several match: the launcher writes no `.dat` file and exits 1, whatever Bun's exit
    code, with an English error naming the target and the `SF:` value
    (`<label>: coverage record SF:<value> names no declared file` or `… names several declared
    files`; wording fixed by the test).
  The launcher's own file is the rule's, not a declared copy: a record whose readings equal the
  launcher's own real path is removed before matching. It is recognized by the same two readings,
  so no form is assumed for it either.
- **Rationale**: whatever form Bun writes, a record is either attributed to exactly one declared
  file or the test fails explicitly; nothing depends on the undocumented base. This replaces
  Revision 10 item 4's matching and finding A2's reading; the file name (`bunlcov_<uuid>.dat`,
  RPY-cov) stands.
- **Tests** (every OS): the coverage spawn test of R8 (one `bunlcov_*.dat` naming the source by its
  `File.path`, no record for `launcher.js` or a path under `.bun/`) stays. New: a spawn test sets
  `COVERAGE_DIR` for a `manual` `bun_test` whose test calls `process.chdir` to a directory under
  `TEST_TMPDIR`, so Bun writes values relative to that directory (observed above), and asserts
  exit 1, the English error naming an `SF:` value and no `.dat` file in `COVERAGE_DIR`. Red: the
  launcher before G15 drops the records and exits 0. The several-copies branch has no fixture: it
  needs a value whose two readings both name declared copies, which no tree builds (a tree path
  would have to equal an absolute path below the root); it is kept and reported as unverified
  (FR-026).
- **Alternatives**: keep dropping unmatched records (a record in another form is lost without an
  error naming it);
  rewrite by suffix (`.bun/<tree path>`), which assumes a form; fail only when every record is
  dropped (a partly lost report passes).

#### 2. The parent-directory lookup of `bun test`: its real reach (FR-018)

- **Source**: BZ-outdirs: `execroot/_main` is the "root of symlink forest" of the main repository,
  and `bazel-out` is under it. Checked for this repository with Bazel 9.2.0 (`bazel info
  execution_root`, 2026-10-15): `execroot/_main` holds a symbolic link to every top-level entry of
  the workspace (`.bazelrc`, `MODULE.bazel`, `BUILD.bazel`, …), and `bazel-out` is a directory
  under it.
- **Reach**: the copy tree's real path is
  `<output_base>/execroot/_main/bazel-out/<config>/bin/<package>/<name>.bun/`, so its ancestors
  include `execroot/_main`. A `bunfig.toml` or `.env` at the root of the consumer's workspace is
  linked there, and is within reach if `bun test` searches upward from its working directory.
  Revision 11 named only `bazel-out/<config>/bin/<package>/`; that understated it.
- **Observed**: `bun test ./_main/pkg/a.test.ts` run in `<ws>/bazel-out/bin/pkg/t.bun/` did not
  apply a `bunfig.toml` (`preload` and `[test] preload` setting a global) or load a `.env` placed
  in `<ws>/`, with and without a `package.json` or a `.git` directory there; the same files copied
  into the working directory took effect. This is an observation on Linux, not a documented rule
  (BUN-45331), and the rules claim nothing from it (FR-026).
- **Decision**: the limitation stays unverified and is stated with this reach (R7, R14, contract).
  `e2e/smoke` gains a root `bunfig.toml` (`preload` and `[test] preload` naming a root
  `smoke_preload.ts` that sets a global) and a root `.env` defining a variable; none of the three
  is declared by any target. Its `bun_test` asserts that the global and the variable are unset.
  The result on each OS is recorded from CI (macOS and Windows only from CI); a failure there is
  reported to the user as a gap (FR-004), not worked around.

### Findings from implementation (2026-10-16)

"Observed" here means run by the implementer with Bazel 9.2.0, Linux (WSL), 2026-10-16; macOS
and Windows not run.

#### G-impl-1. `--noenable_runfiles` fails without a staged runfiles tree on Linux (US4-2, SC-003, FR-011, FR-024) — resolved by spec Revision 13 (2026-10-17)

- **Resolution (spec Revision 13, user decision; constitution v2.0.0)**: Linux and macOS no longer
  launch through the stub. The shell launcher finds its files with the Bash runfiles library of
  rules_shell 0.6.1, whose `rlocation` takes a path from the runfiles directory only when the file
  exists there and otherwise reads the manifest, and whose initialization selects
  `<executable>.runfiles_manifest` when no runfiles variable is set (Part 1 "Plan for spec
  Revision 13", item 3). So the cases below resolve through the manifest: `bazel run
  --noenable_runfiles` (no variable; the adjacent manifest) and `bazel test` without a sandbox
  (`RUNFILES_DIR` names an empty directory; `RUNFILES_MANIFEST_FILE` from BZ-testsetup).
  `launcher.js` already prefers `RUNFILES_MANIFEST_FILE`. Windows prefers the manifest (see
  "Reach"), so US4-2, SC-003 and FR-024 hold as written. Option 1 is superseded: no FR-028 canary,
  no documented limitation and no upstream report (the tdd-log T101 draft is not filed). This is
  the design; it is verified only by the tests and CI runs that plan step 11 names. Until those
  pass, the resolution is unverified (FR-026).
- **Verified locally on Linux (2026-10-17, tdd-log T110, T111)**: `bazel run --noenable_runfiles`
  of `//bun/tests/run/app:main` and of `e2e/smoke`'s `//app:main` exit 0; `bazel test //...
  --noenable_runfiles --spawn_strategy=local --nocache_test_results` passes in the root and in
  `e2e/smoke`; `//bun/tests/run/manifest:manifest_only_test` passes. macOS, Windows and remote
  execution are unverified until the CI run of POST-1. The stale-tree case (item 3 of "Plan for
  spec Revision 13", "Not relied on") is not tested.
- **Decision of 2026-10-16 (superseded)**: option 1. Verified at hermetic-launcher `v0.0.16`: its README "Runfiles discovery"
  says the runfiles directory wins over the manifest on Linux and macOS when both exist, and
  `runfiles-stub/src` has no reference to `RUNFILES_MANIFEST_ONLY`. Document the failure of
  `bazel run` and of `bazel test --spawn_strategy=local` under `--noenable_runfiles` on Linux and
  macOS as a known limitation (`bun_binary` and `bun_test` docs, contract, quickstart), add an
  FR-028 canary that pins today's failure, and run the CI `manifest-only` job's `bazel run` as
  that canary's expected failure. The upstream report is pending the user's approval.

- **Requirement**: US4-2 and SC-003: the self-checking program passes with the runfiles tree
  disabled; FR-024.
- **Observed**: `bazel run --noenable_runfiles //bun/tests/run/app:main -- extra` and
  `(cd e2e/smoke && bazel run --noenable_runfiles //app:main)` exit 1 with "ERROR: execve failed
  with code -2" (tdd-log T077, T079, T086; reproduced 2026-10-16). `bazel test //...
  --noenable_runfiles` passes in both under the default strategy, linux-sandbox, which stages a
  runfiles tree for every test (tdd-log T029, T077); remote execution was not run. The script
  `bazel run --script_path` writes runs `env -u RUNFILES_DIR -u RUNFILES_MANIFEST_FILE -u RUNFILES_MANIFEST_ONLY …` in
  `bazel-bin/bun/tests/run/app/main.runfiles`, which holds only `MANIFEST` and an empty
  `_main/`. Starting the same stub with `RUNFILES_MANIFEST_FILE=<…/main.runfiles_manifest>` runs
  the program (T077).
- **Observed beyond `bazel run`** (T094, 2026-10-16): `bazel test //bun/tests/run:skeleton_test
  --noenable_runfiles --spawn_strategy=local --nocache_test_results` fails, the test log holding
  "ERROR: execve failed with code -2"; the same command with
  `--spawn_strategy=processwrapper-sandbox` passes. Without a sandbox the test's
  `skeleton_test.runfiles/` is not materialized, and the test gets `RUNFILES_DIR` (BZ-teststrategy),
  `RUNFILES_MANIFEST_ONLY=1` (BZ-testrunner) and `RUNFILES_MANIFEST_FILE` (BZ-testsetup). Starting
  `bazel-bin/bun/tests/run/app/main` by hand with `RUNFILES_DIR=<…/main.runfiles>`,
  `RUNFILES_MANIFEST_FILE=<…/main.runfiles_manifest>` and `RUNFILES_MANIFEST_ONLY=1` fails the same
  way; with `RUNFILES_MANIFEST_FILE` alone the program starts.
- **Source**:
  - BZ-run: `bazel run` clears `RUNFILES_DIR`, `RUNFILES_MANIFEST_FILE` and
    `RUNFILES_MANIFEST_ONLY` unconditionally, and `ensureRunfilesBuilt` creates
    `<binary>.runfiles/<workspace name>/` "even if we run with --enable_runfiles=no"
    (bazelbuild/bazel#10621).
  - HL-readme "Runfiles discovery" and HL-src `runfiles.rs` (`Runfiles::create`, line 36;
    `select_source`, line 172) with `PREFER_DIRECTORY_SOURCE` (`linux.rs` line 122 and `macos.rs`
    line 101: `true`; `windows.rs` line 143: `false`):
    with no environment source, the stub picks `<executable>.runfiles/` over
    `<executable>.runfiles_manifest` on Linux and macOS whenever the directory exists, and resolves
    every path only through the source it picked. The README states the premise: those platforms
    "materialize the runfiles tree". Under `--noenable_runfiles` the directory exists but is not
    materialized, so the path to Bun resolves to a file that does not exist. The environment tier
    applies the same preference: `RUNFILES_DIR`, when it names an existing directory, wins over
    `RUNFILES_MANIFEST_FILE`, and the stub does not read `RUNFILES_MANIFEST_ONLY`.
  - BZ-teststrategy: every test gets `RUNFILES_DIR`. BZ-testrunner: Bazel adds
    `RUNFILES_MANIFEST_ONLY=1` when runfiles are disabled ("tell remote-runtest.sh/local-runtest.sh
    about that"). BZ-testsetup: `test-setup.sh` sets `RUNFILES_MANIFEST_FILE` to
    `$TEST_SRCDIR/MANIFEST` and, when `RUNFILES_MANIFEST_ONLY` is `1` and that file exists, exports
    it, because "test programs should use manifest file to find runfiles".
  - RPY `python/runfiles/runfiles.py` (`Runfiles.CreateOrRaise`): a non-empty
    `RUNFILES_MANIFEST_FILE` selects the manifest; `RUNFILES_DIR` is used only otherwise. The stub's
    environment tier on Linux and macOS has the opposite order.
  - HL-pr59 and HL-issue61: the directory preference is deliberate. #59 ("fix: select one runfiles
    source", merged 2026-06-24) made the stub "prefer a directory within either tier", because
    choosing the manifest first resolved generated Python virtual environments into physical
    outputs; #61 was closed as not planned. A report asking for the manifest first reverses that
    choice. Honouring `RUNFILES_MANIFEST_ONLY=1` would also reverse it under sandboxes, because
    Bazel sets that variable whenever runfiles are disabled (BZ-testrunner), staged tree or not. A
    per-path fallback to the manifest is not enough either: the stub exports only the source it
    selected (HL-src `linux.rs` lines 501–508, "Use the selected source consistently for lookup and
    child environment export", HL-pr59), so `launcher.js` would still get the empty `RUNFILES_DIR`.
    Selecting the directory only when the first transformed argument exists under it, and that
    tier's manifest otherwise, keeps the preference wherever the tree is staged.
  - Neither side offers a documented switch: `finalize-stub` has no option to force the manifest
    (HL-readme "`finalize-stub` options"), and `ctx.configuration.runfiles_enabled` is
    `documented = false` in Bazel 9.2.0 (`BuildConfigurationApi.java` line 118). A macro can
    branch on `--enable_runfiles` with `select` (BZ-lib-runfiles, as rules_js does), but no branch
    helps: the stub is the same in both configurations, `bazel test` gives it `RUNFILES_DIR`
    before it starts, and the working directory `bazel run` gives under `--noenable_runfiles` is
    not documented.
- **Reach**: Linux; macOS by the same code path (not run). Windows prefers the manifest
  (`PREFER_DIRECTORY_SOURCE` false), so this gap does not apply there; the Windows `bazel run`
  result comes from CI (POST-1). Under `--noenable_runfiles`, observed failing: `bazel run` and
  `bazel test --spawn_strategy=local` of `//bun/tests/run:skeleton_test`; observed passing:
  `bazel test //...` under linux-sandbox, and `skeleton_test` under processwrapper-sandbox. Other
  targets under those two strategies, other strategies and remote execution were not run.
- **What `bazel test //... --noenable_runfiles` exercises** (T095): under linux-sandbox, the
  strategy of the local runs (T077, T079) and of the CI `manifest-only` job, every test runs with
  a staged runfiles tree and an existing `RUNFILES_DIR` (T029), so the stub takes the directory
  and that run does not exercise the manifest-only path. On Linux it is exercised only by the
  tests that start a target with `RUNFILES_DIR` removed and `RUNFILES_MANIFEST_FILE` set to
  Bazel's manifest: `//bun/tests/run/spaces:manifest_spawn_test` (T029) and the two
  manifest-only cases of `//bun/tests/run/tree:sibling_spawn_test` (T096), both in the root;
  `e2e/smoke` has none.
- **CI**: the `manifest-only` job's `bazel run --noenable_runfiles` step fails in both folders until
  this is decided (T081).
- **Options**:
  1. Report the defect to hermetic-launcher (the directory is preferred where it is not
     materialized), pin the issue in the `MODULE.bazel` bump comment and an FR-028 canary as for
     G1 and G4, and state the failure as a limitation until a fixed release. The report (tdd-log
     T101) keeps the directory preference of HL-pr59 and asks for one change: within each tier,
     select the directory only when the first transformed argument exists under it, otherwise that
     tier's manifest, for lookup and for the exported environment. It fixes `bazel run` (adjacent
     manifest) and `bazel test` without a sandbox (`RUNFILES_MANIFEST_FILE`, exported by
     BZ-testsetup). Spec: US4-2, US4 "Independent Test", SC-003, FR-011 and FR-024 ("including the
     `bazel run` step") gain the exception for `bazel run` and for `bazel test` without a sandbox
     on Linux, and on macOS labelled unverified (FR-026, not run); FR-028 lists G-impl-1 among the
     places with a canary, although nothing here works around it. The CI `manifest-only` job keeps
     `bazel test` under linux-sandbox and runs the `bazel run` step as the canary's expected
     failure. Filing the issue is an outward action for the user.
  2. Option 1 without the upstream report: the limitation is permanent until someone else fixes it.
  3. Replace the stub on Linux and macOS with a generated shell script that finds the manifest:
     reverses R1, needs a shell at run time, and still needs the undocumented
     `runfiles_enabled`, a `select` on `--enable_runfiles`, or a script used in every
     configuration. Constitution VI forbids generated
     shell scripts.
  3a. Replace the stub with a native launcher the ruleset builds, for example `launcher.js`
     compiled with `bun build --compile` (constitution VI allows "a native executable");
     `launcher.js` already prefers `RUNFILES_MANIFEST_FILE`. Reverses R1, puts a compiled Bun
     (tens of megabytes) in every target's runfiles, and needs a cross-compiled executable per
     target platform; not run, so whether it closes the gap is unverified. Not recommended.
  4. Set `RUNFILES_MANIFEST_FILE` through `RunEnvironmentInfo` (BZ-runenv): `bazel run` applies it
     after the `-u` list, but the value's base directory differs between `--enable_runfiles`
     (`<name>.runfiles/_main`) and `--noenable_runfiles` (`<name>.runfiles`), neither is documented,
     and the same environment reaches `bazel test`, where Bazel sets the runfiles variables
     itself; and in `bazel test` without a sandbox `RUNFILES_DIR` (BZ-teststrategy) still wins at
     the environment tier, so it cannot fix that case. Not recommended.
  5. Carry a patched hermetic-launcher template until a fixed release: `compile_stub` takes a
     `template_file` (HL-readme, line 114), so the ruleset could pass a stub built with the change
     of option 1. Needs the patched Rust built per target platform, pinned and tested, and dropped
     at the bump; patching the module's sources alone does not change the prebuilt templates. Not
     run, so whether it closes the gap is unverified. Not recommended.
- **Recommendation**: option 1, its limitation and report covering `bazel test` without a sandbox
  as well as `bazel run` (T094). It is the pattern already used for upstream defects (G1, G4,
  FR-028), keeps every claim documented, and closes the gap with a dependency bump instead of a
  second launcher.

#### `bun_test` carrying the Windows Bun is analyzed (SC-007, US4-3) — resolved by T122

Until T122, `bun/tests/target_toolchain_test.bzl` had no `windows_x64` case for `bun_test`: on a
Linux host a `bun_test` configured for `windows_x64` did not analyze (tdd-log T074, T122). Cause,
found in T122 with `bazel query 'somepath(…)'` and `--toolchain_resolution_debug` at Bazel 9.2.0:
Bazel runs the test action on an execution platform with all constraints of the target platform
(the test exec group's `@bazel_tools//tools/test:default_test_toolchain_type`), so the analysis
test registered `windows_x64` as an execution platform; the test rule's implicit tools of that exec
group are then built for Windows, and `@bazel_tools//tools/launcher:launcher_toolchain_type`
resolves to the toolchain that builds `@bazel_tools//src/tools/launcher` from source, which finds no
C++ toolchain. Two configurations of that launcher failed: `--coverage_report_generator=<a file>`
removed one, so `@bazel_tools//tools/test:coverage_report_generator` (a `java_binary`) is one
source; the other was not isolated (no flag replaces `@bazel_tools//tools/test:collect_coverage`,
an `sh_binary` and the only other binary among the implicit tools).

Mechanism (TE-exec): "Users can register additional toolchains for this type to influence this
behavior and their toolchains will take precedence over the default ones." The analysis test
`rule_platform_test_windows_x64_test` sets, in its own `config_settings` only,
`--extra_toolchains=//bun/tests/platforms:windows_test_on_host`: a test-only `toolchain` of
`default_test_toolchain_type` with `target_compatible_with = ["@platforms//os:windows"]` and no
execution constraint, whose `toolchain` is a test-only rule returning an empty `ToolchainInfo`
("Toolchains of this type do not carry any data in the form of providers", TE-exec). The test
action then runs on the first registered execution platform, as TE-exec says of Bazel's
`legacy_test_toolchain`, which likewise "does not impose any constraints and thus test actions
without manually specified exec constraints are configured for the first registered execution
platform"; that platform is the host:
the modules register none, and `--toolchain_resolution_debug` shows "Selected execution platform
@@platforms//host:host" for it. The test action and its tools are configured for the host; the target's Bun is still
resolved for the target platform, and the test asserts that the runfiles hold
`@bun_windows-x64//:bun.exe` and no other Bun. Nothing is registered in `MODULE.bazel`, so
consumers get nothing new. Verified on Linux (WSL) only; that a Windows `bun_test` runs remains the
Windows CI job's evidence (POST-1, FR-026).

Sources (TE-exec): https://bazel.build/reference/test-encyclopedia ("Execution platform");
https://bazel.build/extending/exec-groups ("the `test` execution group is present by default on
Starlark test rules").

Until T122 the no-stub analysis test had no `bun_test` case for the same reason (Revision 13, T106):
`//bun/tests/platforms:no_stub` is now a Windows platform (`@platforms//os:windows`,
`@platforms//cpu:aarch64`, for which hermetic-launcher 0.0.16 registers no template, HL-toolchains),
so only `platform_failure_no_stub_binary_test` exists. The T122 mechanism would let a `bun_test`
case analyze; none was added, so that a `bun_test` for a Windows platform without a stub fails
analysis naming the template toolchain type stays unverified (FR-026).

#### G-impl-2. A Windows CI job "with no `bash` on `PATH` and `BAZEL_SH` unset" still gives Bazel a Bash (SC-005, constitution VI; T116) — decided 2026-10-17 (implementer): option 1

Found while starting T116 (2026-10-17). Nothing was added to `.github/workflows/ci.yaml`. Sources:
bazelbuild/bazel at `9.2.0`, bazelbuild/rules_shell at `v0.6.1`, actions/runner-images at
`ee1ff4569e381a9649b400338bdc8ceb7e18a80e` (Windows image version 20261007.264.1). Reviewed
adversarially by a subagent and by Codex; their verified findings are applied below.

- **The client finds a Bash and exports it.** Before parsing options ("ParseOptionsOrDie already
  populate --client_env, so detect bash before it happens", `src/main/cpp/blaze.cc`, lines
  1633–1636), the Windows client runs `DetectBashAndExportBazelSh`
  (`src/main/cpp/blaze_util_windows.cc`, lines 1449–1475): a non-empty `BAZEL_SH` is kept;
  otherwise it takes an MSYS2 install recorded in the registry, else the first `bash.exe` on
  `PATH` (no exclusion of the WSL `bash.exe`), and exports it as `BAZEL_SH`. So unsetting
  `BAZEL_SH` in the job does not reach `bazel run` children or repository rules.
- **The server falls back to MSYS2.** With neither `--shell_executable` nor `BAZEL_SH`, Bazel's
  shell is `c:/msys64/usr/bin/bash.exe` (`BazelRuleClassProvider.SHELL_EXECUTABLES`, line 95;
  precedence in `getDefaultPathFromOptions`, lines 116–127; documented in the
  `--shell_executable` help, `ShellConfiguration.java`, lines 80–86).
- **Bazel puts Bash on every action's and test's `PATH`.** `pathOrDefault`
  (`BazelRuleClassProvider.java`, lines 347–394) prepends the shell's directory and its sibling
  (`C:\msys64\usr\bin;C:\msys64\bin` for the default) and always adds `%SYSTEMROOT%`,
  `System32` and `System32\WindowsPowerShell\v1.0`; `SHELL_ACTION_ENV` applies it with and
  without `--incompatible_strict_action_env` (lines 162–179). `--action_env` entries are applied
  after it (lines 181–190), so `--action_env=PATH=…` overrides it.
- **rules_shell has its own Bash.** Its `local_config_shell` repository rule
  (`shell/private/repositories/sh_config.bzl`, lines 104–123) takes `BAZEL_SH`, else
  `bash.exe` on `PATH` outside `%WINDIR%`, else `c:/msys64/usr/bin/bash.exe` (line 19); it never
  reads `--shell_executable`.
- **`windows-latest` has these Bashes.** `windows-latest` is Windows Server 2025
  (`README.md`, line 37). `images/windows/Windows2025-VS2026-Readme.md` lists MSYS2 at
  `C:\msys64` ("pre-installed on image but not added to PATH") and the shells
  `C:\Program Files\Git\bin\bash.exe`, `C:\msys64\usr\bin\bash.exe` and
  `C:\Windows\System32\bash.exe` (the WSL launcher). Whether its MSYS2 is in the registry keys
  the client reads is unverified.
- **Consequence.** A job that only clears `PATH` and `BAZEL_SH` would still leave Bazel a Bash
  (the client's detection, the MSYS2 fallback, the `PATH` Bazel builds for actions and tests), so
  it would not show that no Windows build or run needs Bash. T116's own condition applies: report
  to the user. Until a job passes, the claims in `bun/defs.bzl` line 33 and `bun/private/run.bzl`
  line 33 that the Windows stub "needs no Bash" are unverified (FR-026). Whether root `bazel test
  //...` or `e2e/smoke` needs Bash on Windows today is unknown: the existing Windows jobs run with
  Bash available. Neither the shell launcher nor the stub of this feature asks Bazel for a shell
  on Windows: ordinary Windows `bazel test` runs the native test wrapper and ordinary `bazel run`
  starts the target directly; a shell is used only with `--run_under` or `--script_path` (per the
  reviewers' reading of `TestActionBuilder.java` and `RunCommandLine.java`; not re-read here).
- **Options** (option 1 applied by T116, 2026-10-17):
  1. `bazel` flags only, in the job's `bazelrc`: `--shell_executable=` and `--repo_env=BAZEL_SH=`
     both set to a path that does not exist (Bazel's shell and rules_shell's toolchain), plus
     `--action_env=PATH=…`, `--host_action_env=PATH=…`, `--test_env=PATH=…` and `--run_env=PATH=…`
     naming a `PATH` without any Bash directory, and `--run_env==BAZEL_SH` (each flag's help
     documents `name=value`; `--action_env` and `--run_env` document `=name` unsetting). Every
     action that takes Bazel's default environment, test and `bazel run` process starts with a
     `PATH` without Bash and no usable Bazel shell; repository rules and actions that set their own
     environment keep their own `PATH`, and a program that starts Bash by absolute path, or by bare
     name through Windows' search of the system directory (`CreateProcessW` searches it before
     `PATH`), is not caught. Whether the test wrapper and Bun run with that `PATH` (for example
     without `System32`) is unverified. T116's text ("no `bash` on `PATH` and `BAZEL_SH` unset") is
     restated to these flags; SC-005 ("without Bash on `PATH`") is restated to the same reach (spec
     Revision 14).
  2. Only `--shell_executable=` and `--repo_env=BAZEL_SH=` to a path that does not exist. Smaller,
     but processes still get the `PATH` Bazel builds, which includes `System32\bash.exe`; SC-005
     would be restated.
  3. A non-`bazel` step before the Bazel steps that makes every Bash on the image unreachable
     (delete `C:\msys64`, remove or rename Git's and `System32`'s `bash.exe`). Matches SC-005
     literally; depends on the runner image's layout and on removing a system-owned file.
  4. No job: restate SC-005 and the two docstrings to state that a Windows build or run without
     Bash is unverified (FR-026), and drop T116.
- **Recommendation**: option 1. It uses documented flags and `bazel` steps only, covers each route
  by which Bazel itself would hand a Bash to an action that takes its default environment, a test or
  a `bazel run` process, and does not depend on the image's file layout. The run must not reuse
  cached results (`--nocache_test_results`, no disk cache), as the `output-root-with-space` job
  already avoids them.
- **Applied (T116)**: job `windows-without-bash` in `.github/workflows/ci.yaml`, both folders,
  with `--shell_executable` and `--repo_env=BAZEL_SH` set to `C:/no-bash/bash.exe`,
  `PATH=C:\Windows` for `--action_env`, `--host_action_env`, `--test_env` and `--run_env`,
  `--run_env==BAZEL_SH`, `--nocache_test_results` and no disk cache. `C:\Windows` is `%SYSTEMROOT%`,
  which Bazel's own default `PATH` includes, and is not among the image's Bash locations listed
  above. In a bazelrc a backslash escapes the next character, so the file holds `C:\\Windows`
  (observed: `--announce_rc` shows `C:\Windows` read as `C:Windows`, also inside single quotes, and
  `C:\\Windows` as `C:\Windows`). Not covered: the `PATH` of repository rules (only their `BAZEL_SH`
  is set) and of actions that set their own environment. Two tests set their own `PATH` to
  `%SYSTEMROOT%\system32`, which holds the WSL `bash.exe`: `e2e/smoke`'s `version_test`
  (bazel-skylib 1.9.0 `diff_test`, which calls `findstr.exe` and `fc.exe`) and the root's
  `//tools:preset.update_test` (bazel_lib 3.0.0 `lib/private/diff_test_tmpl.bat`, line 9). The
  result comes from POST-1 (FR-026).

### Plan for spec Revision 13 (2026-10-17, constitution v2.0.0; technical decisions by the implementer, no new gap)

Revision 13 (user decision) makes the Linux and macOS executable a generated shell launcher that
finds its files with Bazel's runfiles library for Bash; Windows keeps the hermetic-launcher stub.
Constitution v2.0.0 VI requires that launcher, and V restricts hermetic-launcher to Windows. This
section records the library's home for Bazel 9.2.0, how a bazel-contrib ruleset uses it, the
launcher's design and the lowest dependency versions. "Read" means the source was read at the
version named. "Observed" means run by the planner with Bazel 9.2.0 in this repository on Linux
(WSL), 2026-10-17. No launcher was built or run for this revision.

Sources added:

| Name | Source |
|---|---|
| BZ-tools-bash | `tools/bash/runfiles/BUILD.tools` at Bazel 9.2.0, identical to `embedded_tools/tools/bash/runfiles/BUILD` in the install base: `alias(name = "runfiles", actual = "@rules_shell//shell/runfiles")` |
| BZ-moduletools | `src/MODULE.tools` at Bazel 9.2.0, line 39: `bazel_dep(name = "rules_shell", version = "0.6.1")` |
| BZ-deploying | https://bazel.build/rules/deploying, "Runfiles library" (`site/en/rules/deploying.md` at 9.2.0): a ruleset's runfiles library is "a library target located at `//<LANG>/runfiles`", and "User targets that need to access their data dependencies will typically add this target to their `deps` attribute" |
| BZ-module-runfiles | https://bazel.build/external/module (`site/en/external/module.md` at 9.2.0, lines 198–202): to look up runfiles, use `$(rlocationpath ...)` "or one of the runfiles libraries in `@bazel_tools//tools/{bash,cpp,java}/runfiles` or, for a ruleset `rules_foo`, in `@rules_foo//foo/runfiles`" |
| RSH | bazelbuild/rules_shell `0.6.1` (BCR; tag `v0.6.1` = `e071f45e20`): `shell/runfiles/BUILD`, `shell/runfiles/runfiles.bash`, `shell/private/root_symlinks.bzl`; read from the module's extracted source in the output base |
| RSH-35 | https://github.com/bazelbuild/rules_shell/pull/35 (merged 2025-08-11, first in 0.6.0): the library's setup instructions name `@rules_shell//shell/runfiles` instead of `@bazel_tools//tools/bash/runfiles`, which "works for now but should be dropped eventually" |
| RSH-68 | https://github.com/bazelbuild/rules_shell/pull/68 (merged 2026-08-12, tag `v0.9.0`; the BCR `metadata.json` lists versions up to 0.8.0 on 2026-10-17): `rlocation` consults the manifest before the runfiles directory |
| RPY-interp | bazel-contrib/rules_python `192b1c2dd72d0e42136bcbe6e44ffad0f354d620` (`main`, 2026-10-16): `python/private/interpreter.bzl` (`interpreter_binary`), `python/private/interpreter_tmpl.sh`, `python/private/common.bzl` (`runfiles_root_path`, line 547) |
| RPY-stage1 | `python/private/stage1_bootstrap_template.sh` at the same commit, at `fc7dc414` (RPY) and in rules_python 1.7.0 (`find_runfiles_root`) |
| SKY-shell | bazelbuild/bazel-skylib `1.9.0`, `lib/shell.bzl` (`shell.quote`, line 37) |
| HL-toolchains | `launcher/private/toolchains.bzl` at hermetic-launcher `v0.0.16`: `PLATFORMS` lists `x86_64_windows` as the only Windows platform with a registered template ("Windows/aarch64 ships for standalone use but has no auto-registered Bazel toolchain") |

#### 1. The library and its label for Bazel 9.2.0 (FR-001; constitution V, VI)

- **Source**: BZ-tools-bash: in Bazel 9.2.0, `@bazel_tools//tools/bash/runfiles` is an alias of
  `@rules_shell//shell/runfiles`. Observed (`bazel query --output=build`): the alias resolves to
  `@@rules_shell+//shell/runfiles:runfiles`, whose `actual` is `:runfiles_impl`. That target is an
  `sh_library` whose `data` is a `root_symlinks` target. The `root_symlinks` target places
  `runfiles.bash` at the runfiles path `bazel_tools/tools/bash/runfiles/runfiles.bash` (RSH
  `shell/runfiles/BUILD`; `ROOT_SYMLINKS_SUPPORTED = not hasattr(native, "sh_binary")`, RSH
  `root_symlinks.bzl`). The documented initialization code looks the library up at that path.
- **The library's documentation**: the "USAGE" header of RSH `runfiles.bash`: (1) "Depend on this
  runfiles library from your build rule" (`@rules_shell//shell/runfiles`); (2) insert the
  "runfiles.bash initialization v3" block "to the top of your main script"; (3) "Use rlocation to
  look up runfile paths". It also documents `runfiles_export_envvars`: "Exports the environment
  variables that subprocesses need in order to use runfiles". BZ-deploying and BZ-module-runfiles
  name both labels as runfiles libraries.
- **Decision**: depend on `@rules_shell//shell/runfiles`. It is the label the library's own
  documentation names (RSH-35), and it has the `//<LANG>/runfiles` form that BZ-deploying
  prescribes. `@bazel_tools//tools/bash/runfiles` also works in Bazel 9.2.0
  (BZ-module-runfiles), but the rules_shell maintainers say it should eventually be dropped
  (RSH-35).
- **Alternatives**: `@bazel_tools//tools/bash/runfiles`, rules_python's choice (RPY-interp). It
  needs no new `bazel_dep`, but it is the alias RSH-35 expects to be dropped. A hand-written
  lookup, as RPY-stage1 has (item 2), is not the runfiles library constitution VI names, and it
  does not read the manifest.

#### 2. How rules_python uses it (constitution VI's reference)

- **Finding**: constitution VI and spec Revision 13 point to "rules_python's bootstrap". The
  bootstrap of `py_binary` and `py_test`, RPY-stage1, does not source the Bash runfiles library,
  on `main` or in 1.7.0. Its `find_runfiles_root` takes `RUNFILES_DIR`, or derives
  `<executable>.runfiles` from `RUNFILES_MANIFEST_FILE`, or walks from `$0`, and then reads every
  file from that directory. It never resolves a path through the manifest. In rules_python the
  library's other users are tests (`tests/bootstrap_impls/*.sh`).
- **The pattern that uses the library**: `interpreter_binary` (RPY-interp). It is an executable
  rule that expands the static template `interpreter_tmpl.sh` with
  `ctx.actions.expand_template(..., is_executable = True)`, substituting the runfiles-root path of
  the toolchain's interpreter computed by `runfiles_root_path`. It merges the `default_runfiles`
  of `@bazel_tools//tools/bash/runfiles`, held in a private `_bash_runfiles` attribute, into its
  runfiles. The template starts with `#!/usr/bin/env bash` and holds the initialization v3 block
  verbatim. It resolves the interpreter with `rlocation`, fails when the result is empty or names
  no file, and `exec`s it with `"$@"`. That is the launcher this feature needs, with the
  toolchain's Bun in place of the toolchain's Python.
- **Decision**: follow `interpreter_binary`. The design meets constitution VI as written: a
  generated shell launcher that finds its files with Bazel's runfiles library for Bash. The
  constitution's pointer to "rules_python's bootstrap" names a file that does not use the library,
  so it is reported to the user. Clarifying it is a constitution amendment and the user's
  decision; the design does not depend on it.

#### 3. Manifest handling, and why G-impl-1 is resolved (RSH `runfiles.bash` 0.6.1)

- **Source**:
  - Initialization v3 (header, lines 70–80) tries, in order: `$RUNFILES_DIR/<lib>`, the
    `<lib>` line of `$RUNFILES_MANIFEST_FILE`, `$0.runfiles/<lib>`, the `<lib>` line of
    `$0.runfiles_manifest`, then that of `$0.exe.runfiles_manifest`.
  - On load (lines 90–98), when neither `RUNFILES_DIR` names a directory nor
    `RUNFILES_MANIFEST_FILE` a file, the library exports
    `RUNFILES_MANIFEST_FILE=$0.runfiles_manifest` if that file exists. Otherwise it exports
    `$0.runfiles/MANIFEST`, and otherwise `RUNFILES_DIR=$0.runfiles` if the library is under it.
  - `rlocation` calls `runfiles_rlocation_checked` (lines 373–495). It returns
    `$RUNFILES_DIR/<path>` only when that path exists (`-e`). Otherwise it looks the path up in the
    manifest, including the escaped form (leading space, `\s`, `\n`, `\b`) described by
    BZ-manifest. It prints an empty string when the manifest has no entry or the entry names no
    file.
- **Cases G-impl-1 recorded**:

  | Case | Runfiles variables | How the launcher finds its files |
  |---|---|---|
  | `bazel run --noenable_runfiles` | none (BZ-run clears them); `<exe>.runfiles/` holds only `MANIFEST` and an empty `_main/` | initialization: `$0.runfiles/<lib>` is absent, so it reads `$0.runfiles_manifest`; on load the library exports `RUNFILES_MANIFEST_FILE`; every `rlocation` reads the manifest |
  | `bazel test --spawn_strategy=local --noenable_runfiles` | `RUNFILES_DIR` (an empty directory, BZ-teststrategy), `RUNFILES_MANIFEST_FILE` (BZ-testsetup), `RUNFILES_MANIFEST_ONLY=1` | initialization: the second line (the manifest); every `rlocation` misses under the directory and reads the manifest |
  | sandboxed test, or `--enable_runfiles` | `RUNFILES_DIR`, a staged tree | under the directory |
  | spawn tests that remove `RUNFILES_DIR` and set `RUNFILES_MANIFEST_FILE` (T029, T096) | manifest only | the manifest |

  The library does not read `RUNFILES_MANIFEST_ONLY`, and none of these cases needs it.
- **Environment for `launcher.js`**: the launcher calls `runfiles_export_envvars` before `exec`.
  `launcher.js` prefers `RUNFILES_MANIFEST_FILE` (R5), so it reads the manifest whenever one
  exists, and the program sees both variables whenever both can be derived.
- **Not relied on**: the directory-first order of 0.6.1. RSH-68 (v0.9.0, not on BCR) puts the
  manifest first. Both orders give the same file in a staged tree and in an empty one. One case is
  not researched: a tree left stale by an earlier `--enable_runfiles` build, then run with
  `--noenable_runfiles` and no sandbox. There 0.6.1 resolves through the stale directory. It is
  reported as unverified, not claimed.
- **Repository mapping**: when a row for (caller repository, first segment) exists in
  `_repo_mapping`, `rlocation` maps the first segment through it; otherwise it uses the path
  unchanged (lines 160–208). The launcher passes paths whose first segment is already a canonical
  name (`_main/…`, `<canonical name>/…`), computed as RPY-interp's `runfiles_root_path` does.
  BZ-repomap ("Step 3 a)") keeps this case viable ("Passing in runfiles paths from Starlark via
  environment variables or arguments").

#### 4. The Linux and macOS launcher (FR-001 step 1)

- **Decision**: on a target platform without `@platforms//os:windows`, the executable is
  `ctx.actions.expand_template(template = <bun/private/launcher.sh.tpl>, output = <name>,
  is_executable = True)`, as RPY-interp does. The template:
  - starts with `#!/usr/bin/env bash`, followed by the initialization v3 block verbatim from RSH
    0.6.1;
  - resolves four rlocation paths with `rlocation`: Bun (`BunInfo.bun` of the target toolchain),
    `isolated_bunfig.toml`, `launcher.js` and `<name>.launch.json`. When a result is empty or
    names no file, it prints an English error naming the rlocation path and exits 1, as
    RPY-interp does;
  - calls `runfiles_export_envvars`;
  - runs `exec "$bun" "--config=$bunfig" --no-env-file "$launcher" "$launch_config" "$@"`.

  The rule substitutes each rlocation path as a word quoted with `shell.quote` (SKY-shell),
  because package and target names may contain shell metacharacters.
- **Both rules**: the first process of a `bun_test` also gets `--config=`. It runs `launcher.js`
  as a runtime `bun <file>`, for which BUN-run documents `--config`. So `isolated_bunfig.toml` is
  in the runfiles of every executable on Linux and macOS. The second process is unchanged (R2,
  R7).
- **`launcher.js` is unchanged**: with either launcher, `process.argv` is
  `[bun, launcher.js, launch.json, ...args]` (R10). The `BUN_OPTIONS` check of FR-018a stays in
  `launcher.js` on every OS.
- **`exec`** replaces the shell, so the exit code, signals and standard streams are Bun's
  (FR-015).
- **Run-time requirement**: `/usr/bin/env`, `bash`, and the utilities `runfiles.bash` calls
  (`grep`, `sed`, `cut`, `tr`, `wc`, `awk`, `tail`, `uname`, `dirname`, `basename`) on the host
  that runs the target, as for any rules_shell launcher. The contract states it. (`tail` added
  2026-10-17 in T113: RSH `runfiles.bash` 0.6.1 line 283, `runfiles_current_repository`.)
- **Other non-Windows OSes**: a consumer's own Bun toolchain for another OS (for example FreeBSD)
  gets the same shell launcher. Nothing is claimed for those OSes (FR-026).
- **Toolchains**: `launcher.finalizer_toolchain_type` becomes optional as well
  (`mandatory = False`), because a Linux or macOS target must not need hermetic-launcher's
  toolchains. On a Windows target, either hermetic-launcher type resolving to `None` fails
  analysis in English naming the type (R1). The embedded-argument limit applies to Windows
  targets only.
- **Alternatives**:
  - Keep the stub on Linux and macOS: G-impl-1 stays open, and Revision 13 decided otherwise.
  - Export `BUN_RUNTIME_TRANSPILER_CACHE_PATH=0` in the shell launcher: it would remove the
    first-process cache entry on Linux and macOS, but Revision 13 keeps that FR-018a limitation,
    so it is left for a spec revision.
  - Wrap the program in rules_shell's `sh_binary`: the target would be an `sh_binary`, not a
    `bun_binary`, and its script would still need the target's Bun and launch configuration.
    rules_python's template is the pattern for a rule-generated launcher.

#### 5. Lowest versions (constitution IV)

- **`rules_shell` 0.6.1, non-dev**: `shell/runfiles` exists from tag `v0.3.0` (absent at
  `v0.2.0`). But Bazel 9.2.0's `MODULE.tools` requires 0.6.1 (BZ-moduletools), and `bazel_tools`
  takes part in every module's resolution. Observed: `bazel mod explain rules_shell
  --include_builtin` lists `bazel_tools@_` with `rules_shell@0.6.1` below it. Every consumer within
  `bazel_compatibility = [">=9.2.0"]` therefore resolves 0.6.1 or later, so no lower version can
  run or be tested by `e2e/smoke`. 0.6.1 is the lowest version the ruleset works with, and
  declaring it adds nothing to what consumers resolve. The library's documentation (item 1) is
  read at 0.6.1.
- **`bazel_skylib` 1.9.0, non-dev**, for `shell.quote`. It replaces the dev 1.9.2 declaration;
  the root still resolves 1.9.2 through `bazel_skylib_gazelle_plugin`. `hermetic_launcher` 0.0.16
  already requires 1.9.0 (R1), so consumers resolve 1.9.0 or later and no lower version can be
  tested. `shell.quote` at 1.9.0 is SKY-shell.
- `e2e/smoke`'s lock file is refreshed; it must pass with exactly these versions.

#### 6. Consequences carried into the plan

- G-impl-1 is resolved by design (item 3). Its canary (T100) and upstream report (T101) are not
  needed. Quickstart rows 2a, 10 and 13 expect passes and verify the resolution, together with a
  `bazel test --spawn_strategy=local --noenable_runfiles` row.
- G4 and the first-process `bunfig.toml` limitation of FR-018a apply to Windows only. Canary C4
  still runs on every OS, because it pins Bun's behavior, not the stub's; the workaround it names
  is the Windows limitation.
- G1 and canary C7 stay Windows only.
- The no-stub analysis test needs a Windows platform without a template toolchain. A FreeBSD
  platform now gets the shell launcher and analyzes. hermetic-launcher 0.0.16 registers a Windows
  template only for x86_64 (HL-toolchains), so a Windows platform on another CPU, with a Bun the
  test registers, serves.
- **Open, for the spec owner (O-13)**: Revision 13 restates FR-001 only. FR-022 ("MUST NOT …
  write shell scripts or shell launchers") and SC-005 ("Zero shell scripts, shell launchers …")
  still contradict the restated FR-001 and constitution v2.0.0 VI. `speckit-analyze` treats a
  conflict with a MUST principle as critical (constitution, Governance), so they need a spec
  revision before implementation. This plan does not restate them.

## Part 2 — Decisions

Design after spec Revisions 5–10: every `bun_binary`/`bun_test` copies what it uses into its own
tree (R6), Bun runs only those copies, and a load guard rejects any other file Bun would load
(R13). R6 of the earlier plan ("sources read from the source tree") is superseded.

### R1. Launcher: shell launcher (Linux, macOS) or hermetic-launcher stub (Windows) → JavaScript launcher → second Bun (FR-001)

- **Revision 13 (2026-10-17)**: on a target platform without `@platforms//os:windows`, the
  executable is the generated shell launcher of Part 1 "Plan for spec Revision 13", item 4. It
  uses the Bash runfiles library of `rules_shell` 0.6.1 and follows rules_python's
  `interpreter_binary`, and it execs Bun with `--config=<isolated_bunfig.toml>`, `--no-env-file`,
  `launcher.js` and `<name>.launch.json`. The rest of this section is the Windows launcher. Both
  hermetic-launcher toolchain types are optional, and on a Windows target an unresolved one fails
  analysis as described below.
- **Decision (Windows)**: `bazel_dep(name = "hermetic_launcher", version = "0.0.16")` (non-dev). The
  executable is a stub built with `launcher.compile_stub(..., cfg = "target")` from
  `@hermetic_launcher//launcher:lib.bzl`. The rules declare `launcher.finalizer_toolchain_type`
  (execution platform), `launcher.template_toolchain_type` and `//bun/toolchain:target_type` as
  optional toolchains (`config_common.toolchain_type(..., mandatory = False)`; the finalizer was
  mandatory before Revision 13). When the Bun toolchain resolves to `None` on any target, or a
  hermetic-launcher toolchain does on a Windows target, the implementation calls `fail()` with an
  English message naming the toolchain type and the target platform. So a target platform with no
  Bun, or a Windows one with no stub, fails analysis (no shell fallback on Windows).
  BZ-toolchains "Optional toolchains": "When an optional toolchain type cannot be resolved,
  analysis continues, and the result of `ctx.toolchains[…]` is `None`". Why not mandatory:
  observed with Bazel 9.2.0 (scratch module, 2026-10-04), an unresolved mandatory toolchain aborts
  analysis ("No matching toolchains found … Analysis failed") before the rule runs, so a
  bazel-skylib `analysistest` with `expect_failure = True` cannot observe it (spec Assumption on
  US4-4); with the optional type and `fail()`, the same `analysistest` passed. Embedded
  arguments: `[bun (runfile), "--no-env-file", launcher.js (runfile), <name>.launch.json
  (runfile)]`, 4 of 10. On a Windows target, the rule fails analysis in English when an embedded
  argument exceeds 256 bytes (HL-readme limit). On Windows the output is named `<name>.exe` (RJS
  does the same: Windows dispatches on the extension). Both the extension and the choice between
  stub and shell launcher are made with `ctx.target_platform_has_constraint` (BZ-ctx) against
  `@platforms//os:windows`.
- **One static file, two roles**: `bun/private/launcher.js` is the launcher when it is Bun's main
  module (`import.meta.main`) and the load guard (R13) when the second process preloads it. Both
  roles resolve runfiles the same way, and a single file needs no relative import between rule
  files, which would rely on the layout of `rules_bun`'s source tree (the reliance Revision 5
  removed).
- **Rationale**: HL-readme documents runfiles resolution from a tree and from a manifest, Linux,
  macOS and Windows, and stubs for any target platform from any host (byte patching). The template
  toolchain is matched by `target_compatible_with` and the finalizer by `exec_compatible_with`
  (HL-src `toolchains.bzl`), so the stub follows the target platform. The stub exports
  `RUNFILES_DIR` or `RUNFILES_MANIFEST_FILE` (only the source it selected) to the child.
- **Lowest version**: 0.0.16. 0.0.15 lacks 317d4a8 "fix(macos): declare rdx clobbered by the
  syscall trap" (`git log v0.0.15..v0.0.16`); hermeticbuild/hermetic-launcher#79 asked for the
  release that contains it. 0.0.16 declares `bazel_skylib` 1.9.0 and `platforms` 1.1.0, so
  consumers resolve `platforms` ≥ 1.1.0 (constitution IV allows it; `e2e/smoke` must pass with it).
- **Reference rulesets**: RJS uses hermetic_launcher 0.0.16 for `js_binary` behind
  `--@aspect_rules_js//js:use_hermetic_launcher`, documented as "an experimental alternative, off
  by default" (RJS `docs/hermetic_launcher.md`); its stub embeds node, node options, the generated
  `.cjs` and a preload (RJS `js_binary.bzl` `_js_launcher`). Where no stub toolchain resolves,
  RJS writes a shell placeholder. On a Windows target this ruleset fails analysis instead (FR-001,
  constitution VI); on Linux and macOS it writes its shell launcher (Revision 13).
  rules_python and rules_go launch through Bazel's native Windows launcher or a compiled binary;
  neither offers a shell-free launcher for an interpreted program, which is why the user approved
  hermetic-launcher (constitution V, 2026-10-01).
- **Approval**: constitution v1.2.0 V named hermeticbuild/hermetic-launcher, approved 2026-10-01;
  since v2.0.0 it is the Windows launcher only.
- **Decided limitation**: argument fidelity on Windows (G1, hermetic-launcher#80).

### R2. Second process (FR-001 step 3, FR-015)

- **Decision**: the launcher starts `process.execPath` (the toolchain's Bun that the shell
  launcher or the stub started) with
  `Bun.spawn`, `stdio: ["inherit", "inherit", "inherit"]`, waits, and exits with the child's exit
  code; when the child ends by a signal it exits with `128 + n` (the POSIX shell convention,
  recorded as unverified on Windows). Every file path it passes is the real path
  (`fs.realpathSync`) of the runfile it resolved, which is a copy in the per-target tree (R6).
  - `bun_binary`: `[--config=<bunfig>, --no-env-file, --no-install, --preload=<launcher.js>,
    <entry point>, ...program args]`, in the launcher's working directory. Nothing is inserted;
    when the first program argument is `--`, the launcher exits 1 with an English error naming
    it, because Bun 1.4.2 drops one `--` directly after the entry point (Revision 10, G13
    withdrawn; pinned by a test).
  - `bun_test`: R8; the working directory is the copy-tree root (Revision 10).
  - Environment: the parent's, minus `BUN_OPTIONS`, plus `BUN_RUNTIME_TRANSPILER_CACHE_PATH=0`
    (R7) and `RULES_BUN_LAUNCH_CONFIG=<real path of launch.json>`, the guard's configuration,
    which the guard reads and never deletes (R13, Revision 9).
- **Declared-file limit** (Revision 9): before `Bun.spawn`, the launcher builds the guard's
  pattern (R13) and exits 1 with an English error naming the target, the declared-file count and
  the limit when the pattern is longer than 1,048,576 characters, the limit measured on Bun 1.4.2
  (Part 1, "Plan review for spec Revision 9").
- **Command-line length** (Revisions 8, 9): before `Bun.spawn`, the launcher computes the length
  of the command line it hands to the running OS: on Windows the WIN-argv-quoted arguments joined by
  spaces plus the terminating null, on Linux and macOS the unquoted arguments joined by spaces plus
  the terminating null (UTF-16 code units). Above 32,767 characters (WIN-create) it exits 1 with an
  English error naming the length and the limit, on every OS. A `bun_test` with many test files
  under a deep output base is the likely case.
- **Observed** (2026-10-03): the entry is the main module (`import.meta.main` true) and
  `process.argv.slice(2)` is the program's arguments (`["a","","b c"]` came through unchanged on
  Linux). A preload does not change that; `--preload` is documented by BUN-run ("Import a module
  before Bun loads other modules").
- **Rationale**: the stub cannot set environment variables (hermetic-launcher #78, open), so on
  Windows `BUN_OPTIONS` removal, the transpiler-cache setting and the guard are possible only in a
  child process. The shell launcher could set variables, but Linux and macOS keep the same chain,
  so that one `launcher.js` serves every OS (FR-001, Revision 13).

### R3. Toolchain resolved for the target platform (FR-002, FR-009, FR-010)

- **Decision**: new `toolchain_type(name = "target_type")` in `//bun/toolchain`, and a new public
  rule `bun_target_toolchain` (`bun/toolchain.bzl`) whose `bun` attribute omits `cfg` (target, the
  default). It returns `platform_common.ToolchainInfo(buninfo = BunInfo(...))`, the same provider
  as `bun_toolchain`. Each `bun_<platform>` repository adds a `bun_target_toolchain` target, and
  `bun_toolchains` adds one `toolchain()` per platform with `target_compatible_with` set to that
  platform's constraints and no `exec_compatible_with`. `bun_toolchain`, `execution_type` and
  their toolchains are unchanged.
- **Rationale**: BZ-toolchains: dependencies with `cfg = "target"` "are built for the parent's
  target platform … intended to be linked into or shipped with the final output". RPY declares
  its runtime toolchain type with `target_compatible_with` and `exec_compatible_with = []`
  (`py_toolchain_suite.bzl` lines 66–67, 81–84), and the `py_runtime` interpreter attribute has
  no `cfg` (`py_runtime_rule.bzl` line 328); its exec tools are a separate type matched by
  `exec_compatible_with` (line 114). Registration stays with the consumer's existing
  `register_toolchains("@bun_toolchains//:all")`.
- **Alternatives**: one rule with two attributes, or `cfg` chosen per instance — not expressible
  (a `cfg` is fixed per attribute); reusing `execution_type` for runtime — wrong platform (spec
  "Today the ruleset…").

### R4. Library rule and provider (FR-006)

- **Decision**: add `bun_library(srcs, data, deps)` and provider `BunLibraryInfo(srcs:
  depset[File], data: depset[File])`: the transitive TypeScript/JavaScript sources, and the
  transitive files of `data` targets (their `DefaultInfo.files`), which a `bun_binary` or
  `bun_test` copies into its tree (R6). `deps` of all three rules require `BunLibraryInfo`;
  `data` accepts any target. All three return `DefaultInfo(runfiles = …)` that merges the
  `default_runfiles` of `data` and `deps` uncopied (RJS-data), so a data target's own runfiles
  (for example another executable's) keep their layout.
- **Rationale**: RPY `py_library`/`PyInfo` and RJS `js_library`/`JsInfo` carry sources between
  targets through a provider. The binary needs to tell sources from data to copy both, which
  runfiles alone cannot. Restricting `deps` now keeps it additive later: npm packages and
  bundling (later features) extend the provider, and narrowing an unrestricted `deps` afterwards
  would break consumers.
- **Alternative**: `filegroup` in `deps` — leaves no provider to tell sources from data.

### R5. Locating files at run time: runfiles (FR-011, FR-012)

- **Decision**: the launcher reads `RUNFILES_MANIFEST_FILE`, or else `RUNFILES_DIR`. On Windows
  the stub exports the one it selected; on Linux and macOS the shell launcher exports both
  whenever both can be derived (`runfiles_export_envvars`, Part 1 "Plan for spec Revision 13",
  item 3). It resolves rlocation paths as Bazel's runfiles libraries do: a manifest line
  starting with a space is escaped (`\s`, `\n`, `\b` in the link; `\n`, `\b` in the target) per
  BZ-manifest; RPY `runfiles.py` `_LoadRunfiles` is the bazel-contrib reference implementation.
  All paths in `launch.json` are rlocation paths (`_main/…` or `<canonical repo>/…`, as HL-src
  `_to_rlocation_path` does), which need no repository mapping. The program and the test see
  `RUNFILES_DIR`/`RUNFILES_MANIFEST_FILE` unchanged.
- **Locating data (FR-012, Revision 8)**: programs and tests locate their data relative to
  `import.meta.dir` (BUN-meta). Bun runs the copies by real path (R6), and each data copy sits at
  `<name>.bun/<rlocation path>` beside the source copies, so `join(import.meta.dir, "<relative
  path>")` reads the declared data file with a runfiles tree and with a manifest only. This is the
  mechanism for both rules, and the only one for `bun_test`, whose arguments must be options
  (FR-013). For a file of another repository the relative path contains that repository's
  canonical name, which Bazel does not keep stable (BZ-repomap); `bun_binary` can instead pass
  `$(rlocationpath …)` in `args` and resolve it through `RUNFILES_DIR`/`RUNFILES_MANIFEST_FILE`
  as Bazel's runfiles libraries do (RPY). The original data files stay in runfiles next to their
  copies for that use; they are not in the guard's declared set (R13), because FR-003 requires
  Bun to run the copies, so a module imported through an original's path fails. No public
  JavaScript helper is added (it would need npm packaging or a new public file; FR-012).
- **Manifest-only**: `--enable_runfiles` defaults to off on Windows (BZ-flags). The manifest maps
  each copy's rlocation path to its path in the output tree, where the copies sit in the same
  relative layout (R6), so imports between copies resolve as with a runfiles tree. RJS handles
  that case by setting `JS_BINARY__NO_RUNFILES` and running from the execroot output tree
  (`js_binary.bzl` line 526, `js_binary.cjs.tpl` lines 168–172), a rules_js-only pattern not used
  here.

### R6. Per-target copy tree (FR-003; G6, G10–G12)

- **Decision**: at analysis, each `bun_binary`/`bun_test` collects its entry point or test files,
  `srcs`, `preload`, the `srcs` and `data` of `BunLibraryInfo` from `deps`, and the files of its
  own `data` targets, dedupes them by rlocation path, and for each declares
  `<name>.bun/<rlocation path>` with `ctx.actions.declare_file` and copies it there with
  `copy_file_action(ctx, src, dst)` from `@bazel_lib//lib:copy_file.bzl` (BL-copy), declaring
  `toolchains = COPY_FILE_TOOLCHAINS`. The copies, not the originals, go to `launch.json` and are
  what Bun runs. The copies are in the target's runfiles, so the entry point and preloads are too
  (Revision 5).
- **The tree's root** (Revision 11): every copy is under a repository directory (`_main/…`,
  `<canonical name>/…`), so the root of the tree holds no file. The root is the working directory
  of a `bun_test`'s second process (R8). The rule's `isolated_bunfig.toml` is not copied into the
  tree (Revision 10 copied it to the root); a `bun_binary` passes the real path of the static file
  in its runfiles (R7).
- **Sources**: BL-copy: `copy_file_action` "is exposed as a public API so it can be used within
  other rule implementations"; it runs the coreutils toolchain's `cp` with `ctx.actions.run`,
  "no shell is required"; bazel-lib registers that toolchain in its own `MODULE.bazel`.
  BZ-ctx: `declare_file` paths are relative to the current package; BZ-outdirs: outputs of package
  `foo/bar` are under `bazel-out/<config>/bin/foo/bar/`. So the copies keep, inside
  `<name>.bun/`, the relative layout of their rlocation paths, and the runfiles tree mirrors the
  same layout under `<repo>/<package>/<name>.bun/`. Relative imports between copies resolve the
  same way whether Bun reads the runfiles path or the real path (Bun 1.4.2 reads real paths,
  observed 2026-10-03).
- **Path**: `<rlocation path>`, not `File.short_path`: for another repository's file
  `short_path` starts with `../`, which put the copy outside the tree (observed; "Findings for
  the re-plan").
- **Directories in `data`** (G12, decided 2026-10-05): a TreeArtifact among the files to copy
  (`File.is_directory`) fails analysis in English naming `data` and the directory; documented as
  unsupported.
- **Reference rulesets**: RJS copies source files to the shared `bin` tree of their package
  (`copy_to_bin`, RJS-data); the per-target tree is this design's choice (G6), so a file another
  target of the package copied is not a sibling. Cost: one copy per file per target.
- **Lowest `bazel_lib`** (constitution IV): `bazel_lib` becomes a non-dev dependency, replacing
  the dev one (3.7.2); `3.0.0` is the lowest stable candidate, and before `3.5.0` the action's
  toolchain label resolves in the consumer's repository mapping (BL-history), which may fail for
  `e2e/smoke`. The version is fixed by running the root and `e2e/smoke` test sets from `3.0.0`
  upward and recording each failure, once the rules, their tests and the `e2e/smoke` targets
  exist (Polish), because only they exercise `copy_file_action` from a consumer. It adds `bazel_features` and `rules_shell` to
  what consumers resolve ("Findings for the re-plan").

### R7. Isolation of the second process (FR-018, FR-018a, FR-019)

- **Decision**: static file `bun/private/isolated_bunfig.toml` with `env = false` and
  `[install] auto = "disable"` (BUN-bunfig), not copied (R6). It is in the runfiles of every
  `bun_binary`, and on Linux and macOS of every `bun_test` too, because the shell launcher passes
  it to the first process as `--config=<path>` (Revision 13). `bun_binary` passes its real path as `--config=<real path>` (the `=` form; G4) and adds
  `--no-env-file` (BUN-env) and `--no-install` (BUN-run). `bun_test` passes no configuration
  option, because bun.com documents none for `bun test` and no lookup rule (BUN-45331): its second
  process runs with the copy-tree root, which holds only declared files and no `bunfig.toml`, as
  its working directory, and the rules claim nothing about where Bun looks (Part 1 "Plan for spec
  Revision 11", item 1). The launcher deletes
  `BUN_OPTIONS` from the child environment and sets `BUN_RUNTIME_TRANSPILER_CACHE_PATH=0`
  (BUN-env table: "Prepends command-line arguments to any Bun execution"; "set to an empty string
  or the string "0", caching is disabled"). Before starting the child, the launcher exits with an
  English error when `BUN_OPTIONS` is set (FR-018a). Not delivered through `RunEnvironmentInfo`.
- **Decided limitations**: on Windows the first process may read `$cwd/bunfig.toml` (G4, FR-018a;
  on Linux and macOS it gets `--config=`, Revision 13). On every OS it may write a
  transpiler-cache entry for the launcher (FR-018a). Whether `bun test` searches the parent
  directories of the copy-tree root for `bunfig.toml` or `.env` is undocumented and unverified
  (Revision 11); those directories include `execroot/_main`, which links every top-level entry of
  the main repository, so a workspace-root `bunfig.toml` or `.env` is within reach if it does. The
  `e2e/smoke` root fixture records the result per OS (Revision 12, Part 1 "Plan for spec Revision
  12", item 2).
- **Observed**: `bun <file>` and `bun test <file>` without `--config=` run the `preload` of
  `$cwd/bunfig.toml` and load `$cwd/.env`; with it, neither happens. Only `--config=<path>` works
  (G4). `bun test` run in a directory whose `bunfig.toml` sets `env = false` does not load that
  directory's `.env` (2026-10-08). These are observations; for `bun test` none is relied on
  (Revision 11).

### R8. Test protocol (FR-016, FR-016a)

| Bazel (BZ-encyclopedia, BZ-coverage) | Bun option (source) | Observed |
|---|---|---|
| `TESTBRIDGE_TEST_ONLY` | `--test-name-pattern=<value>` (BUN-testcli; describe labels joined by spaces, BUN-discovery); with `TEST_TOTAL_SHARDS` > 1 an English error instead (Revision 10) | `-t "Math ops adds"` selects the nested test; a pattern matching nothing exits 1 |
| `TEST_TOTAL_SHARDS`, `TEST_SHARD_INDEX` (zero-based) | `--shard=<index+1>/<total>` (BUN-parallel: one-based, files sorted by path, file `i` → shard `(i mod n)+1`) | a shard with no file exits 0 ("running 0/1 test file"); `--shard=0/2` exits 1 |
| `TEST_SHARD_STATUS_FILE` | launcher creates or touches it (RGO `generate_test_main.go` lines 136–142 does the same) | — |
| `XML_OUTPUT_FILE` | `--reporter=junit --reporter-outfile=<file>` (BUN-reporters) | nested `<testsuite>` per `describe`, `<testcase name=… >` per test |
| `COVERAGE_DIR` | `--coverage --coverage-reporter=lcov --coverage-dir=<dir under TEST_TMPDIR>` (BUN-coverage, BUN-testcli), then `$COVERAGE_DIR/bunlcov_<uuid>.dat` (RPY-cov; G7 re-based) | writes `lcov.info`; `SF:` paths relative to the working directory at the time Bun writes the report (2026-10-15); not relied on: each value must match exactly one declared copy (G15, Revision 12) |

- **Command**: `[test, --preload=<launcher.js>, <protocol options>, --preload=<copy> per preload,
  ...args, ./<tree path> per test file]`, started with the copy-tree root as its working
  directory, which holds no `bunfig.toml` (R7; Revisions 10–11). The guard is the first preload,
  so the consumer's preloads load after it (R13). The command-line length check of R2 applies.
- **Filter** (Revision 10, G8 withdrawn): `TESTBRIDGE_TEST_ONLY` becomes `--test-name-pattern=`;
  no undocumented option is added, so a filter that selects nothing fails with Bun's exit code 1.
  When `TEST_TOTAL_SHARDS` is greater than 1 as well, the launcher exits 1 with an English error
  that filtering a sharded `bun_test` is not supported, before touching the shard status file or
  starting the second process. A shard that gets no file exits 0 (observed); a test pins it
  (FR-016).
- **Coverage** (G7, re-based on RPY-cov by Revision 10): `bun_test` declares
  `_lcov_merger` (`configuration_field(fragment = "coverage", name = "output_generator")`,
  `cfg = config.exec(exec_group = "test")`) and returns
  `coverage_common.instrumented_files_info(ctx, source_attributes = ["srcs"],
  dependency_attributes = ["deps", "data"])`; `bun_library` returns the same with its own `srcs`
  (BZ-coverage). After the child exits, the launcher reads `lcov.info` as LCOV (LCOV-format) and
  matches each `SF:` value against the declared copies (G15, Revision 12): the value joined to the
  copy-tree root and, when absolute, the value itself, compared with the copies' real paths. The
  launcher's own record (Bun reports the guard file, observed 2026-10-04 and 2026-10-15) is
  removed by the same comparison with its own real path. Exactly one matching copy: the value is
  rewritten to the original's `File.path` (from `launch.json`). No copy or several: no `.dat` file
  is written and the launcher exits 1 with an English error naming the value. Otherwise it writes
  the result to `$COVERAGE_DIR/bunlcov_<crypto.randomUUID()>.dat` (BUN-webapis), the
  `<prefix>_<unique>.dat` name RPY-cov writes. That the merged report names the source is verified
  by the CI coverage check (FR-016a). `_collect_cc_coverage` is not declared. Under `bazel test`
  on every OS, a spawn test sets `COVERAGE_DIR` for a `manual` `bun_test` and checks that the one
  `bunlcov_*.dat` file names the source by its `File.path`; a second one, whose test changes its
  working directory, checks the English error and that no `.dat` file is written (G15).
- **Reading the merged report** (Revision 5): `bazel coverage --combined_report=lcov` writes
  `$(bazel info output_path)/_coverage/_coverage_report.dat` (BZ-covcmd). A CI step runs a checking
  `bun_binary` with `bazel run … -- bazel-out/_coverage/_coverage_report.dat`, resolved against
  `BUILD_WORKING_DIRECTORY` (BZ-outdirs documents the `bazel-out` symlink), so the report is a
  command-line path, never a cached input.
- **Test files on the command line** (Revision 10): BUN-discovery: a path must start with `./` or
  `/` to be a file rather than a filter. The launcher passes `./` followed by each test copy's
  tree path (its path inside the copy tree, equal to the original's rlocation path), relative to
  the copy-tree root that is the working directory, so every test file is addressable on every OS
  and drive (the G9 limitation is removed).
- **Arguments** (FR-013, Revision 9): an allowlist. Each `bun_test` argument must equal one of
  these forms exactly; anything else — a positional argument, a bare `--`, any short option
  (including attached and combined forms such as `-talpha`, `-uts`, `-r./x.ts`), a documented
  option not listed, an undocumented one — fails with an English error naming the argument:

  | Form | Source |
  |---|---|
  | `--timeout=<n>`, `--rerun-each=<n>`, `--retry=<n>`, `--concurrent`, `--randomize`, `--seed=<n>`, `--bail`, `--bail=<n>`, `--max-concurrency=<n>`, `--todo` | BUN-testcli |
  | `--isolate` | BUN-parallel ("re-runs `--preload` scripts in the new global", so every file is guarded) |
  | `--smol`, `--conditions=<value>`, `--prefer-offline`, `--frozen-lockfile` | BUN-testruntime |

  Documented for `bun test` and not on the list, because each undoes a guarantee: `-t`/
  `--test-name-pattern`, `--reporter`, `--reporter-outfile`, `--dots`, `--coverage`,
  `--coverage-reporter`, `--coverage-dir`, `--shard` (owned by FR-016, FR-016a); `-u`/
  `--update-snapshots` (FR-016b); `--env-file`, `--preload` (FR-018, FR-016c: preloads are
  declared inputs); `--tsconfig-override`, `--timings`, `--update-timings` (read or write a file the
  target does not declare); `--parallel`, `--no-isolate`, `--parallel-delay` (worker processes,
  for which BUN-parallel does not document that `--config` is forwarded, FR-018); `--watch`,
  `--hot` (never exit; spec boundary "watch mode"); `--inspect`, `--inspect-brk` (spec boundary
  "debugging"; `--inspect-brk` waits for a debugger, so no test under `bazel test` can show it
  working, FR-017). Positional arguments are file filters (FR-007). A test runs a passing `manual`
  `bun_test` once with each allowed form and pins each rejection class.
- **Preloads** (FR-016c): `bun_test(preload = [...])`, copied (R6) and passed as
  `--preload=<copy>` after the guard (BUN-testruntime "Runs scripts before test files").
- **Snapshots** (FR-016b, G2): not supported; documented.

### R9. Environment (FR-014)

- **Decision**: `env` (string dict) and, on `bun_test`, `env_inherit` (string list), returned as
  `RunEnvironmentInfo(environment = …, inherited_environment = …)`. Values are taken literally
  (spec Revision 15, T121): until T121 they got `ctx.expand_location(value, targets = data + deps +
  srcs)`, which BZ-ctxapi documents for `$(location …)` and `$(locations …)`, but the expanded
  path does not resolve from the copy tree or without a runfiles tree, so the expansion was
  removed. Data is located through `import.meta.dir` (FR-012); `$(rlocationpath …)` is offered in
  `args` only, which Bazel expands itself (BZ-common; Revision 5).
- **Rationale**: BZ-common: `env`/`env_inherit` "do not apply to Starlark-defined test rules … you
  can add an "env" attribute and use it to populate a RunEnvironmentInfo Provider". Make-variable
  substitution is not offered: `ctx.expand_make_variables` is "Deprecated" (BZ-ctx), so
  constitution V forbids it. BZ-runenv: "If a variable is contained in both `environment` and
  `inherited_environment`, the value inherited from the shell environment will take precedence if
  set."
- **Inherited and set** (Revision 5): a `manual` `bun_test` with `env_inherit` is run by a CI step
  whose `env:` sets the variable; Bazel takes `inherited_environment` values from the client
  environment (BZ-runenv).

### R10. Arguments (FR-013)

- **Decision**: the rules do not handle `args`: Bazel substitutes and tokenizes them and passes
  them before `bazel run` arguments or `--test_arg` values (BZ-common). The shell launcher passes
  them as `"$@"` after its own arguments, and the stub appends them after its embedded arguments
  (HL-readme). Either way, the launcher receives them as `process.argv.slice(3)`.
  `bun_test` checks them against the allowlist of R8 (Revision 9).

### R11. CI (FR-024)

- **Decision**: the existing matrix (ubuntu, macos, windows × root, `e2e/smoke`) gains `bazel run`
  of the self-checking program after `bazel test //...`. One Linux job repeats root and
  `e2e/smoke`, including the `bazel run` step, with `--noenable_runfiles` (FR-024, Revision 10).
  One Linux job runs `bazel coverage --combined_report=lcov` on one `bun_test` and then the
  checking `bun_binary` (R8). One step per OS runs the `env_inherit` test with the variable set (R9). One
  Windows job runs the root and `e2e/smoke` test sets and the `bazel run` step with
  `bazel --output_user_root="C:/bazel root"` (BZ-startup), so runfiles paths contain a space
  (Revision 9). Workflow steps call only `bazel` (constitution VI).

### R12. Test strategy (FR-020, FR-021)

- `analysistest` (bazel-skylib) for providers, `RunEnvironmentInfo`, the copies and their paths,
  the Bun selected per target platform (five literal platforms in `bun/tests/platforms`), the
  target configuration of a generated Bun, and analysis failures (`expect_failure = True`).
- Revision 5 cases: a test-only rule with a `cfg = "exec"` attribute on a `bun_binary` shows the
  executable carries the execution platform's Bun; a test-only Windows platform with a registered
  `bun_target_toolchain` but no hermetic-launcher template toolchain fails analysis (Windows since
  Revision 13; a non-Windows platform gets the shell launcher).
- Revision 13 cases: analysis tests show that a Linux or macOS target's executable is the expanded
  shell launcher and that its runfiles hold `bazel_tools/tools/bash/runfiles/runfiles.bash` and
  `isolated_bunfig.toml`, while a Windows target's executable is the `.exe` stub. Real runs:
  `bazel run --noenable_runfiles` and `bazel test --spawn_strategy=local --noenable_runfiles`
  pass on Linux (red: today's "execve failed" of G-impl-1). The isolation spawn test also asserts
  that the `preload` of `$cwd/bunfig.toml` does not run in the first process on Linux and macOS
  (red: the stub's first process runs it, G4). On Windows that assertion is not made, because the
  FR-018a limitation applies there.
- Real runs: `bun_test` targets under `bazel test //...`; expected failures are `manual` targets
  run by a passing `bun_test` that resolves their launcher through runfiles and starts it with
  `Bun.spawn`, removing the test-protocol variables FR-021 lists and keeping the runfiles
  variables. Isolation fixtures are written under `TEST_TMPDIR` by that test; load-guard
  fixtures are outputs of a test-only rule (R13).
- The local registry for US3-3 is a `Bun.serve` server in the spawning test (no network).
- Revision 8 fixtures, each a spawn test of a `manual` target: standard input written by the
  spawning test is echoed by the program (FR-015); `BUN_OPTIONS` set makes the launcher exit 1
  with its English error before the program runs (FR-018a); with
  `BUN_RUNTIME_TRANSPILER_CACHE_PATH` pointing at an empty directory and `BUN_INSPECT_CONNECT_TO`
  removed, a program whose declared source is larger than 4 KB prints the variable as `0` and the
  directory holds no more `.pile` files than after a run of a one-line program (the first
  process may cache the launcher, FR-018a) (FR-018, BUN-cache); a source, a data file and a test
  file whose names contain a space are imported, read and run, with a runfiles tree and with a
  manifest only (spec Edge Cases; the manifest escaping of BZ-manifest, formerly canary C15); a
  program receives `--config=z` as its first argument unchanged and fails with the launcher's
  English error when its first argument is `--` (Revision 10); a `manual` `bun_test` whose 400
  generated test files with 90-character base names give a command line over 32,767 characters
  on every OS fails with the launcher's English error (R2, Revision 9).
- Revision 9 fixtures: a `manual` `bun_binary` exiting 3 is spawned and the exit code is 3
  (US1-1); the describe-label filter (FR-016); the allowlist (R8); the guard's fail-closed
  configuration (R13); the declared-file limit with 22,000 data files (R13); the Windows CI job with
  an output root containing a space (R11); the canaries of FR-028 (data-model "Upstream
  canaries").
- Revision 10 fixtures: a filter that selects nothing fails; `TESTBRIDGE_TEST_ONLY` with
  `TEST_TOTAL_SHARDS=2` fails with the English error and runs no test; a shard with no file passes
  (formerly canary C14); a `bun_test` sees the copy-tree root as `process.cwd()` and does not load a
  `.env` placed there by a test-only rule.
- Revision 12 fixtures: the coverage spawn test whose test changes its working directory fails with
  the G15 error and writes no `.dat` file; `e2e/smoke`'s `bun_test` asserts that a root
  `bunfig.toml` preload and a root `.env`, declared by no target, take no effect (result recorded
  per OS; a failure is a gap, Part 1 "Plan for spec Revision 12").
- Red order (FR-020, Revisions 8–10): the launcher starts without exit-code propagation, isolation
  options, copy tree, guard, leading-`--` rejection, sharded-filter rejection, `BUN_OPTIONS`
  check, allowlist, declared-file limit or length check; each is added only after its test has run red against the launcher without it. A
  guard test of behavior that already existed records a reverted mutation instead. A canary's red
  is a mutation of its pinned expectation, recorded and reverted (Revision 9).

### R13. Load guard (spec Revision 7; G10, G11)

- **Decision**: the second process preloads `launcher.js` first (R2, R8). In that role it reads
  the configuration file named by `RULES_BUN_LAUNCH_CONFIG` (`launch.json`), never deleting the
  variable or the file (Revision 9), resolves through runfiles (R5) the real path of every copy in
  the target's tree (only the copies: FR-003), and registers with `Bun.plugin` one
  `onLoad({ filter, namespace: "file" })`. `filter` is a regular expression that matches any path
  except the declared paths: a negative lookahead, anchored at both ends, over the declared paths
  built as a prefix trie (each character escaped, shared prefixes emitted once, branches as
  non-capturing groups), because one alternation of every path exceeds Bun 1.4.2's
  regular-expression size limit (observed failing at 8,000 paths of about 160 characters,
  Revision 8; the limit is 1,048,576 pattern characters, Revision 9); the callback throws
  `Error("<label>: <path> is not declared by this target")` (wording fixed by the test). It
  never returns, so Bun's own resolution and loading are untouched for declared files.
- **Fail closed** (Revision 9): when `RULES_BUN_LAUNCH_CONFIG` is unset, the file cannot be read or
  parsed, or a declared path cannot be resolved, the guard registers an `onLoad` whose filter
  matches every path and whose callback throws an English error naming the reason, so every module
  load is rejected. A spawn test starts the toolchain's Bun with `--preload=<launcher.js>` and a
  declared entry point, once with the variable unset and once naming a missing file: both exit
  non-zero with the guard's error and the entry point does not run.
- **Declared-file limit** (Revision 9): the pattern compiles only up to 1,048,576 characters on
  Bun 1.4.2 (Part 1, "Plan review for spec Revision 9"). The trie fits more paths than one
  alternation, but not unboundedly many: the launcher checks the length before it starts the
  second process (R2) and fails in English naming the declared-file count. Tested with 22,000
  data files of 50-character random names; the limit is pinned by a canary.
- **Sources** (Revision 10: documented API only): BUN-plugins (`Bun.plugin`, `onLoad` with
  `filter` and `namespace`, default namespace `"file"`); BUN-sveltetest (an `onLoad` callback that
  throws, preloaded before the tests); BUN-onloadargs (`path` is the resolved path); BUN-bunfig
  `preload` ("register plugins by adding them to this list") and BUN-run `--preload` ("Import a
  module before Bun loads other modules"). Each guard behavior is pinned by a test on every OS
  (Revision 7). The regular-expression length limit is an observation of Bun 1.4.2, pinned by
  canary C13 (FR-028).
- **`bun test --isolate`**: BUN-parallel documents that `--isolate` "re-runs `--preload` scripts in
  the new global", so the guard registers again for every file and reads the same configuration
  file. Pinned by a test with an undeclared import in the second file.
- **Why a file, not the list in a variable**: the declared set grows with the target, and a
  Windows environment variable holds at most 32,767 characters
  (https://learn.microsoft.com/windows/win32/api/winbase/nf-winbase-setenvironmentvariable).
- **Tests** (each on Linux, macOS and Windows, and on Linux with `--noenable_runfiles`): the
  undeclared files are outputs of a test-only rule in the same package, declared at the paths a
  stale copy would have inside a `manual` target's tree (G10) and at an ancestor `package.json`
  with `"imports"`, an ancestor `node_modules` package and a file reached by a `../` climb (G11);
  a passing `bun_test` builds both (as `data`) and spawns the `manual` target. Also ESM, CommonJS,
  JSON and `bun test` imports, `bun test --isolate` with an undeclared import in its second file,
  and a consumer preload with an undeclared import. Each import passes when declared and fails,
  naming the file, when not. Large set (Revision 8): a `manual` target whose `data` holds 10,000
  files written by a test-only rule imports a declared one and fails on an undeclared one; it is
  red against a single-alternation filter ("regular expression too large") before the trie
  exists. Over the limit (Revision 9): a `manual` target with 22,000 data files fails with the
  launcher's English error naming the count; it is red before the check exists (Bun's own
  "regular expression too large" error from the preload instead). Fail closed (Revision 9): see
  above. A test-only rule writing into
  bazel-out by declared outputs avoids relying on leftovers of an earlier build.
- **Limitations, documented in the rules' `doc`** (Revision 7): modules loaded before the guard (a
  `bunfig.toml` preload of the first process, G4, Windows only since Revision 13); code the program starts itself (Workers, child
  processes, `Bun.build`); ancestor `tsconfig.json` and `package.json` influencing how a declared
  import resolves; plain file reads (`Bun.file`, `fs`); a guard error the consumer's own
  `try`/`catch` catches (for example around a dynamic `import()`), which does not fail the run
  (Revision 8, observed); JSX, which needs the `react` package that npm support (a later feature)
  provides (BUN-jsx); file types no test covers (TSX without JSX, `.node`, `.wasm`) reported as
  unverified. The guard is a check, not complete isolation; the full fix is
  Bun honoring `--preserve-symlinks` (oven-sh/bun PR #36757).

### R14. Limitations a consumer is told about

Each was approved by the user; the rules' `doc` strings list them and FR-026 forbids claiming
more:

| Limitation | Decision |
|---|---|
| Windows: arguments containing `"`, more than 128 runtime arguments | G1 (until a hermetic-launcher release fixes #80) |
| Snapshot tests unsupported | G2, FR-016b |
| Windows: the first process may read `$cwd/bunfig.toml`; every OS: it writes a transpiler-cache entry for the launcher | G4 (Windows only since Revision 13), FR-018a |
| Linux and macOS: running a target needs `/usr/bin/env`, `bash` and the utilities the Bash runfiles library calls | Revision 13 (Part 1 "Plan for spec Revision 13", item 4) |
| Ancestor `tsconfig.json`/`package.json` of the copy tree influence resolution | G6, Revision 7 |
| A filter that selects nothing fails; filtering a sharded `bun_test` fails with an English error | Revision 10 (G8 withdrawn) |
| A `bun_binary` whose first program argument is `--` fails with an English error | Revision 10 (G13 withdrawn) |
| A `bun_test`'s code runs with the copy-tree root as its working directory | Revision 10 (G3 withdrawn) |
| Where `bun test` looks for `bunfig.toml` is undocumented; whether it searches the parent directories of the copy-tree root is unverified; those include `execroot/_main`, which links every top-level entry of the main repository, so a workspace-root `bunfig.toml` or `.env` is within reach if it does (the `e2e/smoke` root fixture records each OS) | Revisions 11, 12 (oven-sh/bun#45331) |
| Under `bazel coverage`, a `bun_test` whose coverage report holds an `SF:` value that matches no declared file, or several, fails with an English error naming the value (for example after the test changes its working directory) | Revision 12 (G15) |
| `bun_test` accepts the allowlisted options and passes them unchanged; only `--timeout` and `--isolate` are tested for their effect | Revision 11 (finding U2 of 2026-10-08) |
| Guard limits listed in R13, including a caught guard error and JSX | Revision 7, Revision 8 |
| Directories in `data` fail analysis | G12 (decided 2026-10-05) |
| A second-process command line over 32,767 characters, measured as the running OS builds it, fails on every OS | Revisions 8, 9 |
| A target whose declared files make the guard pattern longer than 1,048,576 characters (Bun 1.4.2) fails, naming the count | Revision 9 |
| `bun_test` accepts only the allowlisted options of R8 | Revision 9 |
| Data of another repository has no stable path relative to `import.meta.dir` | Revision 8 (R5) |

## Part 3 — Divergences from the reference rulesets

| Topic | Reference | Here | Why |
|---|---|---|---|
| Launcher on Linux and macOS | RPY `interpreter_binary`: generated shell launcher with the Bash runfiles library; RJS: generated shell launcher by default | generated shell launcher with the Bash runfiles library (`@rules_shell//shell/runfiles`) | same pattern as RPY-interp; label from the library's own documentation (RSH-35); Revision 13 |
| No stub for a Windows target platform | RJS writes a shell placeholder | analysis fails | FR-001, constitution VI |
| Manifest-only runfiles | RJS runs from the execroot output tree (`JS_BINARY__NO_RUNFILES`) | runfiles manifest only | not a runfiles mechanism; rules_js-only pattern |
| Where copies go | RJS `copy_to_bin`: shared `bin/<package>/` | per-target `<name>.bun/` | G6: other targets' copies are not siblings |
| Which data is copied | RJS: source files only | every file of `data` targets | FR-003 |
| Undeclared files Bun would load | no reference ruleset checks | load guard (R13) | spec Revision 7 (G10, G11) |
| `env` substitution | native rules: `$(location)` and Make variables | none: values taken literally | an expanded path does not resolve from the copy tree or without a runfiles tree (Revision 15); `ctx.expand_make_variables` is deprecated |
| Working directory | RJS `chdir` attribute | not offered | spec "Proposed boundaries" |
| `bun_test` working directory | BZ-encyclopedia: tests start in `$TEST_SRCDIR/$TEST_WORKSPACE` | the launcher starts there; its second process runs at the copy-tree root | Revisions 10–11: test files are passed `./`-relative to the root (no G9 drive limit), and the root holds only declared files; bun.com documents no `bunfig.toml` lookup for `bun test` (oven-sh/bun#45331) |
| Coverage file name | RPY-cov `pylcov_<uuid4>.dat` | `bunlcov_<uuid>.dat` | same pattern, Bun naming |
| Runtime toolchain rule | RPY `py_runtime` | `bun_target_toolchain` | same pattern, Bun naming |
