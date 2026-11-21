"""Analysis tests of platform-specific optional dependencies (FR-016, US3, research R8; feature 004
research R11 for libc, which Bun 1.4.4 writes)."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun:defs.bzl", "BunLibraryInfo", "bun_binary")
load("//bun/private:bun_install_types.bzl", "BEHAVIOR", "LIBC_ALL", "libc_for_dependency", "meta_is_disabled", "platform_names", "platform_value")
load("//bun/private:bun_lockfile.bzl", "load_lockfile", "lockfile_clean", "lockfile_resolve")
load("//bun/private:bun_tree.bzl", "hoist")
load("//bun/private:lockfile.bzl", "read_lockfile")
load("//bun/private:platforms.bzl", "NPM_CPU", "NPM_OS", "npm_only_names", "package_platforms", "platform_bits", "platform_classes", "platform_tuples")

_BASIC = "//bun/tests/npm/fixtures/basic:node_modules/"
_AIX = "//bun/tests/npm/fixtures/aix:node_modules/aix-user"
_ANY = "//bun/tests/npm/fixtures/any_platform:node_modules/any-platform"

def _cleaned(env, project):
    file = "bun/tests/npm/fixtures/{}/bun.lock".format(project)
    loaded = load_lockfile(read_lockfile(RESULTS[project]["text"], file).value, file)
    asserts.equals(env, None, loaded.error)
    asserts.equals(env, None, lockfile_resolve(loaded.value, hoist))
    return lockfile_clean(loaded.value, hoist).value

def _platform_classes_test_impl(ctx):
    env = unittest.begin(ctx)

    # The tuples are the hub's `select()` branches: every OS alone and with each CPU, on Linux each
    # also with each libc, and the default branch of an unmapped platform (research R3).
    tuples = platform_tuples()
    asserts.equals(env, 71, len(tuples))
    asserts.true(env, (None, None, None) in tuples, "the unmapped platform")
    asserts.true(env, ("linux", "x64", "musl") in tuples and ("linux", "x64", None) in tuples and ("darwin", None, None) in tuples)

    # Linux without the libc constraint is every libc (`Libc::ALL`); off Linux, too.
    asserts.equals(env, LIBC_ALL, platform_bits(("linux", "x64", None)).libc)
    asserts.equals(env, LIBC_ALL, platform_bits(("darwin", "arm64", None)).libc)
    asserts.equals(env, platform_value("libc", "musl"), platform_bits(("linux", "x64", "musl")).libc)

    # A lockfile without a restricted package has one class.
    asserts.equals(env, [tuples], platform_classes(_cleaned(env, "dependency_conflict")))

    # Tuples group by the packages `is_disabled` leaves out: `native-aix-x64` only on aix/x64,
    # `native-darwin-arm64` only on darwin/arm64, the `nomatch` packages nowhere.
    classes = platform_classes(_cleaned(env, "conformance_platform"))
    asserts.equals(env, [1, 1, 69], sorted([len(c) for c in classes]))
    asserts.true(env, [("aix", "x64", None)] in classes and [("darwin", "arm64", None)] in classes)
    return unittest.end(env)

_platform_classes_test = unittest.make(_platform_classes_test_impl)

def _carried_on(platform, os = None, cpu = None, libc = None, behavior = BEHAVIOR.OPTIONAL):
    """Whether a package with these fields is carried on a platform tuple, as the resolver decides."""
    meta = struct(
        os = package_platforms("os", os),
        arch = package_platforms("cpu", cpu),
        libc = package_platforms("libc", libc),
    )
    bits = platform_bits(platform)
    return not meta_is_disabled(meta, bits.cpu, bits.os, libc_for_dependency(bits.libc, behavior))

def _bun_rule_test_impl(ctx):
    env = unittest.begin(ctx)
    linux_glibc = ("linux", "x64", "glibc")
    linux_musl = ("linux", "x64", "musl")
    linux = ("linux", "x64", None)
    darwin = ("darwin", "arm64", None)
    windows = ("win32", "x64", None)

    # The cases the `npm` extension's "Packages" paragraph states (feature 006 T084), on the
    # platform tuples the hub selects by. `any` allows every value unless a known value follows.
    for platform in [linux_glibc, darwin, windows]:
        asserts.true(env, _carried_on(platform, os = ["linux", "any"]), platform)
    asserts.false(env, _carried_on(darwin, os = ["any", "linux"]))

    # A list of removals only allows every other value.
    asserts.false(env, _carried_on(windows, os = ["!win32"]))
    asserts.true(env, _carried_on(darwin, os = ["!win32"]))

    # A value Bun knows but `@platforms` has no constraint for matches no target platform.
    asserts.equals(env, [], [t for t in platform_tuples() if _carried_on(t, os = ["sunos"])])
    asserts.equals(env, [], [t for t in platform_tuples() if _carried_on(t, cpu = ["ppc64"])])

    # `libc`: on Linux with the libc constraint only the matching variant; on Linux without it and
    # off Linux every variant (`Libc::CURRENT`); a non-optional dependency whatever its `libc`.
    asserts.false(env, _carried_on(linux_musl, libc = ["glibc"]))
    asserts.true(env, _carried_on(linux_glibc, libc = ["glibc"]))
    asserts.true(env, _carried_on(linux, libc = ["glibc"]))
    asserts.true(env, _carried_on(darwin, libc = ["glibc"]))
    asserts.true(env, _carried_on(linux_musl, libc = ["glibc"], behavior = BEHAVIOR.PROD))

    # An `os` or `cpu` the hub selects on that Bun does not name (T112): Bun refuses it as a
    # target, so a package's list is read for it as npm's `checkList` reads it, as on `main`; on
    # the values Bun names, Bun's reading decides (a value it does not name matches none of them).
    for kind, table in [("os", NPM_OS), ("cpu", NPM_CPU)]:
        for value in sorted(table.keys()):
            asserts.true(env, value in platform_names(kind) or value in npm_only_names(kind), "{} {} is named by Bun or read as npm reads it".format(kind, value))
    riscv64 = ("linux", "riscv64", None)
    netbsd = ("netbsd", "x64", None)
    asserts.true(env, _carried_on(riscv64, cpu = ["riscv64"]), "cpu riscv64 on riscv64")
    asserts.false(env, _carried_on(linux, cpu = ["riscv64"]), "cpu riscv64 on x64")
    asserts.false(env, _carried_on(riscv64, cpu = ["!riscv64"]), "cpu !riscv64 on riscv64")
    asserts.true(env, _carried_on(linux, cpu = ["!riscv64"]), "cpu !riscv64 on x64")
    asserts.false(env, _carried_on(riscv64, cpu = ["x64"]), "cpu x64 on riscv64")
    asserts.true(env, _carried_on(riscv64, cpu = ["x64", "riscv64"]), "cpu x64, riscv64 on riscv64")
    asserts.true(env, _carried_on(riscv64), "no cpu on riscv64")
    asserts.true(env, _carried_on(netbsd, os = ["netbsd"]), "os netbsd on netbsd")
    asserts.false(env, _carried_on(linux, os = ["netbsd"]), "os netbsd on linux")
    asserts.false(env, _carried_on(netbsd, os = ["!netbsd"]), "os !netbsd on netbsd")
    asserts.true(env, _carried_on(netbsd, os = ["!win32"]), "os !win32 on netbsd")
    asserts.true(env, _carried_on(netbsd, os = ["any"]), "os any on netbsd")
    asserts.false(env, _carried_on(netbsd, os = ["linux", "any"]), "os linux, any on netbsd: npm's checkList")
    asserts.equals(env, [("netbsd", None, None)] + [("netbsd", c, None) for c in sorted(NPM_CPU.keys())], [t for t in platform_tuples() if _carried_on(t, os = ["netbsd"])])
    return unittest.end(env)

_bun_rule_test = unittest.make(_bun_rule_test_impl)

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

_PLATFORM_PEER = "//bun/tests/npm/fixtures/conformance_platform_peer:node_modules/plat-peer-host"

def _root_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.equals(env, ctx.attr.expected, _carried(target, "plat-peer-host"))
    record = target[BunLibraryInfo].packages.to_list()[0]
    roots = [i for i in record.instances.to_list() if i.id == record.root]
    asserts.equals(env, 1, len(roots), "the link's root instance")
    if roots:
        asserts.equals(env, ctx.attr.peers, roots[0].peer_hash != "", "whether the root has peer bindings")
    return analysistest.end(env)

def _make_root(platform):
    return analysistest.make(
        _root_impl,
        attrs = {"expected": attr.string_list(), "peers": attr.bool()},
        config_settings = {"//command_line_option:platforms": str(Label("//bun/tests/platforms:" + platform))},
    )

_root_linux_x64_test = _make_root("linux_x64")
_root_darwin_aarch64_test = _make_root("darwin_aarch64")

_PLATFORM_EDGE = "//bun/tests/npm/fixtures/conformance_platform_edge:edge_fixture"

def _edge_impl(ctx):
    env = analysistest.begin(ctx)
    name = analysistest.target_under_test(env).label.name
    marker = "/{}.bun/".format(name)
    links = []
    for action in analysistest.target_actions(env):
        if action.mnemonic == "UnresolvedSymlink":
            for f in action.outputs.to_list():
                if marker in f.path and "/.store/" in f.path:
                    links.append(f.path[f.path.find(marker) + len(marker):])
    asserts.equals(env, ctx.attr.expected, sorted(links), "the store's dependency links")
    return analysistest.end(env)

def _make_edge(platform):
    return analysistest.make(
        _edge_impl,
        attrs = {"expected": attr.string_list()},
        config_settings = {"//command_line_option:platforms": str(Label("//bun/tests/platforms:" + platform))},
    )

_edge_glibc_test = _make_edge("linux_x64_glibc")
_edge_musl_test = _make_edge("linux_x64_musl")

_PLATFORM_ENTRY = "//bun/tests/npm/conformance/accepted/platform_peer_1_4_2:entry_fixture"

def _without_hash(path):
    """A store path with each `+<peer hash>` written `+<hash>`."""
    parts = path.split("+")
    return "+".join([parts[0]] + ["<hash>" + part[16:] for part in parts[1:]])

def _entry_impl(ctx):
    env = analysistest.begin(ctx)
    name = analysistest.target_under_test(env).label.name
    marker = "/{}.bun/".format(name)
    links = []
    for action in analysistest.target_actions(env):
        if action.mnemonic == "UnresolvedSymlink":
            for f in action.outputs.to_list():
                if marker in f.path and "/.store/" in f.path:
                    links.append(_without_hash(f.path[f.path.find(marker) + len(marker):]))
    asserts.equals(env, ctx.attr.expected, sorted(links), "the store's dependency links")
    return analysistest.end(env)

def _make_entry(platform):
    return analysistest.make(
        _entry_impl,
        attrs = {"expected": attr.string_list()},
        config_settings = {"//command_line_option:platforms": str(Label("//bun/tests/platforms:" + platform))},
    )

_entry_linux_x64_test = _make_entry("linux_x64")
_entry_darwin_aarch64_test = _make_entry("darwin_aarch64")

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

    # A sole `any` matches every platform (Bun's `Negatable::combine`, feature 005 FR-006).
    for platform in ["linux_x64", "darwin_aarch64", "windows_x64"]:
        _RULES[platform](name = "{}_any_{}_test".format(name, platform), target_under_test = _ANY, package = "", expected = ["any-platform"])
        tests.append("{}_any_{}_test".format(name, platform))

    # plat-peer-host@1.0.0 is a different store entry by platform (feature 006 BC-12): on darwin
    # its own q-darwin provides its p's peer q; elsewhere that is disabled, so the peer binds the
    # root's q@1.0.0 and the root has peer bindings. The hub selects the root by platform.
    _root_linux_x64_test(name = name + "_root_linux_x64_test", target_under_test = _PLATFORM_PEER, expected = ["p", "q"], peers = True)
    _root_darwin_aarch64_test(name = name + "_root_darwin_aarch64_test", target_under_test = _PLATFORM_PEER, expected = ["p", "q-darwin"], peers = False)
    tests += [name + "_root_linux_x64_test", name + "_root_darwin_aarch64_test"]

    # native's optional edge to native-linux-x64-musl exists on musl only, while the root's
    # non-optional dependency on it holds everywhere (T101): a target holding both links native's
    # only where the store does.
    _edge_glibc_test(name = name + "_edge_glibc_test", target_under_test = _PLATFORM_EDGE, expected = [".store/native@1.0.0/node_modules/native-linux-x64"])
    _edge_musl_test(name = name + "_edge_musl_test", target_under_test = _PLATFORM_EDGE, expected = [".store/native@1.0.0/node_modules/native-linux-x64-musl"])
    tests += [name + "_edge_glibc_test", name + "_edge_musl_test"]

    # plat-peer-host's p is the entry of p@1.0.0 that binds q to q-darwin@1.0.0 on darwin, and the
    # one without q elsewhere, where q-darwin is disabled (BC-16): the hub selects the edge.
    _entry_linux_x64_test(name = name + "_entry_linux_x64_test", target_under_test = _PLATFORM_ENTRY, expected = [".store/plat-peer-host@1.0.0/node_modules/p"])
    _entry_darwin_aarch64_test(
        name = name + "_entry_darwin_aarch64_test",
        target_under_test = _PLATFORM_ENTRY,
        expected = [
            ".store/p@1.0.0+<hash>/node_modules/q",
            ".store/plat-peer-host@1.0.0/node_modules/p",
            ".store/plat-peer-host@1.0.0/node_modules/q",
        ],
    )
    tests += [name + "_entry_linux_x64_test", name + "_entry_darwin_aarch64_test"]

    _platform_classes_test(name = name + "_platform_classes_test")
    tests.append(name + "_platform_classes_test")
    _bun_rule_test(name = name + "_bun_rule_test")
    tests.append(name + "_bun_rule_test")

    _exec_tool(name = name + "_exec_tool", tool = name + "_native_tool", tags = ["manual"])
    exec_test(name = name + "_exec_test", target_under_test = name + "_exec_tool")
    tests.append(name + "_exec_test")
    native.test_suite(name = name, tests = tests)
