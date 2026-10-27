"""Unit tests of the workspace glob matcher of `//bun/private:workspaces.bzl` (R9, US4-4).

The semantics are the ones Bun 1.4.4 shows (T081 pins them against Bun): a negative pattern,
wherever it stands in the list, removes what any glob matched, not a directory listed by its path.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//bun:defs.bzl", "BunLibraryInfo")
load("//bun/private:workspaces.bzl", "match_members")

# Directory -> its child directories; a directory in _MANIFESTS holds a package.json.
_TREE = {
    "": [".hidden", "node_modules", "other", "packages", "tools"],
    ".hidden": ["h"],
    "node_modules": ["zz"],
    "other": ["c"],
    "packages": [".dot", "a", "ab", "b", "deep", "excluded", "nopkg"],
    "packages/a": ["node_modules"],
    "packages/a/node_modules": ["n"],
    "packages/deep": ["x"],
    "tools": ["t1", "t22"],
}

_MANIFESTS = [
    ".hidden/h",
    "node_modules/zz",
    "other/c",
    "packages/.dot",
    "packages/a",
    "packages/a/node_modules/n",
    "packages/ab",
    "packages/b",
    "packages/deep/x",
    "packages/excluded",
    "tools/t1",
    "tools/t22",
]

def _match(patterns):
    result = match_members(
        patterns,
        lambda path: _TREE.get(path, []),
        lambda path: path in _MANIFESTS,
        "package.json",
    )
    return result.value if result.error == None else result.error

def _wildcards_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, ["packages/a", "packages/ab", "packages/b", "packages/excluded"], _match(["packages/*"]))
    asserts.equals(env, ["packages/a", "packages/b"], _match(["packages/?"]))
    asserts.equals(env, ["tools/t1"], _match(["tools/t?"]))
    asserts.equals(env, ["packages/a", "packages/ab"], _match(["packages/a*"]))
    asserts.equals(env, ["packages/a", "packages/ab", "packages/b", "packages/deep/x", "packages/excluded"], _match(["packages/**"]))
    asserts.equals(env, ["packages/deep/x"], _match(["**/x"]))
    asserts.equals(env, ["packages/a"], _match(["packages/**/a"]))
    asserts.equals(env, ["packages/a", "packages/ab", "packages/b", "packages/excluded"], _match(["./packages/*/"]))
    return unittest.end(env)

def _classes_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, ["packages/a", "packages/b"], _match(["packages/[ab]"]))
    asserts.equals(env, ["packages/a", "packages/b"], _match(["packages/[a-b]"]))
    asserts.equals(env, ["packages/b", "packages/excluded"], _match(["packages/[!a]*"]))
    asserts.equals(env, ["packages/b", "packages/excluded"], _match(["packages/[^a]*"]))
    asserts.equals(env, [], _match(["packages/[ab"]))
    asserts.equals(env, ["packages/a", "packages/b"], _match(["packages/{a,b}"]))

    # Braces expand within one segment only.
    asserts.equals(env, [], _match(["{packages/ab,tools/t22}"]))
    return unittest.end(env)

def _negation_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, ["packages/a", "packages/ab", "packages/b"], _match(["packages/*", "!packages/excluded"]))
    asserts.equals(env, ["packages/ab", "packages/excluded"], _match(["packages/*", "!packages/{a,b}"]))
    asserts.equals(env, ["packages/a", "packages/ab", "packages/b"], _match(["packages/*", "!**/excluded"]))

    # A negative pattern removes what any glob matched, before or after it.
    asserts.equals(env, ["packages/a", "packages/ab", "packages/b"], _match(["!packages/excluded", "packages/*"]))
    asserts.equals(env, ["packages/b", "packages/excluded"], _match(["packages/*", "!packages/a*", "packages/a*"]))
    asserts.equals(env, ["other/c", "tools/t1", "tools/t22"], _match(["**", "!packages/**"]))

    # A directory listed by its path is not removed by a negative pattern.
    asserts.equals(env, ["packages/ab", "packages/b", "packages/excluded"], _match(["packages/*", "!packages/a*", "packages/ab"]))
    asserts.equals(env, ["packages/a", "packages/b"], _match(["packages/a", "packages/b", "!packages/a"]))
    asserts.equals(env, ["packages/a"], _match(["packages/a", "!packages/*"]))
    return unittest.end(env)

def _members_test_impl(ctx):
    env = unittest.begin(ctx)

    # Only a directory holding package.json is a member; node_modules and hidden directories are
    # not searched by wildcards.
    asserts.equals(env, ["other/c", "packages/a", "packages/ab", "packages/b", "packages/deep/x", "packages/excluded", "tools/t1", "tools/t22"], _match(["**"]))
    asserts.equals(env, [], _match(["packages/a/node_modules/*"]))
    asserts.equals(env, ["packages/.dot"], _match(["packages/.*"]))
    asserts.equals(env, [".hidden/h"], _match([".hidden/*"]))
    error = _match(["packages/nopkg"])
    asserts.true(env, type(error) == "string" and "packages/nopkg" in error and "package.json" in error, str(error))
    return unittest.end(env)

wildcards_test = unittest.make(_wildcards_test_impl)
classes_test = unittest.make(_classes_test_impl)
negation_test = unittest.make(_negation_test_impl)
members_test = unittest.make(_members_test_impl)

# US4-6: w1's optional dependency native-linux-x64 (os linux, cpu x64) is carried on Linux x64 only.
_OPTIONAL = "//bun/tests/npm/fixtures/workspace/packages/w1:node_modules/native-linux-x64"

def _optional_impl(ctx):
    env = analysistest.begin(ctx)
    carried = sorted([
        instance.id.split("@")[0]
        for record in analysistest.target_under_test(env)[BunLibraryInfo].packages.to_list()
        for instance in record.instances.to_list()
    ])
    asserts.equals(env, ctx.attr.expected, carried)
    return analysistest.end(env)

def _make_optional(platform):
    return analysistest.make(
        _optional_impl,
        attrs = {"expected": attr.string_list()},
        config_settings = {"//command_line_option:platforms": str(Label("//bun/tests/platforms:" + platform))},
    )

optional_linux_x64_test = _make_optional("linux_x64")
optional_linux_aarch64_test = _make_optional("linux_aarch64")
optional_darwin_x64_test = _make_optional("darwin_x64")
optional_darwin_aarch64_test = _make_optional("darwin_aarch64")
optional_windows_x64_test = _make_optional("windows_x64")

_OPTIONAL_RULES = {
    "darwin_aarch64": optional_darwin_aarch64_test,
    "darwin_x64": optional_darwin_x64_test,
    "linux_aarch64": optional_linux_aarch64_test,
    "linux_x64": optional_linux_x64_test,
    "windows_x64": optional_windows_x64_test,
}

def workspaces_test_suite(name):
    """Checks the workspace glob matcher and the optional dependencies a workspace member links.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    unittest.suite(name + "_glob", wildcards_test, classes_test, negation_test, members_test)
    tests = [name + "_glob"]
    for platform, rule in sorted(_OPTIONAL_RULES.items()):
        test = "{}_optional_{}_test".format(name, platform)
        rule(
            name = test,
            target_under_test = _OPTIONAL,
            expected = ["native-linux-x64"] if platform == "linux_x64" else [],
        )
        tests.append(test)
    native.test_suite(name = name, tests = tests)
