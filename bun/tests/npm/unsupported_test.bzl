"""Analysis tests of the entries the `npm` extension does not fetch (FR-010, research R13)."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun/private:providers.bzl", "BunLibraryInfo")

_PACKAGE = "//bun/tests/npm/fixtures/unsupported:node_modules/"

def _make_failure_test(message):
    def impl(ctx):
        env = analysistest.begin(ctx)
        asserts.expect_failure(env, message)
        return analysistest.end(env)

    return analysistest.make(impl, expect_failure = True)

_file_test = _make_failure_test("local@file:local cannot be used: it is a file: dependency")
_tarball_test = _make_failure_test("cannot be used: it is a tarball URL dependency")
_nointegrity_test = _make_failure_test("nointegrity@1.0.0 cannot be used: bun.lock records no integrity for it")
_patched_test = _make_failure_test("r@1.0.0 cannot be used: it is patched (patchedDependencies)")

def _sibling_test_impl(ctx):
    env = analysistest.begin(ctx)
    records = analysistest.target_under_test(env)[BunLibraryInfo].packages.to_list()
    asserts.equals(env, ["a"], [r.alias for r in records])
    return analysistest.end(env)

_sibling_test = analysistest.make(_sibling_test_impl)

def unsupported_test_suite(name):
    """Checks the lockfile entries the `npm` extension does not fetch.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    tests = []
    for suffix, rule, alias in [
        ("file", _file_test, "local"),
        ("tarball", _tarball_test, "tb"),
        ("nointegrity", _nointegrity_test, "nointegrity"),
        ("patched", _patched_test, "r"),
        ("sibling", _sibling_test, "a"),
    ]:
        rule(name = "{}_{}_test".format(name, suffix), target_under_test = _PACKAGE + alias)
        tests.append("{}_{}_test".format(name, suffix))
    native.test_suite(name = name, tests = tests)
