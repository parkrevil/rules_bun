"""Unit tests for `//bun/private:resolve.bzl` (research R2, data-model "Resolution model")."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun/private:lockfile.bzl", "read_lockfile")
load("//bun/private:platforms.bzl", "platform_tuples")
load("//bun/private:resolve.bzl", "resolve")

def _plain(value):
    return json.decode(json.encode(value))

def _resolution(env, project):
    result = RESULTS[project]["resolution"]
    asserts.equals(env, None, result["error"])
    return result["value"]

def _resolve_inline(env, packages, dependencies, hash_fn = hash):
    text = json.encode({
        "lockfileVersion": 2,
        "workspaces": {"": {"name": "inline", "dependencies": dependencies}},
        "packages": packages,
    })
    lock = read_lockfile(text, "inline/bun.lock")
    asserts.equals(env, None, lock.error)
    result = _plain(resolve(lock.value, hash_fn = hash_fn))
    asserts.equals(env, None, result["error"])
    return result["value"]

def _npm(spec, dependencies = {}, peers = {}, optional_peers = []):
    info = {}
    if dependencies:
        info["dependencies"] = dependencies
    if peers:
        info["peerDependencies"] = peers
    if optional_peers:
        info["optionalPeers"] = optional_peers
    return [spec, "", info, "sha512-AAAA"]

def _nv(resolution, instance_id):
    instance = resolution["instances"][instance_id]
    return "{}@{}".format(instance["name"], instance["version"])

def _closure_nvs(resolution, link):
    return sorted([_nv(resolution, i) for i in link["closure"]])

def _basic_links_test_impl(ctx):
    env = unittest.begin(ctx)
    resolution = _resolution(env, "basic")
    root = resolution["links"][""]
    a = root["a"]
    asserts.equals(env, "a", a["alias"])
    asserts.equals(env, "a@1.0.0", _nv(resolution, a["root"]))
    asserts.equals(env, ["a@1.0.0", "b@1.0.0"], _closure_nvs(resolution, a))
    asserts.equals(env, ["b@2.0.0", "c@1.0.0"], _closure_nvs(resolution, root["c"]))
    asserts.equals(env, ["b@1.0.0", "b@2.0.0", "x@1.0.0", "y@1.0.0"], _closure_nvs(resolution, root["y"]))
    return unittest.end(env)

def _workspace_test_impl(ctx):
    env = unittest.begin(ctx)
    resolution = _resolution(env, "workspace")
    asserts.equals(env, "q@2.0.0", _nv(resolution, resolution["links"]["packages/w1"]["q"]["root"]))
    asserts.equals(env, "q@1.0.0", _nv(resolution, resolution["links"][""]["q"]["root"]))
    aliased = resolution["links"][""]["aliased"]
    asserts.equals(env, "aliased", aliased["alias"])
    asserts.equals(env, "b@2.0.0", _nv(resolution, aliased["root"]))
    return unittest.end(env)

def _alias_edge_test_impl(ctx):
    env = unittest.begin(ctx)
    resolution = _resolve_inline(
        env,
        {"user": _npm("user@1.0.0", {"other": "npm:b@2.0.0"}), "other": _npm("b@2.0.0")},
        {"user": "1.0.0"},
    )
    user = resolution["instances"][resolution["links"][""]["user"]["root"]]
    asserts.equals(env, ["other"], user["edges"].keys())
    asserts.equals(env, "b@2.0.0", _nv(resolution, user["edges"]["other"]))
    return unittest.end(env)

def _cycle_test_impl(ctx):
    env = unittest.begin(ctx)
    resolution = _resolution(env, "basic")
    link = resolution["links"][""]["cyc-a"]
    a = resolution["instances"][link["root"]]
    b_id = a["edges"]["cyc-b"]
    asserts.equals(env, link["root"], resolution["instances"][b_id]["edges"]["cyc-a"])
    asserts.equals(env, ["cyc-a@1.0.0", "cyc-b@1.0.0"], _closure_nvs(resolution, link))
    return unittest.end(env)

def _distinct_test_impl(ctx):
    env = unittest.begin(ctx)

    # One package per `name@version` (BC-6, feature 006): `y/x` and `z/x` are one `x@1.0.0`, whose
    # `b` the loader binds once, by row evidence (research E2).
    resolution = _resolution(env, "basic")
    instances = resolution["instances"]
    y_x = instances[resolution["links"][""]["y"]["root"]]["edges"]["x"]
    z_x = instances[resolution["links"][""]["z"]["root"]]["edges"]["x"]
    asserts.equals(env, "x@1.0.0", _nv(resolution, y_x))
    asserts.equals(env, y_x, z_x)
    asserts.equals(env, "b@1.0.0", _nv(resolution, instances[y_x]["edges"]["b"]))
    return unittest.end(env)

def _ids_test_impl(ctx):
    env = unittest.begin(ctx)
    resolution = _resolution(env, "basic")
    for instance_id, instance in resolution["instances"].items():
        prefix = "{}@{}__".format(instance["name"], instance["version"])
        asserts.true(env, instance_id.startswith(prefix), instance_id)
        asserts.true(env, instance_id[len(prefix):].isdigit(), instance_id)
        asserts.equals(env, instance_id, instance["id"])

    def constant(_text):
        return 7

    # Two instances of one `name@version` differ by their peers; when their hashes collide, the
    # sorted peer bindings number them (`p` with `q@1.0.0`, then `p` with `q@2.0.0`).
    file = "bun/tests/npm/fixtures/basic/bun.lock"
    lock = read_lockfile(RESULTS["basic"]["text"], file)
    resolution = _plain(resolve(lock.value, file, hash_fn = constant))["value"]
    root = resolution["links"][""]
    asserts.equals(env, "p@1.0.0__7__0", root["p"]["root"])
    asserts.equals(env, "p@1.0.0__7__1", resolution["instances"][root["q2-user"]["root"]]["edges"]["p"])

    # Colliding hashes still give the two entries two store directories (BC-11).
    asserts.equals(env, "0000000000000007", resolution["instances"]["p@1.0.0__7__0"].get("peer_hash"))
    asserts.equals(env, "0000000100000007", resolution["instances"]["p@1.0.0__7__1"].get("peer_hash"))
    return unittest.end(env)

def _store_name_test_impl(ctx):
    env = unittest.begin(ctx)
    resolution = _resolution(env, "basic")
    s = resolution["instances"][resolution["links"][""]["@scope/s"]["root"]]
    asserts.equals(env, "@scope+s@1.0.0", s["store_name"])
    a = resolution["instances"][resolution["links"][""]["a"]["root"]]
    asserts.equals(env, "a@1.0.0", a["store_name"])

    # An entry without peers has no peer hash, as Bun's `PeerHash::NONE` (Store.rs L464).
    asserts.equals(env, "", a.get("peer_hash"))

    # p with q@1.0.0 and p through q2-user with q@2.0.0: two store entries of p@1.0.0, each named
    # `<name>@<version>+<peer hash>` as Bun's isolated store names them (Store.rs L450-L466; BC-11).
    root = resolution["links"][""]
    p_q1 = resolution["instances"][root["p"]["root"]]
    p_q2 = resolution["instances"][resolution["instances"][root["q2-user"]["root"]]["edges"]["p"]]
    for p in [p_q1, p_q2]:
        asserts.equals(env, "p@1.0.0", p["store_name"])
        peer_hash = p.get("peer_hash") or ""
        asserts.equals(env, 16, len(peer_hash), peer_hash)
        asserts.equals(env, "", peer_hash.lstrip("0123456789abcdef"), peer_hash)
    asserts.true(env, p_q1.get("peer_hash") != p_q2.get("peer_hash"), "two peer bindings, two peer hashes")
    return unittest.end(env)

def _provided_peer_test_impl(ctx):
    env = unittest.begin(ctx)
    resolution = _resolution(env, "jsx")
    root = resolution["links"][""]
    react_dom = resolution["instances"][root["react-dom"]["root"]]
    asserts.equals(env, root["react"]["root"], react_dom["edges"]["react"])
    asserts.equals(env, ["react-dom@19.2.0", "react@19.2.0", "scheduler@0.27.0"], _closure_nvs(resolution, root["react-dom"]))
    return unittest.end(env)

def _peer_of(resolution, path, chain, peer):
    """The instance the peer `peer` of the last package of `chain` resolves to, or `None`."""
    instance = resolution["instances"][resolution["links"][path][chain[0]]["root"]]
    for alias in chain[1:]:
        instance = resolution["instances"][instance["edges"][alias]]
    target = instance["edges"].get(peer)
    return _nv(resolution, target) if target else None

def _workspace_peer_test_impl(ctx):
    env = unittest.begin(ctx)

    # p-user provides no q, so p's q resolves in the workspace p-user is reached from, not by
    # the walk from p's own key `p` (which finds the root's q@1.0.0).
    asserts.equals(env, "q@1.0.0", _peer_of(_resolution(env, "basic"), "", ["p-user", "p"], "q"))
    workspace = _resolution(env, "workspace")
    asserts.equals(env, "q@2.0.0", _peer_of(workspace, "packages/w1", ["p-user", "p"], "q"))
    asserts.equals(env, "q@2.0.0", _peer_of(workspace, "packages/w1", ["p"], "q"))
    return unittest.end(env)

def _optional_peer_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, None, _peer_of(_resolution(env, "basic"), "", ["p-user", "p"], "r"))
    asserts.equals(env, None, _peer_of(_resolution(env, "basic"), "", ["p"], "r"))
    resolution = _resolve_inline(
        env,
        {"needs": _npm("needs@1.0.0", peers = {"gone": "1.0.0"}, optional_peers = ["gone"])},
        {"needs": "1.0.0"},
    )
    needs = resolution["instances"][resolution["links"][""]["needs"]["root"]]
    asserts.equals(env, "ok", needs["status"])
    asserts.equals(env, {}, needs["edges"])
    return unittest.end(env)

def _missing_peer_test_impl(ctx):
    env = unittest.begin(ctx)

    # A peer nothing provides and the lockfile does not resolve is not linked, and the package is
    # usable (BC-5, feature 006), as the pinned Bun installs it.
    resolution = _resolve_inline(
        env,
        {
            "needs": _npm("needs@1.0.0", peers = {"gone": "1.0.0"}),
            "user": _npm("user@1.0.0", {"needs": "1.0.0"}),
        },
        {"user": "1.0.0"},
    )
    user = resolution["instances"][resolution["links"][""]["user"]["root"]]
    asserts.equals(env, "ok", user["status"])
    needs = resolution["instances"][user["edges"]["needs"]]
    asserts.equals(env, "ok", needs["status"])
    asserts.equals(env, "needs", needs["name"])
    asserts.equals(env, {}, needs["edges"])
    return unittest.end(env)

def _peer_cycle_test_impl(ctx):
    env = unittest.begin(ctx)
    resolution = _resolve_inline(
        env,
        {
            "holder": _npm("holder@1.0.0", {"pc-a": "1.0.0"}),
            "pc-a": _npm("pc-a@1.0.0", peers = {"pc-b": "1.0.0"}),
            "pc-b": _npm("pc-b@1.0.0", peers = {"pc-a": "1.0.0"}),
        },
        {"pc-a": "1.0.0", "pc-b": "1.0.0", "holder": "1.0.0"},
    )
    root = resolution["links"][""]
    instances = resolution["instances"]
    a = instances[root["pc-a"]["root"]]
    b = instances[root["pc-b"]["root"]]
    asserts.equals(env, root["pc-b"]["root"], a["edges"]["pc-b"])
    asserts.equals(env, root["pc-a"]["root"], b["edges"]["pc-a"])

    # Reached through holder, which provides neither, pc-a's peer resolves in the workspace.
    held = instances[instances[root["holder"]["root"]]["edges"]["pc-a"]]
    asserts.equals(env, "pc-b@1.0.0", _nv(resolution, held["edges"]["pc-b"]))
    return unittest.end(env)

def _peer_instances_test_impl(ctx):
    env = unittest.begin(ctx)
    resolution = _resolution(env, "basic")
    root = resolution["links"][""]
    p_root = root["p"]["root"]
    p_q2 = resolution["instances"][root["q2-user"]["root"]]["edges"]["p"]
    asserts.equals(env, "q@1.0.0", _nv(resolution, resolution["instances"][p_root]["edges"]["q"]))
    asserts.equals(env, "q@2.0.0", _nv(resolution, resolution["instances"][p_q2]["edges"]["q"]))
    asserts.true(env, p_root != p_q2, "p with q@1.0.0 and p with q@2.0.0 are distinct instances")
    return unittest.end(env)

def _unfetched_test_impl(ctx):
    env = unittest.begin(ctx)

    # An entry rules_bun does not fetch is marked so, the status ID-4 (feature 006) lets fail
    # analysis; any other instance is not.
    resolution = _resolution(env, "unsupported")
    for instance in resolution["instances"].values():
        asserts.equals(env, instance["status"] != "ok", instance.get("unfetched"), instance["id"])
    asserts.true(env, any([i.get("unfetched") for i in resolution["instances"].values()]))
    return unittest.end(env)

def _roots_by_peer(resolution, link, chain):
    """The platforms of each root of a per-platform link, by the version its chain's peer `q` binds."""
    by_q = {}
    for root_id, platforms in link["roots"].items():
        instance = resolution["instances"][root_id]
        for alias in chain:
            instance = resolution["instances"][instance["edges"][alias]]
        by_q[_nv(resolution, instance["edges"]["q"])] = platforms
    return by_q

def _platform_holder_test_impl(ctx):
    env = unittest.begin(ctx)
    tuples = len(platform_tuples())

    # The root's plat-peer-host: its p binds the peer q to plat-peer-host's own q (q-darwin@1.0.0)
    # on darwin; elsewhere q-darwin is disabled, so p's q leaks to plat-peer-host and binds the
    # root's q@1.0.0. Two store entries of plat-peer-host@1.0.0, one root per platform (BC-12).
    resolution = _resolution(env, "conformance_platform_peer")
    link = resolution["links"][""]["plat-peer-host"]
    asserts.equals(env, None, link["root"])
    by_q = _roots_by_peer(resolution, link, ["p"])
    asserts.equals(env, ["q-darwin@1.0.0", "q@1.0.0"], sorted(by_q.keys()))
    asserts.true(env, ["darwin", "arm64", None] in by_q["q-darwin@1.0.0"], by_q)
    asserts.equals(env, [], [t for t in by_q["q-darwin@1.0.0"] if t[0] != "darwin"])
    asserts.true(env, ["linux", "x64", None] in by_q["q@1.0.0"], by_q)
    asserts.equals(env, tuples, len(by_q["q-darwin@1.0.0"]) + len(by_q["q@1.0.0"]))

    # The same through the workspace w, whose own q is q-darwin@1.0.0: its "p" (T077).
    resolution = _resolution(env, "conformance_platform_peer_workspace")
    link = resolution["links"]["packages/w"]["p"]
    asserts.equals(env, None, link["root"])
    by_q = _roots_by_peer(resolution, link, [])
    asserts.equals(env, ["q-darwin@1.0.0", "q@1.0.0"], sorted(by_q.keys()))
    asserts.equals(env, [], [t for t in by_q["q-darwin@1.0.0"] if t[0] != "darwin"])
    asserts.equals(env, tuples, len(by_q["q-darwin@1.0.0"]) + len(by_q["q@1.0.0"]))

    # A link whose root is one store entry on every platform has no per-platform roots.
    asserts.equals(env, {}, resolution["links"][""]["q"]["roots"])
    return unittest.end(env)

def _platform_entry_error_test_impl(ctx):
    env = unittest.begin(ctx)

    # host@1.0.0's p binds its optional peer r to host's r-darwin@1.0.0 on darwin; elsewhere that
    # dependency is disabled and no row resolves the peer, so p links no r, while host's own entry
    # (no peers) is one entry on every platform (T077). The pinned Bun hoists such an r to the root,
    # so it writes no such lockfile; this one is written by hand.
    text = json.encode({
        "lockfileVersion": 2,
        "workspaces": {"": {"name": "inline", "dependencies": {"host": "1.0.0"}}},
        "packages": {
            "host": ["host@1.0.0", "", {"dependencies": {"p": "1.0.0"}, "optionalDependencies": {"r": "npm:r-darwin@1.0.0"}}, "sha512-AAAA"],
            "host/r": ["r-darwin@1.0.0", "", {"os": "darwin"}, "sha512-AAAA"],
            "p": ["p@1.0.0", "", {"peerDependencies": {"r": "^1.0.0"}, "optionalPeers": ["r"]}, "sha512-AAAA"],
        },
    })
    lock = read_lockfile(text, "inline/bun.lock")
    asserts.equals(env, None, lock.error)
    result = resolve(lock.value, "inline/bun.lock")
    asserts.true(env, result.error != None and 'the store links "p" of host@1.0.0 to different packages on different platforms' in result.error, result.error)
    return unittest.end(env)

basic_links_test = unittest.make(_basic_links_test_impl)
workspace_test = unittest.make(_workspace_test_impl)
alias_edge_test = unittest.make(_alias_edge_test_impl)
cycle_test = unittest.make(_cycle_test_impl)
distinct_test = unittest.make(_distinct_test_impl)
ids_test = unittest.make(_ids_test_impl)
store_name_test = unittest.make(_store_name_test_impl)
provided_peer_test = unittest.make(_provided_peer_test_impl)
workspace_peer_test = unittest.make(_workspace_peer_test_impl)
optional_peer_test = unittest.make(_optional_peer_test_impl)
missing_peer_test = unittest.make(_missing_peer_test_impl)
peer_cycle_test = unittest.make(_peer_cycle_test_impl)
peer_instances_test = unittest.make(_peer_instances_test_impl)
unfetched_test = unittest.make(_unfetched_test_impl)
platform_holder_test = unittest.make(_platform_holder_test_impl)
platform_entry_error_test = unittest.make(_platform_entry_error_test_impl)

def resolve_test_suite(name):
    unittest.suite(
        name,
        basic_links_test,
        workspace_test,
        alias_edge_test,
        cycle_test,
        distinct_test,
        ids_test,
        store_name_test,
        provided_peer_test,
        workspace_peer_test,
        optional_peer_test,
        missing_peer_test,
        peer_cycle_test,
        peer_instances_test,
        unfetched_test,
        platform_holder_test,
        platform_entry_error_test,
    )
