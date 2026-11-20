"""Unit tests for `//bun/private:bun_tree.bzl` (research Part 2 S4, S7).

Bun prints the `packages` keys of `bun.lock` from the hoisted trees (each key is a tree's path and a
row's name), so hoisting a lockfile the pinned Bun wrote must give back exactly its keys.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun/private:bun_install_types.bzl", "BEHAVIOR", "LIBC_ALL", "platform_value")
load("//bun/private:bun_lockfile.bzl", "INVALID", "dependency_ids", "load_lockfile", "lockfile_resolve")
load("//bun/private:bun_tree.bzl", "bind_served_peers", "hoist", "is_filtered_dependency_or_workspace", "is_unlinked_member")
load("//bun/private:lockfile.bzl", "read_lockfile")

def _resolved(env, text, file = "inline/bun.lock"):
    read = read_lockfile(text, file)
    asserts.equals(env, None, read.error)
    loaded = load_lockfile(read.value, file)
    asserts.equals(env, None, loaded.error)
    asserts.equals(env, None, lockfile_resolve(loaded.value, hoist))
    return loaded.value

def _fixture(env, project):
    return _resolved(env, RESULTS[project]["text"], "bun/tests/npm/fixtures/{}/bun.lock".format(project))

def _tree_paths(lockfile):
    """`<tree path>/<name>` of every hoisted row, as the `bun.lock` writer prints the keys."""
    trees = lockfile.trees
    paths = []
    for tree in trees:
        names = []
        current = tree
        unlinked = False
        for _ in range(len(trees)):
            if current.parent == INVALID:
                break
            names.insert(0, lockfile.dependencies[current.dependency_id].name)

            # The writer prints everything below an unlinked workspace under `./<name>`.
            unlinked = is_unlinked_member(lockfile, current)
            current = trees[current.parent]
        prefix = "/".join(names)
        if unlinked:
            prefix = "./" + prefix
        for i in range(tree.dependencies.off, tree.dependencies.off + tree.dependencies.len):
            dep_id = lockfile.hoisted_dependencies[i]
            paths.append((prefix + "/" if prefix else "") + lockfile.dependencies[dep_id].name)
    return sorted(paths)

def _keys(project):
    """The `packages` keys of a fixture."""
    return sorted(read_lockfile(RESULTS[project]["text"], project).value.keys)

def _keys_test_impl(ctx):
    env = unittest.begin(ctx)

    # process_subtree / hoist_dependency (TREE L1412-L2051) give back the keys Bun wrote. Not for
    # `dependency_conflict`: there the loader binds `x@1.0.0`'s `b` by row evidence to another
    # package than the install that wrote the keys did (research E2), so its trees differ.
    for project in ["basic", "hoisted", "workspace", "conformance_nested", "conformance_peer_contexts", "conformance_bundled", "conformance_alias_workspace", "missing_peer"]:
        asserts.equals(env, _keys(project), _tree_paths(_fixture(env, project)), project)
    return unittest.end(env)

def _served_peers_test_impl(ctx):
    env = unittest.begin(ctx)

    # `bind_served_peers` (TREE L814-L834): each served peer gets the package recorded with it,
    # unless the peer itself is a row of some tree.
    dependencies = [
        struct(name = "q", behavior = BEHAVIOR.PEER),
        struct(name = "r", behavior = BEHAVIOR.PEER),
        struct(name = "s", behavior = BEHAVIOR.PROD),
    ]
    resolutions = [7, 8, 9]
    bind_served_peers([(0, 1), (1, 2), (2, 3)], [[1], [2]], dependencies, resolutions)
    asserts.equals(env, [1, 8, 3], resolutions)
    return unittest.end(env)

def _filter_test_impl(ctx):
    env = unittest.begin(ctx)
    lockfile = _fixture(env, "conformance_platform")
    linux = struct(cpu = platform_value("cpu", "x64"), os = platform_value("os", "linux"), libc = platform_value("libc", "glibc"))
    aix = struct(cpu = platform_value("cpu", "ppc64"), os = platform_value("os", "aix"), libc = LIBC_ALL)

    def filtered(name, platform):
        for dep_id in dependency_ids(lockfile, 0):
            dep = lockfile.dependencies[dep_id]
            if dep.name == name and not dep.behavior & BEHAVIOR.WORKSPACE:
                return is_filtered_dependency_or_workspace(lockfile, dep_id, 0, platform)
        fail("no dependency " + name)

    # A disabled package is skipped whether or not the dependency is optional (TREE L1336-L1358,
    # BC-7); on its own platform it is linked.
    asserts.true(env, filtered("nomatch-aix-ppc64", linux))
    asserts.false(env, filtered("nomatch-aix-ppc64", aix))

    # An unresolved dependency is skipped unless it is an optional peer (TREE L1323-L1327).
    unbound = _fixture(env, "conformance_unbound")
    for dep_id in dependency_ids(unbound, 0):
        dep = unbound.dependencies[dep_id]
        if dep.name == "state":
            asserts.true(env, is_filtered_dependency_or_workspace(unbound, dep_id, 0, linux), "an unresolved optional dependency")

    # A registry package's dev dependency is not placed (TREE L1360-L1362, `is_placed`).
    dev = _resolved(
        env,
        '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "dependencies": {"a": "1.0.0"}}}, "packages": {' +
        '"a": ["a@1.0.0", "", {"devDependencies": {"b": "1.0.0"}}, "sha512-a"], "b": ["b@1.0.0", "", {}, "sha512-b"]}}',
    )
    a = dev.pkg_map["a"]
    asserts.true(env, is_filtered_dependency_or_workspace(dev, dependency_ids(dev, a)[0], a, linux))
    return unittest.end(env)

def _unlinked_member_test_impl(ctx):
    env = unittest.begin(ctx)

    # A workspace whose name a root dependency took has no row in the root tree (TREE L95-L112).
    lockfile = _fixture(env, "conformance_alias_workspace")
    unlinked = [t for t in lockfile.trees if is_unlinked_member(lockfile, t)]
    asserts.equals(env, ["@scope/lib", "lib"], sorted([lockfile.dependencies[t.dependency_id].name for t in unlinked]))
    return unittest.end(env)

keys_test = unittest.make(_keys_test_impl)
served_peers_test = unittest.make(_served_peers_test_impl)
filter_test = unittest.make(_filter_test_impl)
unlinked_member_test = unittest.make(_unlinked_member_test_impl)

def bun_tree_test_suite(name):
    unittest.suite(
        name,
        keys_test,
        served_peers_test,
        filter_test,
        unlinked_member_test,
    )
