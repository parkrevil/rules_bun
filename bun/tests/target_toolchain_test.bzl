"""Analysis tests for the Bun toolchain resolved for the target platform."""

load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//bun:defs.bzl", "bun_binary", "bun_test")
load("//bun:toolchain.bzl", "bun_target_toolchain")
load(":toolchain_test.bzl", "ResolvedBunInfo", "resolved_bun")

_TARGET_TYPE = "//bun/toolchain:target_type"

def _resolved_target_bun_impl(ctx):
    return [DefaultInfo(files = depset([ctx.toolchains[_TARGET_TYPE].buninfo.bun]))]

resolved_target_bun = rule(
    implementation = _resolved_target_bun_impl,
    doc = "Exposes the Bun of the toolchain of `target_type` resolved for the target platform.",
    toolchains = [_TARGET_TYPE],
)

# Keys name targets in //bun/tests/platforms; values are written out by hand so
# that a wrong PLATFORMS entry makes the matching test fail.
_EXPECTED_BUN = {
    "darwin_aarch64": Label("@bun_darwin-aarch64//:bun"),
    "darwin_x64": Label("@bun_darwin-x64//:bun"),
    "linux_aarch64": Label("@bun_linux-aarch64//:bun"),
    "linux_x64": Label("@bun_linux-x64//:bun"),
    "windows_x64": Label("@bun_windows-x64//:bun.exe"),
}

def _target_selection_test_impl(ctx):
    env = analysistest.begin(ctx)

    platform = ctx.attr.target_platform
    files = analysistest.target_under_test(env)[DefaultInfo].files.to_list()
    asserts.equals(env, 1, len(files), "The resolved target toolchain must provide exactly one Bun")
    if len(files) == 1:
        asserts.equals(
            env,
            _EXPECTED_BUN[platform],
            files[0].owner,
            "The Bun selected for target platform {} is not the release for that platform".format(platform),
        )

    return analysistest.end(env)

def _target_selection_test(platform):
    return analysistest.make(
        _target_selection_test_impl,
        attrs = {"target_platform": attr.string(default = platform)},
        config_settings = {
            "//command_line_option:platforms": [str(Label("//bun/tests/platforms:" + platform))],
        },
    )

target_selection_darwin_aarch64_test = _target_selection_test("darwin_aarch64")
target_selection_darwin_x64_test = _target_selection_test("darwin_x64")
target_selection_linux_aarch64_test = _target_selection_test("linux_aarch64")
target_selection_linux_x64_test = _target_selection_test("linux_x64")
target_selection_windows_x64_test = _target_selection_test("windows_x64")

_TARGET_SELECTION_TESTS = {
    "darwin_aarch64": target_selection_darwin_aarch64_test,
    "darwin_x64": target_selection_darwin_x64_test,
    "linux_aarch64": target_selection_linux_aarch64_test,
    "linux_x64": target_selection_linux_x64_test,
    "windows_x64": target_selection_windows_x64_test,
}

def target_toolchain_selection_test_suite(name):
    """Checks that each target platform selects the Bun release built for it.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    tests = []
    for platform, test in _TARGET_SELECTION_TESTS.items():
        fixture = "{}_{}_fixture".format(name, platform)

        # Only the analysis test, which sets the target platform, analyzes it.
        resolved_target_bun(name = fixture, tags = ["manual"])
        test_name = "{}_{}_test".format(name, platform)
        test(name = test_name, target_under_test = ":" + fixture)
        tests.append(":" + test_name)

    native.test_suite(name = name, tests = tests)

def _target_cfg_test_impl(ctx):
    env = analysistest.begin(ctx)

    files = analysistest.target_under_test(env)[DefaultInfo].files.to_list()
    asserts.equals(env, 1, len(files), "The resolved target toolchain must provide exactly one Bun")
    if len(files) == 1:
        asserts.equals(
            env,
            Label("//bun/tests:target_cfg_bun"),
            files[0].owner,
            "The test-only target toolchain was not the one resolved",
        )
        asserts.false(
            env,
            "-exec" in files[0].path,
            "bun_target_toolchain built its Bun in the execution configuration: " + files[0].path,
        )

    return analysistest.end(env)

target_cfg_test = analysistest.make(
    _target_cfg_test_impl,
    config_settings = {
        "//command_line_option:extra_toolchains": [str(Label("//bun/tests:target_cfg_toolchain"))],
    },
)

def target_cfg_test_suite(name):
    """Checks that `bun_target_toolchain` builds `bun` for the target platform.

    Declares the toolchain `<name>_toolchain`, which only this test registers.

    Args:
        name: Prefix of the fixture targets and the test.
    """
    write_file(
        name = name + "_bun",
        out = name + "_bun/bun",
        content = [""],
        tags = ["manual"],
    )
    bun_target_toolchain(
        name = name + "_bun_toolchain",
        bun = ":" + name + "_bun",
        version = "0.0.0",
        tags = ["manual"],
    )
    native.toolchain(
        name = name + "_toolchain",
        toolchain = ":" + name + "_bun_toolchain",
        toolchain_type = _TARGET_TYPE,
    )
    resolved_target_bun(name = name + "_fixture", tags = ["manual"])
    target_cfg_test(name = name + "_test", target_under_test = ":" + name + "_fixture")

def _bun_owners(files):
    """Returns the labels of the Bun releases among `files`."""
    owners = [f.owner for f in files]
    return [label for label in _EXPECTED_BUN.values() if label in owners]

def _rule_platform_test_impl(ctx):
    env = analysistest.begin(ctx)

    platform = ctx.attr.target_platform
    runfiles = analysistest.target_under_test(env)[DefaultInfo].default_runfiles.files.to_list()
    asserts.equals(
        env,
        [_EXPECTED_BUN[platform]],
        _bun_owners(runfiles),
        "The runfiles for target platform {} must hold its Bun release and no other".format(platform),
    )

    return analysistest.end(env)

def _rule_platform_test(platform, test_rule = False):
    target_platform = str(Label("//bun/tests/platforms:" + platform))
    config_settings = {"//command_line_option:platforms": [target_platform]}
    if test_rule and platform == "windows_x64":
        # On a non-Windows host, a Windows execution platform makes the test
        # action's implicit tools need Bazel's Windows launcher built from
        # source, which needs a C++ toolchain; this test-only toolchain lets the
        # test action run on the host instead.
        config_settings["//command_line_option:extra_toolchains"] = [
            str(Label("//bun/tests/platforms:windows_test_on_host")),
        ]
    elif test_rule:
        # Bazel runs a test on an execution platform with the constraints of its
        # target platform (@bazel_tools//tools/test:default_test_toolchain_type).
        # The host comes first, so the rule's own actions keep the host as their
        # execution platform and a Bun resolved for it differs from the target's.
        config_settings["//command_line_option:extra_execution_platforms"] = [
            str(Label("@platforms//host")),
            target_platform,
        ]
    return analysistest.make(
        _rule_platform_test_impl,
        attrs = {"target_platform": attr.string(default = platform)},
        config_settings = config_settings,
    )

binary_platform_darwin_aarch64_test = _rule_platform_test("darwin_aarch64")
binary_platform_darwin_x64_test = _rule_platform_test("darwin_x64")
binary_platform_linux_aarch64_test = _rule_platform_test("linux_aarch64")
binary_platform_linux_x64_test = _rule_platform_test("linux_x64")
binary_platform_windows_x64_test = _rule_platform_test("windows_x64")
test_platform_darwin_aarch64_test = _rule_platform_test("darwin_aarch64", test_rule = True)
test_platform_darwin_x64_test = _rule_platform_test("darwin_x64", test_rule = True)
test_platform_linux_aarch64_test = _rule_platform_test("linux_aarch64", test_rule = True)
test_platform_linux_x64_test = _rule_platform_test("linux_x64", test_rule = True)
test_platform_windows_x64_test = _rule_platform_test("windows_x64", test_rule = True)

_RULE_PLATFORM_TESTS = {
    "binary": {
        "darwin_aarch64": binary_platform_darwin_aarch64_test,
        "darwin_x64": binary_platform_darwin_x64_test,
        "linux_aarch64": binary_platform_linux_aarch64_test,
        "linux_x64": binary_platform_linux_x64_test,
        "windows_x64": binary_platform_windows_x64_test,
    },
    "test": {
        "darwin_aarch64": test_platform_darwin_aarch64_test,
        "darwin_x64": test_platform_darwin_x64_test,
        "linux_aarch64": test_platform_linux_aarch64_test,
        "linux_x64": test_platform_linux_x64_test,
        "windows_x64": test_platform_windows_x64_test,
    },
}

ExecRunfilesInfo = provider(
    doc = "The runfiles of an executable built in the execution configuration.",
    fields = {"files": "`depset` of the runfiles."},
)

def _exec_holder_impl(ctx):
    return [ExecRunfilesInfo(files = ctx.attr.binary[DefaultInfo].default_runfiles.files)]

exec_holder = rule(
    implementation = _exec_holder_impl,
    doc = "Builds `binary` in the execution configuration, as a build action's tool would be.",
    attrs = {
        "binary": attr.label(
            cfg = "exec",
            executable = True,
            mandatory = True,
        ),
    },
)

def _exec_binary_test_impl(ctx):
    env = analysistest.begin(ctx)

    runfiles = analysistest.target_under_test(env)[ExecRunfilesInfo].files.to_list()
    expected = ctx.attr.bun[ResolvedBunInfo].buninfo.bun.owner
    asserts.equals(
        env,
        [expected],
        _bun_owners(runfiles),
        "A bun_binary built for a build action must carry the Bun of the execution platform",
    )

    return analysistest.end(env)

exec_binary_test = analysistest.make(
    _exec_binary_test_impl,
    attrs = {"bun": attr.label(mandatory = True, providers = [ResolvedBunInfo])},
    config_settings = {
        "//command_line_option:platforms": [str(Label("//bun/tests/platforms:windows_x64"))],
    },
)

def rule_platform_test_suite(name):
    """Checks that `bun_binary` and `bun_test` run the Bun of their platform.

    For each target platform their runfiles hold that platform's Bun release and no
    other; a `bun_binary` built for a build action carries the Bun of the execution
    platform.

    Args:
        name: Name of the test suite and prefix of its fixtures and tests.
    """
    bun_binary(name = name + "_binary", entry_point = "binary/main.ts", tags = ["manual"])
    bun_test(name = name + "_test_fixture", srcs = ["binary/main.ts"], tags = ["manual"])
    fixtures = {"binary": name + "_binary", "test": name + "_test_fixture"}
    tests = []
    for kind, platform_tests in _RULE_PLATFORM_TESTS.items():
        for platform, test in platform_tests.items():
            test_name = "{}_{}_{}_test".format(name, kind, platform)
            test(name = test_name, target_under_test = ":" + fixtures[kind])
            tests.append(":" + test_name)

    exec_holder(name = name + "_exec_holder", binary = ":" + name + "_binary", tags = ["manual"])
    resolved_bun(name = name + "_exec_bun", tags = ["manual"])
    exec_binary_test(
        name = name + "_exec_test",
        target_under_test = ":" + name + "_exec_holder",
        bun = ":" + name + "_exec_bun",
    )
    tests.append(":" + name + "_exec_test")

    native.test_suite(name = name, tests = tests)

def _platform_config(platform, test_rule, extra_toolchains = []):
    target_platform = str(Label("//bun/tests/platforms:" + platform))
    config_settings = {"//command_line_option:platforms": [target_platform]}
    if test_rule:
        config_settings["//command_line_option:extra_execution_platforms"] = [
            str(Label("@platforms//host")),
            target_platform,
        ]
    if extra_toolchains:
        config_settings["//command_line_option:extra_toolchains"] = extra_toolchains
    return config_settings

def _missing_toolchain_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.toolchain_type)
    asserts.expect_failure(env, str(Label("//bun/tests/platforms:" + ctx.attr.target_platform)))
    return analysistest.end(env)

def _missing_toolchain_test(platform, toolchain_type, test_rule, extra_toolchains = []):
    return analysistest.make(
        _missing_toolchain_test_impl,
        expect_failure = True,
        attrs = {
            "target_platform": attr.string(default = platform),
            "toolchain_type": attr.string(default = toolchain_type),
        },
        config_settings = _platform_config(platform, test_rule, extra_toolchains),
    )

_NO_STUB_TOOLCHAIN = [str(Label("//bun/tests:platform_failure_no_stub_toolchain"))]

no_bun_binary_test = _missing_toolchain_test("no_bun", str(Label("//bun/toolchain:target_type")), False)
no_bun_test_test = _missing_toolchain_test("no_bun", str(Label("//bun/toolchain:target_type")), True)
no_stub_binary_test = _missing_toolchain_test("no_stub", "template_toolchain_type", False, _NO_STUB_TOOLCHAIN)

# No no_stub case for bun_test: no_stub is a Windows platform, and a bun_test for
# Windows analyzes on a non-Windows host only with the test toolchain that
# _rule_platform_test registers for windows_x64; no such case was added.

def _freebsd_launcher_test_impl(ctx):
    env = analysistest.begin(ctx)

    executable = analysistest.target_under_test(env)[DefaultInfo].files_to_run.executable
    action = _executable_action(env, executable)
    asserts.true(
        env,
        action != None and action.mnemonic == "TemplateExpand",
        "The executable for freebsd_x64 must be the shell launcher expanded from a template",
    )

    return analysistest.end(env)

_FREEBSD_TOOLCHAIN = [str(Label("//bun/tests:platform_failure_freebsd_toolchain"))]

freebsd_binary_test = analysistest.make(
    _freebsd_launcher_test_impl,
    config_settings = _platform_config("freebsd_x64", False, _FREEBSD_TOOLCHAIN),
)
freebsd_test_test = analysistest.make(
    _freebsd_launcher_test_impl,
    config_settings = _platform_config("freebsd_x64", True, _FREEBSD_TOOLCHAIN),
)

def _executable_name_test_impl(ctx):
    env = analysistest.begin(ctx)

    executable = analysistest.target_under_test(env)[DefaultInfo].files_to_run.executable
    asserts.equals(
        env,
        ctx.attr.exe,
        executable.basename.endswith(".exe"),
        "The executable for {} is named {}".format(ctx.attr.target_platform, executable.basename),
    )

    return analysistest.end(env)

def _executable_name_test(platform, exe):
    return analysistest.make(
        _executable_name_test_impl,
        attrs = {
            "exe": attr.bool(default = exe),
            "target_platform": attr.string(default = platform),
        },
        config_settings = _platform_config(platform, False),
    )

windows_executable_name_test = _executable_name_test("windows_x64", True)
linux_executable_name_test = _executable_name_test("linux_x64", False)

def _test_only_bun_toolchain(name, target_compatible_with):
    write_file(
        name = name + "_bun",
        out = name + "_bun/bun",
        content = [""],
        tags = ["manual"],
    )
    bun_target_toolchain(
        name = name + "_bun_toolchain",
        bun = ":" + name + "_bun",
        version = "0.0.0",
        tags = ["manual"],
    )
    native.toolchain(
        name = name + "_toolchain",
        target_compatible_with = target_compatible_with,
        toolchain = ":" + name + "_bun_toolchain",
        toolchain_type = _TARGET_TYPE,
    )

def platform_failure_test_suite(name):
    """Checks the analysis failures for a platform without Bun or without a stub, the `.exe` suffix, and FreeBSD.

    Declares the toolchains `<name>_no_stub_toolchain`, a Bun for
    `//bun/tests/platforms:no_stub`, and `<name>_freebsd_toolchain`, a Bun for
    `//bun/tests/platforms:freebsd_x64`, which only these tests register. A
    non-Windows platform with no hermetic-launcher toolchain gets the shell
    launcher; nothing is claimed about running on FreeBSD.

    Args:
        name: Name of the test suite and prefix of its fixtures and tests.
    """
    _test_only_bun_toolchain(name + "_no_stub", ["@platforms//os:windows", "@platforms//cpu:aarch64"])
    _test_only_bun_toolchain(name + "_freebsd", ["@platforms//os:freebsd", "@platforms//cpu:x86_64"])

    bun_binary(name = name + "_binary", entry_point = "binary/main.ts", tags = ["manual"])
    bun_test(name = name + "_test_fixture", srcs = ["binary/main.ts"], tags = ["manual"])
    cases = {
        "no_bun_binary": (no_bun_binary_test, name + "_binary"),
        "no_bun_test": (no_bun_test_test, name + "_test_fixture"),
        "no_stub_binary": (no_stub_binary_test, name + "_binary"),
        "freebsd_binary": (freebsd_binary_test, name + "_binary"),
        "freebsd_test": (freebsd_test_test, name + "_test_fixture"),
        "windows_executable": (windows_executable_name_test, name + "_binary"),
        "linux_executable": (linux_executable_name_test, name + "_binary"),
    }
    tests = []
    for case, (test, fixture) in cases.items():
        test(name = "{}_{}_test".format(name, case), target_under_test = ":" + fixture)
        tests.append(":{}_{}_test".format(name, case))

    native.test_suite(name = name, tests = tests)

def _rlocation_path(f):
    if f.short_path.startswith("../"):
        return f.short_path[3:]
    return "_main/" + f.short_path

def _executable_action(env, executable):
    for action in analysistest.target_actions(env):
        if executable in action.outputs.to_list():
            return action
    return None

_BASH_RUNFILES = "bazel_tools/tools/bash/runfiles/runfiles.bash"

def _has_bash_runfiles(runfiles):
    """Returns whether `runfiles` holds the Bash runfiles library at its documented runfiles path."""
    if [e for e in runfiles.root_symlinks.to_list() if e.path == _BASH_RUNFILES]:
        return True
    return bool([f for f in runfiles.files.to_list() if _rlocation_path(f) == _BASH_RUNFILES])

def _shell_launcher_test_impl(ctx):
    env = analysistest.begin(ctx)

    platform = ctx.attr.target_platform
    target = analysistest.target_under_test(env)
    name = target.label.name
    executable = target[DefaultInfo].files_to_run.executable
    asserts.equals(
        env,
        name,
        executable.basename,
        "The executable for {} must be named after the target".format(platform),
    )

    runfiles = target[DefaultInfo].default_runfiles
    files = runfiles.files.to_list()
    buns = [f for f in files if f.owner == _EXPECTED_BUN[platform]]
    asserts.equals(env, 1, len(buns), "The runfiles for {} must hold {} once".format(platform, _EXPECTED_BUN[platform]))

    action = _executable_action(env, executable)
    asserts.true(env, action != None, "No action writes the executable for {}".format(platform))
    if action != None:
        asserts.equals(
            env,
            "TemplateExpand",
            action.mnemonic,
            "The executable for {} must be the shell launcher expanded from a template".format(platform),
        )
        content = action.content if action.mnemonic == "TemplateExpand" else ""
        asserts.true(
            env,
            content.startswith("#!/usr/bin/env bash\n"),
            "The shell launcher for {} must start with #!/usr/bin/env bash".format(platform),
        )
        expected = [
            "_main/bun/private/isolated_bunfig.toml",
            "_main/bun/private/launcher.js",
            "_main/{}/{}.launch.json".format(target.label.package, name),
        ] + [_rlocation_path(f) for f in buns]
        for path in expected:
            asserts.true(
                env,
                shell.quote(path) in content,
                "The shell launcher for {} must hold the rlocation path {} quoted for the shell".format(platform, path),
            )

    asserts.true(
        env,
        _has_bash_runfiles(runfiles),
        "The runfiles for {} must hold the Bash runfiles library at {}".format(platform, _BASH_RUNFILES),
    )
    asserts.true(
        env,
        "bun/private/isolated_bunfig.toml" in [f.short_path for f in files],
        "The runfiles for {} must hold isolated_bunfig.toml".format(platform),
    )

    return analysistest.end(env)

def _shell_launcher_test(platform, test_rule = False):
    return analysistest.make(
        _shell_launcher_test_impl,
        attrs = {"target_platform": attr.string(default = platform)},
        config_settings = _platform_config(platform, test_rule),
    )

launcher_binary_darwin_aarch64_test = _shell_launcher_test("darwin_aarch64")
launcher_binary_darwin_x64_test = _shell_launcher_test("darwin_x64")
launcher_binary_linux_aarch64_test = _shell_launcher_test("linux_aarch64")
launcher_binary_linux_x64_test = _shell_launcher_test("linux_x64")
launcher_test_darwin_aarch64_test = _shell_launcher_test("darwin_aarch64", test_rule = True)
launcher_test_darwin_x64_test = _shell_launcher_test("darwin_x64", test_rule = True)
launcher_test_linux_aarch64_test = _shell_launcher_test("linux_aarch64", test_rule = True)
launcher_test_linux_x64_test = _shell_launcher_test("linux_x64", test_rule = True)

_LAUNCHER_TESTS = {
    "binary": {
        "darwin_aarch64": launcher_binary_darwin_aarch64_test,
        "darwin_x64": launcher_binary_darwin_x64_test,
        "linux_aarch64": launcher_binary_linux_aarch64_test,
        "linux_x64": launcher_binary_linux_x64_test,
    },
    "test": {
        "darwin_aarch64": launcher_test_darwin_aarch64_test,
        "darwin_x64": launcher_test_darwin_x64_test,
        "linux_aarch64": launcher_test_linux_aarch64_test,
        "linux_x64": launcher_test_linux_x64_test,
    },
}

def _long_name_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.true(
        env,
        analysistest.target_under_test(env)[DefaultInfo].files_to_run.executable != None,
        "A bun_binary with a long name must analyze for {}".format(ctx.attr.target_platform),
    )
    return analysistest.end(env)

launcher_long_name_test = analysistest.make(
    _long_name_test_impl,
    attrs = {"target_platform": attr.string(default = "linux_x64")},
    config_settings = _platform_config("linux_x64", False),
)

def _windows_launcher_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    executable = target[DefaultInfo].files_to_run.executable
    asserts.true(env, executable.basename.endswith(".exe"), "The executable for windows_x64 is named " + executable.basename)
    action = _executable_action(env, executable)
    asserts.true(
        env,
        action != None and action.mnemonic != "TemplateExpand",
        "The executable for windows_x64 must be the hermetic-launcher stub, not a shell launcher",
    )
    asserts.false(
        env,
        _has_bash_runfiles(target[DefaultInfo].default_runfiles),
        "The runfiles for windows_x64 must not hold the Bash runfiles library",
    )

    return analysistest.end(env)

launcher_windows_test = analysistest.make(
    _windows_launcher_test_impl,
    config_settings = _platform_config("windows_x64", False),
)

def launcher_platform_test_suite(name, long_name_binary):
    """Checks which launcher `bun_binary` and `bun_test` get for each target platform.

    Linux and macOS get a shell launcher that finds its files with the Bash runfiles
    library; Windows gets the hermetic-launcher stub `<name>.exe`.

    Args:
        name: Name of the test suite and prefix of its fixtures and tests.
        long_name_binary: A `bun_binary` whose `<name>.launch.json` path exceeds 256 bytes.
    """
    bun_binary(name = name + "_binary", entry_point = "binary/main.ts", tags = ["manual"])
    bun_test(name = name + "_test_fixture", srcs = ["binary/main.ts"], tags = ["manual"])
    fixtures = {"binary": name + "_binary", "test": name + "_test_fixture"}
    tests = []
    for kind, platform_tests in _LAUNCHER_TESTS.items():
        for platform, test in platform_tests.items():
            test_name = "{}_{}_{}_test".format(name, kind, platform)
            test(name = test_name, target_under_test = ":" + fixtures[kind])
            tests.append(":" + test_name)

    launcher_long_name_test(name = name + "_long_name_test", target_under_test = long_name_binary)
    launcher_windows_test(name = name + "_windows_test", target_under_test = ":" + name + "_binary")
    tests += [":" + name + "_long_name_test", ":" + name + "_windows_test"]

    native.test_suite(name = name, tests = tests)
