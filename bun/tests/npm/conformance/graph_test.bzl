"""Unit tests for `graph.bzl`: the ruleset side of the conformance graph (contract "Ruleset side")."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(":graph.bzl", "conformance_graphs")

_LINUX_GLIBC = ("linux", "x64", "glibc")
_LINUX_MUSL = ("linux", "x64", "musl")
_LINUX_UNCONSTRAINED = ("linux", "x64", "unconstrained")
_DARWIN = ("darwin", "arm64", None)
_TUPLES = [_LINUX_GLIBC, _LINUX_MUSL, _LINUX_UNCONSTRAINED, _DARWIN]

def _instance(name, version, edges = {}, status = "ok"):
    return struct(
        id = "{}@{}__1".format(name, version),
        name = name,
        version = version,
        store_name = "{}@{}".format(name, version),
        key = name,
        edges = edges,
        dependency_keys = {},
        peers = [],
        status = status,
    )

def _link(alias, root, closure, optional = {}):
    return struct(alias = alias, root = root, closure = closure, optional = optional)

def _resolution(instances, links, members = {}):
    return struct(
        value = struct(
            instances = {i.id: i for i in instances},
            links = links,
            members = members,
        ),
        error = None,
    )

def _graph_for(classes, platform):
    for cls in classes:
        if list(platform) in cls["platforms"]:
            return cls["graph"]
    fail("no class holds {}".format(platform))

def _entry_names(graph):
    return sorted(["{}@{}".format(e["name"], e["version"]) for e in graph["entries"]])

def _target(graph, target):
    if target.startswith("w:"):
        return target
    entry = graph["entries"][int(target[2:])]
    return "{}@{}".format(entry["name"], entry["version"])

def _closure_test_impl(ctx):
    env = unittest.begin(ctx)
    b = _instance("b", "1.0.0")
    a = _instance("a", "1.0.0", edges = {"b": b.id})
    resolution = _resolution([a, b], {"": {"a": _link("a", a.id, sorted([a.id, b.id]))}})
    classes = conformance_graphs(resolution, _TUPLES)

    # A closure is linked on every platform: one class.
    asserts.equals(env, 1, len(classes))
    asserts.equals(env, sorted([list(t) for t in _TUPLES]), sorted(classes[0]["platforms"]))
    graph = classes[0]["graph"]
    asserts.equals(env, ["a@1.0.0", "b@1.0.0"], _entry_names(graph))
    asserts.equals(env, ["a"], sorted(graph["holders"][""].keys()))
    asserts.equals(env, "a@1.0.0", _target(graph, graph["holders"][""]["a"]))
    a_entry = graph["entries"][int(graph["holders"][""]["a"][2:])]
    asserts.equals(env, {"b": "b@1.0.0"}, {k: _target(graph, v) for k, v in a_entry["links"].items()})
    return unittest.end(env)

closure_test = unittest.make(_closure_test_impl)

def _optional_test_impl(ctx):
    env = unittest.begin(ctx)
    glibc = _instance("native-glibc", "1.0.0")
    musl = _instance("native-musl", "1.0.0")
    mac = _instance("native-darwin", "1.0.0")
    native = _instance("native", "1.0.0", edges = {"native-darwin": mac.id, "native-glibc": glibc.id, "native-musl": musl.id})
    optional = {
        glibc.id: [[[["linux"], ["x64"], ["glibc"]]]],
        musl.id: [[[["linux"], ["x64"], ["musl"]]]],
        mac.id: [[[["darwin"], ["arm64"], []]]],
    }
    resolution = _resolution([native, glibc, musl, mac], {"": {"native": _link("native", native.id, [native.id], optional)}})
    classes = conformance_graphs(resolution, _TUPLES)

    # Four tuples, four different graphs.
    asserts.equals(env, 4, len(classes))
    asserts.equals(env, ["native-glibc@1.0.0", "native@1.0.0"], _entry_names(_graph_for(classes, _LINUX_GLIBC)))
    asserts.equals(env, ["native-musl@1.0.0", "native@1.0.0"], _entry_names(_graph_for(classes, _LINUX_MUSL)))

    # Linux without the libc constraint carries every libc variant.
    asserts.equals(env, ["native-glibc@1.0.0", "native-musl@1.0.0", "native@1.0.0"], _entry_names(_graph_for(classes, _LINUX_UNCONSTRAINED)))

    # `libc` is null off Linux; a glibc-only package is not carried there.
    asserts.equals(env, ["native-darwin@1.0.0", "native@1.0.0"], _entry_names(_graph_for(classes, _DARWIN)))

    # The edge to an instance not carried on a platform is no link there.
    graph = _graph_for(classes, _DARWIN)
    root = graph["entries"][int(graph["holders"][""]["native"][2:])]
    asserts.equals(env, ["native-darwin"], sorted(root["links"].keys()))
    return unittest.end(env)

optional_test = unittest.make(_optional_test_impl)

def _optional_root_test_impl(ctx):
    env = unittest.begin(ctx)
    mac = _instance("native-darwin", "1.0.0")
    b = _instance("b", "1.0.0")
    links = {"": {
        "b": _link("b", b.id, [b.id]),
        "native-darwin": _link("native-darwin", mac.id, [], {mac.id: [[[["darwin"], ["arm64"], []]]]}),
    }}
    classes = conformance_graphs(_resolution([b, mac], links), _TUPLES)
    asserts.equals(env, 2, len(classes))

    # A platform-restricted root is absent, and instances reached from no holder are no entries.
    graph = _graph_for(classes, _LINUX_GLIBC)
    asserts.equals(env, ["b"], sorted(graph["holders"][""].keys()))
    asserts.equals(env, ["b@1.0.0"], _entry_names(graph))
    asserts.equals(env, ["b", "native-darwin"], sorted(_graph_for(classes, _DARWIN)["holders"][""].keys()))

    # Equal graphs are one class: every Linux tuple.
    linux = [cls for cls in classes if ["linux", "x64", "glibc"] in cls["platforms"]][0]
    asserts.equals(env, 3, len(linux["platforms"]))
    return unittest.end(env)

optional_root_test = unittest.make(_optional_root_test_impl)

def _members_test_impl(ctx):
    env = unittest.begin(ctx)
    b = _instance("b", "1.0.0")
    links = {"": {}, "packages/app": {"b": _link("b", b.id, [b.id])}, "packages/lib": {}}
    members = {"": {}, "packages/app": {"lib": "packages/lib"}, "packages/lib": {}}
    graph = conformance_graphs(_resolution([b], links, members), [_LINUX_GLIBC])[0]["graph"]

    # Every workspace is a holder; a workspace dependency is a `w:<path>` target.
    asserts.equals(env, ["", "packages/app", "packages/lib"], sorted(graph["holders"].keys()))
    asserts.equals(env, "w:packages/lib", graph["holders"]["packages/app"]["lib"])
    asserts.equals(env, "b@1.0.0", _target(graph, graph["holders"]["packages/app"]["b"]))
    return unittest.end(env)

members_test = unittest.make(_members_test_impl)

def _error_test_impl(ctx):
    env = unittest.begin(ctx)
    result = conformance_graphs(struct(value = None, error = "bun.lock: broken"), _TUPLES)
    asserts.equals(env, {"error": "bun.lock: broken"}, result)
    return unittest.end(env)

error_test = unittest.make(_error_test_impl)

def _unfetched_test_impl(ctx):
    env = unittest.begin(ctx)
    local = _instance("local", "1.0.0", status = "it is a file: dependency, which rules_bun does not fetch")
    resolution = _resolution([local], {"": {"local": _link("local", local.id, [local.id])}})
    graph = conformance_graphs(resolution, [_LINUX_GLIBC])[0]["graph"]

    # An unfetched instance is still an entry: Bun installs it.
    asserts.equals(env, ["local@1.0.0"], _entry_names(graph))
    return unittest.end(env)

unfetched_test = unittest.make(_unfetched_test_impl)

def graph_test_suite(name):
    unittest.suite(
        name,
        closure_test,
        optional_test,
        optional_root_test,
        members_test,
        error_test,
        unfetched_test,
    )
