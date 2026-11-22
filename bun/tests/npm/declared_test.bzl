"""Analysis tests of declared dependencies the store links on no platform class (feature 006 T111).

The `npm` extension's naming rule gives each package a workspace package declares its
`:node_modules/<package>` target (P4, FR-014, SC-005). Where the pinned Bun's store links that
dependency on no platform class (an optional or non-optional package no platform matches, BC-7; an
optional dependency under `unresolved`, BC-1; an optional or peer dependency without a key, BC-3
and BC-5), the target still exists and carries nothing, as `main`'s optional targets carry nothing
on platforms their package does not match.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun/private:providers.bzl", "BunLibraryInfo")

_FIXTURES = "//bun/tests/npm/fixtures/"

# Fixture package -> the declared dependencies the store links on no platform class.
_NOWHERE = {
    # The root's optional bin-sunos (os sunos) and nomatch-aix-ppc64 (cpu ppc64); the workspace's
    # non-optional nomatch-sunos-x64 (BC-7) and optional bin-sunos.
    "conformance_declared_nowhere": ["bin-sunos", "nomatch-aix-ppc64"],
    "conformance_declared_nowhere/packages/w": ["bin-sunos", "nomatch-sunos-x64"],
    # The root's non-optional nomatch-aix-ppc64 (os aix, cpu ppc64; BC-7).
    "conformance_platform": ["nomatch-aix-ppc64"],
    # Optional and peer dependencies without a key (BC-3), peers nothing provides (BC-5).
    "conformance_unbound": ["r", "state"],
    "conformance_unbound/packages/w": ["q", "x"],
    # Optional dependencies under `unresolved` (BC-1); single-bin keeps its bin target (T169).
    "conformance_unresolved": ["b", "single-bin"],
    "conformance_unresolved/packages/w": ["q"],
}

def _empty_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    records = target[BunLibraryInfo].packages.to_list()
    asserts.equals(env, 1, len(records), "the link records of " + str(target.label))
    for record in records:
        asserts.equals(env, ctx.attr.alias, record.alias)
        asserts.equals(env, [], [i.id for i in record.instances.to_list()], "the instances {} carries".format(target.label))
    asserts.equals(env, [], target[DefaultInfo].files.to_list(), "the files {} builds".format(target.label))
    return analysistest.end(env)

def _make_empty(platform):
    return analysistest.make(
        _empty_impl,
        attrs = {"alias": attr.string(mandatory = True)},
        config_settings = {"//command_line_option:platforms": str(Label("//bun/tests/platforms:" + platform))},
    )

_empty_linux_x64_glibc_test = _make_empty("linux_x64_glibc")
_empty_darwin_aarch64_test = _make_empty("darwin_aarch64")
_empty_windows_x64_test = _make_empty("windows_x64")
_empty_aix_x64_test = _make_empty("aix_x64")

_EMPTY = {
    "aix_x64": _empty_aix_x64_test,
    "darwin_aarch64": _empty_darwin_aarch64_test,
    "linux_x64_glibc": _empty_linux_x64_glibc_test,
    "windows_x64": _empty_windows_x64_test,
}

def declared_test_suite(name):
    """Checks that a declared dependency the store links nowhere has a target carrying nothing.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    tests = []
    for package, aliases in sorted(_NOWHERE.items()):
        for alias in aliases:
            for platform, rule in sorted(_EMPTY.items()):
                test = "{}_{}_{}_{}_test".format(name, package.replace("/", "_"), alias, platform)
                rule(
                    name = test,
                    target_under_test = "{}{}:node_modules/{}".format(_FIXTURES, package, alias),
                    alias = alias,
                )
                tests.append(test)
    native.test_suite(name = name, tests = tests)
