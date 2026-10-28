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

_BINS_NODE = "//bun/tests/npm/fixtures/bins_node:node_modules/"

_NODE_BIN = _BINS_NODE + "node-bin/bin/"

_NOT_JAVASCRIPT = "which is not a JavaScript program for Node or Bun: "

_NO_EXTENSION = "it has none of the extensions .ts, .tsx, .mts, .cts, .js, .jsx, .mjs, .cjs and its first line is no #! line naming node or bun"

def _make_failure_test(messages):
    def impl(ctx):
        env = analysistest.begin(ctx)
        for message in messages:
            asserts.expect_failure(env, message)
        return analysistest.end(env)

    return analysistest.make(impl, expect_failure = True)

def _not_runnable(package, entry, path, reason):
    return 'the bin entry "{}" of the npm package {} is the file {}, {}{}'.format(entry, package, path, _NOT_JAVASCRIPT, reason)

# FR-012: a bin is runnable when it has a source extension or its first line is a #! line naming
# node or bun; any other fails analysis with the reason.
_non_js_test = _make_failure_test([_not_runnable("nonjs-bin@1.0.0", "nonjs", "bin/tool", _NO_EXTENSION)])
_sh_test = _make_failure_test([_not_runnable("node-bin@1.0.0", "sh", "bin/sh", _NO_EXTENSION)])
_noline_test = _make_failure_test([_not_runnable("node-bin@1.0.0", "noline", "bin/noline", _NO_EXTENSION)])
_dir_test = _make_failure_test([_not_runnable("node-bin@1.0.0", "dir", "bin/dir", "it is a directory")])

# bin/gone is left out by the hub's exclude_package_contents.
_gone_test = _make_failure_test([_not_runnable("node-bin@1.0.0", "gone", "bin/gone", "the package holds no such file")])

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
        ("node-bin", "node-bin@1.0.0", "tsc"),
        ("node-bin", "node-bin@1.0.0", "envs"),
        ("node-bin", "node-bin@1.0.0", "abs"),
        ("node-bin", "node-bin@1.0.0", "bunbin"),
    ]:
        test = "{}_{}_test".format(name, bin)
        _bin_test(
            name = test,
            target_under_test = "{}{}/bin/{}".format(_BINS_NODE if package == "node-bin" else _BASIC, package, bin),
            package = package,
            store_name = store_name,
            bin = bin,
        )
        tests.append(test)
    for suffix, rule, target in [
        ("non_js", _non_js_test, _BASIC + "nonjs-bin/bin/nonjs"),
        ("sh", _sh_test, _NODE_BIN + "sh"),
        ("noline", _noline_test, _NODE_BIN + "noline"),
        ("dir", _dir_test, _NODE_BIN + "dir"),
        ("gone", _gone_test, _NODE_BIN + "gone"),
    ]:
        rule(name = "{}_{}_test".format(name, suffix), target_under_test = target)
        tests.append("{}_{}_test".format(name, suffix))
    native.test_suite(name = name, tests = tests)
