# Implementation Plan: Run Bun Programs and Bun Tests (`bun_binary`, `bun_test`)

**Branch**: `002-bun-binary-test` | **Date**: 2026-10-17 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-bun-binary-test/spec.md` (Revisions 1–13, FR-028)

**Status**: Updated for spec Revision 13 and constitution v2.0.0 (2026-10-17). On Linux and macOS
the executable is a shell launcher the rule generates. It finds its files with Bazel's runfiles
library for Bash, `@rules_shell//shell/runfiles` (rules_shell 0.6.1, the version Bazel 9.2.0
requires), following rules_python's `interpreter_binary`, and it execs Bun with
`--config=<isolated_bunfig.toml>`, `--no-env-file`, `launcher.js` and the launch configuration.
Windows keeps the hermetic-launcher stub. G-impl-1 is resolved by design (the library falls back to
the manifest per file); G4, the first-process `bunfig.toml` limitation of FR-018a, and G1 apply to
Windows only (research.md Part 1 "Plan for spec Revision 13"). Two findings go to the user: rules_python's `py_binary` bootstrap
does not itself use the Bash runfiles library (its `interpreter_binary` does), and spec FR-022 and
SC-005 still forbid shell launchers (open item O-13). Updated for spec Revision 12 (2026-10-15): G15 is decided: the coverage rewrite matches
each `SF:` value against the declared copies (joined to the copy-tree root, and as an absolute
path), rewrites exactly one match to that source's `File.path`, and fails the test with an English
error naming the value on none or several, so no `SF:` form is relied on; the parent-directory
lookup of `bun test` is stated with its real reach (the copy tree's ancestors include
`execroot/_main`, which links every top-level entry of the main repository); `e2e/smoke` gains a
root `bunfig.toml` and `.env` its `bun_test` asserts have no effect, recorded per OS (research.md
Part 1 "Plan for spec Revision 12"). Updated for spec Revision 11 (2026-10-15): bun.com documents no `bunfig.toml` lookup
for `bun test` (oven-sh/bun#45331), so a `bun_test` makes no claim about it; the rules guarantee
and test the Bazel side only (the second process runs at the copy-tree root, which holds only
declared files, and the rule writes no `bunfig.toml` there); canary C4 pins the runtime command;
FR-001 step 1 names the real embedded arguments (research.md Part 1 "Plan for spec Revision
11"). Re-planned for spec Revision 10 (2026-10-08): constitution V is not amended, and every
reliance on undocumented upstream behavior is replaced by a documented mechanism, a
bazelbuild/bazel-contrib ruleset pattern or an explicit English error. G3, G8 and G13 are withdrawn,
G7 is re-based on rules_python's coverage pattern, the load guard is sourced from bun.com only, and
the canaries are narrowed to upstream defects and the regular-expression limit (research.md Part 1
"Plan for spec Revision 10"). Gaps G1–G15 are decided (G1–G9 on 2026-10-03, G10–G11 on 2026-10-04,
G12–G13 on 2026-10-05, G14 on 2026-10-06, G15 on 2026-10-15); the other decided gaps are not
reopened. Upstream:
hermetic-launcher#80 (G1), #81 (G4),
oven-sh/bun#44531 (G2), oven-sh/bun PR #36757 (Revision 7); a bazel-lib request for a documented
copy-directory tool (G12) is to be filed.

## Summary

Add `bun_binary`, `bun_test` and `bun_library` (`bun/defs.bzl`), a target-platform Bun toolchain
(`//bun/toolchain:target_type`, `bun_target_toolchain` in `bun/toolchain.bzl`), and the launch
chain of FR-001 (Revision 13). The executable starts the target platform's Bun on a static
JavaScript launcher. On Linux and macOS the executable is a generated shell launcher that uses the
Bash runfiles library and passes `--config=` with the rule's `bunfig.toml`; on Windows it is a
hermetic-launcher native stub. The JavaScript launcher resolves runfiles (tree or manifest), maps the Bazel test protocol
onto `bun test` options, keeps undeclared `bunfig.toml`, `.env` and auto-install out (FR-018), and starts the
program or `bun test` in a second Bun process, with a command line within 32,767 characters as the
running OS builds it. A `bun_binary` gets `--config=` with the rule's static `bunfig.toml`; a
`bun_test` gets no configuration option and runs at the root of its copy tree, which holds only
declared files and no `bunfig.toml`, with test files passed `./`-relative (Revisions 10–11). A program argument list starting with `--`, and a test filter on a
sharded `bun_test`, fail with English errors. Each binary or test copies every file
it uses into its own tree `<name>.bun/` with bazel-lib's shell-free `copy_file_action`, and Bun
runs only those copies (FR-003, G6); programs and tests find their data relative to `import.meta.dir`. The second process
first preloads a load guard, a `Bun.plugin` `onLoad` whose filter, a prefix trie of the declared
paths, matches only files outside the declared set and throws, using documented API only
(Revisions 7–8 and 10, G10, G11); the guard
reads its configuration from a file it never deletes and rejects every load when it cannot
(Revision 9), and a target whose pattern would exceed Bun 1.4.2's 1,048,576-character limit fails
naming its declared-file count. `bun_test` arguments are checked against an allowlist of
documented, harmless `bun test` options (Revision 9). A directory in `data` fails analysis (G12).
Coverage is written as `bunlcov_<uuid>.dat`, rules_python's pattern (G7), with each `SF:` value
matched to exactly one declared copy or the test failing in English (G15). Every upstream defect the
rules work around, and the regular-expression limit, has a canary (FR-028). Developed test-first with genuine reds,
`analysistest` and real runs on Linux, macOS and Windows CI (research R1–R14).

## Technical Context

**Language/Version**: Starlark on Bazel 9.2.0 (`bazel_compatibility = [">=9.2.0"]`); JavaScript
(the launcher and load guard) run by Bun 1.4.2

**Primary Dependencies**: new non-dev `hermetic_launcher` 0.0.16 (the Windows launcher) and
`bazel_lib` (lowest working version from 3.0.0 upward, fixed in Polish; replaces the dev
`bazel_lib` 3.7.2); new non-dev `rules_shell` 0.6.1 (`@rules_shell//shell/runfiles`, the Linux and
macOS launcher's runfiles library) and `bazel_skylib` 1.9.0 (`shell.quote`; replaces the dev
1.9.2 declaration). For both, every Bazel 9.2.0 consumer already resolves at least that version,
through `bazel_tools` and `hermetic_launcher` (research.md Part 1 "Plan for spec Revision 13",
item 5). `platforms` is raised from 1.0.0 to 1.1.0, which `hermetic_launcher` 0.0.16 declares
(constitution IV). Unchanged: `package_metadata` 0.0.6, and dev `gazelle`,
`bazel_skylib_gazelle_plugin`, `bazelrc-preset.bzl`.

**Storage**: N/A

**Testing**: bazel-skylib `analysistest`/`unittest`; `bun_test` targets of this feature for real
runs, including spawn tests of `manual` targets and test-only rules that write undeclared files
for the load guard, 10,000 data files for the large guard set, 22,000 for the declared-file limit
and 400 test files with 90-character names for the command-line length check; canaries C1, C2,
C4, C7, C13, C16 (FR-028); a coverage spawn test whose test changes its working directory (G15); an
`e2e/smoke` root `bunfig.toml` and `.env` declared by no target (Revision 12); analysis tests of
the launcher each target platform gets, and a first-process `bunfig.toml` assertion on Linux and
macOS (Revision 13); CI `bazel run`, `env_inherit`, `--noenable_runfiles` (including `bazel run`),
`bazel coverage` and `--output_user_root` with a space

**Target Platform**: target platforms linux-x64, linux-aarch64, darwin-x64, darwin-aarch64,
windows-x64 (Bun releases ∩ hermetic-launcher toolchains); CI on ubuntu-latest, macos-latest,
windows-latest

**Project Type**: Bazel ruleset (library)

**Performance Goals**: N/A. Inherent costs: one extra Bun start per run (R2), one copy per file
per target (R6), one guard-pattern build in the launcher (declared-file limit) and one filter
compile per process, or per test file under `--isolate`, and one match per loaded module (R13;
observed on Linux: 13 ms to compile at 8,000 paths, 213 ms at 100,000, a match under 0.001 ms)

**Constraints**: no `run_shell` (VI); the only generated shell script is the Linux and macOS
launcher, which uses the Bash runfiles library as documented (VI, v2.0.0); no Bash on Windows;
documented APIs only, no deprecated ones (V: hence no `ctx.expand_make_variables`); English
everywhere; test-first records with genuine reds (FR-020); on Windows, embedded stub arguments
≤ 10, each ≤ 256 bytes; the guard's input
passes through a file, not a variable, which is never deleted (fail closed when absent), and its
filter is a prefix trie of at most 1,048,576 characters (Bun 1.4.2's limit, R13); the second
process's command line, as the running OS builds it, ≤ 32,767 characters on every OS (R2);
`bun_test` arguments from the allowlist only (R8); no Bun option bun.com does not document for the
command it is passed to (Revision 10)

**Scale/Scope**: about 12 Starlark/BUILD files changed or added, one JavaScript launcher, one shell
launcher template, one `bunfig.toml`, test fixtures in `bun/tests/` and `e2e/smoke/`

No NEEDS CLARIFICATION remains.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Pre-research | Post-design | Evidence |
|---|---|---|---|
| I. Public API boundary | PASS | PASS | New public names: `bun_binary`, `bun_test`, `bun_library`, `BunLibraryInfo`, `BUN_TARGET_TOOLCHAIN_TYPE` in `bun/defs.bzl`; `bun_target_toolchain` in `bun/toolchain.bzl`; `//bun/toolchain:target_type` (named by v1.2.0). Implementation in `bun/private/`; tests in `bun/tests/`, `e2e/smoke/`. No public helper for data: `import.meta.dir` is Bun's. [contracts/public-api.md](contracts/public-api.md). |
| II. Tested claims | PASS | PASS | Every behavior has a test (data-model "Test fixtures"), including each guard behavior on every OS, the caught-error limitation, the four Revision 8 fixtures, the length check and the Revision 9 tests (declared-file limit, fail closed, allowlist, describe-label filter, non-zero exit, output root with a space). Every undocumented reliance has a canary with a recorded red (data-model "Upstream canaries", FR-028). Platforms are reported per actual run; macOS/Windows only after CI. Limitations are listed as such (research R14); TSX without JSX, `.node`, `.wasm` are reported unverified. G15's no-match error has a spawn test; its several-matches branch has no fixture and is reported unverified. The parent-directory lookup of `bun test` is claimed as nothing: the `e2e/smoke` root fixture records what each OS does (Revision 12). |
| III. Pinned, verified downloads | PASS | PASS | Bun downloads unchanged; the target toolchain reuses the same repositories. `hermetic_launcher` and `bazel_lib` download their prebuilt tools with their own pinned checksums. No host tool in a repository rule or build action: the launcher runs `process.execPath`, the toolchain's Bun; copies run bazel-lib's coreutils toolchain; the shell launcher is written by `ctx.actions.expand_template`. On Linux and macOS, running a target uses the host's `bash` and the utilities the Bash runfiles library calls. That is run time, not a build action, and it is what constitution VI v2.0.0 requires (Revision 13). |
| IV. Minimum dependency versions | PASS | PASS | `hermetic_launcher` 0.0.16 is the lowest with the macOS fix (R1); it needs `platforms` 1.1.0, so the root declaration is raised to that and no higher. `bazel_lib` is fixed by running from 3.0.0 upward (R6). `rules_shell` 0.6.1 and `bazel_skylib` 1.9.0 are the lowest versions any consumer can resolve: Bazel 9.2.0's `bazel_tools` requires `rules_shell` 0.6.1, and `hermetic_launcher` 0.0.16 requires `bazel_skylib` 1.9.0. A lower declaration could not be run or tested (research Part 1 "Plan for spec Revision 13", item 5). `e2e/smoke` runs with exactly the declared versions. |
| V. Supported APIs only | PASS (hermetic-launcher approved 2026-10-01; the Windows launcher only since v2.0.0) | PASS (G1–G15 decided, G-impl-1 resolved; Revisions 10–13) | Each API and Bun option is sourced in research.md; the Linux and macOS launcher uses the Bash runfiles library of bazelbuild/rules_shell as its documentation specifies (depend on `@rules_shell//shell/runfiles`, initialization v3 verbatim, `rlocation`, `runfiles_export_envvars`), with rules_python's `interpreter_binary` as the bazel-contrib pattern and `ctx.actions.expand_template`; canonical runfiles paths passed from Starlark are the case the repository-mapping design keeps (BZ-repomap, Step 3 a)); `copy_file_action` is bazel-lib public API (bazel-contrib); `import.meta.dir` is documented (BUN-meta). Revisions 10–12 remove every reliance on undocumented behavior: `bun test` gets no configuration option and no claim is made about where it looks for `bunfig.toml` (G3 withdrawn; Revision 11, oven-sh/bun#45331); the rules guarantee only the Bazel side (working directory at the copy-tree root, which holds no file), and whether Bun searches the root's ancestors, which include `execroot/_main` and so a workspace-root `bunfig.toml` or `.env`, is a stated, unverified limitation the `e2e/smoke` root fixture observes per OS, a failure being a gap (Revision 12); no `--pass-with-no-tests` (G8 withdrawn, English error for filter × shards); no `--` insertion (G13 withdrawn, English error); coverage follows rules_python's `pylcov_<uuid>.dat` and the LCOV format (G7), and no `SF:` form is relied on: each value must match exactly one declared copy, read joined to the copy-tree root or as an absolute path, or the test fails with an English error naming it (G15, Revision 12, which replaces the launcher's reading of the base of a relative path); the guard uses only `onLoad`, a throwing callback, `OnLoadArgs.path` and `--preload` as bun.com documents them. What remains are upstream defects worked around (oven-sh/bun#43689; G1 and G4 on Windows only since Revision 13; G2) and the measured regular-expression limit, each pinned by a canary (C1, C2, C4, C7, C13); hermetic-launcher's side of G4 is a `MODULE.bazel` comment (G14). Empty-shard exit and manifest escaping (rules_python `runfiles.py` pattern) are pinned by ordinary tests. `bun_test` forwards only options bun.com documents (R8). |
| VI. Shell-free actions; launchers as the reference rulesets build them (v2.0.0) | PASS | PASS for the design; spec text open (O-13) | Linux and macOS: a generated shell launcher that finds its files with the Bash runfiles library (research Part 1 "Plan for spec Revision 13"). Windows: the hermetic-launcher native stub, so no Windows build or run needs Bash. Actions are `ctx.actions.run` (stub finalizer, bazel-lib `cp`), `ctx.actions.write` and `ctx.actions.expand_template`; tests are `analysistest` and `bun_test`; CI steps call only `bazel`. VI names "rules_python's bootstrap" as the reference. rules_python's `py_binary` bootstrap does not use the library; its `interpreter_binary` does, and the design follows that (reported to the user). **O-13**: spec FR-022 and SC-005 still forbid shell launchers, which contradicts the restated FR-001 and VI; Revision 13 did not restate them, and a spec revision must before implementation (Governance: a conflict with a MUST principle blocks). |
| VII. Releases from tags | PASS | PASS | No `version`; additions only, no breaking change. |

Complexity Tracking: none.

## Gate decisions

Details, evidence and options in research.md Part 1.

| Gap | Decision |
|---|---|
| G1 Windows stub mangles `"` and drops arguments past 128 | upstream #80; Windows quote test waits for the release; documented; Windows only (Linux and macOS use the shell launcher, Revision 13) |
| G2 no read-only snapshot mode | snapshots unsupported, documented (FR-016b) |
| G3 `--config` not documented for `bun test` | withdrawn (Revision 10), restated (Revision 11): no configuration option for `bun test`; the second process runs at the copy-tree root, which holds only declared files, and the rule writes no `bunfig.toml`; Bun's lookup is undocumented (oven-sh/bun#45331), parent-directory search unverified; its reach includes `execroot/_main`, and the `e2e/smoke` root fixture records each OS (Revision 12) |
| G4 stub cannot pass `--config=<path>` | first-process limitation (FR-018a); upstream #81; Windows only since Revision 13 (the shell launcher passes `--config=`) |
| G5 `bun test` does not auto-install | observation replaces the red (SC-006) |
| G6 shared copy tree exposes siblings | per-target tree `<name>.bun/`; ancestors documented |
| G7 coverage file name and `SF:` form undocumented | re-based (Revision 10): `$COVERAGE_DIR/bunlcov_<uuid>.dat` as rules_python writes `pylcov_{}.dat`; `SF:` matching restated by G15; checked by the CI coverage step |
| G8 sharded filter with no match exits 1 | withdrawn (Revision 10): filter × shards fails with an English error; a filter that selects nothing fails |
| G9 test file on another Windows drive | removed by Revision 10: test files are `./`-relative to the copy-tree root |
| G10 stale copy importable | load guard (Revision 7) |
| G11 climbs, `"imports"`, `node_modules` reachable | load guard (Revision 7); guard limits documented |
| G12 directory in `data` | analysis fails in English naming `data` and the directory; documented as unsupported; request upstream in bazel-lib (2026-10-05) |
| G13 Bun drops a leading `--` of the program's arguments | withdrawn (Revision 10): a program argument list starting with `--` fails with an English error |
| G14 hermetic-launcher's side of the G4 canary has no testable API | `MODULE.bazel` comment next to the `bazel_dep`; carried in FR-028 (2026-10-06) |
| G-impl-1 `--noenable_runfiles` fails without a staged runfiles tree on Linux (stub prefers the directory) | resolved by Revision 13 (2026-10-17): the Linux and macOS shell launcher resolves through the Bash runfiles library, which falls back to the manifest per file; no canary, no limitation, no upstream report; verified only once plan step 11's tests and CI pass |
| G15 the coverage rewrite depended on the base of a relative `SF:` path | each value is matched against the declared copies' real paths, joined to the copy-tree root and as an absolute path; exactly one match is rewritten to that source's `File.path`; none or several: exit 1, English error naming the value, no `.dat`; the launcher's own record is removed by the same comparison (Revision 12, 2026-10-15) |

## Project Structure

### Documentation (this feature)

```text
specs/002-bun-binary-test/
├── spec.md
├── plan.md              # this file
├── research.md          # Part 1 gaps G1–G15 and G-impl-1, Revision 8 fixes, Revision 9–13 decisions; Part 2 R1–R14; Part 3 divergences
├── data-model.md        # rules, attributes, providers, copy tree, launch config, guard, fixtures, canaries
├── quickstart.md        # validation commands
├── contracts/
│   └── public-api.md
├── checklists/requirements.md
├── tdd-log.md           # written during /speckit-implement (FR-020 records)
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
MODULE.bazel                          # + bazel_dep hermetic_launcher 0.0.16 with the G14 comment; platforms 1.0.0 → 1.1.0; bazel_lib becomes non-dev; + rules_shell 0.6.1; bazel_skylib non-dev 1.9.0 (Revision 13)
MODULE.bazel.lock                     # refreshed
bun/
├── defs.bzl                          # + bun_binary, bun_test, bun_library, BunLibraryInfo, BUN_TARGET_TOOLCHAIN_TYPE
├── toolchain.bzl                     # + bun_target_toolchain
├── BUILD.bazel                       # bzl_library deps
├── toolchain/BUILD.bazel             # + toolchain_type(name = "target_type")
├── private/
│   ├── BUILD.bazel                   # + bzl_library targets; exports launcher.js, isolated_bunfig.toml
│   ├── toolchain.bzl                 # + bun_target_toolchain (bun attr without cfg)
│   ├── repositories.bzl              # platform repo BUILD + bun_target_toolchain target
│   ├── toolchains_repo.bzl           # + <platform>_target_toolchain with target_compatible_with
│   ├── providers.bzl                 # + BunLibraryInfo
│   ├── library.bzl                   # bun_library
│   ├── run.bzl                       # shared: copy tree, launcher (shell on Linux/macOS, stub on Windows), launch config, runfiles, RunEnvironmentInfo; bun_binary, bun_test
│   ├── launcher.sh.tpl               # static template of the Linux/macOS shell launcher: runfiles.bash initialization v3, rlocation, exec Bun (Revision 13)
│   ├── launcher.js                   # static: launcher as main module, load guard as preload (R1, R2, R5, R7, R8, R13); allowlist, limits
│   └── isolated_bunfig.toml          # env = false; install.auto = "disable"; --config= of bun_binary's second process and, on Linux/macOS, of every first process; from runfiles, not copied
└── tests/
    ├── BUILD.bazel                   # + new suites and fixtures
    ├── run_test.bzl                  # analysistests: providers, copies, RunEnvironmentInfo, failures, coverage info
    ├── target_toolchain_test.bzl     # analysistests: Bun per target platform, target cfg, exec cfg, no stub (Windows), launcher per platform, exec toolchain unchanged
    ├── platforms/BUILD.bazel         # five platforms + test-only ones without a toolchain / a Windows one without a stub
    ├── support/                      # bun_library "spawn": the spawn helper of the spawn tests (FR-021)
    ├── run/                          # fixtures: lib/, data/, programs, tests, spawn tests, guard fixtures, isolation tests
    └── canary/                       # FR-028 canaries C1, C2, C4, C7, C13, C16
e2e/smoke/
├── MODULE.bazel(.lock)               # lock refreshed (hermetic_launcher, bazel_lib, platforms 1.1.0, rules_shell, bazel_skylib)
├── BUILD.bazel                       # + bun_binary, bun_test
├── bunfig.toml                       # Revision 12 fixture: preload and [test] preload of smoke_preload.ts; declared by no target
├── smoke_preload.ts                  # Revision 12 fixture: sets a global; declared by no target
├── .env                              # Revision 12 fixture: defines a variable; declared by no target
└── app/                              # consumer sources, data, test (the test asserts the three root files take no effect)
.github/workflows/ci.yaml             # + bazel run, env_inherit, --noenable_runfiles (with bazel run), coverage, Windows --output_user_root with a space
```

**Structure Decision**: keep the baseline layout from feature 001. Rule code in one
`bun/private/run.bzl` (both rules share all but the command), the library in `library.bzl`, the
JavaScript launcher and guard as one static file so that no relative import between rule files is
needed; per-target data goes in a generated JSON file (`ctx.actions.write`). The only template is
the Linux and macOS shell launcher (`launcher.sh.tpl`, `ctx.actions.expand_template`, as
rules_python's `interpreter_binary` expands `interpreter_tmpl.sh`); it holds paths and arguments
only, and the logic stays in `launcher.js` (Revision 13).

## Implementation Order

Dependencies drive the order; tasks.md is authoritative. Each behavior step records its red first
(FR-020) in `tdd-log.md`. A red is genuine: the behavior under test is absent when its test first
runs, so the launcher starts minimal and gains each option, check and the guard only after the
test that needs it has failed. A mutation is recorded only for behavior that already existed
before its test (the analysis-time behaviors of earlier steps, for example) and for canaries, whose
red is a mutation of the pinned expectation (data-model "Upstream canaries"). Each canary is
written in the step that introduces its workaround.

1. **Setup**: record the starting state (root and `e2e/smoke` pass). Add `hermetic_launcher` with
   the G14 comment;
   raise `platforms` to 1.1.0; make `bazel_lib` non-dev at 3.7.2 for now. Refresh both lock files
   and run feature 001's tests unchanged (FR-010).
2. **US4 foundation / R3**: analysistests first (red: `target_type` does not exist), then the
   toolchain type, `bun_target_toolchain` and the repository changes; optional toolchains with an
   English `fail` (R1; a mandatory one aborts analysis, which `analysistest` cannot observe);
   per-platform selection, target-cfg, exec-cfg and no-stub tests; feature 001 tests still pass.
3. **US1 minimal launch / R1, R2, R4, R10**:
   - analysis: `bun_library`, providers, entry-point and embedded-argument failures,
     `RunEnvironmentInfo`;
   - the launcher starts the second process on the entry point's runfile with no isolation
     option and no guard, and exits 0 when the child ends; a self-checking program (import
     across packages, checked-in data, args, env, `import.meta.main`) and the argument spawn test
     (empty, spaces; quotes on Linux/macOS; Windows quotes wait on G1); canary C7 (Windows);
   - non-zero exit (US1-1, Revision 9): the spawn test of a `manual` `bun_binary` exiting 3 is red
     (exit 0), then the launcher exits with the child's code;
   - standard input (FR-015): the test is red while the launcher starts the child without
     `stdin: "inherit"` (observed: the child reads nothing), then the launcher inherits it;
   - leading `--` (Revision 10): the spawn test with `--` as the first argument expects the
     launcher's English error and is red (the program runs and sees `["x"]` for `-- x`), then the
     launcher rejects it; the same test keeps `--config=z` as a first argument, which passes.
4. **Copy tree / R6, R5**: tests first, red against the minimal launcher: an undeclared sibling is
   imported (US3-4); generated data is not found relative to `import.meta.dir`; a directory in
   `data` does not fail analysis (G12). Then the copy tree (paths `<name>.bun/<rlocation path>`,
   entry point and preloads in runfiles), and the directory failure; canary C1. Then the
   spaces-in-paths fixture (source, data and test file names with a space, tree and manifest-only,
   with the manifest-escaping assertion that was canary C15).
5. **US2 / R8, R9**: `bun_test` with declared files only, a failing test via spawn, env and
   `env_inherit`, `TEST_TMPDIR`, data via `import.meta.dir`; the allowlist (Revision 9: each
   allowed form passes, and a positional argument, a bare `--`, `-talpha`, `-uts`, `-r./x.ts`,
   `--path-ignore-patterns=x`, `--changed` and owned options are red until the check exists);
   the filter, the describe-label filter (Revision 9) and a filter that selects nothing failing
   (red while the launcher maps no filter); sharding (an empty shard passes, an ordinary test);
   filter × shards, red until the launcher fails with its English error (Revision 10); JUnit
   XML, preloads, coverage info, `_lcov_merger` and the `bunlcov_<uuid>.dat` rewrite with its
   spawn test (G7 re-based), matching each `SF:` value against the declared copies (G15); then the
   G15 error: a spawn test whose `manual` `bun_test` calls `process.chdir` into `TEST_TMPDIR`
   expects exit 1, the English error naming an `SF:` value and no `.dat` file, red while unmatched
   records are dropped (exit 0), then the launcher fails instead; snapshots unsupported (canary C2); then the command-line length test
   (400 test files with 90-character names), red before the check, which measures the line as the
   running OS builds it. Test files are passed `./`-relative to the copy-tree root once step 6
   moves the working directory there; until then they are passed as real paths.
6. **US3 isolation / R7**: for each item, the spawn test from `TEST_TMPDIR` first, red on Linux
   because the launcher does not yet provide the protection, then the protection (SC-006: reds on
   Linux, greens on all three OSes): `bunfig.toml` (`bun_binary`: `--config=` with the static
   `isolated_bunfig.toml`; `bun_test`: the second process runs at the copy-tree root, which holds
   no file, with test files passed `./`-relative, and the green also asserts that root; canary C4
   on the runtime `--config <path>` / `-c <path>` command), `.env` (`env = false`;
   `--no-env-file` for `bun_binary`), install with a local `Bun.serve` registry
   (`install.auto = "disable"` and `--no-install` for `bun_binary`; for `bun_test` no documented
   option exists and the G5 observation is checked, Revision 11), `BUN_OPTIONS`
   (rejection test, then the check and the removal from the child's environment), the transpiler
   cache (test, then `BUN_RUNTIME_TRANSPILER_CACHE_PATH=0`).
7. **Load guard / R13**: the guard tests first, red with no guard: stale copy, climb, `"imports"`,
   `node_modules`, ESM/CJS/JSON, a preload's import, `bun test --isolate`; then the guard with a
   single-alternation filter, reading `RULES_BUN_LAUNCH_CONFIG` without deleting it, using only the
   documented API of research Part 1 "Plan for spec Revision 10", item 5. Then the fail-closed test, red while the guard registers nothing without a
   configuration, then the reject-all branch. Then the 10,000-file test, red ("regular expression
   too large"), then the prefix trie. Then the 22,000-file test, red (Bun's "regular expression
   too large" from the preload instead of the English count error), then the launcher's
   declared-file limit; canary C13. The caught-error limitation is pinned by a test after the
   guard exists.
8. **US4 / R11**: `--noenable_runfiles` locally on Linux, `bazel test` and `bazel run`; CI matrix
   steps, the Linux `--noenable_runfiles` job with its `bazel run` step (FR-024), and the Windows
   job with `--output_user_root="C:/bazel root"` (Revision 9); Windows and macOS results recorded
   only from CI.
9. **US5**: `e2e/smoke` `bun_binary` and `bun_test` through the public API; `git grep -n
   'bun/private' -- e2e` record. The root `bunfig.toml` (`preload` and `[test] preload` naming
   `smoke_preload.ts`, which sets a global), `smoke_preload.ts` and `.env` (a variable), declared
   by no target, and the `bun_test`'s assertion that neither the global nor the variable is set
   (Revision 12). It guards existing behavior, so its red is a reverted mutation inverting the
   expectation (FR-020). The result on each OS is recorded (Linux locally, macOS and Windows from
   CI); a failure is reported to the user as a gap (FR-004), not worked around.
10. **Polish**: lower `bazel_lib` to the lowest version with which the root and `e2e/smoke` test
    sets pass (from 3.0.0 upward; record each failure; constitution IV); `doc` strings with every
    limitation of research R14, the allowlist and the declared-file limit; file the bazel-lib
    request (G12); hand-back checks from AGENTS.md;
    adversarial review; CI per OS recorded.
11. **Revision 13: shell launcher on Linux and macOS** (research Part 1 "Plan for spec Revision
    13"). Precondition: O-13 is settled by a spec revision of FR-022 and SC-005. Tests first,
    each red against today's stub on Linux:
    - analysis: a Linux and a macOS target's executable is the expanded template, and its
      runfiles hold `bazel_tools/tools/bash/runfiles/runfiles.bash` and `isolated_bunfig.toml`;
      a Windows target's executable is still the `.exe` stub (red: the Linux executable is a
      stub);
    - the no-stub test moves to a Windows platform without a template toolchain, because a
      non-Windows platform now analyzes (red: the FreeBSD `no_stub` case passes analysis once the
      shell launcher exists, so the test is changed before the implementation);
    - manifest only: `bazel run --noenable_runfiles` of the self-checking programs, root and
      `e2e/smoke`, and `bazel test --spawn_strategy=local --noenable_runfiles` of
      `//bun/tests/run:skeleton_test` (red: "execve failed with code -2", G-impl-1);
    - first process: the isolation spawn test's `$cwd/bunfig.toml` `preload` prints a marker,
      and on Linux and macOS the marker must be absent (red: the stub's first process runs it,
      G4). The assertion is not made on Windows (FR-018a).

    Then: `bazel_dep` `rules_shell` 0.6.1 and non-dev `bazel_skylib` 1.9.0 (lock files
    refreshed); `launcher.sh.tpl`; `run.bzl` chooses the template or the stub with
    `ctx.target_platform_has_constraint` against `@platforms//os:windows`, adds `_bash_runfiles`
    (`@rules_shell//shell/runfiles`, its `default_runfiles` merged) and `_launcher_template`, and
    gives `bun_test` `_bunfig`; the finalizer toolchain becomes optional, and the embedded-argument
    check runs for Windows targets only. The existing argument, standard-input, exit-code,
    spaces-in-paths and isolation spawn tests must pass unchanged on Linux with the shell launcher.
    `doc` strings and the contract drop the first-process `bunfig.toml` limitation for Linux and
    macOS and add the run-time requirement. CI then records the `manifest-only` job's `bazel run`
    step as passing; macOS and Windows results come from CI only. The tasks this replaces (T092's
    option 1, T097's limitation wording, T099–T101) are re-derived by `speckit-tasks`.

## Upstream canaries (FR-028)

Every upstream defect the rules work around, and the regular-expression limit, has a canary that
asserts today's behavior and fails with an English message naming the workaround and the upstream
link once a version bump changes it (spec FR-028, Revision 10). The list, with what each pins, its
red (a mutation of the pinned expectation) and its OS, is data-model "Upstream canaries":

| Canary | Reliance |
|---|---|
| C1 | Bun follows symlinks despite `--preserve-symlinks` (copy tree, load guard; oven-sh/bun#43689, PR #36757) |
| C2 | header-only `.snap` in CI mode (G2, oven-sh/bun#44531) |
| C4 | `bun --config <path> <file>` and `bun -c <path> <file>` run `<path>` as the entry point (G4, Bun's side of hermetic-launcher#81; Revision 11; the workaround it names is the Windows first-process limitation since Revision 13, and it still runs on every OS because it pins Bun) |
| C7 | the Windows stub's argument parsing (G1, hermetic-launcher#80; Windows only) |
| C13 | the 1,048,576-character regular-expression limit (trie, declared-file limit) |
| C16 | the Windows stub passes an inherited `BUN_OPTIONS` on to Bun (FR-018a, hermetic-launcher#78; Windows only; Revision 15) |

hermetic-launcher's side of G4 is the `MODULE.bazel` comment (G14). Withdrawn by Revision 10: C3,
C5, C6 (their workarounds are withdrawn), C8, C9 (G7 on rules_python's pattern and LCOV), C10–C12
(the guard's API is documented). C14 (empty shard) and C15 (manifest escaping) are ordinary tests.
G-impl-1 has no canary: Revision 13 resolves it instead of working around it.
The `--isolate` preload re-run is documented (BUN-parallel) and needs no canary; its test stays.

## Risks

- **Shell launcher on macOS** (Revision 13): `runfiles.bash` 0.6.1 handles macOS paths (its
  header records a macOS fix in version 3), but the launcher runs on macOS only in CI; nothing is
  claimed for macOS before CI passes.
- **Stale runfiles tree**: under `--noenable_runfiles` without a sandbox, `runfiles.bash` 0.6.1
  takes a file from `<exe>.runfiles/` when it exists there, so a tree an earlier
  `--enable_runfiles` build left behind would be used; this case is not researched and is
  reported unverified (rules_shell#68 changes the order in v0.9.0, not yet on BCR).
- **Windows**: argument fidelity (G1), `.exe` naming,
  the manifest-only path, the guard's path spelling (drive-letter case, separators), the length
  of paths under `<name>.bun/`, and the command-line length computed by the WIN-argv rules are
  verified only by Windows CI.
- **Guard path form**: the declared set uses `fs.realpathSync`; if Bun's `onLoad` path is spelled
  differently on an OS (for example macOS `/private/var` or Windows case), the guard rejects a
  declared file. The per-OS tests catch it; nothing is claimed before they pass.
- **Large-set test cost**: 10,000 and 22,000 data files mean 32,000 copy actions per OS; if this
  makes CI slow on Windows, that is reported, not hidden by smaller sets (a smaller set would not
  be red against a single alternation, or would not exceed the limit).
- **Windows path length**: the 22,000-file and 400-test-file fixtures keep each path under the
  260-character `MAX_PATH` at the GitHub runners' default output base by estimate only; whether
  Bun on Windows reads longer paths is not researched. Windows CI decides; a failure is reported.
- **Output root with a space on Windows**: whether Bazel 9.2.0 itself runs with
  `--output_user_root` containing a space on Windows has not been run; a failure outside the
  ruleset is reported, not worked around.
- **Limit check vs. plugin compile**: the launcher compares the pattern string's length with the
  constant (not `RegExp.source`, which escapes `/`). `Bun.plugin` accepted a filter of exactly
  1,048,576 characters on Linux; canary C13 pins that and the rejection above it on each OS.
- **Canary C1 on Windows**: creating a symlink may need a privilege the runner lacks; then C1 is
  reported unverified on Windows, not skipped silently.
- **Coverage paths**: that the merger keeps the rewritten `SF:` records is checked only by the CI
  coverage job on Linux (G7); a mismatch there is reported, not worked around with an
  undocumented form. A consumer test that changes its working directory fails under
  `bazel coverage` with the G15 error (Bun writes `SF:` relative to the working directory at report
  time, observed 2026-10-15); this is stated in the contract.
- **`bun_test` working directory** (Revision 10): tests that read files relative to
  `process.cwd()` see the copy-tree root, not `$TEST_SRCDIR/$TEST_WORKSPACE`; the contract states
  it, and data is located through `import.meta.dir` (FR-012).
- **`bun test` configuration lookup** (Revisions 11–12): undocumented (oven-sh/bun#45331). If Bun
  searches parent directories of the copy-tree root, a `bunfig.toml` or `.env` there could apply.
  Those directories are not only `bazel-out/<config>/bin/<package>/`: they include
  `execroot/_main`, which links every top-level entry of the main repository, so a workspace-root
  `bunfig.toml` or `.env` is within reach. This is reported as unverified; the isolation greens
  observe only the spawn fixture's directory, and the `e2e/smoke` root fixture observes the
  workspace root on each OS. On Linux, Bun 1.4.2 did not read either from an ancestor directory
  (observed 2026-10-15, research Part 1 "Plan for spec Revision 12"); macOS and Windows are known
  only from CI. A failure there stops the work as a gap (FR-004). When bun.com documents the rule,
  the design is revisited.
- **`bazel_lib` floor**: versions before 3.5.0 may fail in `e2e/smoke` (BL-history); the floor may
  end up higher than 3.0.0, which raises what consumers resolve.
- **Upstream timing**: if G1/G4 are fixed upstream, a `hermetic_launcher` raise is needed before
  the Windows quote test can pass or the Windows first-process limitation can go; the G14 comment
  in `MODULE.bazel` is the reminder.
- **Embedded-argument limit** (Windows targets): deep package paths can exceed 256 bytes; analysis
  fails with an English message rather than truncating.

## Complexity Tracking

None.
