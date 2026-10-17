"""Analysis tests for `bun_library`, `bun_binary` and `bun_test`."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun:defs.bzl", "BUN_TOOLCHAIN_TYPE", "BunLibraryInfo", "bun_binary", "bun_library", "bun_test")
load(":target_toolchain_test.bzl", "resolved_target_bun")

def _paths(files):
    return sorted([f.short_path for f in files])

def _runfiles_fixture_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + "/out.txt")
    runfile = ctx.actions.declare_file(ctx.label.name + "/runfile.txt")
    ctx.actions.write(out, "")
    ctx.actions.write(runfile, "")
    return [DefaultInfo(files = depset([out]), runfiles = ctx.runfiles(files = [runfile]))]

runfiles_fixture = rule(
    implementation = _runfiles_fixture_impl,
    doc = "Provides `<name>/out.txt` in `DefaultInfo.files` and `<name>/runfile.txt` only in its runfiles.",
)

_LIB = "bun/tests/library/"

def _library_info_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    info = target[BunLibraryInfo]
    asserts.equals(
        env,
        [_LIB + "inner.ts", _LIB + "outer.ts"],
        _paths(info.srcs.to_list()),
        "BunLibraryInfo.srcs must hold the transitive sources",
    )
    asserts.equals(
        env,
        [_LIB + "inner.txt", _LIB + "outer.txt", "bun/tests/library_data/out.txt"],
        _paths(info.data.to_list()),
        "BunLibraryInfo.data must hold the transitive files of data targets",
    )
    asserts.equals(
        env,
        [_LIB + "outer.ts"],
        _paths(target[DefaultInfo].files.to_list()),
        "DefaultInfo.files of bun_library must be its own srcs",
    )

    runfiles = _paths(target[DefaultInfo].default_runfiles.files.to_list())
    for expected in [
        _LIB + "inner.ts",
        _LIB + "outer.ts",
        _LIB + "inner.txt",
        _LIB + "outer.txt",
        "bun/tests/library_data/out.txt",
        "bun/tests/library_data/runfile.txt",
    ]:
        asserts.true(
            env,
            expected in runfiles,
            "The runfiles of bun_library lack {}: {}".format(expected, runfiles),
        )

    return analysistest.end(env)

library_info_test = analysistest.make(_library_info_test_impl)

def _library_coverage_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    asserts.true(env, InstrumentedFilesInfo in target, "bun_library returns no InstrumentedFilesInfo")
    if InstrumentedFilesInfo in target:
        instrumented = _paths(target[InstrumentedFilesInfo].instrumented_files.to_list())
        for expected in [_LIB + "inner.ts", _LIB + "outer.ts"]:
            asserts.true(
                env,
                expected in instrumented,
                "InstrumentedFilesInfo of bun_library lacks {}: {}".format(expected, instrumented),
            )

    return analysistest.end(env)

library_coverage_test = analysistest.make(
    _library_coverage_test_impl,
    config_settings = {
        "//command_line_option:collect_code_coverage": True,
        "//command_line_option:instrumentation_filter": "^//bun/tests[/:]",
    },
)

def library_test_suite(name):
    """Checks the providers and runfiles of `bun_library`.

    Declares the fixtures `library_inner`, `library_outer` and `library_data`.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    runfiles_fixture(name = "library_data", tags = ["manual"])
    bun_library(
        name = "library_inner",
        srcs = ["library/inner.ts"],
        data = ["library/inner.txt"],
        tags = ["manual"],
    )
    bun_library(
        name = "library_outer",
        srcs = ["library/outer.ts"],
        data = ["library/outer.txt", ":library_data"],
        deps = [":library_inner"],
        tags = ["manual"],
    )
    library_info_test(name = name + "_info_test", target_under_test = ":library_outer")
    library_coverage_test(name = name + "_coverage_test", target_under_test = ":library_outer")
    native.test_suite(name = name, tests = [":" + name + "_info_test", ":" + name + "_coverage_test"])

def _rlocation_path(f):
    if f.short_path.startswith("../"):
        return f.short_path[3:]
    return "_main/" + f.short_path

def _single_file(target):
    return target[DefaultInfo].files.to_list()[0]

def _launch_config(env, name):
    """Returns the decoded content of the `FileWrite` action that writes `<name>.launch.json`."""
    for action in analysistest.target_actions(env):
        if action.mnemonic == "FileWrite" and [o for o in action.outputs.to_list() if o.basename == name + ".launch.json"]:
            return json.decode(action.content)
    return None

def _stub_arguments(env, executable):
    """Returns the arguments the stub embeds, read from the action that writes the executable."""
    for action in analysistest.target_actions(env):
        if executable in action.outputs.to_list():
            argv = action.argv
            return argv[argv.index("--") + 1:]
    return None

def _skeleton_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    executable = target[DefaultInfo].files_to_run.executable
    asserts.false(env, executable.is_source, "The executable of bun_binary must not be a source file")

    bun = _single_file(ctx.attr.bun)
    runfiles = _paths(target[DefaultInfo].default_runfiles.files.to_list())
    for expected in [bun.short_path, "bun/private/launcher.js", "bun/tests/run/hello.launch.json"]:
        asserts.true(env, expected in runfiles, "The runfiles of bun_binary lack {}: {}".format(expected, runfiles))

    config = _launch_config(env, "hello")
    asserts.true(env, config != None, "No FileWrite action writes hello.launch.json")
    if config != None:
        asserts.equals(env, "binary", config.get("mode"), "launch.json mode")
        asserts.equals(env, str(Label("//bun/tests/run:hello")), config.get("label"), "launch.json label")
        asserts.equals(
            env,
            "_main/bun/tests/run/hello.bun/_main/bun/tests/run/hello.ts",
            config.get("entry_point"),
            "launch.json entry_point must name the copy of the entry point",
        )

    return analysistest.end(env)

skeleton_test = analysistest.make(
    _skeleton_test_impl,
    attrs = {"bun": attr.label(mandatory = True)},
)

_WINDOWS_PLATFORM = {
    "//command_line_option:platforms": [str(Label("//bun/tests/platforms:windows_x64"))],
}

def _windows_stub_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    executable = target[DefaultInfo].files_to_run.executable
    asserts.equals(env, "hello.exe", executable.basename, "The Windows executable of bun_binary must be the stub <name>.exe")

    windows_bun = Label("@bun_windows-x64//:bun.exe")
    buns = [f for f in target[DefaultInfo].default_runfiles.files.to_list() if f.owner == windows_bun]
    asserts.equals(env, 1, len(buns), "The runfiles of bun_binary for windows_x64 must hold {} once".format(windows_bun))
    if len(buns) == 1:
        asserts.equals(
            env,
            [_rlocation_path(buns[0]), "--no-env-file", "_main/bun/private/launcher.js", "_main/bun/tests/run/hello.launch.json"],
            _stub_arguments(env, executable),
            "The Windows stub must embed Bun, --no-env-file, the launcher and the launch configuration",
        )

    return analysistest.end(env)

windows_stub_test = analysistest.make(_windows_stub_test_impl, config_settings = _WINDOWS_PLATFORM)

def skeleton_test_suite(name):
    """Checks the executable, runfiles and launch configuration of `//bun/tests/run:hello`, and its Windows stub.

    Args:
        name: Name of the test suite and prefix of its fixture and test.
    """
    resolved_target_bun(name = name + "_bun", tags = ["manual"])
    skeleton_test(
        name = name + "_test",
        target_under_test = "//bun/tests/run:hello",
        bun = ":" + name + "_bun",
    )
    windows_stub_test(name = name + "_windows_stub_test", target_under_test = "//bun/tests/run:hello")
    native.test_suite(name = name, tests = [":" + name + "_test", ":" + name + "_windows_stub_test"])

_BIN = "bun/tests/binary/"

def _binary_env_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    asserts.equals(
        env,
        {"MANY": "$(locations :binary_data_group)", "ONE": "$(location :binary_data_a)"},
        target[RunEnvironmentInfo].environment,
        "RunEnvironmentInfo.environment must hold env with $(location) and $(locations) unchanged",
    )

    return analysistest.end(env)

binary_env_test = analysistest.make(_binary_env_test_impl)

def _binary_library_info_test_impl(ctx):
    env = analysistest.begin(ctx)

    info = analysistest.target_under_test(env)[BunLibraryInfo]
    asserts.equals(
        env,
        [_BIN + "main.ts", _LIB + "inner.ts", _LIB + "outer.ts"],
        _paths(info.srcs.to_list()),
        "BunLibraryInfo.srcs of bun_binary must hold the entry point and the transitive sources",
    )
    asserts.equals(
        env,
        [_BIN + "a.txt", _BIN + "b.txt", _BIN + "c.txt", _LIB + "inner.txt", _LIB + "outer.txt", "bun/tests/library_data/out.txt"],
        _paths(info.data.to_list()),
        "BunLibraryInfo.data of bun_binary must hold the transitive data files",
    )

    return analysistest.end(env)

binary_library_info_test = analysistest.make(_binary_library_info_test_impl)

def binary_test_suite(name):
    """Checks `RunEnvironmentInfo` and `BunLibraryInfo` of `bun_binary`.

    Uses the fixtures of `library_test_suite`.

    Args:
        name: Name of the test suite and prefix of its fixtures and tests.
    """
    native.filegroup(name = name + "_data_a", srcs = ["binary/a.txt"], tags = ["manual"])
    native.filegroup(name = name + "_data_group", srcs = ["binary/b.txt", "binary/c.txt"], tags = ["manual"])
    bun_binary(
        name = name + "_fixture",
        entry_point = "binary/main.ts",
        data = [":" + name + "_data_a", ":" + name + "_data_group"],
        deps = [":library_outer"],
        env = {
            "MANY": "$(locations :{}_data_group)".format(name),
            "ONE": "$(location :{}_data_a)".format(name),
        },
        tags = ["manual"],
    )
    binary_env_test(name = name + "_env_test", target_under_test = ":" + name + "_fixture")
    binary_library_info_test(name = name + "_library_info_test", target_under_test = ":" + name + "_fixture")
    native.test_suite(name = name, tests = [":" + name + "_env_test", ":" + name + "_library_info_test"])

def _entry_point_failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "entry_point must be exactly one file with one of the extensions")
    return analysistest.end(env)

entry_point_failure_test = analysistest.make(_entry_point_failure_test_impl, expect_failure = True)

_LONG_NAME = "long_" + "x" * 235

def _long_path_failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "_main/bun/tests/{}.launch.json is longer than 256 bytes".format(_LONG_NAME))
    return analysistest.end(env)

# The limit is the Windows stub's (hermetic-launcher), so the test targets Windows.
long_path_failure_test = analysistest.make(
    _long_path_failure_test_impl,
    expect_failure = True,
    config_settings = _WINDOWS_PLATFORM,
)

def analysis_failure_test_suite(name):
    """Checks that `bun_binary` fails analysis with an English message on invalid input.

    Args:
        name: Name of the test suite and prefix of its fixtures and tests.
    """
    native.filegroup(name = name + "_two_sources", srcs = ["library/inner.ts", "library/outer.ts"], tags = ["manual"])
    fixtures = {
        "no_entry_point": {},
        "two_entry_points": {"entry_point": ":" + name + "_two_sources"},
        "text_entry_point": {"entry_point": "binary/a.txt"},
    }
    tests = []
    for case, kwargs in fixtures.items():
        bun_binary(name = "{}_{}".format(name, case), tags = ["manual"], **kwargs)
        entry_point_failure_test(name = "{}_{}_test".format(name, case), target_under_test = ":{}_{}".format(name, case))
        tests.append(":{}_{}_test".format(name, case))

    bun_binary(name = _LONG_NAME, entry_point = "binary/main.ts", tags = ["manual"])
    long_path_failure_test(name = name + "_long_path_test", target_under_test = ":" + _LONG_NAME)
    tests.append(":" + name + "_long_path_test")

    native.test_suite(name = name, tests = tests)

_TREE = "bun/tests/copy_tree_fixture.bun/"

# Rlocation paths of the files the copy-tree fixture uses, each copied once.
_TREE_FILES = [
    "_main/bun/tests/library/inner.ts",
    "_main/bun/tests/library/inner.txt",
    "_main/bun/tests/library/outer.ts",
    "_main/bun/tests/library/outer.txt",
    "_main/bun/tests/library_data/out.txt",
    "_main/bun/tests/tree/data.txt",
    "_main/bun/tests/tree/helper.ts",
    "_main/bun/tests/tree/main.ts",
]

_BUNFIG = "_main/bun/private/isolated_bunfig.toml"

def _assert_no_copy_at_tree_root(env, tree):
    """Asserts that every copy below `tree` has at least two path segments."""
    for a in analysistest.target_actions(env):
        if a.mnemonic != "CopyFile":
            continue
        for o in a.outputs.to_list():
            below = o.short_path[len(tree):] if o.short_path.startswith(tree) else o.short_path
            asserts.true(
                env,
                "/" in below,
                "The copy {} must not be declared directly at the root of {}".format(o.short_path, tree),
            )

def _copy_tree_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    copies = sorted([
        o.short_path
        for a in analysistest.target_actions(env)
        if a.mnemonic == "CopyFile"
        for o in a.outputs.to_list()
    ])
    asserts.equals(
        env,
        [_TREE + f for f in _TREE_FILES],
        copies,
        "bun_binary must copy each file it uses once to <name>.bun/<rlocation path>",
    )

    config = _launch_config(env, "copy_tree_fixture")
    asserts.true(env, config != None, "No FileWrite action writes copy_tree_fixture.launch.json")
    if config != None:
        asserts.equals(
            env,
            "_main/" + _TREE + "_main/bun/tests/tree/main.ts",
            config.get("entry_point"),
            "launch.json entry_point must name the copy of the entry point",
        )
        pairs = sorted(config.get("copies", []))
        asserts.equals(
            env,
            ["_main/" + _TREE + f for f in _TREE_FILES],
            [p[0] for p in pairs],
            "launch.json copies must name every copy by its rlocation path",
        )
        for copy, original in pairs:
            short = copy[len("_main/" + _TREE + "_main/"):]
            asserts.true(
                env,
                original == short or original.endswith("/bin/" + short),
                "launch.json copies must pair {} with the File.path of its original, got {}".format(copy, original),
            )

        asserts.equals(
            env,
            _BUNFIG,
            config.get("bunfig"),
            "launch.json bunfig of bun_binary must name the rlocation path of isolated_bunfig.toml",
        )

    _assert_no_copy_at_tree_root(env, _TREE)

    runfiles = _paths(target[DefaultInfo].default_runfiles.files.to_list())
    expected = [_TREE + f for f in _TREE_FILES] + [
        "bun/tests/tree/data.txt",
        "bun/tests/library/inner.txt",
        "bun/private/isolated_bunfig.toml",
        _single_file(ctx.attr.bun).short_path,
    ]
    for path in expected:
        asserts.true(env, path in runfiles, "The runfiles of bun_binary lack {}".format(path))

    return analysistest.end(env)

copy_tree_test = analysistest.make(
    _copy_tree_test_impl,
    attrs = {"bun": attr.label(mandatory = True)},
)

_TEST_TREE = "bun/tests/copy_tree_test_fixture.bun/"

def _copy_tree_test_rule_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    config = _launch_config(env, "copy_tree_test_fixture")
    asserts.true(env, config != None, "No FileWrite action writes copy_tree_test_fixture.launch.json")
    if config != None:
        asserts.false(env, "bunfig" in config, "launch.json of bun_test must have no bunfig")
        asserts.equals(
            env,
            [["_main/" + _TEST_TREE + "_main/bun/tests/tree/main.ts", "_main/bun/tests/tree/main.ts"]],
            config.get("tests"),
            "launch.json tests of bun_test must pair the rlocation path of each copy with its tree path",
        )

    _assert_no_copy_at_tree_root(env, _TEST_TREE)

    # The shell launcher of a Linux or macOS target passes it to the first process.
    runfiles = _paths(target[DefaultInfo].default_runfiles.files.to_list())
    asserts.true(
        env,
        "bun/private/isolated_bunfig.toml" in runfiles,
        "The runfiles of bun_test must hold isolated_bunfig.toml",
    )

    return analysistest.end(env)

# The shell launcher is the Linux and macOS one, so the target platform is pinned
# to linux_x64 on every host. As for the other bun_test platform tests, the host
# comes first among the execution platforms, so the rule's own actions run there.
copy_tree_test_rule_test = analysistest.make(
    _copy_tree_test_rule_test_impl,
    config_settings = {
        "//command_line_option:extra_execution_platforms": [
            str(Label("@platforms//host")),
            str(Label("//bun/tests/platforms:linux_x64")),
        ],
        "//command_line_option:platforms": [str(Label("//bun/tests/platforms:linux_x64"))],
    },
)

def _directory_fixture_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name)
    buninfo = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo
    args = ctx.actions.args()
    args.add("-e", 'require("node:fs").writeFileSync(Bun.argv.at(-1) + "/file.txt", "")')
    args.add(out.path)
    ctx.actions.run(
        executable = buninfo.bun,
        arguments = [args],
        outputs = [out],
        tools = buninfo.tool_files,
        toolchain = BUN_TOOLCHAIN_TYPE,
        mnemonic = "DirectoryFixture",
    )
    return [DefaultInfo(files = depset([out]))]

directory_fixture = rule(
    implementation = _directory_fixture_impl,
    doc = "Writes a directory holding one file, with the Bun of the execution platform.",
    toolchains = [BUN_TOOLCHAIN_TYPE],
)

def _directory_failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "data holds the directory bun/tests/copy_tree_directory")
    return analysistest.end(env)

directory_failure_test = analysistest.make(_directory_failure_test_impl, expect_failure = True)

def copy_tree_test_suite(name):
    """Checks the per-target copy trees of `bun_binary` and `bun_test` and the failure for a directory in `data`.

    Uses the fixtures of `library_test_suite`.

    Args:
        name: Name of the test suite and prefix of its fixtures and tests.
    """
    resolved_target_bun(name = name + "_bun", tags = ["manual"])
    bun_binary(
        name = "copy_tree_fixture",
        entry_point = "tree/main.ts",
        srcs = ["tree/helper.ts", "tree/main.ts"],
        data = ["tree/data.txt", "library/outer.txt"],
        deps = [":library_outer"],
        tags = ["manual"],
    )
    copy_tree_test(name = name + "_test", target_under_test = ":copy_tree_fixture", bun = ":" + name + "_bun")

    bun_test(
        name = "copy_tree_test_fixture",
        srcs = ["tree/main.ts"],
        tags = ["manual"],
    )
    copy_tree_test_rule_test(name = name + "_test_rule_test", target_under_test = ":copy_tree_test_fixture")

    directory_fixture(name = "copy_tree_directory", tags = ["manual"])
    bun_library(name = name + "_directory_library", data = [":copy_tree_directory"], tags = ["manual"])
    bun_binary(
        name = name + "_directory_binary",
        entry_point = "tree/main.ts",
        data = [":copy_tree_directory"],
        tags = ["manual"],
    )
    directory_failure_test(name = name + "_directory_library_test", target_under_test = ":" + name + "_directory_library")
    directory_failure_test(name = name + "_directory_binary_test", target_under_test = ":" + name + "_directory_binary")

    native.test_suite(name = name, tests = [
        ":" + name + "_test",
        ":" + name + "_test_rule_test",
        ":" + name + "_directory_library_test",
        ":" + name + "_directory_binary_test",
    ])

def _no_srcs_failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "srcs must name at least one test file")
    return analysistest.end(env)

no_srcs_failure_test = analysistest.make(_no_srcs_failure_test_impl, expect_failure = True)

def _env_inherit_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.equals(
        env,
        ["RULES_BUN_A", "RULES_BUN_B"],
        analysistest.target_under_test(env)[RunEnvironmentInfo].inherited_environment,
        "RunEnvironmentInfo.inherited_environment must equal env_inherit",
    )
    return analysistest.end(env)

env_inherit_test = analysistest.make(_env_inherit_test_impl)

def test_rule_test_suite(name):
    """Checks the analysis of `bun_test`: `srcs` must not be empty, `env_inherit` is passed on.

    Args:
        name: Name of the test suite and prefix of its fixtures and tests.
    """
    bun_test(name = name + "_no_srcs_fixture_test", tags = ["manual"])
    bun_test(
        name = name + "_env_inherit_fixture_test",
        srcs = ["binary/main.ts"],
        env_inherit = ["RULES_BUN_A", "RULES_BUN_B"],
        tags = ["manual"],
    )
    no_srcs_failure_test(name = name + "_no_srcs_test", target_under_test = ":" + name + "_no_srcs_fixture_test")
    env_inherit_test(name = name + "_env_inherit_test", target_under_test = ":" + name + "_env_inherit_fixture_test")
    native.test_suite(name = name, tests = [":" + name + "_no_srcs_test", ":" + name + "_env_inherit_test"])

def _test_coverage_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    asserts.true(env, InstrumentedFilesInfo in target, "bun_test returns no InstrumentedFilesInfo")
    if InstrumentedFilesInfo in target:
        instrumented = _paths(target[InstrumentedFilesInfo].instrumented_files.to_list())
        for expected in [_BIN + "main.ts", _LIB + "inner.ts", _LIB + "outer.ts"]:
            asserts.true(
                env,
                expected in instrumented,
                "InstrumentedFilesInfo of bun_test lacks {}: {}".format(expected, instrumented),
            )

    return analysistest.end(env)

test_coverage_test = analysistest.make(
    _test_coverage_test_impl,
    config_settings = {
        "//command_line_option:collect_code_coverage": True,
        "//command_line_option:instrumentation_filter": "^//bun/tests[/:]",
        # Bazel instruments the sources of a test rule itself only with this option.
        "//command_line_option:instrument_test_targets": True,
    },
)

def test_coverage_test_suite(name):
    """Checks that `bun_test` names its sources and those of its `deps` for coverage.

    Uses the fixtures of `library_test_suite`.

    Args:
        name: Name of the test suite and prefix of its fixture and test.
    """
    bun_test(
        name = name + "_fixture_test",
        srcs = ["binary/main.ts"],
        deps = [":library_outer"],
        tags = ["manual"],
    )
    test_coverage_test(name = name + "_test", target_under_test = ":" + name + "_fixture_test")
    native.test_suite(name = name, tests = [":" + name + "_test"])
