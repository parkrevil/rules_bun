"""Analysis tests of one instance per package version per target (FR-003, FR-017, US5-4)."""

load("@bazel_lib//lib:copy_to_directory.bzl", "copy_to_directory")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun:defs.bzl", "bun_test")
load("//bun/private:npm_package.bzl", "npm_instance", "npm_link")

_BASIC = "//bun/tests/npm/fixtures/basic:node_modules/"
_CONFLICT = "//bun/tests/npm/fixtures/dependency_conflict:node_modules/"

def _make_failure_test(messages):
    def impl(ctx):
        env = analysistest.begin(ctx)
        for message in messages:
            asserts.expect_failure(env, message)
        return analysistest.end(env)

    return analysistest.make(impl, expect_failure = True)

# y/x and z/x are x@1.0.0 entries whose dependency b resolves to b@2.0.0 under y and b@1.0.0 under
# z (the dependency_conflict fixture, feature 004 research R12).
_dependency_test = _make_failure_test(["x@1.0.0", 'dependency "b"', "b@2.0.0"])

# p with the root's q@1.0.0, and p through q2-user, which provides q@2.0.0.
_peer_test = _make_failure_test(["p@1.0.0", 'peer "q"', "q@1.0.0", "q@2.0.0"])

_missing_peer_test = _make_failure_test(["ident-a@1.0.0 cannot be used", 'its peer dependency "state"'])

# a@1.0.0 at the key "a" of two lockfiles with one content identity: npm_workspace resolves its b to
# b@1.0.0, npm_overrides_top to b@2.0.0. One instance ID names both, so only hub-qualified
# identities tell them apart.
_hubs_test = _make_failure_test(["a@1.0.0", 'dependency "b"', "b@1.0.0", "b@2.0.0"])

# a-outer@1.0.0's peer ident-a is ident-a@1.0.0 in both instances; the instances of ident-a differ
# by their own peer state, so the error names state's two versions, not ident-a@1.0.0 twice.
_peer_chain_test = _make_failure_test(["ident-a@1.0.0", 'peer "state"', "state@1.0.0", "state@2.0.0"])

def _hubs_alike_impl(ctx):
    env = analysistest.begin(ctx)
    outputs = [f.short_path for action in analysistest.target_actions(env) for f in action.outputs.to_list()]
    for entry in [".store/a@1.0.0/node_modules/a", ".store/b@1.0.0/node_modules/b"]:
        asserts.equals(env, 1, len([o for o in outputs if o.endswith(entry)]), "copies of " + entry)
    return analysistest.end(env)

# a@1.0.0 of npm_workspace reaches b@1.0.0, which npm_hoisted links too; both hubs describe b@1.0.0
# alike (the same replacement archive, no exclusion), so it is carried once (US9; feature 005 US2).
_hubs_alike_test = analysistest.make(_hubs_alike_impl)

# a@1.0.0 of npm_basic, which leaves test/** out of every package, and of npm_workspace, which leaves
# nothing out (feature 005 FR-001).
_hubs_exclude_test = _make_failure_test(["a@1.0.0", "npm_basic", "npm_workspace", "exclusion policy", '["test/**"]', "[]"])

_IDENTITY = {"exclude": [], "integrity": "sha512-AAAA", "source": "https://registry.example/x/-/x-1.0.0.tgz"}

def _identity_alike_impl(ctx):
    env = analysistest.begin(ctx)
    outputs = [f.short_path for action in analysistest.target_actions(env) for f in action.outputs.to_list()]
    entry = ".store/x@1.0.0/node_modules/x"
    asserts.equals(env, 1, len([o for o in outputs if o.endswith(entry)]), "copies of " + entry)
    return analysistest.end(env)

# x@1.0.0 of two hubs with one content identity: carried once (feature 005 FR-001).
_identity_alike_test = analysistest.make(_identity_alike_impl)

_identity_integrity_test = _make_failure_test(["x@1.0.0", "hub_a", "//a:bun.lock", "hub_b", "//b:bun.lock", "integrity", "sha512-AAAA", "sha512-BBBB"])
_identity_source_test = _make_failure_test(["x@1.0.0", "//a:bun.lock", "//b:bun.lock", "source", "https://registry.example/x/-/x-1.0.0.tgz", "//archives:x.tgz"])
_identity_exclude_test = _make_failure_test(["x@1.0.0", "//a:bun.lock", "//b:bun.lock", "exclusion policy", "[]", '["docs/**"]'])

# One identity, but x's dependency b resolves to two versions: the dependency is named.
_identity_edge_test = _make_failure_test(["x@1.0.0", 'dependency "b"', "b@1.0.0", "b@2.0.0"])

def _identity_links(name, second, edges = False):
    """Two link targets of x@1.0.0 from the hubs hub_a and hub_b over one tree.

    Args:
        name: Prefix of the targets.
        second: Content identity attributes of hub_b's instance that differ from hub_a's.
        edges: Whether x depends on b, b@1.0.0 in hub_a and b@2.0.0 in hub_b.

    Returns:
        The labels of the two links.
    """
    copy_to_directory(name = name + "_tree", srcs = ["no_packages.test.ts"], tags = ["manual"])
    tree = ":" + name + "_tree"
    links = []
    for n, hub in enumerate(["hub_a", "hub_b"]):
        identity = dict(_IDENTITY)
        if n == 1:
            identity.update(second)
        common = dict(hub = hub, lockfile = "//{}:bun.lock".format(hub[-1]), tree = tree, tags = ["manual"])
        instances = []
        x_edges = {}
        if edges:
            b = "{}_b@{}.0.0__{}".format(name, n + 1, n)
            npm_instance(name = b, package = "b", store_name = "b@{}.0.0".format(n + 1), **(common | _IDENTITY))
            instances.append(b)
            x_edges = {"b": b}
        x = "{}_x@1.0.0__{}".format(name, n)
        npm_instance(name = x, edges = x_edges, package = "x", store_name = "x@1.0.0", **(common | identity))
        npm_link(name = "{}_link{}".format(name, n), alias = "x", root = x, instances = [":" + i for i in [x] + instances], tags = ["manual"])
        links.append(":{}_link{}".format(name, n))
    return links

def _peer_chain_links(name):
    """Two link targets whose a-outer@1.0.0 instances differ only below their peer (US5-4).

    The instance names sort as a hub's IDs do (`<name>@<version>__<n>`), a-outer first.
    """
    copy_to_directory(name = name + "_tree", srcs = ["no_packages.test.ts"], tags = ["manual"])
    tree = ":" + name + "_tree"
    links = []
    for n in ["1", "2"]:
        outer, ident, state = ["{}_{}__{}".format(name, nv, n) for nv in ["a-outer@1.0.0", "ident-a@1.0.0", "state@{}.0.0".format(n)]]
        npm_instance(name = state, package = "state", store_name = "state@{}.0.0".format(n), tree = tree, tags = ["manual"])
        npm_instance(name = ident, edges = {"state": state}, package = "ident-a", peers = ["state"], store_name = "ident-a@1.0.0", tree = tree, tags = ["manual"])
        npm_instance(name = outer, edges = {"ident-a": ident}, package = "a-outer", peers = ["ident-a"], store_name = "a-outer@1.0.0", tree = tree, tags = ["manual"])
        npm_link(name = "{}_link{}".format(name, n), alias = "a-outer", root = outer, instances = [":" + i for i in [outer, ident, state]], tags = ["manual"])
        links.append(":{}_link{}".format(name, n))
    return links

def uniqueness_test_suite(name):
    """Checks that a target gets one instance per package version.

    Args:
        name: Name of the test suite and prefix of its tests.
    """
    cases = [
        ("dependency", _dependency_test, [_CONFLICT + "y", _CONFLICT + "z"]),
        ("peer", _peer_test, [_BASIC + "p", _BASIC + "q2-user"]),
        ("missing_peer", _missing_peer_test, ["//bun/tests/npm/fixtures/missing_peer:node_modules/ident-a"]),
        ("hubs_alike", _hubs_alike_test, ["//bun/tests/npm/fixtures/hoisted:node_modules/b", "//bun/tests/npm/fixtures/workspace:node_modules/a"]),
        ("hubs_exclude", _hubs_exclude_test, [_BASIC + "a", "//bun/tests/npm/fixtures/workspace:node_modules/a"]),
        ("identity_alike", _identity_alike_test, _identity_links(name + "_identity_alike", {})),
        ("identity_integrity", _identity_integrity_test, _identity_links(name + "_identity_integrity", {"integrity": "sha512-BBBB"})),
        ("identity_source", _identity_source_test, _identity_links(name + "_identity_source", {"source": "//archives:x.tgz"})),
        ("identity_exclude", _identity_exclude_test, _identity_links(name + "_identity_exclude", {"exclude": ["docs/**"]})),
        ("identity_edge", _identity_edge_test, _identity_links(name + "_identity_edge", {}, edges = True)),
        ("hubs", _hubs_test, ["//bun/tests/npm/fixtures/workspace:node_modules/a", "//bun/tests/npm/fixtures/overrides_top:node_modules/a"]),
        ("peer_chain", _peer_chain_test, _peer_chain_links(name + "_peer_chain")),
    ]
    tests = []
    for suffix, rule, deps in cases:
        target = "{}_{}".format(name, suffix)
        bun_test(name = target, srcs = ["no_packages.test.ts"], deps = deps, tags = ["manual"])
        rule(name = target + "_test", target_under_test = target)
        tests.append(target + "_test")
    native.test_suite(name = name, tests = tests)
