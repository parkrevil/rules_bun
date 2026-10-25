"""Analysis tests of the `bin` targets of packages (FR-018, US6, research R10)."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

_BASIC = "//bun/tests/npm/fixtures/basic:node_modules/"

def _bin_test_impl(ctx):
    env = analysistest.begin(ctx)
    marker = "/_npm_bin/{}/{}.bun/".format(ctx.attr.package, ctx.attr.bin)
    copies = []
    for action in analysistest.target_actions(env):
        if action.mnemonic not in ["CopyDirectory", "CopyFile", "UnresolvedSymlink"]:
            continue
        for f in action.outputs.to_list():
            i = f.path.find(marker)
            asserts.true(env, i != -1, "an output outside {}: {}".format(marker, f.path))
            if i != -1:
                asserts.false(env, "/node_modules/" in f.path[:i], "a copy tree under node_modules: " + f.path)
                copies.append(f.path[i + len(marker):])
    store = ".store/{}/node_modules/{}".format(ctx.attr.store_name, ctx.attr.package)
    asserts.true(env, store in copies, "the store entry {} is copied: {}".format(store, copies))
    return analysistest.end(env)

_bin_test = analysistest.make(
    _bin_test_impl,
    attrs = {"bin": attr.string(), "package": attr.string(), "store_name": attr.string()},
)

def _non_js_test_impl(ctx):
    env = analysistest.begin(ctx)
    for part in ["nonjs-bin@1.0.0", 'bin entry "nonjs"', "bin/tool", "extension"]:
        asserts.expect_failure(env, part)
    return analysistest.end(env)

_non_js_test = analysistest.make(_non_js_test_impl, expect_failure = True)

def bins_test_suite(name):
    """Checks the `bin` targets the `npm` extension generates for packages.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    tests = []
    for package, store_name, bin in [
        ("single-bin", "single-bin@1.0.0", "single-bin"),
        ("@scope/s", "@scope+s@1.0.0", "s-tool"),
        ("@scope/s", "@scope+s@1.0.0", "s-other"),
        ("weird-bin", "weird-bin@1.0.0", "run_tool"),
    ]:
        test = "{}_{}_test".format(name, bin)
        _bin_test(
            name = test,
            target_under_test = "{}{}/bin/{}".format(_BASIC, package, bin),
            package = package,
            store_name = store_name,
            bin = bin,
        )
        tests.append(test)
    _non_js_test(name = name + "_non_js_test", target_under_test = _BASIC + "nonjs-bin/bin/nonjs")
    tests.append(name + "_non_js_test")
    native.test_suite(name = name, tests = tests)
