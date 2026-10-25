"""Analysis tests of the package layout in a target's copy tree (research R5, R6, G3, G8)."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun:defs.bzl", "BunLibraryInfo", "bun_test")
load(":tree_actions.bzl", "TreeActionsInfo", "tree_actions_aspect")

_BASIC = "_main/bun/tests/npm/fixtures/basic"

def _tree_path(f, name):
    """The path of an output relative to `<name>.bun/`, or `None` outside it."""
    marker = "/{}.bun/".format(name)
    i = f.path.find(marker)
    return None if i == -1 else f.path[i + len(marker):]

def _outputs(actions, mnemonic, name):
    paths = []
    for action in actions:
        if action.mnemonic == mnemonic:
            for f in action.outputs.to_list():
                path = _tree_path(f, name)
                if path != None:
                    paths.append(path)
    return sorted(paths)

def _launch_config(actions, name):
    for action in actions:
        if action.mnemonic == "FileWrite" and [o for o in action.outputs.to_list() if o.basename == name + ".launch.json"]:
            return json.decode(action.content)
    return None

_STORE = {
    "@scope+s@1.0.0": "@scope/s",
    "a@1.0.0": "a",
    "b@1.0.0": "b",
    "b@2.0.0": "b",
    "c@1.0.0": "c",
}

def _layout_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    name = target.label.name
    actions = analysistest.target_actions(env)

    stores = sorted([".store/{}/node_modules/{}".format(s, p) for s, p in _STORE.items()])
    asserts.equals(env, stores, _outputs(actions, "CopyDirectory", name))

    edges = [".store/a@1.0.0/node_modules/b", ".store/c@1.0.0/node_modules/b"]
    direct = ["{}/node_modules/{}".format(_BASIC, alias) for alias in ["@scope/s", "a", "c"]]
    asserts.equals(env, sorted(edges + direct), _outputs(actions, "UnresolvedSymlink", name))

    for path in _outputs(actions, "CopyFile", name) + _outputs(actions, "CopyDirectory", name):
        if not path.startswith(".store/"):
            asserts.false(env, "node_modules/" in path, "a copy under node_modules outside .store: " + path)

    config = _launch_config(actions, name)
    asserts.equals(env, stores, sorted(config.get("directories", [])))

    runfiles = [f.basename for f in target[DefaultInfo].default_runfiles.files.to_list()]
    asserts.true(env, "check.ok" in runfiles, "the replacement stamps are in runfiles")

    baseline = len(ctx.attr.baseline.actions)
    asserts.equals(env, len(_STORE) + len(edges) + len(direct) + baseline, len(actions), "P + E + L + A")
    return analysistest.end(env)

layout_test = analysistest.make(
    _layout_test_impl,
    attrs = {"baseline": attr.label(mandatory = True)},
)

def _no_packages_library_impl(ctx):
    return [BunLibraryInfo(srcs = depset(ctx.files.srcs), data = depset())]

# A library rule written before `BunLibraryInfo.packages` existed.
_no_packages_library = rule(
    implementation = _no_packages_library_impl,
    attrs = {"srcs": attr.label_list(allow_files = True)},
)

def _no_packages_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    actions = analysistest.target_actions(env)
    asserts.equals(env, [], _outputs(actions, "CopyDirectory", target.label.name))
    asserts.false(env, "directories" in _launch_config(actions, target.label.name))
    return analysistest.end(env)

no_packages_test = analysistest.make(_no_packages_test_impl)

def _exclusion_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_under_test(env)[TreeActionsInfo].actions
    asserts.equals(env, 1, len(actions), "one instance tree")
    if actions:
        _, inputs = actions[0]
        files = sorted([f.short_path.partition("/package/")[2] for f in inputs if "/package/" in f.short_path])
        asserts.equals(env, ["index.js", "package.json"], files)
    return analysistest.end(env)

# The excluded files are no input of the instance tree, so neither the tree nor the guard's
# declared set, which admits the tree's store entry, holds them (FR-033).
exclusion_test = analysistest.make(_exclusion_test_impl, extra_target_under_test_aspects = [tree_actions_aspect])

def layout_test_suite(name):
    """Checks the package layout in a target's copy tree.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    _no_packages_library(
        name = name + "_no_packages_library",
        srcs = ["no_packages.test.ts"],
        tags = ["manual"],
    )
    bun_test(
        name = name + "_no_packages_fixture",
        srcs = ["no_packages.test.ts"],
        deps = [name + "_no_packages_library"],
        tags = ["manual"],
    )
    no_packages_test(
        name = name + "_no_packages_test",
        target_under_test = name + "_no_packages_fixture",
    )
    layout_test(
        name = name + "_test",
        target_under_test = "//bun/tests/npm/fixtures/basic:imports_test",
        baseline = "//bun/tests/npm/fixtures/basic:imports_baseline",
    )
    exclusion_test(
        name = name + "_exclusion_test",
        target_under_test = "//bun/tests/npm/fixtures/basic:node_modules/excluded",
    )
    native.test_suite(name = name, tests = [name + "_test", name + "_no_packages_test", name + "_exclusion_test"])
