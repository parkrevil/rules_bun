"""Implementation of the `bun_binary` and `bun_test` rules."""

load("@bazel_lib//lib:copy_file.bzl", "COPY_FILE_TOOLCHAINS", "copy_file_action")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@hermetic_launcher//launcher:lib.bzl", "launcher")
load(":library.bzl", "SOURCE_EXTENSIONS", "check_no_directory", "library_info", "library_runfiles")
load(":providers.bzl", "BunLibraryInfo")

_TARGET_TYPE = Label("//bun/toolchain:target_type")

_FILES_DOC = """
Files: the target copies its {main}, sources, {preload}and data files, including those of its
`deps`, into its own directory `<name>.bun/` next to its outputs, and Bun runs those copies. A file
the target does not declare, even one next to a declared file in the source tree, is not there, so
importing it fails with Bun's module-not-found error. A `bun_library` or a target whose `data`
holds a directory fails analysis.

Load guard: if Bun is about to load a module file outside the declared copies (a copy left from an
earlier build, a file reached by a `../` import, `package.json` `"imports"` or `node_modules`, or
the original of a declared data file), the run fails with an English error naming the file. If the
guard cannot read its configuration, it rejects every module load. The guard is a check, not
complete isolation: it does not cover modules loaded before it, code the program starts itself
(Workers, child processes, `Bun.build`) or plain file reads (`Bun.file`, `fs`), and `tsconfig.json`
and `package.json` in ancestor directories of `<name>.bun/` can still change how a declared import
resolves. A guard error that the code catches itself (for example `try`/`catch` around a dynamic
`import()`) does not fail the run. JSX needs the `react` package, which rules_bun does not provide
yet; TSX without JSX, `.node` and `.wasm` files are not covered by a test.

Launching: on Linux and macOS the executable `<name>` is a shell launcher that finds Bun and the
rule's files with the Bash runfiles library (`@rules_shell//shell/runfiles`), so running it needs
`/usr/bin/env`, `bash` and the utilities that library calls (`grep`, `sed`, `cut`, `tr`, `wc`,
`awk`, `tail`, `uname`, `dirname`, `basename`). For a Windows target platform the executable is
`<name>.exe`, a hermetic-launcher stub, which runs without Bash (see Platforms). The shell launcher
finds its files through a runfiles manifest when no runfiles tree is staged, so `bazel run
--noenable_runfiles` and `bazel test --noenable_runfiles` without a sandbox work.

Platforms: the tests that run these rules' targets pass on Linux (WSL) and, in CI, on the GitHub
Actions images `ubuntu-24.04`, `macos-26-arm64` and `windows-2025-vs2026`. On Windows they also pass
with Bazel's shell set to a path that does not exist and no Bash directory on the `PATH` of
actions, tests and `bazel run`. `bazel run` and `bazel test` with `--noenable_runfiles` and no
sandbox, and `bazel coverage`, ran on Linux only.

Limits: the guard's pattern may be at most 1,048,576 characters with Bun 1.4.2, and its length
grows with the unique part of the declared files' real paths; beyond that the run fails naming
the declared-file count. When the command line of the Bun process that runs the {code}, as the
running operating system builds it, would exceed 32,767 characters (the Windows limit), the run
fails naming the length and the limit, on every operating system. On Linux and macOS the Bun
process that runs only the rule's launcher writes no transpiler-cache entry, and a set
`BUN_OPTIONS` fails the run before Bun starts. Each of these is tested on the platforms named in
Platforms, the Linux and macOS ones on Linux and macOS.

Windows only, each tested on `windows-2025-vs2026` unless marked unverified: an argument containing
`"` does not arrive unchanged, and of 130 runtime arguments fewer arrive
(https://github.com/hermeticbuild/hermetic-launcher/issues/80 reports the first split and arguments
past 128 dropped); the Bun process that runs only the rule's launcher may read a `bunfig.toml` of
the working directory (https://github.com/hermeticbuild/hermetic-launcher/issues/81; unverified);
an inherited `BUN_OPTIONS` reaches that process, because the stub cannot change the environment
(https://github.com/hermeticbuild/hermetic-launcher/issues/78), so code it names runs there; and a
target whose runfiles path of `<name>.launch.json` is longer than 256 bytes fails analysis naming
the path.

A target platform without a `//bun/toolchain:target_type` toolchain, or a Windows target platform
without a hermetic-launcher stub, fails analysis naming the missing toolchain type.
"""

# hermetic-launcher limits each embedded stub argument to 256 bytes.
_MAX_EMBEDDED_ARGUMENT = 256

def _rlocation_path(f):
    return launcher.to_rlocation_path(f)

def _check_entry_point(ctx):
    files = ctx.files.entry_point
    if len(files) != 1 or ("." + files[0].extension) not in SOURCE_EXTENSIONS:
        fail("{}: entry_point must be exactly one file with one of the extensions {}; got {}".format(
            ctx.label,
            " ".join(SOURCE_EXTENSIONS),
            [f.short_path for f in files],
        ))

def _check_embedded_arguments(ctx, files):
    for f in files:
        path = _rlocation_path(f)
        if len(path) > _MAX_EMBEDDED_ARGUMENT:
            fail("{}: the runfiles path {} is longer than {} bytes, the limit of an embedded launcher argument".format(
                ctx.label,
                path,
                _MAX_EMBEDDED_ARGUMENT,
            ))

def _copy_tree(ctx, files):
    """Copies each file once to `<name>.bun/<rlocation path>`.

    Args:
        ctx: The rule context.
        files: List of `File`s, possibly with duplicates.

    Returns:
        A dict from the rlocation path of each original to its copy.
    """
    copies = {}
    for f in files:
        path = _rlocation_path(f)
        if path in copies:
            continue
        copy = ctx.actions.declare_file("{}.bun/{}".format(ctx.label.name, path))
        copy_file_action(ctx, f, copy)
        copies[path] = copy
    return copies

def _required_toolchain(ctx, toolchain_type):
    """Returns the resolved toolchain of an optional type, or fails naming the type and the target platform."""
    toolchain = ctx.toolchains[toolchain_type]
    if toolchain == None:
        fail("{}: no toolchain of type {} matches the target platform {}".format(
            ctx.label,
            toolchain_type,
            ctx.fragments.platform.platform,
        ))
    return toolchain

def _windows_stub(ctx, buninfo, launch_config):
    """Compiles the hermetic-launcher stub `<name>.exe`, the Windows launcher (FR-001)."""
    _required_toolchain(ctx, launcher.template_toolchain_type)
    _required_toolchain(ctx, launcher.finalizer_toolchain_type)
    _check_embedded_arguments(ctx, [buninfo.bun, ctx.file._launcher, launch_config])
    stub = ctx.actions.declare_file(ctx.label.name + ".exe")
    launcher.entrypoint(buninfo.bun).embedded_args("--no-env-file").runfiles(ctx.file._launcher, launch_config).compile(
        ctx,
        output_file = stub,
        cfg = "target",
    )
    return stub

def _shell_launcher(ctx, buninfo, launch_config):
    """Writes the shell launcher `<name>`, the Linux and macOS launcher (FR-001)."""
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.expand_template(
        template = ctx.file._launcher_template,
        output = executable,
        substitutions = {
            "%bun%": shell.quote(_rlocation_path(buninfo.bun)),
            "%bunfig%": shell.quote(_rlocation_path(ctx.file._bunfig)),
            "%launch_config%": shell.quote(_rlocation_path(launch_config)),
            "%launcher%": shell.quote(_rlocation_path(ctx.file._launcher)),
        },
        is_executable = True,
    )
    return executable

def _bun_run_impl(ctx, mode):
    buninfo = _required_toolchain(ctx, _TARGET_TYPE).buninfo

    if mode == "binary":
        _check_entry_point(ctx)
        main_files = ctx.files.entry_point
        sources = ctx.files.entry_point + ctx.files.srcs
    else:
        if not ctx.files.srcs:
            fail("{}: srcs must name at least one test file".format(ctx.label))
        main_files = ctx.files.srcs
        sources = ctx.files.srcs

    info = library_info(sources, ctx.attr.data, ctx.attr.deps)
    preloads = ctx.files.preload if mode == "test" else []
    to_copy = info.srcs.to_list() + preloads + info.data.to_list()
    check_no_directory(ctx.label, to_copy)
    originals = {_rlocation_path(f): f for f in to_copy}
    copies = _copy_tree(ctx, to_copy)

    config = {
        "copies": [[_rlocation_path(copy), originals[path].path] for path, copy in copies.items()],
        "label": str(ctx.label),
        "mode": mode,
    }
    main_copies = [_rlocation_path(copies[_rlocation_path(f)]) for f in main_files]
    if mode == "binary":
        config["bunfig"] = _rlocation_path(ctx.file._bunfig)
        config["entry_point"] = main_copies[0]
    else:
        config["tests"] = [[copy, _rlocation_path(f)] for copy, f in zip(main_copies, main_files)]
        config["preload"] = [_rlocation_path(copies[_rlocation_path(f)]) for f in preloads]
    launch_config = ctx.actions.declare_file(ctx.label.name + ".launch.json")
    ctx.actions.write(launch_config, json.encode(config))

    windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])
    rule_files = [ctx.file._launcher, launch_config]
    if windows:
        executable = _windows_stub(ctx, buninfo, launch_config)
        if mode == "binary":
            rule_files.append(ctx.file._bunfig)
    else:
        executable = _shell_launcher(ctx, buninfo, launch_config)
        rule_files.append(ctx.file._bunfig)

    runfiles = library_runfiles(
        ctx,
        buninfo.tool_files + rule_files + copies.values(),
        ctx.attr.data,
        ctx.attr.deps,
    )
    runfiles = runfiles.merge(ctx.runfiles(transitive_files = info.data))
    if not windows:
        runfiles = runfiles.merge(ctx.attr._bash_runfiles[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(executable = executable, runfiles = runfiles),
        info,
        coverage_common.instrumented_files_info(
            ctx,
            source_attributes = ["entry_point", "srcs"] if mode == "binary" else ["srcs"],
            dependency_attributes = ["deps", "data"],
        ),
        RunEnvironmentInfo(
            environment = ctx.attr.env,
            inherited_environment = getattr(ctx.attr, "env_inherit", []),
        ),
    ]

_COMMON_ATTRS = {
    "data": attr.label_list(
        doc = """Files needed at run time. Each file is copied into `<name>.bun/` and is read
relative to `import.meta.dir` of the file that reads it, with the same relative path as in the
source tree. A directory fails analysis.""",
        allow_files = True,
    ),
    "deps": attr.label_list(
        doc = "`bun_library` targets the sources import; their sources and data files are copied too.",
        providers = [BunLibraryInfo],
    ),
    "env": attr.string_dict(
        doc = """Environment variables of the program or tests. Values are taken literally: `$(location)`
and other substitutions are not expanded. Locate data files through `import.meta.dir`.""",
    ),
    "_bash_runfiles": attr.label(
        default = Label("@rules_shell//shell/runfiles"),
    ),
    "_bunfig": attr.label(
        default = Label("//bun/private:isolated_bunfig.toml"),
        allow_single_file = True,
    ),
    "_launcher": attr.label(
        default = Label("//bun/private:launcher.js"),
        allow_single_file = True,
    ),
    "_launcher_template": attr.label(
        default = Label("//bun/private:launcher.sh.tpl"),
        allow_single_file = True,
    ),
    "_windows_constraint": attr.label(
        default = Label("@platforms//os:windows"),
    ),
}

# A target platform without a Bun, or a Windows platform without a launcher stub,
# fails analysis in English (_required_toolchain) instead of aborting toolchain
# resolution. Linux and macOS targets need no hermetic-launcher toolchain.
_TOOLCHAINS = [
    config_common.toolchain_type(_TARGET_TYPE, mandatory = False),
    config_common.toolchain_type(launcher.template_toolchain_type, mandatory = False),
    config_common.toolchain_type(launcher.finalizer_toolchain_type, mandatory = False),
] + COPY_FILE_TOOLCHAINS

bun_binary = rule(
    implementation = lambda ctx: _bun_run_impl(ctx, "binary"),
    doc = """Runs a TypeScript or JavaScript entry point with Bun.

`bazel run` runs `entry_point` as Bun's main module with the target's `args` and `env`;
`process.argv.slice(2)` is exactly the program's arguments, and the exit code, standard input,
standard output and standard error are Bun's. An argument list whose first argument is `--` fails
with an English error, because Bun 1.4.2 drops a `--` directly after the entry point. A
`$(rlocationpath …)` in `args` names the original data file, which may be read through
`RUNFILES_DIR` or `RUNFILES_MANIFEST_FILE`, but importing it fails the load guard. A data file of
another repository has no stable path relative to `import.meta.dir`, because the path contains
that repository's canonical name; pass `$(rlocationpath …)` instead.

Isolation: Bun reads only the configuration file the rule supplies (`--config=`, with
`env = false` and `install.auto = "disable"`) and gets `--no-env-file` and `--no-install`, so a
`bunfig.toml` or `.env` in the working directory takes no effect and a missing package is not
installed. The working directory is the one `bazel run` gives. The program runs with
`BUN_RUNTIME_TRANSPILER_CACHE_PATH=0`, so Bun writes no transpiler-cache entry for it.
""" + _FILES_DOC.format(main = "entry point", preload = "", code = "program"),
    executable = True,
    fragments = ["platform"],
    attrs = _COMMON_ATTRS | {
        "entry_point": attr.label(
            doc = "The file Bun runs as its main module: exactly one file with one of the extensions of `srcs`.",
            allow_files = True,
        ),
        "srcs": attr.label_list(
            doc = "Source files the entry point imports (`.ts .tsx .mts .cts .js .jsx .mjs .cjs`).",
            allow_files = SOURCE_EXTENSIONS,
        ),
    },
    toolchains = _TOOLCHAINS,
)

bun_test = rule(
    implementation = lambda ctx: _bun_run_impl(ctx, "test"),
    doc = """Runs test files with `bun test`.

Runs exactly the files in `srcs`, with the root of `<name>.bun/` as the working directory
(`process.cwd()`), not `$TEST_SRCDIR/$TEST_WORKSPACE`; that root holds no file. Each value of
`args` and `--test_arg` must be one of `--timeout=<n>`, `--rerun-each=<n>`, `--retry=<n>`,
`--concurrent`, `--randomize`, `--seed=<n>`, `--bail`, `--bail=<n>`, `--max-concurrency=<n>`,
`--todo`, `--isolate`, `--smol`, `--conditions=<value>`, `--prefer-offline` or
`--frozen-lockfile`; anything else, including short options, positional arguments and a bare
`--`, fails with an English error naming it. An accepted form is passed to `bun test` unchanged;
what it does is Bun's, and only `--timeout` and `--isolate` are covered by a test of their effect.
Under `--isolate` every file stays under the load guard.

Bazel's test protocol: `--test_filter` becomes `--test-name-pattern` (a test name may be prefixed
with its `describe` labels), and a filter that matches no test fails; `--test_filter` on a target
with `shard_count` greater than 1 fails with an English error; a shard that gets no file passes;
`XML_OUTPUT_FILE` receives Bun's JUnit report. Under `bazel coverage` the report is written to
`COVERAGE_DIR` as `bunlcov_<uuid>.dat`, each record naming the source file of a declared file.
Every file Bun reports must match exactly one declared file (its path read relative to the
working directory or as an absolute path); otherwise, for example after the test calls
`process.chdir`, the test fails with an English error naming the reported path and no coverage
file is written. Snapshot tests (`toMatchSnapshot`) are not supported.

Isolation: bun.com documents no `--config` and no `bunfig.toml` lookup for `bun test`
(https://github.com/oven-sh/bun/issues/45331), so the rule passes no configuration option to
`bun test` and offers no `bunfig.toml`; use `preload`. Whether Bun reads a `bunfig.toml` or `.env` from a parent
directory of `<name>.bun/` is not verified. Those parent directories include Bazel's
`execroot/_main`, which links every top-level entry of the main repository, so a `bunfig.toml`
or `.env` at the root of the workspace is within reach if Bun searches upward; the rules_bun
consumer test module has both, declared by no target, and checks that neither takes effect. Bun
1.4.2 does not install a missing package under `bun test`.
""" + _FILES_DOC.format(main = "test files", preload = "preloads ", code = "tests"),
    test = True,
    fragments = ["platform"],
    attrs = _COMMON_ATTRS | {
        "preload": attr.label_list(
            doc = "Files `bun test` imports before the test files, in order (`--preload`).",
            allow_files = SOURCE_EXTENSIONS,
        ),
        "_lcov_merger": attr.label(
            default = configuration_field(fragment = "coverage", name = "output_generator"),
            executable = True,
            cfg = config.exec(exec_group = "test"),
        ),
        "env_inherit": attr.string_list(
            doc = "Names of environment variables to take from the environment Bazel was invoked in; they take precedence over `env`.",
        ),
        "srcs": attr.label_list(
            doc = "The test files; every one is run and nothing else. Supporting sources come through `deps`.",
            allow_files = SOURCE_EXTENSIONS,
        ),
    },
    toolchains = _TOOLCHAINS,
)
