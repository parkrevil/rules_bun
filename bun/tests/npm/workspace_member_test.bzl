"""Analysis tests of a registry package's dependency on a workspace member (feature 006 BC-4)."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun:defs.bzl", "bun_test")

_FIXTURE = "//bun/tests/npm/fixtures/conformance_registry_to_workspace"
_MEMBER = _FIXTURE + "/packages/member-lib:pkg"

def _declared_impl(ctx):
    env = analysistest.begin(ctx)
    outputs = [f.short_path for action in analysistest.target_actions(env) for f in action.outputs.to_list()]

    # The store entry of member-user links member-lib to the member's package in the copy tree.
    link = ".store/member-user@1.0.0/node_modules/member-lib"
    asserts.equals(env, 1, len([o for o in outputs if o.endswith(link)]), "links " + link)
    return analysistest.end(env)

_declared_test = analysistest.make(_declared_impl)

def _undeclared_impl(ctx):
    env = analysistest.begin(ctx)
    for text in ["member-user@1.0.0", '"member-lib"', _MEMBER.lstrip("/"), "add", "deps"]:
        asserts.expect_failure(env, text)
    return analysistest.end(env)

_undeclared_test = analysistest.make(_undeclared_impl, expect_failure = True)

def workspace_member_test_suite(name):
    """Checks that a target links a package's workspace-member dependency only when it declares it.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    cases = [
        ("declared", _declared_test, [_FIXTURE + ":node_modules/member-user", _MEMBER]),
        ("undeclared", _undeclared_test, [_FIXTURE + ":node_modules/member-user"]),
    ]
    tests = []
    for suffix, rule, deps in cases:
        target = "{}_{}".format(name, suffix)
        bun_test(name = target, srcs = ["no_packages.test.ts"], deps = deps, tags = ["manual"])
        rule(name = target + "_test", target_under_test = target)
        tests.append(target + "_test")
    native.test_suite(name = name, tests = tests)
