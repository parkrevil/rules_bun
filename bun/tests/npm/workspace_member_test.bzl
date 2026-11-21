"""Analysis tests of a registry package's dependency on a workspace member (feature 006 BC-4)."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun:defs.bzl", "bun_library", "bun_test")
load(":consumer_rules.bzl", "consumer_carrier", "consumer_library", "consumer_wrapper")

_FIXTURE = "//bun/tests/npm/fixtures/conformance_registry_to_workspace"
_MEMBER = _FIXTURE + "/packages/member-lib:pkg"

# The same layout, whose member's target `pkg` is an alias of a target in the fixture's root
# package, which carries the member's files (T146).
_ALIAS_FIXTURE = "//bun/tests/npm/fixtures/conformance_member_alias"
_ALIAS_MEMBER = _ALIAS_FIXTURE + "/packages/member-lib:pkg"
_ALIAS_INDEX = "_main/bun/tests/npm/fixtures/conformance_member_alias/packages/member-lib/index.js"

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

def _bin_impl(ctx):
    env = analysistest.begin(ctx)
    outputs = [f.short_path for action in analysistest.target_actions(env) for f in action.outputs.to_list()]

    # A bin target has no deps: the hub hands it the members its package's closure links, and its
    # copy tree links member-lib as a declaring target's does.
    tree = "_npm_bin/member-user/member-user.bun/"
    link = tree + ".store/member-user@1.0.0/node_modules/member-lib"
    asserts.equals(env, 1, len([o for o in outputs if o.endswith(link)]), "links " + link)
    index = tree + "_main/bun/tests/npm/fixtures/conformance_registry_to_workspace/packages/member-lib/index.js"
    asserts.equals(env, 1, len([o for o in outputs if o.endswith(index)]), "copies " + index)
    return analysistest.end(env)

_bin_test = analysistest.make(_bin_impl)

def _alias_outputs(env):
    return [f.short_path for action in analysistest.target_actions(env) for f in action.outputs.to_list()]

def _alias_declared_impl(ctx):
    env = analysistest.begin(ctx)
    outputs = _alias_outputs(env)

    # Bazel reports the alias's target under its own label; the member counts as declared through
    # it, and the store links member-lib to the member's package, where its files are copied.
    link = ".store/member-user@1.0.0/node_modules/member-lib"
    asserts.equals(env, 1, len([o for o in outputs if o.endswith(link)]), "links " + link)
    asserts.equals(env, 1, len([o for o in outputs if o.endswith("/" + _ALIAS_INDEX)]), "copies " + _ALIAS_INDEX)
    return analysistest.end(env)

_alias_declared_test = analysistest.make(_alias_declared_impl)

def _alias_bin_impl(ctx):
    env = analysistest.begin(ctx)
    outputs = _alias_outputs(env)
    tree = "_npm_bin/member-user/member-user.bun/"
    link = tree + ".store/member-user@1.0.0/node_modules/member-lib"
    asserts.equals(env, 1, len([o for o in outputs if o.endswith(link)]), "links " + link)
    asserts.equals(env, 1, len([o for o in outputs if o.endswith(tree + _ALIAS_INDEX)]), "copies " + _ALIAS_INDEX)
    return analysistest.end(env)

_alias_bin_test = analysistest.make(_alias_bin_impl)

def _alias_undeclared_impl(ctx):
    env = analysistest.begin(ctx)
    for text in ["member-user@1.0.0", '"member-lib"', _ALIAS_MEMBER.lstrip("/"), "add", "deps"]:
        asserts.expect_failure(env, text)
    return analysistest.end(env)

_alias_undeclared_test = analysistest.make(_alias_undeclared_impl, expect_failure = True)

def workspace_member_test_suite(name):
    """Checks how targets and bins link a package's workspace-member dependency.

    A target links it only when it declares the member's target, built by any rule and reached
    through any rule that passes its `BunLibraryInfo` on; a package's bin always does.

    Args:
        name: Name of the test suite and prefix of its tests.
    """

    # The member reached through a consumer's rule between the program and the member (T094).
    consumer_wrapper(name = name + "_wrapper", libraries = [_MEMBER], tags = ["manual"])

    # The member reached only where its files do not all reach the program's copy tree (T124): in
    # a library's `data`, which carries the member's sources but not its `package.json`, and
    # through a target that provides no `BunLibraryInfo`.
    bun_library(name = name + "_data", data = [_MEMBER], tags = ["manual"])
    consumer_carrier(name = name + "_carrier", targets = [_MEMBER], tags = ["manual"])
    consumer_library(name = name + "_extras", extras = [name + "_carrier"], tags = ["manual"])

    # The other attributes that carry files (T132): a library's `srcs`, and a consumer's library's
    # `entry_point`, `preload` and `tools`, which it does not pass on. The aspect walks every
    # attribute; each of these fails because the member's `package.json` is not copied (T140).
    bun_library(name = name + "_srcs", srcs = [_MEMBER], tags = ["manual"])
    consumer_library(name = name + "_entry_point", entry_point = _MEMBER, tags = ["manual"])
    consumer_library(name = name + "_preload", preload = [_MEMBER], tags = ["manual"])
    consumer_library(name = name + "_tools", tools = [_MEMBER], tags = ["manual"])

    # The member in an attribute of a rule that returns `BunLibraryInfo` but passes none of the
    # member's files on (T140): the member's `BunLibraryInfo` is reached, its files are not copied.
    consumer_library(name = name + "_member_extras", extras = [_MEMBER], tags = ["manual"])
    cases = [
        ("declared", _declared_test, [_FIXTURE + ":node_modules/member-user", _MEMBER]),
        ("declared_through_rule", _declared_test, [_FIXTURE + ":node_modules/member-user", name + "_wrapper"]),
        ("undeclared", _undeclared_test, [_FIXTURE + ":node_modules/member-user"]),
        ("through_data", _undeclared_test, [_FIXTURE + ":node_modules/member-user", name + "_data"]),
        ("through_carrier", _undeclared_test, [_FIXTURE + ":node_modules/member-user", name + "_extras"]),
        ("through_srcs", _undeclared_test, [_FIXTURE + ":node_modules/member-user", name + "_srcs"]),
        ("through_entry_point", _undeclared_test, [_FIXTURE + ":node_modules/member-user", name + "_entry_point"]),
        ("through_preload", _undeclared_test, [_FIXTURE + ":node_modules/member-user", name + "_preload"]),
        ("through_tools", _undeclared_test, [_FIXTURE + ":node_modules/member-user", name + "_tools"]),
        ("through_extras", _undeclared_test, [_FIXTURE + ":node_modules/member-user", name + "_member_extras"]),
        # The member's target is an alias (T146): declared through it, and not declared.
        ("alias_declared", _alias_declared_test, [_ALIAS_FIXTURE + ":node_modules/member-user", _ALIAS_MEMBER]),
        ("alias_undeclared", _alias_undeclared_test, [_ALIAS_FIXTURE + ":node_modules/member-user"]),
    ]
    tests = []
    for suffix, rule, deps in cases:
        target = "{}_{}".format(name, suffix)
        bun_test(name = target, srcs = ["no_packages.test.ts"], deps = deps, tags = ["manual"])
        rule(name = target + "_test", target_under_test = target)
        tests.append(target + "_test")
    _bin_test(name = name + "_bin_test", target_under_test = _FIXTURE + ":node_modules/member-user/bin/member-user")
    tests.append(name + "_bin_test")
    _alias_bin_test(name = name + "_alias_bin_test", target_under_test = _ALIAS_FIXTURE + ":node_modules/member-user/bin/member-user")
    tests.append(name + "_alias_bin_test")
    native.test_suite(name = name, tests = tests)
