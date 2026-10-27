"""Unit tests for `//bun/private:resolve.bzl` (research R2, data-model "Resolution model")."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun/private:lockfile.bzl", "read_lockfile")
load("//bun/private:resolve.bzl", "resolve", "walk_key")

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

def _walk_test_impl(ctx):
    env = unittest.begin(ctx)
    basic = RESULTS["basic"]["lockfile"]["value"]["entries"]
    asserts.equals(env, "c/b", walk_key(basic, ["c"], "b"))
    asserts.equals(env, "b", walk_key(basic, ["a"], "b"))
    asserts.equals(env, "y/x/b", walk_key(basic, ["y", "x"], "b"))
    asserts.equals(env, "b", walk_key(basic, ["z", "x"], "b"))
    asserts.equals(env, None, walk_key(basic, ["a"], "missing"))

    # The nearest parent's entry wins over the root's.
    asserts.equals(env, "y/b", walk_key({"b": 1, "y": 1, "y/b": 1, "y/x": 1}, ["y", "x"], "b"))

    # `@s/a/b`'s parent is `@s/a`, never `@s`: splitting the scope would find `@s/c`.
    scoped = {"@s/a": 1, "@s/a/b": 1, "@s/c": 1, "c": 1, "@s/a/@s/d": 1, "@s/d": 1}
    asserts.equals(env, "c", walk_key(scoped, ["@s/a", "b"], "c"))
    asserts.equals(env, "@s/a/@s/d", walk_key(scoped, ["@s/a", "b"], "@s/d"))
    return unittest.end(env)

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
    resolution = _resolution(env, "basic")
    instances = resolution["instances"]
    y_x = instances[resolution["links"][""]["y"]["root"]]["edges"]["x"]
    z_x = instances[resolution["links"][""]["z"]["root"]]["edges"]["x"]
    asserts.equals(env, "x@1.0.0", _nv(resolution, y_x))
    asserts.equals(env, "x@1.0.0", _nv(resolution, z_x))
    asserts.true(env, y_x != z_x, "y/x and z/x resolve b to different keys: " + y_x)
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

    resolution = _resolve_inline(
        env,
        {
            "y": _npm("y@1.0.0", {"x": "1.0.0"}),
            "z": _npm("z@1.0.0", {"x": "1.0.0"}),
            "y/x": _npm("x@1.0.0", {"b": "*"}),
            "z/x": _npm("x@1.0.0", {"b": "*"}),
            "y/b": _npm("b@2.0.0"),
            "z/x/b": _npm("b@2.0.0"),
        },
        {"y": "1.0.0", "z": "1.0.0"},
        hash_fn = constant,
    )
    instances = resolution["instances"]
    root = resolution["links"][""]

    # The edge maps sort as `b` -> `y/b` before `b` -> `z/x/b`.
    asserts.equals(env, "x@1.0.0__7__0", instances[root["y"]["root"]]["edges"]["x"])
    asserts.equals(env, "x@1.0.0__7__1", instances[root["z"]["root"]]["edges"]["x"])
    asserts.equals(env, "b@2.0.0__7", instances["x@1.0.0__7__0"]["edges"]["b"])
    asserts.equals(env, "b@2.0.0__7", instances["x@1.0.0__7__1"]["edges"]["b"])
    return unittest.end(env)

def _store_name_test_impl(ctx):
    env = unittest.begin(ctx)
    resolution = _resolution(env, "basic")
    s = resolution["instances"][resolution["links"][""]["@scope/s"]["root"]]
    asserts.equals(env, "@scope+s@1.0.0", s["store_name"])
    a = resolution["instances"][resolution["links"][""]["a"]["root"]]
    asserts.equals(env, "a@1.0.0", a["store_name"])
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
    asserts.true(env, needs["status"] != "ok", "a missing non-optional peer makes the instance unusable")
    asserts.equals(env, "needs", needs["name"])
    asserts.true(env, '"gone"' in needs["status"], needs["status"])
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

walk_test = unittest.make(_walk_test_impl)
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

def resolve_test_suite(name):
    unittest.suite(
        name,
        walk_test,
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
    )
