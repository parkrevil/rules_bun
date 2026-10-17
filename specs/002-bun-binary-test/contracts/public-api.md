# Contract: rules_bun Public API after feature 002

Constitution I (v2.0.0): the public API is `bun/*.bzl`, `//bun/toolchain:execution_type` and
`//bun/toolchain:target_type`. **New** marks additions; nothing is removed, renamed or changed in
behavior.

## Toolchain types

| Label | Resolved against | Status |
|---|---|---|
| `//bun/toolchain:execution_type` | execution platform | unchanged |
| `//bun/toolchain:target_type` | target platform | **new** |

## `@rules_bun//bun:defs.bzl`

| Symbol | Kind | Contract |
|---|---|---|
| `BUN_TOOLCHAIN_TYPE` | `Label` | unchanged (`execution_type`) |
| `BUN_TARGET_TOOLCHAIN_TYPE` | `Label` | **new**; equals `//bun/toolchain:target_type` |
| `BunInfo` | provider | unchanged |
| `BunLibraryInfo` | provider | **new**; fields `srcs: depset[File]` (transitive sources), `data: depset[File]` (transitive data files) |
| `bun_library` | rule | **new**; `srcs`, `data`, `deps` |
| `bun_binary` | executable rule | **new**; `entry_point`, `srcs`, `data`, `deps`, `env`, plus Bazel's common executable attributes (`args`, …) |
| `bun_test` | test rule | **new**; `srcs` (test files), `data`, `deps`, `preload`, `env`, `env_inherit`, plus Bazel's common test attributes (`args`, `shard_count`, `size`, …) |

Behavior promised to consumers (each covered by a test named in data-model.md). Platforms: root
`bazel test //...`, which holds the tests that run targets and the analysis tests, passes on Linux
(WSL; tdd-log.md) and, in CI run 39051132545 of POST-1 (commit 63044a8), on the GitHub Actions
images `ubuntu-24.04`, `macos-26-arm64` and `windows-2025-vs2026`. An item tested on fewer
platforms, or unverified, says so.

- The Bun that runs comes from a toolchain of `target_type` resolved for the target's platform.
  With no such toolchain, analysis fails with an English message naming the missing toolchain
  type. On a Windows target, analysis also fails this way when no hermetic-launcher stub exists
  for that platform.
- Launching (FR-001, Revision 13): on Linux and macOS the target's executable is a shell launcher
  that finds its files with Bazel's runfiles library for Bash (`@rules_shell//shell/runfiles`).
  It works with a runfiles tree and with a manifest only, including `bazel run
  --noenable_runfiles` and `bazel test` without a sandbox. Running it needs `/usr/bin/env`, `bash`
  and the utilities that library calls (`grep`, `sed`, `cut`, `tr`, `wc`, `awk`, `tail`, `uname`,
  `dirname`, `basename`) on the machine that runs the target; tested on Linux and macOS.
  `bazel run --noenable_runfiles` and `bazel test` without a sandbox ran on Linux only (job
  `manifest-only`). For a Windows target platform the executable is a native hermetic-launcher
  stub (`<name>.exe`); the builds, tests and `bazel run` of both modules pass without Bash on
  Windows (job `windows-without-bash`: Bazel's shell set to a path that does not exist, no Bash
  directory on the `PATH` of actions, tests and `bazel run`).
- Files: each `bun_binary`/`bun_test` copies its entry point or test files, sources, preloads and
  data files, including those of its `deps`, into its own directory `<name>.bun/` next to its
  outputs, and Bun runs those copies. A file the target does not declare, even one next to a
  declared file in the source tree, is not in that directory, so importing it fails with Bun's
  module-not-found error. A directory in `data`, direct or through `deps`, fails analysis with an
  English message naming `data` and the directory.
- Load guard: if Bun is about to load a module file outside that declared set (for example a copy
  left from an earlier build, or a file reached by a `../` import, `package.json` `"imports"` or
  `node_modules`), the run fails with an English error that names the file. If the guard cannot
  read its configuration, it rejects every module load. A target with so many declared files that
  the guard's pattern would exceed the limit of the pinned Bun fails before the program or tests
  start, with an English error naming the declared-file count.
- `bun_binary`: `bazel run` runs `entry_point` as Bun's main module with the target's `args` and
  `env`; `process.argv.slice(2)` is exactly the program's arguments; exit code, stdin, stdout and
  stderr are Bun's. An argument list whose first argument is `--` fails with an English error
  naming it, because Bun 1.4.2 drops a `--` directly after the entry point.
- `bun_test`: runs exactly the files in `srcs` with `bun test`, with the root of `<name>.bun/` as
  the working directory (`process.cwd()`) of the tests; each value of `args` and
  `--test_arg` must be one of these forms, else the run fails with an English error naming it:
  `--timeout=<n>`, `--rerun-each=<n>`, `--retry=<n>`, `--concurrent`, `--randomize`, `--seed=<n>`,
  `--bail`, `--bail=<n>`, `--max-concurrency=<n>`, `--todo`, `--isolate`, `--smol`,
  `--conditions=<value>`, `--prefer-offline`, `--frozen-lockfile` (research R8). Short options, positional arguments and a bare `--` are
  rejected. An accepted form is passed to `bun test` unchanged; what it does is Bun's, and only
  `--timeout` and `--isolate` are covered by a test of their effect. Under `--isolate` every file stays under the load guard
  (https://bun.com/docs/test/parallel: Bun re-runs preloads for each file). `--test_filter`,
  including a test name prefixed with its `describe` labels, sharding, `XML_OUTPUT_FILE` and
  `bazel coverage` map onto Bun as research R8 lists. A filter that matches no test fails, as Bun
  reports it; `--test_filter` on a target with `shard_count` greater than 1 fails with an English
  error that filtering a sharded `bun_test` is not supported; a shard that gets no file passes.
  Coverage is written to `COVERAGE_DIR` as `bunlcov_<unique>.dat`, each record naming the source
  file of a declared file. Every file Bun reports must match exactly one declared file (its path
  read relative to the working directory or as an absolute path); otherwise the test fails with
  an English error naming the reported path, and no coverage file is written.
- Isolation, in the process that runs the consumer's code:
  - `bun_binary`: Bun reads only the configuration file the rule supplies (`--config=`, with
    `env = false` and `install.auto = "disable"`) and gets `--no-env-file` and `--no-install`, so
    it ignores the consumer's `bunfig.toml` and `.env` files and does not auto-install.
  - `bun_test`: bun.com documents no `--config` and no `bunfig.toml` lookup for `bun test`
    (oven-sh/bun#45331), so the rule passes no configuration option and promises nothing about
    where Bun looks. It promises that the tests run with the root of `<name>.bun/` as the working
    directory and that this root holds no file: no `bunfig.toml` or `.env` the target did not
    declare is there. It does not promise anything about the parent directories of that root (see
    Known limitations). A `bunfig.toml` or `.env` the target declares is a declared input. Bun 1.4.2
    does not auto-install under `bun test`, which a test checks on every OS; no documented option
    turns it off.
  - `BUN_OPTIONS`, which bun.com documents as arguments prepended to every Bun execution: on Linux
    and macOS a set `BUN_OPTIONS` fails the run with an English error naming it before Bun starts
    (tested on Linux and macOS; see Known limitations for Windows).
- `env` values are taken literally: `$(location …)` and other substitutions are not expanded,
  because an expanded path does not resolve from the copy tree or without a runfiles tree. Data is
  located through `import.meta.dir` (next item).
- Locating data: a program or test locates a declared data file of the main repository relative
  to `import.meta.dir` of the file that reads it, with the same relative path as in the source
  tree (`join(import.meta.dir, "message.txt")`), with a runfiles tree and with a manifest only.
  A `bun_binary` can also pass `$(rlocationpath …)` in `args` and resolve it through
  `RUNFILES_DIR` or `RUNFILES_MANIFEST_FILE`, as Bazel's runfiles libraries do; that path names the
  original data file, which may be read, but importing it as a module fails the load guard,
  because Bun runs only the copies.
- Command line: when the command line of the process that runs the consumer's code, as the
  running OS builds it, would exceed 32,767 characters (the Windows limit), the run fails with an
  English error naming the length and the limit, on every OS (tested on Linux, macOS and
  Windows).

Known limitations, stated in the rules' `doc` (research R14):

- Windows (canary C7, passed on `windows-2025-vs2026`: a quoted argument does not arrive
  unchanged, and of 130 arguments fewer arrive): an argument containing `"` is split, and runtime
  arguments past 128 are dropped, as hermetic-launcher#80 reports, until a release fixes it.
- Windows (canary C16, passed on `windows-2025-vs2026`: code that an inherited
  `BUN_OPTIONS=--eval=…` names runs): an inherited `BUN_OPTIONS` reaches the first Bun process,
  because the stub cannot change the environment (hermetic-launcher#78), so code it names runs
  there.
- Snapshot tests (`toMatchSnapshot`) are not supported.
- The first Bun process runs only the rule's launcher. On Linux and macOS it writes no
  transpiler-cache entry (tested on Linux and macOS); on Windows it may write one for the launcher
  (unverified: `transpiler_cache_test` does not check the first process there) and may also read
  `bunfig.toml` from the working directory (hermetic-launcher#81; unverified: `isolation_test`
  does not check the first process there; canary C4 pins Bun's side and passed on Linux, macOS
  and Windows); on Linux and macOS it reads only the rule's configuration file (tested on Linux
  and macOS).
- The load guard is a check, not complete isolation. It does not cover modules loaded before it
  (on Windows, such a `bunfig.toml` preload of the first process), code the program starts itself (Workers, child processes,
  `Bun.build`), or plain file reads (`Bun.file`, `fs`); `tsconfig.json` and `package.json` in
  ancestor directories of `<name>.bun/` can still change how a declared import resolves. A guard
  error that the consumer's own `try`/`catch` catches (for example around a dynamic `import()`)
  does not fail the run. JSX needs the `react` package, which npm support (a later feature)
  provides, so JSX is not supported; TSX without JSX, `.node` and `.wasm` files are not covered by
  a test and are unverified.
- The number of declared files is limited: the guard's pattern may be at most 1,048,576
  characters with Bun 1.4.2, and its length grows with the unique part of the declared files' real
  paths; beyond that the run fails naming the declared-file count.
- `bun_test` passes only the options listed above to `bun test`, and its tests run with the root
  of `<name>.bun/` as the working directory, not `$TEST_SRCDIR/$TEST_WORKSPACE`.
- Where `bun test` looks for `bunfig.toml` is not documented (oven-sh/bun#45331); whether it also
  reads a `bunfig.toml` or `.env` from a parent directory of `<name>.bun/` is unverified. Those
  parent directories include Bazel's `execroot/_main`, which links every top-level entry of the
  main repository, so a `bunfig.toml` or `.env` at the root of the workspace is within reach if
  Bun searches upward. The consumer module `e2e/smoke` has both at its root, declared by no
  target, and its `bun_test` checks that neither takes effect; the result is reported per
  operating system the test ran on.
- Under `bazel coverage`, a test that changes its working directory (`process.chdir`) fails,
  because Bun then reports file paths that match no declared file.
- Filtering a sharded `bun_test` is not supported; a filter that matches no test fails.
- A `bun_binary` cannot receive `--` as its first program argument.
- Directories in `data` are not supported (analysis fails).
- A data file of another repository has no stable path relative to `import.meta.dir`, because
  the path contains that repository's canonical name; use `$(rlocationpath …)` in a
  `bun_binary`'s `args`.

Usage:

```starlark
load("@rules_bun//bun:defs.bzl", "bun_binary", "bun_library", "bun_test")

bun_library(
    name = "greet",
    srcs = ["greet.ts"],
)

# main.ts reads join(import.meta.dir, "message.txt").
bun_binary(
    name = "app",
    entry_point = "main.ts",
    data = ["message.txt"],
    deps = [":greet"],
    args = ["--name=world"],
    env = {"GREETING": "hello"},
)

bun_test(
    name = "greet_test",
    srcs = ["greet.test.ts"],
    deps = [":greet"],
)
```

## `@rules_bun//bun:toolchain.bzl`

| Symbol | Contract |
|---|---|
| `bun_toolchain(name, bun, version)` | unchanged; for `execution_type` (`bun` built for the execution platform) |
| `bun_target_toolchain(name, bun, version)` | **new**; for `target_type`; `bun` built for the target platform; returns `ToolchainInfo(buninfo = BunInfo(...))` |

A consumer registers their own runtime Bun with:

```starlark
bun_target_toolchain(name = "my_bun", bun = "@my_bun//:bun", version = "1.4.2")

toolchain(
    name = "my_bun_toolchain",
    target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    toolchain = ":my_bun",
    toolchain_type = "@rules_bun//bun/toolchain:target_type",
)
```

## `@rules_bun//bun:extensions.bzl`, `@rules_bun//bun:repositories.bzl`

Unchanged API. The generated `<name>_toolchains` repository now also declares one
`target_type` toolchain per platform, so the existing
`register_toolchains("@bun_toolchains//:all")` registers both types.

## Dependencies a consumer resolves

New non-dev: `hermetic_launcher` ≥ 0.0.16, hence `bazel_skylib` ≥ 1.9.0; the ruleset's own
`platforms` dependency is raised from 1.0.0 to 1.1.0, which `hermetic_launcher` requires;
`bazel_lib` at the lowest version that passes (from 3.0.0 upward, research R6), which registers
its own coreutils toolchains and adds `bazel_features` and `rules_shell`. `rules_shell` ≥ 0.6.1
and `bazel_skylib` ≥ 1.9.0 are also declared by the ruleset itself (Revision 13). This raises
nothing, because Bazel 9.2.0's built-in `bazel_tools` already requires `rules_shell` 0.6.1, and
`hermetic_launcher` requires `bazel_skylib` 1.9.0.
