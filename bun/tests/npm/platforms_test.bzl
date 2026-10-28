"""Analysis tests of platform-specific optional dependencies (FR-016, US3, research R8; feature 004
research R11 for libc, which Bun 1.4.4 writes)."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//bun:defs.bzl", "BunLibraryInfo", "bun_binary")
load("//bun/private:platforms.bzl", "check_list")

_BASIC = "//bun/tests/npm/fixtures/basic:node_modules/"
_AIX = "//bun/tests/npm/fixtures/aix:node_modules/aix-user"
_ANY = "//bun/tests/npm/fixtures/any_platform:node_modules/any-platform"

# npm-install-checks `checkList` (v9.0.0, fcba600c2e4d) on each case, as feature 005 research E3
# records it: (value, values) -> result.
_CHECK_LIST = [
    ("linux", ["any"], True),
    ("linux", ["linux"], True),
    ("darwin", ["linux"], False),
    ("linux", ["!linux"], False),
    ("darwin", ["!linux"], True),
    ("darwin", ["linux", "!win32"], False),
    ("linux", [], True),
    ("linux", ["any", "!linux"], False),
    ("darwin", ["any", "!linux"], False),
    (None, ["linux"], False),
    (None, ["!linux"], True),
    (None, ["any"], True),
]

def _check_list_test_impl(ctx):
    env = unittest.begin(ctx)
    for value, values, expected in _CHECK_LIST:
        asserts.equals(env, expected, check_list(value, values), "check_list({}, {})".format(repr(value), values))
    return unittest.end(env)

_check_list_test = unittest.make(_check_list_test_impl)

_PLATFORMS = ["linux_x64", "linux_x64_glibc", "linux_x64_musl", "linux_aarch64", "darwin_x64", "darwin_aarch64", "windows_x64"]

# Package -> platform -> the platform-restricted optional packages it carries.
_EXPECTED = {
    "native": {
        "darwin_aarch64": ["native-darwin-arm64"],
        "darwin_x64": ["native-darwin-x64"],
        "linux_aarch64": ["native-linux-arm64"],
        # Bun 1.4.4 writes `libc`: a platform without the libc constraint carries both variants,
        # one with it only the variant whose `libc` accepts it (feature 004 research R11).
        "linux_x64": ["native-linux-x64", "native-linux-x64-musl"],
        "linux_x64_glibc": ["native-linux-x64"],
        "linux_x64_musl": ["native-linux-x64-musl"],
        "windows_x64": ["native-win32-x64"],
    },
    "negated": {p: [] if p == "windows_x64" else ["negated-not-win"] for p in _PLATFORMS},
    # sunos has no @platforms constraint and ppc64 is not in the R8 table.
    "nomatch": {p: [] for p in _PLATFORMS},
}

def _carried(target, package):
    names = []
    for record in target[BunLibraryInfo].packages.to_list():
        for instance in record.instances.to_list():
            name = instance.id.split("@")[0]
            if name != package:
                names.append(name)
    return sorted(names)

def _impl(ctx):
    env = analysistest.begin(ctx)
    asserts.equals(env, ctx.attr.expected, _carried(analysistest.target_under_test(env), ctx.attr.package))
    return analysistest.end(env)

def _make(platform):
    return analysistest.make(
        _impl,
        attrs = {"expected": attr.string_list(), "package": attr.string()},
        config_settings = {"//command_line_option:platforms": str(Label("//bun/tests/platforms:" + platform))},
    )

linux_x64_test = _make("linux_x64")
linux_x64_glibc_test = _make("linux_x64_glibc")
linux_x64_musl_test = _make("linux_x64_musl")
linux_aarch64_test = _make("linux_aarch64")
darwin_x64_test = _make("darwin_x64")
darwin_aarch64_test = _make("darwin_aarch64")
windows_x64_test = _make("windows_x64")
aix_x64_test = _make("aix_x64")

_RULES = {
    "darwin_aarch64": darwin_aarch64_test,
    "darwin_x64": darwin_x64_test,
    "linux_aarch64": linux_aarch64_test,
    "linux_x64": linux_x64_test,
    "linux_x64_glibc": linux_x64_glibc_test,
    "linux_x64_musl": linux_x64_musl_test,
    "windows_x64": windows_x64_test,
}

def _exec_tool_impl(ctx):
    return [ctx.attr.tool[BunLibraryInfo]]

# Builds `tool` for the execution platform, as a rule using a program as a build tool does.
_exec_tool = rule(
    implementation = _exec_tool_impl,
    attrs = {"tool": attr.label(cfg = "exec", mandatory = True)},
)

def _exec_impl(ctx):
    env = analysistest.begin(ctx)
    carried = _carried(analysistest.target_under_test(env), "native")
    asserts.equals(env, ["native-linux-x64", "native-linux-x64-musl"], carried, "the execution platform's packages (US3-2)")
    return analysistest.end(env)

exec_test = analysistest.make(
    _exec_impl,
    config_settings = {
        "//command_line_option:extra_execution_platforms": [str(Label("//bun/tests/platforms:linux_x64"))],
        "//command_line_option:platforms": str(Label("//bun/tests/platforms:windows_x64")),
    },
)

def platforms_test_suite(name):
    """Checks the platform-specific optional dependencies a target links.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    tests = []
    for package in sorted(_EXPECTED.keys()):
        for platform in _PLATFORMS:
            test = "{}_{}_{}_test".format(name, package, platform)
            _RULES[platform](
                name = test,
                target_under_test = _BASIC + package,
                package = package,
                expected = _EXPECTED[package][platform],
            )
            tests.append(test)
    bun_binary(
        name = name + "_native_tool",
        entry_point = "native_tool.ts",
        tags = ["manual"],
        deps = [_BASIC + "native"],
    )

    # `aix` maps to @platforms//os:aix (an Edge Case): native-aix-x64 (os aix, cpu x64) is carried
    # on aix with x86_64 and on no other platform.
    aix_x64_test(name = name + "_aix_x64_test", target_under_test = _AIX, package = "aix-user", expected = ["native-aix-x64"])
    linux_x64_test(name = name + "_aix_linux_x64_test", target_under_test = _AIX, package = "aix-user", expected = [])
    tests += [name + "_aix_x64_test", name + "_aix_linux_x64_test"]

    # A sole `any` matches every platform (npm-install-checks `checkList`, feature 005 FR-006).
    for platform in ["linux_x64", "darwin_aarch64", "windows_x64"]:
        _RULES[platform](name = "{}_any_{}_test".format(name, platform), target_under_test = _ANY, package = "", expected = ["any-platform"])
        tests.append("{}_any_{}_test".format(name, platform))

    _check_list_test(name = name + "_check_list_test")
    tests.append(name + "_check_list_test")

    _exec_tool(name = name + "_exec_tool", tool = name + "_native_tool", tags = ["manual"])
    exec_test(name = name + "_exec_test", target_under_test = name + "_exec_tool")
    tests.append(name + "_exec_test")
    native.test_suite(name = name, tests = tests)
