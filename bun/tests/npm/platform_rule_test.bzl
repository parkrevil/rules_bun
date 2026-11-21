"""Analysis tests of Bun's platform rule for `os` and `libc` (feature 006 BC-13, BC-14, T096).

They read only the hub's targets, so they run on `main`'s resolver as on the branch's.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun:defs.bzl", "BunLibraryInfo")

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
    asserts.equals(env, ctx.attr.expected, _carried(analysistest.target_under_test(env), "rule-user"))
    return analysistest.end(env)

def _make(platform):
    return analysistest.make(
        _impl,
        attrs = {"expected": attr.string_list()},
        config_settings = {"//command_line_option:platforms": str(Label("//bun/tests/platforms:" + platform))},
    )

_darwin_aarch64_test = _make("darwin_aarch64")
_linux_x64_glibc_test = _make("linux_x64_glibc")
_linux_x64_musl_test = _make("linux_x64_musl")
_windows_x64_test = _make("windows_x64")

_RULES = {
    "darwin_aarch64": _darwin_aarch64_test,
    "linux_x64_glibc": _linux_x64_glibc_test,
    "linux_x64_musl": _linux_x64_musl_test,
    "windows_x64": _windows_x64_test,
}

_EVERY_OS = ["rule-libc-glibc", "rule-linux-any"]

# rule-user's optional packages carried per platform: rule-linux-any (os ["linux", "any"], which Bun
# reads as every OS and writes as no os), rule-any-linux (["any", "linux"]: Linux only) and
# rule-libc-glibc (libc glibc, no os: off Linux libc excludes nothing, `Libc::CURRENT`,
# resolver_hooks.rs L869-L874), on the Bun-written lockfile and on the hand-written one.
_EXPECTED = {
    "darwin_aarch64": _EVERY_OS,
    "linux_x64_glibc": ["rule-any-linux", "rule-libc-glibc", "rule-linux-any"],
    "linux_x64_musl": ["rule-any-linux", "rule-linux-any"],
    "windows_x64": _EVERY_OS,
}

_TARGETS = {
    "bun_written": "//bun/tests/npm/fixtures/conformance_platform_rule:node_modules/rule-user",
    "raw": "//bun/tests/npm/platform_rule_raw:node_modules/rule-user",
}

def platform_rule_test_suite(name):
    """Checks the packages Bun's platform rule carries on each platform.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    tests = []
    for lockfile, target in sorted(_TARGETS.items()):
        for platform, expected in sorted(_EXPECTED.items()):
            test = "{}_{}_{}_test".format(name, lockfile, platform)
            _RULES[platform](name = test, target_under_test = target, expected = expected)
            tests.append(test)
    native.test_suite(name = name, tests = tests)
