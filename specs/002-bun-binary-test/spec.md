# Feature Specification: Run Bun Programs and Bun Tests (`bun_binary`, `bun_test`)

**Feature Branch**: `002-bun-binary-test`

**Created**: 2026-10-01

**Status**: Draft (revised after adversarial review)

**Input**: User description: "Add bun_binary and bun_test to rules_bun, the rules a repository uses to run a Bun program with 'bazel run' and to run Bun tests with 'bazel test', following bazel.build documentation and how the official rulesets do it (aspect-build/rules_js js_binary/js_test, bazel-contrib/rules_python py_binary/py_test, bazelbuild/rules_go go_test), developed test-first: every behavior task writes a test, records that it fails for the expected reason, then implements. Scope of this feature: programs and tests whose sources are in the workspace (TypeScript/JavaScript srcs, data files, deps between bun libraries if a library rule is needed), without npm packages; npm dependencies from bun.lock and bundling with bun build are later features and out of scope here. Requirements: the Bun executable comes only from the registered toolchain, resolved for the target platform the binary or test runs on (not the execution platform), using the documented toolchain mechanism; runfiles work on Linux, macOS and Windows, including Windows without runfiles symlinks (manifest-only), using the documented runfiles libraries or mechanisms; args, env (RunEnvironmentInfo), data and test sharding/filtering/XML output behave as the Bazel test encyclopedia specifies where Bun supports them; Bun must not read the user's bunfig.toml, .env files or install packages at run time unless the rule allows it explicitly. Constitution VI forbids generated shell scripts and shell launchers: research must find whether a documented shell-free way exists to make a Bun program an executable target on every platform; if none exists, stop and report the gap so the user can decide on a constitution amendment, rather than working around it. Tests: e2e/smoke gains a consumer bun_binary and bun_test; root tests cover the rules with analysistest and real runs; CI runs Linux, macOS and Windows. Everything in the repository is English."

**Revision (2026-10-01, after review)**: A subagent and Codex reviewed the first draft. Corrected:
`args` are tokenized as Bazel documents, not delivered "unchanged"; fail-fast and premature-exit
were not requested and are removed; the way each real run is executed is named.

**Revision 15 (2026-10-17, final reviews; technical decisions by the implementer)**: (1) The Linux
and macOS shell launcher makes `RUNFILES_DIR` and `RUNFILES_MANIFEST_FILE` absolute before it starts
Bun, so a program or test started by a relative path works; the fail-closed rejection prints its
English error under `bun test` as well, and both are tested. (2) `env` values are taken literally:
`$(location)` expansion in `env` is removed from both rules and the contract, because the expanded
path does not resolve from the copy tree or without a runfiles tree; data is located through
`import.meta.dir` (FR-012). (3) Docstrings and the contract state Windows and macOS behavior as
unverified until a named CI run passes, naming the platforms tests ran on (constitution II).
(4) An analysis test checks that a `bun_test` built for `windows_x64` carries the Windows Bun
(SC-007, US4-3). (5) `BUN_OPTIONS`, which bun.com documents as prepending arguments to any Bun
execution, is rejected by the Linux and macOS shell launcher before it starts Bun, with an English
error; tests cover `--eval` and `--preload` injection. The Windows stub cannot inspect or unset the
environment (hermetic-launcher#78), so on Windows an inherited `BUN_OPTIONS` reaches the first Bun
process and can replace the launcher: this is a documented Windows limitation, pinned by a canary
on the Windows CI job, and FR-018a is restated accordingly.

**Revision 14 (2026-10-17, gap G-impl-2; user decision: option 1)**: On a Windows runner Bazel finds
a Bash by itself, so clearing `PATH` and `BAZEL_SH` in a CI job does not remove it (research
G-impl-2). SC-005's Windows job is restated to Bazel flags: Bazel's shell and rules_shell's
toolchain name a path that does not exist, and actions that take Bazel's default environment,
tests and `bazel run` get a `PATH` without a Bash directory. Not caught: the `PATH` of repository
rules and of actions that set their own environment, a program that starts Bash by absolute path or
by bare name through Windows' search of the system directory, and a test script that sets its own
`PATH` (the `diff_test` of bazel-skylib and of bazel_lib). No public API changes.

**Revision 13 (2026-10-17, constitution v2.0.0; user decision)**: The launcher follows the reference
rulesets. On Linux and macOS a program or test starts from a generated shell launcher that finds
its files with Bazel's runfiles library for Bash (the bootstrap pattern of rules_python; the
library's current home, `@bazel_tools` or bazelbuild/rules_shell, is settled by research for Bazel
9.2.0 with its source) and execs the target platform's Bun on the static JavaScript launcher with
`--config=<resolved path>`, `--no-env-file` and the launcher's configuration. On Windows the
hermetic-launcher native stub stays, because Bash is not guaranteed there. Consequences: G-impl-1
is resolved on Linux and macOS, because the shell launcher uses the runfiles library's documented
manifest handling, and Windows already prefers the manifest (hermetic-launcher README "Runfiles
discovery"), so US4-2, SC-003 and FR-024 hold as written and no upstream report is needed; G4 and
the first-process `bunfig.toml` limitation of FR-018a are removed on Linux and macOS and stay on
Windows; G1 stays Windows-only. FR-001 is restated in these terms, and existing tests of the stub
apply to Windows only. FR-022 and SC-005 are restated to match constitution v2.0.0 VI. No public API changes.

**Revision 12 (2026-10-15, analysis C1, U1; technical decisions by the implementer)**: G15: the
coverage rewrite does not depend on how Bun writes `SF:` paths. Each `SF:` value is matched against
the target's declared copies, read as a path relative to the working directory and as an absolute
path; exactly one match is rewritten to that source's path, and none or several fail the test with
an English error naming the value. The unverified parent-directory lookup of `bun test` is stated
with its real reach: the copy tree's ancestors include `execroot/_main`, which links every
top-level entry of the main repository, so a workspace-root `bunfig.toml` or `.env` is within
reach if Bun searches upward. `e2e/smoke` gains a root `bunfig.toml` whose preload sets a global
and a root `.env`, and its `bun_test` asserts neither takes effect; the result on each OS is
recorded, and a failure there is reported as a gap rather than worked around.

**Revision 11 (2026-10-15, findings C1, I1 and I2 of the 2026-10-08 analysis)**: bun.com documents no lookup rule for
`bunfig.toml` under `bun test` (the `$cwd/bunfig.toml` default is documented for the runtime only;
oven-sh/bun#45331 asks for it). So `bun_test` makes no claim about Bun's lookup. What the rule
guarantees, and tests, is the Bazel side: the second `bun test` process runs with its working
directory at the root of the target's copy tree, which holds only declared files, and the rule
writes no `bunfig.toml` there; a `bunfig.toml` or `.env` the target declares is a declared input
and is used, which is hermetic. Whether Bun also searches parent directories is undocumented and is
recorded as an unverified limitation. FR-018's `bunfig.toml` and `.env` requirements for
`bun_test` are restated in these terms; `bun_binary` keeps `--config=<path>`, `env = false`,
`install.auto = "disable"` and `--no-env-file`, documented for the runtime. Canary C4 pins the
runtime command (`bun --config <path> <file>` and `bun -c <path> <file>` run `<path>` as the entry
point today). FR-001 step 1 is corrected: the stub embeds `--no-env-file`, the static launcher and
its configuration file, not `--config=`. Further findings of that analysis fixed in the artifacts:
A1 (test-file paths), U2 (allowlisted options are claimed as accepted, not as tested in effect),
A2 (the base of a relative `SF:` path), I3 (an analysis names its findings with IDs of its own,
which are not gap (G) or canary (C) numbers; they are cited with the analysis date), I4, I5 and
D1.

**Revision 10 (2026-10-08, analysis C1; user direction: the orthodox, official, standard way)**:
Constitution V is not amended. Every reliance on undocumented upstream behavior is replaced by a
documented mechanism, a pattern of a bazelbuild/bazel-contrib ruleset, or an explicit English
error:
- G3 is withdrawn: `bun test` gets no `--config`. The second process of a `bun_test` runs with its
  working directory at the root of the target's copy tree, where the rule writes its own
  `bunfig.toml` (bun.com documents `$cwd/bunfig.toml` as the default and the project root as its
  place; corrected by Revision 11: that default is documented for the runtime only, and the rule
  writes no `bunfig.toml`), and test files are passed as `./`-relative paths under that root, which also removes the
  G9 limitation. `bun_binary` keeps `--config=<path>`, documented for the runtime.
- G8 is withdrawn: no `--pass-with-no-tests`. When `TESTBRIDGE_TEST_ONLY` is set and
  `TEST_TOTAL_SHARDS` is greater than 1, the launcher fails with an English error that filtering a
  sharded `bun_test` is not supported; a filter that selects nothing fails, as Bun reports.
- G13 is withdrawn: nothing is inserted. A program argument list that starts with `--` fails with
  an English error, because Bun 1.4.2 drops it.
- G7 stands on a ruleset pattern, not undocumented behavior: coverage files are named
  `<prefix>_<unique>.dat` in `COVERAGE_DIR`, as bazel-contrib/rules_python writes
  `pylcov_{}.dat` (`python/private/stage2_bootstrap_template.py`); `SF:` lines are rewritten from
  LCOV, a documented format, resolving each path against the copy-tree root.
- The load guard uses documented API only: `onLoad` (bun.com/docs/runtime/plugins), throwing from it
  (bun.com/docs/guides/test/svelte-test), `OnLoadArgs.path` as the resolved path
  (bun.com/reference/bun/OnLoadArgs), preloads running first (`--preload`).
- G14 is recorded in FR-028: the hermetic-launcher side of G4 is checked by the `MODULE.bazel`
  comment, not a test.
- FR-028 canaries remain only for upstream defects the rules work around (#43689/PR #36757, G1,
  G2, G4) and for the regex size limit; withdrawn workarounds need none.
The findings of the 2026-10-07 analysis (its own IDs, not gap numbers) F1, U1, I1, G1, G2, A1, P1, D1–D3, U2–U4, G3 and O1 are fixed in the
artifacts: the MUSTs of Revisions 8–10 move into FR-013, FR-018 and FR-024; FR-013 is the
allowlist; SC-006 takes reds on Linux and greens on three OSes.

**Revision 9 (2026-10-06, plan review; technical decisions by the implementer)**: (1) The prefix
trie also exceeds Bun 1.4.2's regular-expression size limit (about 20,000 paths with 100-character
unique suffixes, verified by the reviewer); the launcher MUST fail with an English error naming the
declared-file count when the pattern would exceed the limit measured on the pinned Bun, documented
as a limit and tested. (2) `bun_test` arguments are checked against an allowlist of options
bun.com documents for `bun test` and that undo nothing the rules guarantee, not a denylist: Bun
1.4.2 accepts attached and combined short options (`-talpha`, `-uts`, `-r./x.ts`) and options that
skip declared files (`--path-ignore-patterns`, `--changed`), all verified; anything not on the
allowlist fails with an English error naming it. (3) The guard reads its configuration from a file
whose path the launcher passes and never deletes it; a missing or unreadable configuration rejects
every load (fail closed), so `--isolate` does not rely on Bun re-exposing a deleted variable. (4)
FR-028 canaries cover every undocumented reliance, including G7 (merger `.dat`, `SF:` form) and the
guard (throwing `onLoad`, path form, preload order); each is a listed fixture with a recorded red
(a mutation of the pinned expectation). (5) The command-line length check uses the command line
actually built on the running OS; its fixture fixes the name lengths so it exceeds 32,767
characters on every OS. (6) Tests are added for the describe-label filter match (FR-016) and for a
`bun_binary` that exits non-zero (US1-1); one CI job runs with an output root whose path contains a
space (`--output_user_root`), covering runfiles paths with spaces.

**Revision 8 (2026-10-05, plan review; technical decisions by the implementer)**: G12: a
directory in `data` fails analysis with an English error and is documented as unsupported; an
upstream request goes to bazel-lib. G13: Bun 1.4.2 drops a leading `--` from the program's
arguments (verified: `bun <entry> -- x` gives `["x"]`); the launcher always inserts `--` after the
entry point, an exception to FR-017 pinned by a test (as G3). Further fixes the plan MUST carry:
the guard filter is built as a prefix trie, because one alternation over every declared path
exceeds Bun 1.4.2's regular-expression size limit at about 8,000 paths (verified), with a test at
a large declared set; programs and tests locate their data relative to `import.meta.dir`, which
works because Bun runs the copies (FR-012 for `bun_test`); `bun test --isolate` re-runs the guard
per file and is allowed; a guard error caught by the program's own `try`/`catch` does not fail the
run, and JSX needs the `react` package that npm support (a later feature) provides — both are
documented limitations; the second process's command line is kept within Windows' 32,767
characters or the run fails with an English error; the root `platforms` dependency is raised to
1.1.0, which `hermetic_launcher` requires (constitution IV); fixtures are added for standard input,
`BUN_OPTIONS` rejection, `BUN_RUNTIME_TRANSPILER_CACHE_PATH=0` and runfiles paths with spaces;
behavior steps record genuine reds, ordered so an isolation option is not already in place before
its test.

**Revision 7 (2026-10-04, G10–G11 decided by the user after a debate with Codex)**: Keep the
per-target copy tree (G6) and add a load guard. The launcher preloads a Bun plugin
(`Bun.plugin`, documented at https://bun.com/docs/runtime/plugins) whose `onLoad` filter matches
only absolute paths outside the target's declared file set and throws an English error naming the
file; declared files never reach the callback, so Bun's own resolution and loading are untouched.
On Bun 1.4.2 Linux this blocked an undeclared static import from ESM, CommonJS and `bun test`
while declared files ran normally; it covers stale copies (G10) and files reached by `../`
climbs, `package.json` `imports` or `node_modules` (G11). An `onResolve`-based guard was rejected:
Bun 1.4.2 does not call `onResolve` for bare specifiers, tsconfig `paths`, static imports under
`bun test` or `import.meta.resolve`, and reimplementing resolution diverges from Bun (it maps
`./x.js` to `x.ts`). The guard is a check, not complete isolation; these remain and MUST be
documented as known limitations: modules loaded before the guard (a `bunfig.toml` preload of the
first process, G4); code the program starts itself (Workers, child processes, `Bun.build`);
the influence of ancestor `tsconfig.json` and `package.json` on how a declared import resolves;
plain file reads (`Bun.file`, `fs`). Each guard behavior MUST be pinned by a test on every OS;
an unverified file type (TSX, `.node`, `.wasm`) is reported as such. The full fix is Bun honoring
`--preserve-symlinks` (oven-sh/bun PR #36757, commented on 2026-10-04). G12 (directories in
`data`): recommended option 1 (fail analysis with an English error, document as unsupported,
request upstream in bazel-lib), to be confirmed at the plan gate.

**Revision 6 (2026-10-03, plan gaps G6–G9 decided by the user)**: G6: each `bun_binary`/`bun_test`
copies its transitive inputs into its own tree under its package (`<name>.bun/`), so files of other
targets are not importable; `node_modules` and `tsconfig.json` in ancestor directories of the output
tree stay a documented limitation. G7: coverage writes `$COVERAGE_DIR/<unique>.dat` with `SF:`
rewritten to the source's path, an exception to FR-004 pinned by the CI coverage check. G8:
`--pass-with-no-tests` (in `bun test --help`, not on bun.com) is passed whenever a test filter is
set, an exception to FR-017 pinned by a test; a filter that selects nothing then passes. G9: a test
file the launcher cannot address relative to its working directory (another Windows drive) fails
with an English error, documented as a limitation.

**Revision 5 (2026-10-03, plan review)**: The plan relied on Bun reading sources through their
real paths in the source tree, which is undocumented and lets undeclared files, `node_modules`
and `tsconfig.json` in (verified with Bun 1.4.2). The user chose to copy every input into the
output tree (FR-003). The plan MUST also address what the review found:
- coverage: Bazel 9.2.0's merger reads only files ending in `.dat` from `COVERAGE_DIR`
  (`CoverageOutputGenerator`), which bazel.build does not document, and Bun's `SF:` path form is
  not documented; each is a gap under FR-004 unless a documented way is found;
  `bazel coverage --combined_report=lcov` produces the merged report the CI check reads, and that
  check MUST read it as a declared input or a command-line path, not a cached file;
- `--test_filter` with `shard_count > 1`: a shard whose files match nothing exits 1 with Bun
  1.4.2; the plan MUST define and test the result Bazel needs for that case;
- runfiles MUST include the entry point and preloads, not only `srcs`;
- tests that the spec requires and the plan lacked: a `bun_binary` built for the execution
  configuration carries that platform's Bun; a target platform without a stub toolchain fails
  analysis; an inherited variable that is set (FR-014), with the mechanism named;
- `$(rlocationpath ...)` in `env` only if bazel.build documents it for the API used;
- no limitation the user has not approved (for example tests on another Windows drive): each one
  is a gap for the plan gate.

**Revision 4 (2026-10-03, plan gaps G1–G5 decided by the user)**: FR-016b (snapshots unsupported),
FR-017 (one exception), FR-018a (first process may read `$cwd/bunfig.toml`), SC-006 (G5 red
substitute). G1 (Windows argument parsing in the stub, hermetic-launcher#80) waits for an upstream
release; see FR-001.

**Revision 3 (2026-10-02, third review)**: Corrected against the sources: only `MODULE.bazel`
registers toolchains; FR-003 is a stop condition, not a fallback; coverage follows `COVERAGE_DIR`
and `_lcov_merger`; `--shard` is documented as one-based and file-level; the stub cannot set
environment variables, so the launch chain and the place of each protection are stated, and what
remains is a reported gap (FR-018a); snapshot writes, preloads, the main module, protocol-owned
options, environment scrubbing in spawn tests and a network-free install fixture were added.

**Revision 2 (2026-10-01, second review and user decisions)**: The user approved launching through
hermeticbuild/hermetic-launcher and a public `//bun/toolchain:target_type`; the constitution was
amended to v1.2.0 (I, V, VI) accordingly, which settles former FR-001–FR-003. Bun documents a
test name filter, sharding and a JUnit reporter (https://bun.com/docs/cli/test), so all three are
mandatory. Isolation goes through a configuration file the rule supplies with `--config=`, which bun.com
documents as replacing the default `$cwd/bunfig.toml`. Positional arguments and options that would
undo isolation are rejected. Isolation is checked on every OS by spawning the launcher from a
directory the test prepares. Coverage and the transpiler cache were added.

## User Scenarios & Testing *(mandatory)*

Actors:

- **Consumer**: a Bazel module that depends on `rules_bun`, registers its toolchain, and declares
  Bun programs and Bun tests in its BUILD files.
- **Maintainer**: a person who changes `rules_bun` and must know, from test results alone, whether
  the change is correct on every supported platform.
- **Registry**: the Bazel Central Registry presubmit, which runs the consumer module (`e2e/smoke`)
  on every platform it lists.

Today the ruleset provides only a toolchain: a consumer who wants to run a Bun program or a Bun
test has to write their own rule. The toolchain is registered by execution platform only
(`exec_compatible_with`, `bun/private/toolchains_repo.bzl`) and its Bun is built for the execution
configuration (`cfg = "exec"`, `bun/private/toolchain.bzl`), which is right for build actions and
wrong for a program that runs on the target platform.

### User Story 1 - Run a Bun program (Priority: P1)

A consumer declares a Bun program in a BUILD file: an entry point, the TypeScript/JavaScript sources
it imports, and the data files it reads. `bazel run` on that target runs the entry point under the
Bun of the registered toolchain, with the arguments and environment the target declares.

**Why this priority**: It is the smallest thing that makes the ruleset usable for a Bun project,
and the test rule is the same mechanism with a different command.

**Independent Test**: A self-checking program imports a source from another package, reads a data
file, and checks its arguments and one environment variable; it exits non-zero when any of them is
wrong. CI invokes it with `bazel run` on each operating system (`args` and `env` exist only under
`bazel run` and `bazel test`, so no test target can observe them for a program).

**Acceptance Scenarios**:

1. **Given** a program target with an entry point, **When** it is run, **Then** Bun from the
   registered toolchain executes the entry point and the run exits with the program's exit code,
   zero or non-zero.
2. **Given** an entry point that imports a checked-in source file provided by another target, in
   the same or another package, **When** it is run, **Then** the import resolves.
3. **Given** a data file declared on the target or on something it depends on, checked in or
   produced by another rule, **When** the program looks the file up the documented way, **Then** it
   reads the file's content.
4. **Given** arguments declared on the target and arguments given after `--` on the `bazel run`
   command line, **When** the program runs, **Then** it receives the declared arguments, processed
   as bazel.build documents for `args` (location and Make-variable substitution, Bourne-shell
   tokenization), followed by the command-line arguments, and the launch mechanism changes no
   argument boundary or value, including empty arguments and arguments containing spaces or quotes.
5. **Given** environment variables declared on the target, **When** the program runs, **Then** it
   sees each declared variable with its declared value.
6. **Given** a program target, **When** it runs, **Then** its entry point is Bun's main module
   (`import.meta.main` is true) and `process.argv.slice(2)` equals the program's own arguments.

---

### User Story 2 - Run Bun tests (Priority: P1)

A consumer declares a Bun test target with its test files, the sources they import, and data.
`bazel test` runs exactly those test files with Bun's test runner and reports pass or fail.
Filtering, sharding, the XML report and coverage work as the Bazel test encyclopedia specifies.

**Why this priority**: A ruleset that cannot run tests is not complete, and `bazel test //...` is
what CI and the registry run.

**Independent Test**: A passing test target passes under `bazel test //...`. Targets that are
expected to fail are kept out of `//...` and checked by a mechanism that needs no shell written by
this repository (FR-021).

**Acceptance Scenarios**:

1. **Given** a test target whose tests all pass, **When** it is tested, **Then** the target passes.
2. **Given** a test target with one failing test, **When** it is tested, **Then** the target fails
   and the test log names the failing test.
3. **Given** a test file that sits next to the declared ones but is not declared on the target,
   **When** the target is tested, **Then** that file is not run.
4. **Given** environment variables declared on the target, some with values and some to be
   inherited from the invoking environment, **When** the tests run, **Then** they see each declared
   variable with its declared value and each inherited variable with the invoking value, with the
   precedence `RunEnvironmentInfo` documents.
5. **Given** a test that writes to the temporary directory Bazel provides (`TEST_TMPDIR`), **When**
   it runs, **Then** the write succeeds.
6. **Given** declared arguments and `--test_arg` values, **When** the target is tested, **Then**
   Bun's test runner receives the declared arguments followed by the `--test_arg` values.
7. *(FR-016)* **Given** `--test_filter`, **When** the target is tested, **Then** only
   the tests the filter selects run.
8. *(FR-016)* **Given** a target split into N shards, **When** it is tested, **Then**
   every test runs in exactly one shard, in the granularity research records, and each shard
   tells Bazel it supports sharding the way the encyclopedia requires.
9. *(FR-016)* **Given** a test run, **When** it finishes, **Then** the file Bazel
   names in `XML_OUTPUT_FILE` is a report written by Bun that names each test case that ran and its
   result.

---

### User Story 3 - Bun ignores undeclared configuration, `.env` files and does not install (Priority: P2)

Bun does three things by default that make a run depend on files and network state Bazel does not
track: it reads `bunfig.toml` from the working directory, it loads `.env` files, and it installs
missing packages when it finds no `node_modules`. A program or test target does none of them.

**Why this priority**: A result that depends on untracked state cannot be trusted or cached.

**Independent Test**: For each of the three, a test prepares the fixture in a directory under
`TEST_TMPDIR` and spawns the target's launcher there with Bun's documented process API, on Linux,
macOS and Windows. The fixture is first shown to change the result when the protection is absent
(the red record of FR-020), then shown to have no effect with the rule.

**Acceptance Scenarios**:

1. **Given** a `bunfig.toml` in the working directory whose setting no option of the rule
   overrides (for example a `preload` that sets a global), **When** a program or test runs, **Then**
   the setting does not take effect.
2. **Given** a `.env` file in the working directory that defines a variable the invoking
   environment does not, **When** a program or test runs, **Then** the variable is not set.
3. **Given** a program that imports a package that is not present, no `node_modules` directory in
   the working directory the test creates, and Bun's install cache pointed at an empty temporary
   directory, **When** it runs, **Then** it fails with Bun's module-not-found error and the cache
   directory is still empty; the same fixture without the protection installs into the cache (the
   red record). The package comes from a registry the test serves locally, so no run needs the
   network.
4. **Given** a program or test whose source imports a checked-in file that sits next to it but is
   not declared on the target, **When** it runs, **Then** the import fails with Bun's
   module-not-found error, on every OS and with or without a runfiles tree.

---

### User Story 4 - Same behavior on Linux, macOS and Windows (Priority: P2)

A consumer on any of the three operating systems gets stories 1–3. On Windows, where Bazel by
default creates no runfiles directory tree and provides only a manifest, programs and tests still
find their sources and data. The Bun that runs is the one for the platform the program runs on,
which is not always the platform the build runs on.

**Why this priority**: Windows is a supported platform (constitution VI), and a target built for
another platform must carry that platform's Bun or it cannot run there.

**Independent Test**: CI runs the root and consumer test sets and the `bazel run` check on the
three operating systems; one more CI job runs them on Linux with the runfiles tree disabled; an
analysis test sets a target platform different from the host and checks which Bun the target
carries.

**Acceptance Scenarios**:

1. **Given** Windows with Bazel's default runfiles setting (no tree), **When** the program and test
   targets of stories 1–3 run, **Then** they pass.
2. **Given** Linux with `--noenable_runfiles`, **When** the same targets run, **Then** they pass,
   so the manifest-only path is also verified where the maintainer can run it locally.
3. **Given** a target platform P that differs from the execution platform, **When** a program or
   test target is analyzed, **Then** the Bun among its run-time files comes from the repository for
   P, and a toolchain whose Bun is a generated file has that file built for P, not for the
   execution platform.
4. **Given** a target platform for which no Bun toolchain is registered, **When** a program or
   test target is analyzed, **Then** it does not receive the Bun of the host or of the execution
   platform.
5. **Given** an existing rule that runs Bun in a build action through `BUN_TOOLCHAIN_TYPE`,
   **When** it is built after this feature, **Then** it still gets the Bun of the execution
   platform; the tests of feature 001 pass unchanged.

---

### User Story 5 - The consumer module uses both rules (Priority: P3)

The example consumer module gains one Bun program and one Bun test, declared only through the
public API and with exactly the dependency versions the ruleset declares.

**Why this priority**: It proves the rules work from outside the ruleset; it depends on stories 1–4.

**Independent Test**: On Linux, macOS and Windows, with Bazel's default settings (the module has no
`.bazelrc`), `bazel test //...` passes including the Bun test, and `bazel run` on the
self-checking program exits zero.

**Acceptance Scenarios**:

1. **Given** the consumer module as checked in, **When** its full test set runs, **Then** the Bun
   test target runs and passes.
2. **Given** the consumer module's program target, **When** CI runs it with `bazel run`, **Then**
   it exits zero, and it would exit non-zero if an import, a data file, an argument or an
   environment variable were wrong.
3. **Given** the consumer module, **When** `git grep -n 'bun/private' -- e2e` runs, **Then** it
   prints nothing; the hand-back record keeps the output.

### Edge Cases

- Runfiles paths that contain spaces (common in Windows user directories): programs and tests
  still find their files.
- The entry-point attribute does not name exactly one TypeScript or JavaScript file, or a test
  target declares no test file: analysis fails with an English message that names the attribute.
- A test filter that matches no test, and a shard that receives no test file (more shards than
  files, which Bun's documented file-level slicing allows): Bazel's encyclopedia does not define
  the result. Research records what Bun does and a test pins it.
- Working directory: Bazel documents it (tests start in `$TEST_SRCDIR/$TEST_WORKSPACE`; `bazel run`
  starts in the runfiles tree of the binary). The rules do not change it, except that the second
  process of a `bun_test` runs at the root of the target's copy tree (FR-018, Revisions 10–11). On
  Windows without a runfiles tree the runfiles directory holds no source files, so nothing may
  depend on reading files relative to it.
- Bun's default per-test timeout (5 seconds) is independent of Bazel's `timeout`; the rule does
  not change it, and a consumer sets it through declared arguments.
- A program target outside `bazel run` and `bazel test` (run from `bazel-bin`, or used as a tool of
  a build action) does not get `args` or `env`; Bazel documents this, and the rules do not try to
  change it.
- A test written first passes before implementation: the test is wrong and must be changed until
  it fails for the expected reason (FR-020).

## Requirements *(mandatory)*

### Decisions made, and stop conditions

- **FR-001 (launcher, decided; restated by Revision 13)**: Programs and tests MUST launch as the
  bazelbuild and bazel-contrib rulesets do (constitution VI, v2.0.0). The chain has three steps on
  every operating system; only the first differs:
  1. the executable starts the target platform's Bun on the rule's static JavaScript launcher and
     the target's launch configuration file:
     - on Linux and macOS, the executable is a shell launcher the rule generates. It finds its
       files with Bazel's runfiles library for Bash, used as that library documents (research
       records its label for Bazel 9.2.0, its source, the bazel-contrib pattern followed and the
       lowest dependency version, constitution IV), and execs Bun with
       `--config=<resolved path of the rule's configuration file>`, `--no-env-file`, the static
       JavaScript launcher, the launch configuration file and its own arguments;
     - on Windows, where Bash is not guaranteed, the executable is a native stub from
       hermeticbuild/hermetic-launcher (BCR module `hermetic_launcher`; approved by the user on
       2026-10-01, constitution V, the Windows launcher only since v2.0.0). The stub starts Bun
       with embedded arguments `--no-env-file`, the static JavaScript launcher and the launch
       configuration file. It cannot embed the rule's configuration file, because Bun applies only
       `--config=<path>` as one argument and the stub resolves only whole arguments through
       runfiles (gap G4, FR-018a, Windows only);
  2. the JavaScript launcher resolves files, maps the Bazel test protocol and prepares the
     environment; it is the same file on every OS, so the stub's inability to set arbitrary
     environment variables (hermetic-launcher issue #78, open) changes nothing on Windows;
  3. it starts the program or `bun test` in a second Bun process, so that the consumer's entry
     point is the main module (`import.meta.main` is true) and sees only its own arguments.

  Neither launcher documents that arguments are forwarded unchanged end to end, so that MUST be
  proven by tests on each OS (empty arguments, spaces, quotes). On Windows, hermetic-launcher
  documents runfiles resolution from a tree and from a manifest and stubs for a target platform
  other than the host; research MUST record those sources, how rules_js uses it (as an
  experimental, off-by-default option), and the lowest version that works (constitution IV). The
  Windows stub of `hermetic_launcher` 0.0.16 splits arguments with embedded quotes and drops
  runtime arguments past 128 (gap G1, hermetic-launcher#80, decided 2026-10-03): the Windows test
  of quoted arguments waits for a release that fixes it, and until then the limitation MUST be
  documented. hermetic-launcher documents a limit of 10 embedded arguments of at most 256 bytes
  each: a Windows target that would exceed it MUST fail analysis with an English message. A
  Windows target platform for which no stub toolchain is registered MUST fail analysis as well,
  never fall back to a shell script. Existing tests of the stub apply to Windows targets only.
- **FR-002 (target toolchain, decided)**: The rules MUST resolve Bun through a new public toolchain
  type `//bun/toolchain:target_type` (constitution I, v1.2.0), whose toolchains are matched by
  target platform and whose Bun is built for the target configuration. The repository the `bun`
  module extension generates MUST declare toolchains of this type for every supported platform, so
  that the consumer's existing `register_toolchains("@bun_toolchains//:all")` registers them
  (a repository an extension generates cannot register toolchains; bazel.build documents
  `register_toolchains()` in `MODULE.bazel` and `--extra_toolchains`), and a consumer MUST be able to register their own.
  `//bun/toolchain:execution_type` and its behavior stay unchanged.
- **FR-003 (sources run from the output tree, decided 2026-10-03)**: Bun 1.4.2 resolves imports
  from the real path of the importing file and ignores `--preserve-symlinks` and
  `--preserve-symlinks-main` (observed; oven-sh/bun#43689 and #36755 are open), so imports through
  runfiles symlinks or a manifest reach the consumer's source tree, where undeclared files,
  `node_modules` and `tsconfig.json` are visible. The user chose the design rules_js uses: every
  source, test file, preload and data file a target uses MUST be copied (not symlinked) into the
  output tree by a shell-free action, following the `copy_to_bin` pattern of
  bazel-contrib/bazel-lib, and Bun MUST run those copies. Research MUST record the sources for
  this pattern and for the layout of the output tree it relies on; if that layout is not
  documented, work MUST stop and the gap MUST be reported. With this, imports resolve between the
  copies on every OS and runfiles setting, and an undeclared file is not there to import.
- **FR-004 (everything else)**: If no documented Bazel API or documented Bun feature provides a
  mandatory requirement of this specification, work on it MUST stop and the gap MUST be reported;
  recording it does not satisfy the requirement.

### Functional Requirements

**Rules**

- **FR-005**: The ruleset MUST provide a rule that makes a Bun program an executable target
  (`bun_binary`) and a rule that makes Bun tests a test target (`bun_test`), loadable from
  `bun/*.bzl`, with implementation in `bun/private/`.
- **FR-006**: Both rules MUST accept checked-in TypeScript and JavaScript sources, data files
  (checked in or generated), and dependencies on other targets that provide sources and data.
  Whether a separate library rule is needed to carry sources between targets is decided by
  research against the reference rulesets; if one is added it is part of this feature and is
  loaded from `bun/*.bzl`.
- **FR-007**: `bun_binary` MUST take exactly one entry-point file and MUST fail analysis, in
  English, otherwise. `bun_test` MUST run exactly the test files declared on the target — it MUST
  NOT let Bun discover other files, including sources of dependencies — and MUST fail analysis, in
  English, when none is declared.
- **FR-008**: Both rules MUST work without npm packages. They MUST NOT add package installation,
  `bun.lock` handling or bundling as consumer features, which are later features.

**Toolchain**

- **FR-009**: The Bun that runs a program or test MUST come only from a toolchain registered for
  `//bun/toolchain:target_type` and MUST be resolved for the target platform of the program or test
  target, with the mechanism bazel.build documents (https://bazel.build/extending/toolchains). Both the selection (which
  repository the Bun comes from) and the configuration (a generated Bun is built for the target
  platform) MUST be tested. A host-installed Bun MUST never be used (constitution III).
- **FR-010**: Rules that run Bun in build actions through `BUN_TOOLCHAIN_TYPE` MUST keep working,
  and the tests of feature 001 MUST pass without being changed.

**Running**

- **FR-011**: Sources, data and Bun itself MUST be found at run time on Linux, macOS and Windows
  through the documented runfiles libraries or mechanisms, both when a runfiles directory tree
  exists and when only a runfiles manifest exists.
- **FR-012**: A consumer's program or test MUST have a documented way to locate its data files that
  works in both of those cases. bazelbuild publishes no JavaScript runfiles library and npm
  packages are out of scope, so research MUST name the mechanism (for example the
  `RUNFILES_DIR` / `RUNFILES_MANIFEST_FILE` variables the stub can export, read as Bazel's runfiles
  specification describes, or a helper the launcher makes importable) with its source; if it
  needs a new public file or target, that is reported at the plan gate.
- **FR-013**: `args` MUST behave as bazel.build documents for executable and test rules
  (https://bazel.build/reference/be/common-definitions): substitution and tokenization of declared
  arguments are Bazel's; they precede `bazel run` arguments or `--test_arg` values; the launch
  mechanism MUST preserve every argument boundary and value it is given. `bun_binary` arguments go
  to the program, and nothing is inserted before them; an argument list whose first argument is
  `--` MUST fail with an English message, because Bun 1.4.2 drops a `--` directly after the entry
  point (Revision 10, G13 withdrawn). `bun_test` arguments go to Bun's test runner after the
  options the rule itself sets, and each MUST equal a form on an allowlist: options bun.com
  documents for `bun test` that undo nothing the rules guarantee (FR-003, FR-007, FR-016,
  FR-016a, FR-016b, FR-018 including its load guard, FR-019); research R8 lists the forms and why
  each other documented option is not on it. Anything else — a positional argument (`bun test`
  treats it as a file filter, https://bun.com/docs/test), a bare `--`, any short option including
  attached and combined forms (`-talpha`, `-uts`, `-r./x.ts`), a documented option not on the list
  (for example `--path-ignore-patterns`, `--changed`), an undocumented one — MUST fail with an
  English message that names the argument (Revision 9). The declared test files MUST be passed as
  `./`-relative paths under the working directory of the second process (FR-018), which `bun test`
  does not treat as filters. The command line of the second process, measured as the running OS
  builds it, MUST stay within 32,767 characters on every OS, or the run MUST fail with an English
  message naming the length and the limit (Revisions 8–9).
- **FR-014**: Declared environment variables MUST be provided through `RunEnvironmentInfo`, and
  `bun_test` MUST also support variables inherited from the invoking environment. Tests MUST cover
  a declared variable, an inherited variable that is set, one that is unset, and a name that is
  both declared and inherited. Any substitution the rules perform in `env` values MUST be one
  bazel.build documents.
- **FR-015**: The exit code of a run MUST be the exit code of Bun. Standard input, output and error
  MUST pass through.

**Test protocol**

- **FR-016**: `bun_test` MUST leave every variable and writable location the Bazel test
  encyclopedia defines (https://bazel.build/reference/test-encyclopedia) available to the tests
  unchanged, and MUST connect each of these to the documented Bun feature
  (https://bun.com/docs/test), proven by a test:
  - filter: `--test_filter` / `TESTBRIDGE_TEST_ONLY` → `-t`/`--test-name-pattern`
  - sharding: `TEST_TOTAL_SHARDS`, `TEST_SHARD_INDEX` (zero-based) → `--shard=<index + 1>/<total>`;
    bun.com documents `--shard=i/n` as one-based and as slicing the test files sorted by path
    (https://bun.com/docs/test/parallel). The launcher touches `TEST_SHARD_STATUS_FILE`.
  - XML report: `XML_OUTPUT_FILE` → `--reporter=junit --reporter-outfile`

  bun.com documents that the pattern is matched against "the test name prefixed with the labels
  of all its parent describe blocks, separated by spaces" (https://bun.com/docs/test/discovery);
  a test MUST cover that. Research MUST record, and a test MUST pin, what bun.com leaves open: the
  exit code when a filter or shard selects nothing. A filter that selects nothing fails, as Bun
  reports it; no undocumented option is passed. When `TESTBRIDGE_TEST_ONLY` is set and
  `TEST_TOTAL_SHARDS` is greater than 1, the launcher MUST fail with an English error that
  filtering a sharded `bun_test` is not supported (Revision 10, G8 withdrawn).
- **FR-016a**: `bazel coverage` on a `bun_test` target MUST follow the protocol bazel.build
  documents for test rules (https://bazel.build/extending/rules#code-coverage): the test writes
  LCOV files with unique names into `COVERAGE_DIR`, using Bun's documented `lcov` coverage
  reporter, and the rule declares the `_lcov_merger` attribute and instrumented files as that page
  shows. CI MUST run `bazel coverage` on one `bun_test` and check that the merged report names a
  source file. If a step has no documented way, FR-004 applies.
- **FR-016b (decided 2026-10-03, gap G2)**: Snapshot tests are not supported by `bun_test` in this
  feature and MUST be documented as unsupported. Bun documents no way to stop writing snapshot
  files, and with `CI=true` Bun 1.4.2 still creates a header-only `.snap` file (oven-sh/bun#44531).
  `--update-snapshots` is still rejected (FR-013).
- **FR-016c**: `bun_test` MUST accept preload (setup) files as declared inputs. bun.com documents
  test preloads in `bunfig.toml`, but documents no `bunfig.toml` lookup for `bun test`
  (oven-sh/bun#45331), so the rules offer no `bunfig.toml` as a way to set them (FR-018,
  Revision 11).
- **FR-017**: A Bun feature counts as supported only if it is documented on bun.com and a test
  shows it working on the Bun version the module pins. There is no exception: the G3 exception
  (`--config=<path>` for `bun test`) is withdrawn by Revision 10, and so are G8 and G13.

**Isolation**

- **FR-018**: At run time the second Bun process of FR-001, the one that runs the consumer's
  program or tests, MUST NOT take a `bunfig.toml` or a `.env` file from a place the target does not
  declare, and MUST NOT install packages:
  - `bun_binary`: the only configuration file Bun reads is the rule's, passed with
    `--config=<path>`, which bun.com documents for the runtime as "Specify path to Bun config file.
    Default `$cwd/bunfig.toml`" (https://bun.com/docs/runtime); that file MUST set `env = false`
    and `install.auto = "disable"` (https://bun.com/docs/runtime/bunfig). Bun 1.4.2 ignores
    `-c=<path>`, and runs `<path>` as the entry point when given `--config <path>` or `-c <path>`
    (gap G4, canary C4). `--no-env-file` and `--no-install`, documented for the runtime, are added.
  - `bun_test` (Revision 11): bun.com documents neither `--config` for `bun test` nor where
    `bun test` looks for `bunfig.toml` (the `$cwd/bunfig.toml` default is documented for the
    runtime only; oven-sh/bun#45331 asks for it), so the rule passes no configuration option and
    makes no claim about Bun's lookup. What the rule guarantees, and a test checks on every OS, is
    the Bazel side: the second process runs with its working directory at the root of the target's
    copy tree, which holds only the copies of declared files (FR-003), each under its repository
    directory, so no file sits at the root itself; the rule writes no `bunfig.toml` into the tree.
    A `bunfig.toml` or `.env` the target declares is a declared input, and Bun may use it, which is
    hermetic. Whether `bun test` also searches the parent directories of its working directory is
    undocumented and MUST be documented as an unverified limitation. bun.com documents no option
    that turns auto-install off for `bun test`; Bun 1.4.2 does not auto-install there (gap G5,
    observed), which the install fixture of US3-3 checks on every OS; if that changes, FR-004
    applies. No option bun.com does not document for `bun test` is passed.
  - The launcher sets `BUN_RUNTIME_TRANSPILER_CACHE_PATH=0` for the second process. A set
    `BUN_OPTIONS`, which bun.com documents as prepending arguments to any Bun execution
    (https://bun.com/docs/runtime/environment-variables), is rejected with an English error: on
    Linux and macOS by the shell launcher before any Bun starts (Revision 15), and by the
    JavaScript launcher before the second process.
  - Load guard (Revisions 7–10): the second process first preloads a `Bun.plugin` whose `onLoad`
    filter matches only module paths outside the target's declared copies and throws an English
    error naming the file, using only documented API: `onLoad` (https://bun.com/docs/runtime/plugins),
    throwing from it (https://bun.com/docs/guides/test/svelte-test), `OnLoadArgs.path` as the
    resolved path (https://bun.com/reference/bun/OnLoadArgs), and `--preload`, which runs before
    other modules load. The filter MUST be built as a prefix trie of the declared paths, tested
    with a large declared set (Revision 8). The guard MUST read its configuration from a file whose
    path the launcher passes and MUST never delete it; when the configuration is missing or
    unreadable it MUST reject every load (fail closed, Revision 9). When the pattern would exceed
    the regular-expression size limit measured on the pinned Bun, the launcher MUST fail with an
    English error naming the declared-file count, documented as a limit and tested (Revision 9).
    `bun test --isolate`, which re-runs preloads per file (https://bun.com/docs/test/parallel), is
    allowed. A guard error caught by the consumer's own `try`/`catch`, and JSX, which needs the
    `react` package that npm support provides, MUST be documented as limitations (Revision 8).
  None of this is delivered through `RunEnvironmentInfo`, so it holds outside `bazel run` and
  `bazel test` as well. Research MUST record each option and its source.
- **FR-018a (first process; Windows limitation)**: On Linux and macOS the shell launcher starts the
  first Bun process with `--config=<resolved path>` and `--no-env-file` after rejecting a set
  `BUN_OPTIONS` (Revisions 13, 15), so the first process is isolated like the second. On Windows the
  hermetic-launcher stub starts it with `--no-env-file` only, because the stub cannot inspect or set
  the environment (hermetic-launcher#78) and cannot pass `--config=<runfiles path>` as one argument
  (hermetic-launcher#81, G4). There an inherited `BUN_OPTIONS` reaches the first process and can
  replace the launcher, and the first process may read `$cwd/bunfig.toml` (the runfiles root) and
  write a transpiler cache entry for the launcher script. These Windows limitations MUST be
  documented, not presented as isolated, and the `BUN_OPTIONS` one is pinned by a canary on the
  Windows CI job.
- **FR-019**: These protections guard against state the target did not declare. They are not
  attributes a consumer can switch (see Proposed boundaries).

**Process**

- **FR-020**: A task that changes observable behavior MUST first add or change a test, run it and
  record that it fails for the expected reason, then implement until it passes. A red state MAY be
  an analysis or build error when the missing behavior makes the target unanalyzable, as long as
  the error names the missing behavior. A test that guards behavior which already exists MUST
  record its red by a mutation that breaks that behavior, marked as a mutation and reverted. A task
  that only refactors records the existing tests that still pass. A research or documentation task
  records no test. The records are kept with the feature.
- **FR-021**: Root tests MUST cover the rules with `analysistest` (providers including
  `RunEnvironmentInfo`, toolchain per target platform, analysis failures) and with real runs:
  `bun_test` targets under `bazel test //...`, and `bun_binary` through the CI `bazel run` step.
  Cases that are expected to fail at run time (a failing test, a non-zero exit, the missing
  package) MUST be checked without making `bazel test //...` fail: a passing `bun_test` locates the
  failing target's launcher through runfiles, spawns it with Bun's documented process API, and
  asserts its exit code and output. The spawn MUST remove the parent's test-protocol variables
  (`XML_OUTPUT_FILE`, `TEST_TOTAL_SHARDS`, `TEST_SHARD_INDEX`, `TEST_SHARD_STATUS_FILE`,
  `TESTBRIDGE_TEST_ONLY`, `COVERAGE_DIR`) from the child's environment, so the child cannot
  overwrite the parent's outputs, and MUST keep the runfiles variables, because the child's files
  are in the parent's runfiles. The failing targets are tagged `manual`.
- **FR-022**: Every action of the rules that runs a tool MUST use `ctx.actions.run` with `Args`.
  The rules and tests of this repository MUST NOT call `ctx.actions.run_shell`. The only shell
  script the rules generate is the Linux and macOS launcher of a `bun_binary` or `bun_test`, built
  with Bazel's runfiles library for Bash (constitution v2.0.0 VI, Revision 13); no Windows build or
  run requires Bash. Launchers generated by bazel-skylib rules are allowed.
- **FR-023**: The consumer module MUST gain a `bun_binary` and a `bun_test` that use only the
  public API, and MUST pass with exactly the declared dependency versions. A new non-dev
  `bazel_dep` of the ruleset MUST declare the lowest version that works (constitution IV).
- **FR-024**: CI MUST run, on Linux, macOS and Windows, the root and consumer test sets and
  `bazel run` on the self-checking programs; on Linux once more with `--noenable_runfiles`,
  including the `bazel run` step; once, on Windows, the root and consumer test sets and the
  `bazel run` step with an output root whose path contains a space
  (`bazel --output_user_root="C:/bazel root"`, Revision 9); and `bazel coverage` once (FR-016a).
- **FR-025**: All text this feature adds to the repository — diagnostics, docstrings, specs, commit
  messages — MUST be English (AGENTS.md).
- **FR-026**: Documentation and reports MUST claim only behavior a test covers and MUST name the
  platforms each test actually ran on; anything else is reported as unverified (constitution II).
- **FR-028 (upstream canaries)**: Every place where this feature works around an upstream defect
  (the copy tree and load guard for oven-sh/bun#43689 / PR #36757; G2 oven-sh/bun#44531; G4
  hermetic-launcher#81; G1 hermetic-launcher#80) or depends on the regular-expression size limit of
  the pinned Bun (FR-018) MUST have a canary test that pins the current upstream behavior and
  fails, with an English message naming the workaround to remove or revisit and the upstream link,
  as soon as the pinned Bun or `hermetic_launcher` version changes that behavior. Withdrawn
  workarounds (G3, G8, G13; Revision 10) need none. G14 (decided 2026-10-06): hermetic-launcher's
  side of G4 has no API a test could call, so it is checked by a comment next to the
  `hermetic_launcher` `bazel_dep` in `MODULE.bazel` ("On any hermetic_launcher bump, check
  hermetic-launcher#81 (G4) and #80 (G1)"), not by a test; Bun's side of G4 has a canary.
- **FR-027**: `research.md` MUST record the source URL for every API and every Bun option the
  design relies on, and how each reference ruleset solves the same problem. Constitution V names
  bazelbuild and bazel-contrib rulesets; rules_js is at aspect-build and is consulted because the
  user named it, so a pattern found only there MUST be reported as such. rules_js documents its
  hermetic launcher as experimental and off by default (`docs/hermetic_launcher.md`), which MUST
  be recorded with the approval.

### Key Entities

- **Bun program target**: an executable target; has one entry point, sources, data, dependencies,
  arguments and environment; carries the target platform's Bun among its run-time files.
- **Bun test target**: a test target; has declared test files, supporting sources, data,
  dependencies, arguments and environment; speaks the Bazel test protocol on behalf of Bun's test
  runner.
- **Source provider**: a target that gives sources and data to the targets depending on it; either
  an existing kind of target or a library rule, decided by research.
- **Bun toolchains**: toolchains of `//bun/toolchain:execution_type` (Bun for build actions,
  unchanged) and of the new public `//bun/toolchain:target_type` (Bun for programs and tests, built
  for the target platform); the repository the extension generates declares both, the consuming
  module registers them, and consumers may register their own.
- **Gap report**: a requirement no documented API satisfies, with the sources examined and the
  options, handed to the user for a decision.
- **Test-first record**: per task, the failing run before implementation; for guard tests the
  reverted mutation; for refactors the passing existing tests.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A consumer can run a Bun program and a Bun test by declaring one target each, with no
  rule of their own.
- **SC-002**: On 3 of 3 CI operating systems, the consumer module passes with Bazel's default
  settings and the root module passes with its checked-in settings, each including the real
  program run.
- **SC-003**: The same sets pass on Linux with the runfiles tree disabled.
- **SC-004**: Every acceptance scenario is covered by at least one test target, except: a
  program's declared `args` and `env` end to end (story 1, scenarios 4–5), which Bazel applies only
  under `bazel run` and which the CI `bazel run` step covers, with an `analysistest` on
  `RunEnvironmentInfo` and a spawn test of argument forwarding as test targets; and story 5,
  scenario 3, a recorded `git grep`.
- **SC-005**: Zero `run_shell` calls; the only shell scripts the rules write are the Linux and macOS
  launchers of Revision 13; a Windows CI job passes in which Bazel's shell (`--shell_executable`)
  and rules_shell's toolchain (`--repo_env=BAZEL_SH`) name a path that does not exist and every
  action that takes Bazel's default environment, test and `bazel run` process starts with a `PATH`
  that names no Bash directory (`--action_env`, `--host_action_env`, `--test_env`, `--run_env`;
  Revision 14); launchers generated by bazel-skylib rules do not count.
- **SC-006**: For 3 of 3 isolation cases (configuration file, environment file, package install),
  a fixture changes nothing with the protection on 3 of 3 CI operating systems (green), and was
  proven on Linux to change the result without it (red, FR-020); for `bun_test` and package
  install, where Bun 1.4.2 does not auto-install even without the protection, the recorded
  observation replaces that red (gap G5, decided 2026-10-03).
- **SC-007**: For every supported platform other than the host, an analysis test shows the target
  carries that platform's Bun.
- **SC-008**: 100% of behavior-changing tasks have the record FR-020 requires.
- **SC-009**: Every gap is listed in `research.md` and shown to the user at the plan gate before
  any task for that requirement exists in `tasks.md`.

## Assumptions

### Proposed boundaries (approved or changed together with this specification)

These are scope choices the request leaves open. Approving the specification approves them.

- **No isolation switches.** "Unless the rule allows it explicitly" is read as: off by default, and
  attributes for a target's own `bunfig.toml`, for `.env` loading or for installing are later work.
  Options that would undo the protections are rejected (FR-013).
- **No working-directory attribute.** `js_binary` has `chdir`; an equivalent is later work. Under
  `bazel run`, Bazel's documented `BUILD_WORKING_DIRECTORY` is available to the program.
- **Generated sources are out of scope.** The request says "sources are in the workspace".
  Generated data files are in scope; importing a generated TypeScript/JavaScript file is not, and
  is reported as unverified.
- **Use as a build-action tool is analyzed, not run.** An analysis test checks that a `bun_binary`
  built for the execution configuration carries that platform's Bun. A real run in that position
  is not required and is reported as unverified.
- **Only the named isolation items.** Other ambient inputs Bun documents — `tsconfig.json`
  (including its `paths`), a `node_modules` directory above the working directory, `NODE_PATH`,
  and variables that change Bun's test output — are not addressed here and are reported as
  unverified. The test encyclopedia says "The environment may contain additional entries", so
  their absence is not guaranteed.
- **Only the named test-protocol items.** Fail-fast, premature-exit detection and random seed are
  not requested; `bun_test` only leaves their variables untouched. Process-tree
  cleanup on timeout or signal is not a requirement and is reported as unverified.
- **Standalone compiled executables, watch mode and debugging attributes are not consumer
  features of this change.**

### Other assumptions

- Local verification runs on Linux only (WSL); macOS and Windows results come from CI and are
  reported as unverified until CI succeeds there. Other target platforms are verified by analysis
  only, because their Bun cannot run on the CI hosts.
- The root module's checked-in settings (`.bazelrc`, and `--config=ci` in CI, which retries a
  failing test once) stay as they are; only the consumer module runs with Bazel's defaults.
- Story 4 scenario 4 is asserted with `analysistest` and `expect_failure = True`
  (https://bazel.build/rules/testing).
- BCR has `hermetic_launcher` 0.0.16 (2026-10-01, after hermeticbuild/hermetic-launcher#79), which
  contains the macOS fix 317d4a8 that 0.0.15 lacks. Research records the lowest version that works
  on all three operating systems.
- `hermetic_launcher` 0.0.15 and 0.0.16 declare `platforms` 1.1.0 and `bazel_skylib` 1.9.0, so adding it
  raises what consumers resolve; constitution IV allows a raise the change needs, and the consumer
  module MUST pass with the resulting versions.
- The supported Bazel range stays `>=9.2.0`, and the Bun version the tests pin stays the one
  `MODULE.bazel` requests.
- Rule and attribute names follow the reference rulesets (`srcs`, `data`, `deps`, `args`, `env`,
  an entry-point attribute); the exact set is fixed in the plan from research.
- Constitution v1.2.0 names `bun/*.bzl` and `//bun/toolchain:target_type` as public, so the new
  rules and toolchain type need no further amendment.
- Feature 001's FR-011 ("no rules that run Bun programs or tests", "no other public targets") is
  superseded by `AGENTS.md` as revised in commit 75ff1a6 and constitution v1.2.0.
- The registry presubmit runs only on a registry pull request after a release tag, so it is not a
  criterion of this feature; it runs test targets only, so the consumer program's real run is
  verified by CI.
