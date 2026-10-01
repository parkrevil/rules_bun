"""Analysis tests for Bun toolchain resolution and the `bun_toolchain` rule."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun:defs.bzl", "BUN_TOOLCHAIN_TYPE")
load("//bun:toolchain.bzl", "bun_toolchain")

ResolvedBunInfo = provider(
    doc = "The `BunInfo` of the Bun toolchain resolved for a fixture target.",
    fields = {"buninfo": "`BunInfo` from the resolved toolchain."},
)

def _resolved_bun_impl(ctx):
    return [ResolvedBunInfo(buninfo = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo)]

resolved_bun = rule(
    implementation = _resolved_bun_impl,
    toolchains = [BUN_TOOLCHAIN_TYPE],
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

def _selection_test_impl(ctx):
    env = analysistest.begin(ctx)

    platform = ctx.attr.execution_platform
    asserts.equals(
        env,
        _EXPECTED_BUN[platform],
        analysistest.target_under_test(env)[ResolvedBunInfo].buninfo.bun.owner,
        "The Bun selected for execution platform {} is not the release for that platform".format(platform),
    )

    return analysistest.end(env)

def _selection_test(platform):
    return analysistest.make(
        _selection_test_impl,
        attrs = {"execution_platform": attr.string(default = platform)},
        config_settings = {
            "//command_line_option:extra_execution_platforms": [
                str(Label("//bun/tests/platforms:" + platform)),
            ],
        },
    )

selection_darwin_aarch64_test = _selection_test("darwin_aarch64")
selection_darwin_x64_test = _selection_test("darwin_x64")
selection_linux_aarch64_test = _selection_test("linux_aarch64")
selection_linux_x64_test = _selection_test("linux_x64")
selection_windows_x64_test = _selection_test("windows_x64")

_SELECTION_TESTS = {
    "darwin_aarch64": selection_darwin_aarch64_test,
    "darwin_x64": selection_darwin_x64_test,
    "linux_aarch64": selection_linux_aarch64_test,
    "linux_x64": selection_linux_x64_test,
    "windows_x64": selection_windows_x64_test,
}

def toolchain_selection_test_suite(name):
    """Checks that each execution platform selects the Bun release built for it.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    fixture = name + "_fixture"
    resolved_bun(name = fixture)

    tests = []
    for platform, test in _SELECTION_TESTS.items():
        test_name = "{}_{}_test".format(name, platform)
        test(name = test_name, target_under_test = ":" + fixture)
        tests.append(":" + test_name)

    native.test_suite(name = name, tests = tests)

def _optional_bun_impl(ctx):
    toolchain = ctx.toolchains[BUN_TOOLCHAIN_TYPE]
    return [ResolvedBunInfo(buninfo = toolchain.buninfo if toolchain else None)]

optional_bun = rule(
    implementation = _optional_bun_impl,
    toolchains = [config_common.toolchain_type(BUN_TOOLCHAIN_TYPE, mandatory = False)],
)

# Execution platforms no Bun release supports, with their constraints written
# out by hand. The fixture's exec_compatible_with keeps the host platform out,
# so the only candidate execution platform is the unsupported one.
_UNSUPPORTED = {
    "darwin_riscv64": ["@platforms//os:macos", "@platforms//cpu:riscv64"],
    "freebsd_aarch64": ["@platforms//os:freebsd", "@platforms//cpu:aarch64"],
    "freebsd_x64": ["@platforms//os:freebsd", "@platforms//cpu:x86_64"],
    "linux_riscv64": ["@platforms//os:linux", "@platforms//cpu:riscv64"],
    "windows_riscv64": ["@platforms//os:windows", "@platforms//cpu:riscv64"],
}

def _rejection_test_impl(ctx):
    env = analysistest.begin(ctx)

    buninfo = analysistest.target_under_test(env)[ResolvedBunInfo].buninfo
    asserts.true(
        env,
        buninfo == None,
        "A Bun was selected for unsupported execution platform {}: {}".format(
            ctx.attr.execution_platform,
            buninfo.bun.owner if buninfo else None,
        ),
    )

    return analysistest.end(env)

def _rejection_test(platform):
    return analysistest.make(
        _rejection_test_impl,
        attrs = {"execution_platform": attr.string(default = platform)},
        config_settings = {
            "//command_line_option:extra_execution_platforms": [
                str(Label("//bun/tests/platforms:" + platform)),
            ],
        },
    )

rejection_darwin_riscv64_test = _rejection_test("darwin_riscv64")
rejection_freebsd_aarch64_test = _rejection_test("freebsd_aarch64")
rejection_freebsd_x64_test = _rejection_test("freebsd_x64")
rejection_linux_riscv64_test = _rejection_test("linux_riscv64")
rejection_windows_riscv64_test = _rejection_test("windows_riscv64")

_REJECTION_TESTS = {
    "darwin_riscv64": rejection_darwin_riscv64_test,
    "freebsd_aarch64": rejection_freebsd_aarch64_test,
    "freebsd_x64": rejection_freebsd_x64_test,
    "linux_riscv64": rejection_linux_riscv64_test,
    "windows_riscv64": rejection_windows_riscv64_test,
}

def toolchain_rejection_test_suite(name):
    """Checks that no Bun toolchain is selected for an unsupported execution platform.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    tests = []
    for platform, test in _REJECTION_TESTS.items():
        fixture = "{}_{}_fixture".format(name, platform)

        # Only the analysis test, which adds the unsupported execution platform,
        # can analyze the fixture; `bazel test //...` must not build it directly.
        optional_bun(
            name = fixture,
            exec_compatible_with = _UNSUPPORTED[platform],
            tags = ["manual"],
        )
        test_name = "{}_{}_test".format(name, platform)
        test(name = test_name, target_under_test = ":" + fixture)
        tests.append(":" + test_name)

    native.test_suite(name = name, tests = tests)

def _os_named_file_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.os + "/bun")
    ctx.actions.write(out, "")
    return [DefaultInfo(files = depset([out]))]

os_named_file = rule(
    implementation = _os_named_file_impl,
    attrs = {"os": attr.string(mandatory = True)},
)

def _exec_cfg_test_impl(ctx):
    env = analysistest.begin(ctx)

    bun = analysistest.target_under_test(env)[platform_common.ToolchainInfo].buninfo.bun
    asserts.true(
        env,
        bun.short_path.endswith("linux/bun"),
        "bun was not built for the execution platform: " + bun.short_path,
    )

    return analysistest.end(env)

exec_cfg_test = analysistest.make(
    _exec_cfg_test_impl,
    config_settings = {
        "//command_line_option:platforms": str(Label("//bun/tests/platforms:windows_x64")),
        "//command_line_option:extra_execution_platforms": [
            str(Label("//bun/tests/platforms:linux_aarch64")),
        ],
    },
)

def exec_cfg_test_suite(name):
    """Checks that `bun_toolchain` builds `bun` for the execution platform.

    Args:
        name: Prefix of the fixture targets and the test.
    """
    os_named_file(
        name = name + "_bun",
        os = select({
            "@platforms//os:linux": "linux",
            "@platforms//os:macos": "macos",
            "@platforms//os:windows": "windows",
        }),
    )
    bun_toolchain(
        name = name + "_toolchain",
        bun = ":" + name + "_bun",
        version = "0.0.0",
    )
    exec_cfg_test(
        name = name + "_test",
        target_under_test = ":" + name + "_toolchain",
    )

def _bun_bin_value_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    has_variables = platform_common.TemplateVariableInfo in target
    asserts.true(env, has_variables, "bun_toolchain does not provide TemplateVariableInfo")
    if not has_variables:
        return analysistest.end(env)

    asserts.equals(
        env,
        target[platform_common.ToolchainInfo].buninfo.bun.path,
        target[platform_common.TemplateVariableInfo].variables.get("BUN_BIN"),
        "BUN_BIN differs from the path of the toolchain's Bun",
    )

    return analysistest.end(env)

bun_bin_value_test = analysistest.make(_bun_bin_value_test_impl)

def _bun_bin_genrule_test_impl(ctx):
    env = analysistest.begin(ctx)

    bun = ctx.attr.resolved[ResolvedBunInfo].buninfo.bun
    actions = analysistest.target_actions(env)
    asserts.equals(env, 1, len(actions), "The genrule must have exactly one action")
    arguments = [arg.replace("\\", "/") for arg in actions[0].argv]
    asserts.true(
        env,
        [arg for arg in arguments if bun.path in arg],
        "$(BUN_BIN) in the genrule command did not expand to the path of the toolchain's Bun: {}".format(arguments),
    )

    return analysistest.end(env)

bun_bin_genrule_test = analysistest.make(
    _bun_bin_genrule_test_impl,
    attrs = {"resolved": attr.label(providers = [ResolvedBunInfo])},
)
