# Data Model: Run Bun Programs and Bun Tests

Sources and rationale for every item are in [research.md](research.md) (Part 2, R1–R14); the
public surface is in [contracts/public-api.md](contracts/public-api.md). Every gap is decided
(research.md Part 1, G1–G15); G3, G8 and G13 are withdrawn and G7 is re-based by spec Revision 10,
carried as research.md Part 1 "Plan for spec Revision 10"; spec Revision 11 (no `bunfig.toml` in
the copy tree, canary C4 on the runtime command) is carried as "Plan for spec Revision 11"; spec
Revision 12 (G15 coverage matching, the reach of the parent-directory lookup, the `e2e/smoke`
root fixture) is carried as "Plan for spec Revision 12"; spec Revision 13 (the Linux and macOS
shell launcher, G-impl-1 resolved, G1 and G4 on Windows only) is carried as "Plan for spec
Revision 13".

## Providers

| Provider | Fields | Produced by | Consumed by |
|---|---|---|---|
| `BunInfo` (unchanged) | `bun: File`, `version: str`, `tool_files: list[File]` | `bun_toolchain`, `bun_target_toolchain` (in `ToolchainInfo.buninfo`) | rules via `ctx.toolchains[...]` |
| `BunLibraryInfo` (new, public) | `srcs: depset[File]` — transitive TypeScript/JavaScript sources; `data: depset[File]` — transitive files of `data` targets (`DefaultInfo.files`) | `bun_library`, `bun_binary`, `bun_test` | `deps` of all three |
| `DefaultInfo` | `bun_library`: `files` = `srcs`; `runfiles` = `srcs` + data files + `default_runfiles` of `data` and `deps`. Executables: `files` = the executable (the shell launcher on Linux and macOS, the stub on Windows); `runfiles` = the copies (R6) + original data files + those `default_runfiles` + Bun, `launcher.js`, `launch.json`, and `isolated_bunfig.toml` (every `bun_binary`, and every `bun_test` on Linux and macOS); on Linux and macOS also the `default_runfiles` of `@rules_shell//shell/runfiles` (`runfiles.bash` at `bazel_tools/tools/bash/runfiles/runfiles.bash`); on Windows the stub's inputs | all three rules | Bazel, `data` of others |
| `RunEnvironmentInfo` | `environment` = `env` unchanged (values taken literally, spec Revision 15); `inherited_environment` = `env_inherit` (`bun_test`) | `bun_binary`, `bun_test` | Bazel `run`/`test` |
| `InstrumentedFilesInfo` | `source_attributes = ["srcs"]`, `dependency_attributes = ["deps", "data"]` | all three rules | `bazel coverage` |

## Rules and attributes

### `bun_library`

| Attribute | Type | Rule |
|---|---|---|
| `srcs` | label list, files `.ts .tsx .mts .cts .js .jsx .mjs .cjs` | checked-in sources |
| `data` | label list, any | run-time files; a directory fails analysis naming `data` and the directory (G12) |
| `deps` | label list, `providers = [BunLibraryInfo]` | other libraries |

### `bun_binary` (executable)

All `bun_library` attributes, plus:

| Attribute | Type | Validation (analysis, English `fail`) |
|---|---|---|
| `entry_point` | label, exactly one file with an accepted extension | missing, several files, or wrong extension names `entry_point` |
| `env` | string dict | values taken literally; no substitution |
| `args` | Bazel common attribute | not read by the rule (R10) |
| implicit `_launcher`, `_bunfig` | label | `bun/private/launcher.js`, `bun/private/isolated_bunfig.toml` (passed with `--config=`, not copied; Revision 11) |
| implicit `_launcher_template` | label | `bun/private/launcher.sh.tpl`, expanded on Linux and macOS (Revision 13) |
| implicit `_bash_runfiles` | label | `@rules_shell//shell/runfiles`; its `default_runfiles` are merged on Linux and macOS (Revision 13; rules_python `interpreter_binary`) |
| implicit `_windows_constraint` | label | `@platforms//os:windows`: selects the stub and the `.exe` suffix, otherwise the shell launcher |

Toolchains: `//bun/toolchain:target_type`, `launcher.template_toolchain_type` and
`launcher.finalizer_toolchain_type` optional (`mandatory = False`). `None` for the Bun toolchain on
any target, or for a hermetic-launcher toolchain on a Windows target, gives an English `fail`
naming the type and the target platform (R1; the finalizer was mandatory before Revision 13).
Also bazel-lib's `COPY_FILE_TOOLCHAINS` (R6).

### `bun_test` (test)

All `bun_binary` attributes except `entry_point`, with `srcs` redefined. `_bunfig` is passed only to the first process on Linux and macOS (Revision 13); the second process of a `bun_test` gets no configuration file (Revision 11):

| Attribute | Type | Validation |
|---|---|---|
| `srcs` | label list, accepted extensions; **the test files**, every one is run and nothing else | empty → `fail` naming `srcs` |
| `deps` | `providers = [BunLibraryInfo]`; supporting sources | — |
| `preload` | label list, accepted extensions | — |
| `env_inherit` | string list | — |
| implicit `_lcov_merger` | `configuration_field(fragment = "coverage", name = "output_generator")`, `executable = True`, `cfg = config.exec(exec_group = "test")` | — |

Attribute naming follows `py_test` and `go_test`, where `srcs` holds the test sources; supporting
sources come through `deps` (a `bun_library`), so Bun is given exactly the files in `srcs`
(FR-007).

### `bun_target_toolchain` (new) and `bun_toolchain` (unchanged)

| Rule | `bun` attribute | Returned |
|---|---|---|
| `bun_toolchain` | `cfg = "exec"` | `ToolchainInfo(buninfo)`, `TemplateVariableInfo(BUN_BIN)`, `DefaultInfo` |
| `bun_target_toolchain` | no `cfg` (target) | `ToolchainInfo(buninfo)`, `DefaultInfo` |

## Generated repositories

| Repository | Adds |
|---|---|
| `<name>_<platform>` | `bun_target_toolchain(name = "bun_target_toolchain", bun = ":bun", version = …)` next to the existing `bun_toolchain` |
| `<name>_toolchains` | per platform `toolchain(name = "<platform>_target_toolchain", target_compatible_with = <constraints>, toolchain = "@<name>_<platform>//:bun_target_toolchain", toolchain_type = "@rules_bun//bun/toolchain:target_type")` |

## Per-target copy tree (R6)

| Item | Content |
|---|---|
| Inputs copied | `entry_point` or `srcs` (test files), own `srcs`, `preload`, `BunLibraryInfo.srcs` and `.data` of `deps`, files of own `data` targets; deduped by rlocation path |
| Output of each | `<package>/<name>.bun/<tree path>` via `ctx.actions.declare_file`, written by `copy_file_action` (bazel-lib); the tree path is the original's rlocation path |
| The tree's root | the working directory of a `bun_test`'s second process; holds no file, because every tree path begins with a repository directory; the rule writes no `bunfig.toml` into the tree (Revision 11) |
| The tree's ancestors | real path `<output_base>/execroot/_main/bazel-out/<config>/bin/<package>/<name>.bun/`: its ancestors include `execroot/_main`, which links every top-level entry of the main repository, so a workspace-root `bunfig.toml` or `.env` is within reach if `bun test` searches upward; undocumented, unverified, observed per OS by the `e2e/smoke` root fixture (Revision 12) |
| Not copied | `isolated_bunfig.toml` (a `bun_binary` passes it from runfiles); `default_runfiles` of `data` and `deps` (merged into runfiles as they are); originals of data files (kept in runfiles for `$(rlocationpath …)` reads; not declared to the guard, so importing an original fails) |
| Directory (TreeArtifact) among data | analysis fails naming `data` and the directory (G12) |
| Locating data at run time | relative to `import.meta.dir` of the importing copy: data copies keep the layout of their rlocation paths beside the source copies (research R5) |

## Launch configuration (`<name>.launch.json`, written with `ctx.actions.write`)

| Field | Content |
|---|---|
| `mode` | `"binary"` or `"test"` |
| `label` | target label, for English error messages |
| `bunfig` | rlocation path of `isolated_bunfig.toml` (`binary` only) |
| `entry_point` | rlocation path of its copy (`binary`) |
| `tests` | `[[rlocation path of the copy, tree path]]` for each file of `srcs` (`test`); a test file is passed as `./<tree path>` relative to the copy-tree root, which is the copy's real path with its tree path removed |
| `preload` | rlocation paths of the copies of `preload` (`test`) |
| `copies` | `[[rlocation path of the copy, File.path of the original]]` for every copy: the guard's declared set and the set each coverage `SF:` value must match exactly once (G15) |

The launcher passes the real path of this file to the second process in `RULES_BUN_LAUNCH_CONFIG`;
the guard reads it there and neither the variable nor the file is ever deleted (Revision 9).

## Executable (FR-001 step 1)

| Target platform | Executable | Starts |
|---|---|---|
| without `@platforms//os:windows` (Linux, macOS; Revision 13) | `<name>`, expanded from `launcher.sh.tpl` with `ctx.actions.expand_template(is_executable = True)` | `#!/usr/bin/env bash`; runfiles.bash initialization v3 (rules_shell 0.6.1, verbatim); `rlocation` of Bun, `isolated_bunfig.toml`, `launcher.js` and `<name>.launch.json`, each substituted as a `shell.quote`d canonical rlocation path (rules_python `runfiles_root_path`); a set `BUN_OPTIONS`, empty included → English error naming it, exit 1, before any Bun process (Revision 15); an empty or missing result → English error naming the path, exit 1; `runfiles_export_envvars`, then a relative `RUNFILES_DIR` or `RUNFILES_MANIFEST_FILE` made absolute against `$PWD` (Revision 15); `exec <bun> --config=<bunfig> --no-env-file <launcher.js> <launch.json> "$@"` |
| with `@platforms//os:windows` | `<name>.exe`, hermetic-launcher stub | embedded `[bun, "--no-env-file", launcher.js, <name>.launch.json]`; indices 0, 2, 3 are runfiles-resolved; each must be ≤ 256 bytes, else analysis fails naming the path |

Either way `launcher.js` sees `process.argv = [bun, launcher.js, launch.json, ...args]`.

## Launcher state machine (`launcher.js` as main module)

```text
start
 ├─ BUN_OPTIONS set? ──────────────────────────────► exit 1, English error (FR-018a)
 ├─ locate runfiles (RUNFILES_MANIFEST_FILE | RUNFILES_DIR) ─ none ─► exit 1, English error
 ├─ read launch.json; resolve each path to a real path ─ missing ─► exit 1, names the path
 ├─ guard pattern (prefix trie of the copies' real paths) > 1,048,576 characters (Bun 1.4.2)
 │    ─► exit 1, names the label, the declared-file count and the limit (Revision 9)
 ├─ mode = binary:
 │    ├─ first user arg is "--" ─► exit 1, English error naming it (Bun 1.4.2 drops it; Revision 10)
 │    └─ argv = [--config=<isolated_bunfig.toml real path>, --no-env-file, --no-install, --preload=<launcher.js>, entry, ...user args]
 │         cwd unchanged
 ├─ mode = test:
 │    ├─ user args: each must equal an allowlisted form (research R8) ─ else ─► exit 1, names it
 │    │    (positional, bare "--", every short option, unlisted options; Revision 9)
 │    ├─ TESTBRIDGE_TEST_ONLY set and TEST_TOTAL_SHARDS > 1 ─► exit 1, English error: filtering a
 │    │    sharded bun_test is not supported (Revision 10)
 │    ├─ TEST_SHARD_STATUS_FILE → touch; TEST_TOTAL_SHARDS/INDEX → --shard=i+1/n
 │    ├─ TESTBRIDGE_TEST_ONLY → --test-name-pattern=…
 │    ├─ XML_OUTPUT_FILE → --reporter=junit --reporter-outfile=…
 │    ├─ COVERAGE_DIR → --coverage --coverage-reporter=lcov --coverage-dir=<TEST_TMPDIR dir>
 │    └─ argv = [test, --preload=<launcher.js>, protocol options, --preload=<copy>…, ...user args, ./<tree path>…]
 │         cwd = copy-tree root, which holds no file (no configuration option; Revisions 10–11)
 ├─ child env = process.env − BUN_OPTIONS + BUN_RUNTIME_TRANSPILER_CACHE_PATH=0 + RULES_BUN_LAUNCH_CONFIG
 ├─ command line as the running OS builds it > 32,767 characters ─► exit 1, names length and limit
 │    (Windows: WIN-argv quoting; Linux/macOS: unquoted; every OS compares with 32,767; Revision 9)
 ├─ Bun.spawn(process.execPath, argv, stdio inherit); wait
 ├─ mode = test and COVERAGE_DIR: for each SF: value, readings = {join(copy-tree root, value),
 │    value if absolute}, normalized, compared with the real paths (G15, Revision 12):
 │    ├─ equals launcher.js's own real path ─► record removed (the rule's file, not declared)
 │    ├─ exactly one declared copy ─► value := that copy's original File.path
 │    └─ no copy or several ─► no .dat written; exit 1, English error naming the label and value
 │    then write $COVERAGE_DIR/bunlcov_<crypto.randomUUID()>.dat
 │    (rules_python's pylcov_<uuid4>.dat pattern; G7 re-based, Revision 10)
 └─ exit child code (signal n → 128 + n)
```

## Load guard (`launcher.js` as preload, R13)

```text
preload (once per process; once per test file under bun test --isolate, BUN-parallel)
 ├─ read the file named by RULES_BUN_LAUNCH_CONFIG (never deleted); resolve real paths of `copies`
 │    └─ variable unset, file unreadable or unparsable, or a path unresolvable (fail closed):
 │         Bun.plugin onLoad({filter: every path, namespace: "file"})
 │           └─ callback: throw Error naming the reason (every load rejected; Revision 9)
 ├─ filter = ^(?!(?:<declared paths as an escaped prefix trie>)$).*$
 └─ Bun.plugin onLoad({filter, namespace: "file"})
      └─ callback: throw Error naming the label and the path (never returns)
```

The trie keeps the pattern within Bun 1.4.2's limit of 1,048,576 pattern characters for longer
than one alternation of every path does (research Part 1, "Revision 8 fixes" and "Plan review for
spec Revision 9"); the launcher refuses a target whose pattern would be longer before the guard
runs. A consumer's `try`/`catch` around the import catches the error (documented limitation).

## Test fixtures

| Fixture | Kind | Covers |
|---|---|---|
| `target_toolchain_test.bzl` selection suite | analysistest × 5 platforms | US4-3, SC-007, FR-009 selection |
| target cfg test | analysistest with a generated Bun | US4-3 configuration |
| no-toolchain platform | analysistest, `expect_failure` (optional toolchain → `fail`, R1) | US4-4 |
| no-stub platform: a Windows platform with a registered `bun_target_toolchain` and no hermetic-launcher template toolchain (hermetic-launcher 0.0.16 registers a Windows template for x86_64 only) | analysistest, `expect_failure` (optional toolchain → `fail`, R1) | FR-001 (Revision 5; Windows since Revision 13) |
| launcher per platform: a Linux and a macOS target's executable is the expanded shell launcher, with `runfiles.bash` and `isolated_bunfig.toml` in its runfiles; a Windows target's executable is the `.exe` stub | analysistest | FR-001 (Revision 13) |
| manifest only without a staged tree: `bazel run --noenable_runfiles` of the self-checking programs (root, `e2e/smoke`), and `bazel test --spawn_strategy=local --noenable_runfiles` of `//bun/tests/run:skeleton_test`; red: "execve failed with code -2" with the stub (G-impl-1) | CI `manifest-only` job, local Linux runs | US4-2, SC-003, FR-024 (Revision 13) |
| exec-configured `bun_binary` | analysistest through a test-only rule with a `cfg = "exec"` attribute | spec boundary "Use as a build-action tool" (Revision 5) |
| feature 001 suites | unchanged | US4-5, FR-010 |
| `run_test.bzl` providers / `RunEnvironmentInfo` / copies | analysistest | FR-003, FR-005–FR-007, FR-014, SC-004 |
| analysis failures (entry point, no tests, long embedded path on a Windows target, directory in `data`) | analysistest, `expect_failure` | FR-007, FR-001 limit, G12 |
| self-checking program (`bun/tests/run`, `e2e/smoke/app`); reads its data relative to `import.meta.dir` | `bun_binary`, CI `bazel run` | US1-1…6, US5-2, FR-012 |
| non-zero exit | `bun_test` spawning a `manual` `bun_binary` that exits 3; asserts exit code 3 | US1-1 (Revision 9) |
| test reading its data relative to `import.meta.dir` | `bun_test` | FR-012 (`bun_test`) |
| argument spawn test, including `--config=z` as the first argument (arrives unchanged) and `--` as the first argument (exit 1, English error naming it) | `bun_test` spawning a `manual` `bun_binary` | US1-4, US1-6, FR-013, Revision 10 (Windows quotes: G1) |
| standard input | `bun_test` writing to a spawned `manual` `bun_binary`, which echoes it | FR-015 |
| command-line length | `bun_test` spawning a `manual` `bun_test` of 400 generated test files with 90-character base names (generated only as fixture input), so the names alone exceed 32,767 characters on every OS | R2, Revisions 8–9 |
| runfiles paths with spaces | source, data and test files named with a space; tree and manifest-only; under a manifest also asserts the line of `with space.txt` starts with a space and escapes it as `\s` (formerly canary C15) | spec Edge Cases, FR-011 |
| output root with a space | CI job on Windows: root and `e2e/smoke` test sets and the `bazel run` step under `bazel --output_user_root="C:/bazel root"` | spec Edge Cases, FR-011 (Revision 9) |
| passing / failing / undeclared-sibling tests | `bun_test`; failing one `manual`, spawned | US2-1…3, US3-4 |
| load guard (stale copy, climb, `"imports"`, `node_modules`, ESM/CJS/JSON, preload, `bun test --isolate`, caught error) | test-only rule placing undeclared outputs + spawned `manual` targets | G10, G11, Revisions 7–8 |
| load guard, large set | `manual` target with 10,000 data files written by a test-only rule, spawned | Revision 8 (prefix trie) |
| load guard, over the limit | `manual` target with 22,000 data files of 50-character random names written by a test-only rule, spawned: exit 1, English error naming the count | Revision 9 (declared-file limit) |
| load guard, fail closed | spawn test starting the toolchain's Bun with `--preload=<launcher.js>` and a declared entry point, with `RULES_BUN_LAUNCH_CONFIG` unset and naming a missing file: non-zero exit, guard error, entry point not run | Revision 9 |
| env, `env_inherit` (declared, unset, both), `TEST_TMPDIR` | `bun_test` | US2-4…6, FR-014 |
| args allowlist | spawn tests of a passing `manual` `bun_test`: each allowlisted form passes; a positional argument, a bare `--`, `-talpha`, `-uts`, `-r./x.ts`, `--path-ignore-patterns=x`, `--changed`, and one owned option per class fail naming the argument | FR-013 (Revision 9) |
| `env_inherit` set | `manual` `bun_test`, CI step with `env:` | FR-014 (Revision 5) |
| filter (no match fails, exit 1), shard (an empty shard passes, formerly canary C14), filter × shards (exit 1, English error, no test runs), JUnit | `bun_test` with `shard_count`, spawn tests setting the variables | US2-7…9, FR-016, Revision 10 |
| describe-label filter | spawn test with `TESTBRIDGE_TEST_ONLY="Math ops adds"` against a `manual` `bun_test` holding `describe("Math ops")` › `test("adds")` and a sibling test: only `adds` runs (JUnit report, exit 0) | FR-016, BUN-discovery (Revision 9) |
| preload | `bun_test` | FR-016c |
| isolation × 3 | spawn tests in `TEST_TMPDIR`, local registry; red on Linux, green on every OS (SC-006); for `bun_test` the green also checks that `process.cwd()` is the copy-tree root and that the root holds no file (no `bunfig.toml`, no `.env`), the Bazel side Revision 11 guarantees; the greens observe the pinned Bun and claim no lookup rule. On Linux and macOS the `bunfig.toml` fixture's `preload` also prints a marker that must be absent, so the first process does not read it either (red: the stub's first process runs it, G4); not asserted on Windows (FR-018a) | US3, SC-006 (G4, G5; Revisions 10–11, 13) |
| `BUN_OPTIONS` rejection | spawn test with `BUN_OPTIONS` set: exit 1, English error, program not run (every OS; on Linux and macOS the shell launcher fires first); `launcher.js` started directly by the toolchain's Bun with `BUN_OPTIONS` set: exit 1, its English error (every OS); spawn test with `BUN_OPTIONS` set to an `--eval` and to a `--preload` printing a marker: exit 1, English error naming `BUN_OPTIONS`, no marker, and with an empty `BUN_OPTIONS`: exit 1 (shell launcher, Linux and macOS; Revision 15) | FR-018a |
| relative runfiles paths | `bun/tests/run/relative/`: a `bun_binary` and a `bun_test` that print `RUNFILES_DIR` and `RUNFILES_MANIFEST_FILE`, spawned with only a relative `RUNFILES_DIR` (when a runfiles tree is staged), with only a relative `RUNFILES_MANIFEST_FILE`, and by a relative path with no runfiles variable: exit 0, each exported variable absolute (Linux and macOS) | FR-011, FR-012, Revision 15 |
| transpiler cache off | spawn test: `BUN_RUNTIME_TRANSPILER_CACHE_PATH` = empty directory, `BUN_INSPECT_CONNECT_TO` removed, declared source > 4 KB; the program sees `0`, and the directory gains no `.pile` file beyond a one-line program's run | FR-018 |
| coverage | `bun_test` + CI `bazel coverage --combined_report=lcov` + checking `bun_binary` (the merged report names the source by its workspace path); and a spawn test setting `COVERAGE_DIR` for a `manual` `bun_test`: exactly one `bunlcov_*.dat` file, naming the source by its `File.path`, no record for `launcher.js` or a path under `.bun/` (every OS) | FR-016a, G7 (re-based), G15 |
| coverage record matching no declared file | spawn test setting `COVERAGE_DIR` for a `manual` `bun_test` whose test calls `process.chdir` to a directory under `TEST_TMPDIR` (Bun then writes `SF:` relative to it): exit 1, English error naming an `SF:` value, no `.dat` file in `COVERAGE_DIR` (every OS); red: exit 0 while unmatched records are dropped. The several-matches branch has no fixture and is reported unverified | FR-016a, G15 (Revision 12) |
| `e2e/smoke` root `bunfig.toml` and `.env` | consumer module root: `bunfig.toml` with `preload` and `[test] preload` naming `smoke_preload.ts`, which sets a global; `.env` defining a variable; none declared by any target. The consumer `bun_test` asserts the global and the variable are unset. Red: reverted mutation inverting the expectation (existing behavior, FR-020). Result recorded per OS (Linux locally, macOS and Windows from CI); a failure is a gap (FR-004), not worked around | FR-018, US5-1 (Revision 12) |

## Upstream canaries (FR-028)

One canary per upstream defect the rules work around, and one for the regular-expression limit
(spec FR-028; research.md Part 1 "Plan for spec Revision 10", item 6). Each is a `bun_test` in
`bun/tests/canary/` unless stated; it asserts the pinned behavior and, when that assertion fails,
fails with an English message naming the workaround to remove or revisit and the upstream link.
Fixtures are written under `TEST_TMPDIR` and run with the toolchain's Bun (`process.execPath`)
unless stated. **Red** is the recorded mutation of the pinned expectation (FR-020): the expectation
is inverted, the canary fails with its message, and the mutation is reverted.

| # | Reliance pinned (today's behavior) | Workaround named | Upstream link | Red (mutation) | OS |
|---|---|---|---|---|---|
| C1 | `bun --preserve-symlinks --preserve-symlinks-main <link>`: `./b.ts` imported by the linked `a.ts` resolves from the link target's directory | copy tree (R6) and load guard (R13) | oven-sh/bun#43689, PR #36757 | expect the import to fail beside the link | all |
| C2 | `CI=true bun test` with a new `toMatchSnapshot()`: the test fails and a header-only `__snapshots__/<file>.snap` is created | snapshots unsupported (FR-016b, G2) | oven-sh/bun#44531 | expect no `.snap` file | all |
| C4 | `bun --config <path> <file>` and `bun -c <path> <file>`, `<path>` a TOML file whose `preload` prints a marker and `<file>` printing another: neither marker is printed, because Bun runs `<path>` as the entry point (the runtime command of the first process; Revision 11) | Windows first-process limitation (FR-018a, G4; Windows only since Revision 13); hermetic-launcher's side is the `MODULE.bazel` comment (G14) | hermeticbuild/hermetic-launcher#81 | expect `<file>`'s marker | all (it pins Bun, not the stub) |
| C7 | the stub splits an argument containing `"` and drops runtime arguments past 128 (spawned `manual` `bun_binary`) | documented Windows limitation; Windows quote test waits (G1) | hermeticbuild/hermetic-launcher#80 | expect the arguments unchanged | Windows (`target_compatible_with`) |
| C13 | `new RegExp` compiles a 1,048,576-character pattern string, `Bun.plugin` accepts it as an `onLoad` filter, and `new RegExp` rejects a 1,048,577-character one ("regular expression too large") | prefix trie and declared-file limit (R13) | PR #36757 (removes the guard) | expect the longer pattern to compile | all |
| C16 | the stub passes an inherited `BUN_OPTIONS` on to the first Bun process: `--eval` printing a marker, set for the spawned `manual` `bun_binary` `//bun/tests/run:hello`, prints the marker | documented Windows `BUN_OPTIONS` limitation (FR-018a, Revision 15) | hermeticbuild/hermetic-launcher#78 | expect no marker | Windows (`target_compatible_with`) |

Withdrawn by spec Revision 10 (numbers are not reused): C3 (G3), C5 (G8), C6 (G13), C8 and C9
(G7, now on rules_python's pattern and the LCOV format), C10–C12 (the guard now uses documented
API only). C14 (an empty shard exits 0) and C15 (manifest escaping) are ordinary tests in "Test
fixtures". G-impl-1 gets no canary: Revision 13 resolves it (research.md Part 1 "Plan for spec
Revision 13").

Each canary is written with the step that introduces its workaround (plan "Implementation Order").

## Test-first record (`tdd-log.md`)

Per task: the command, the failing output naming the missing behavior (or the reverted mutation
for guards of existing behavior and for canaries, or the passing existing tests for refactors),
then the passing run. Platform named on every record. Behavior is added in the order of plan
"Implementation Order", so exit-code propagation, an isolation option, the copy tree, the guard,
its trie, its fail-closed branch, the leading-`--` rejection, the sharded-filter rejection, the
`BUN_OPTIONS` check, the allowlist, the declared-file limit, the length check and the G15 coverage
error are each absent
when their test first runs (genuine red).
