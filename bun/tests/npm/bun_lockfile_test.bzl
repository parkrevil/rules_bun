"""Unit tests for the loader of `//bun/private:bun_lockfile.bzl` (research Part 2 S1-S3, S5).

The loader is tested on lockfiles the pinned Bun wrote (`@npm_fixture_results`) and on inline texts
for the forms Bun writes no fixture for. Which package a dependency binds to is what the tests
assert; the conformance test checks the same against the pinned Bun itself.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun/private:bun_lockfile.bzl", "INVALID", "load_lockfile", "lockfile_clean", "lockfile_resolve", "shared_version")
load("//bun/private:bun_tree.bzl", "hoist")
load("//bun/private:lockfile.bzl", "read_lockfile")

def _load_text(text, file = "inline/bun.lock"):
    read = read_lockfile(text, file)
    if read.error:
        return read
    return load_lockfile(read.value, file)

def _load(env, project):
    result = _load_text(RESULTS[project]["text"], "bun/tests/npm/fixtures/{}/bun.lock".format(project))
    asserts.equals(env, None, result.error, project)
    return result.value

def _describe(lockfile, pkg_id):
    if pkg_id == INVALID:
        return None
    package = lockfile.packages[pkg_id]
    if package.resolution.tag == 72:
        return "workspace:" + package.resolution.value
    if package.resolution.tag == 2:
        v = package.resolution.value
        return "{}@{}.{}.{}{}".format(package.name, v.major, v.minor, v.patch, "-" + v.pre if v.pre else "")
    return "{}@{}".format(package.name, package.resolution.value)

def _dependency_ids(lockfile, pkg_id):
    slice = lockfile.packages[pkg_id].dependencies
    return range(slice.off, slice.off + slice.len)

def _bound(lockfile, key, name):
    """What the dependency `name` of the package at `key` (`""`: the root) binds to.

    The root's own dependency is meant, not the workspace dependency each member adds to it.
    """
    pkg_id = 0 if key == "" else lockfile.pkg_map[key]
    for dep_id in _dependency_ids(lockfile, pkg_id):
        dependency = lockfile.dependencies[dep_id]
        if dependency.name == name and not dependency.behavior & 32:
            return _describe(lockfile, lockfile.resolutions[dep_id])
    fail("{} has no dependency {}".format(key, name))

def _workspace_bound(lockfile, path, name):
    for pkg_id in range(len(lockfile.packages)):
        resolution = lockfile.packages[pkg_id].resolution
        if resolution.tag == 72 and resolution.value == path:
            for dep_id in _dependency_ids(lockfile, pkg_id):
                if lockfile.dependencies[dep_id].name == name:
                    return _describe(lockfile, lockfile.resolutions[dep_id])
    fail("{} has no dependency {}".format(path, name))

def _dedupe_test_impl(ctx):
    env = unittest.begin(ctx)

    # One package per `name@resolution` (`append_package_dedupe`, LOCKFILE L2685-L2711): the rows
    # `y/x` and `z/x` of `dependency_conflict` are one package `x@1.0.0`.
    lockfile = _load(env, "dependency_conflict")
    asserts.equals(env, lockfile.pkg_map["y/x"], lockfile.pkg_map["z/x"])
    asserts.equals(env, 8, len(lockfile.packages), "the root and seven packages")
    return unittest.end(env)

def _row_evidence_test_impl(ctx):
    env = unittest.begin(ctx)

    # Research E2: the `z/x` row's walk to the root (`WalkedToRoot`) outranks the `y/x` row's walk
    # to `y/b` (`Walked`), so `x@1.0.0` binds `b` to `b@1.0.0` (LOCK L2963-L2997).
    lockfile = _load(env, "dependency_conflict")
    asserts.equals(env, "b@1.0.0", _bound(lockfile, "y/x", "b"))
    asserts.equals(env, "b@2.0.0", _bound(lockfile, "y", "b"))
    asserts.equals(env, "x@1.0.0", _bound(lockfile, "y", "x"))
    asserts.equals(env, "x@2.0.0", _bound(lockfile, "", "x"))
    return unittest.end(env)

def _workspaces_test_impl(ctx):
    env = unittest.begin(ctx)

    # The workspaces follow the root under their names (LOCK L2263-L2305); a root alias of a
    # workspace's name takes the key, and the workspace's dependencies are bound by `./<name>/`
    # keys (LOCK L2859-L2921, research E6).
    lockfile = _load(env, "conformance_alias_workspace")
    asserts.equals(env, 72, lockfile.packages[1].resolution.tag)
    asserts.equals(env, "a@1.0.0", _bound(lockfile, "", "lib"))
    asserts.equals(env, "c@1.0.0", _bound(lockfile, "", "@scope/lib"))
    asserts.equals(env, "b@2.0.0", _workspace_bound(lockfile, "packages/lib", "b"))
    asserts.equals(env, "b@2.0.0", _workspace_bound(lockfile, "packages/scoped", "b"))

    # A registry package's dependency on a workspace member binds to the member (BC-4).
    members = _load(env, "conformance_registry_to_workspace")
    asserts.equals(env, "workspace:packages/member-lib", _bound(members, "member-user", "member-lib"))
    return unittest.end(env)

def _unresolved_test_impl(ctx):
    env = unittest.begin(ctx)

    # `unresolved` resets a binding the walk found (LOCK L3027-L3031, BC-1).
    lockfile = _load(env, "conformance_unresolved")
    asserts.equals(env, None, _bound(lockfile, "", "b"))
    asserts.equals(env, None, _bound(lockfile, "opt-user", "state"))
    asserts.equals(env, None, _workspace_bound(lockfile, "packages/w", "q"))
    asserts.equals(env, "a@1.0.0", _workspace_bound(lockfile, "packages/w", "a"))

    # A name under `unresolved` that is no optional dependency changes no binding (LOCK L3531-L3537).
    other = _load_text(
        '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "dependencies": {"a": "1.0.0"}}}, "packages": {' +
        '"a": ["a@1.0.0", "", {"dependencies": {"b": "1.0.0"}, "unresolved": ["b"]}, "sha512-x"], ' +
        '"b": ["b@1.0.0", "", {}, "sha512-y"]}}',
    )
    asserts.equals(env, None, other.error)
    asserts.equals(env, "b@1.0.0", _bound(other.value, "a", "b"))
    return unittest.end(env)

def _unbound_test_impl(ctx):
    env = unittest.begin(ctx)

    # An optional or peer dependency without a key stays unresolved (`may_stay_unresolved`, LOCK
    # L3298, BC-3); a workspace's too.
    lockfile = _load(env, "conformance_unbound")
    asserts.equals(env, None, _bound(lockfile, "", "state"))
    asserts.equals(env, None, _bound(lockfile, "", "r"))
    asserts.equals(env, None, _workspace_bound(lockfile, "packages/w", "x"))
    asserts.equals(env, None, _workspace_bound(lockfile, "packages/w", "q"))

    # Any other fails loading (`dependency_resolution_failure`, LOCK L3302-L3345).
    root = _load_text('{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "dependencies": {"zz": "1.0.0"}}}, "packages": {}}')
    asserts.equals(env, None, root.value)
    asserts.true(env, "inline/bun.lock" in root.error and "Failed to resolve root prod dependency 'zz'" in root.error, root.error)
    row = _load_text(
        '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "dependencies": {"a": "1.0.0"}}}, "packages": {' +
        '"a": ["a@1.0.0", "", {"dependencies": {"zz": "1.0.0"}}, "sha512-x"]}}',
    )
    asserts.true(env, "Failed to resolve prod dependency 'zz' for package 'a'" in row.error, row.error)
    return unittest.end(env)

def _duplicate_path_test_impl(ctx):
    env = unittest.begin(ctx)

    # A `packages` key equal to a workspace's name holding a `file:` folder: Bun refuses the
    # lockfile ("Duplicate package path", LOCK L2748-L2760, FR-004).
    result = _load_text(
        '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "dependencies": {"lib": "file:vendor/lib"}}, ' +
        '"packages/lib": {"name": "lib"}}, "packages": {"lib": ["lib@file:vendor/lib", {}]}}',
    )
    asserts.equals(env, None, result.value)
    asserts.true(env, "inline/bun.lock" in result.error and "Duplicate package path" in result.error and "\"lib\"" in result.error, result.error)
    return unittest.end(env)

def _unlinked_key_test_impl(ctx):
    env = unittest.begin(ctx)

    # A `./<name>/` key of a linked workspace is loaded and never bound: the workspace's own
    # dependencies are bound by `<name>/<dep>`, then `<dep>` (LOCK L2864-L2900).
    result = _load_text(
        '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "packages/w": {"name": "w", "dependencies": {"b": "^1.0.0"}}}, ' +
        '"packages": {"b": ["b@1.0.0", "", {}, "sha512-x"], "./w/b": ["b@2.0.0", "", {}, "sha512-y"], "w": ["w@workspace:packages/w"]}}',
    )
    asserts.equals(env, None, result.error)
    asserts.true(env, "./w/b" in result.value.pkg_map)
    asserts.equals(env, "b@1.0.0", _workspace_bound(result.value, "packages/w", "b"))
    return unittest.end(env)

def _version_peers_test_impl(ctx):
    env = unittest.begin(ctx)

    # A registry package's peer binds to the highest version in range (S3, LOCK L3067-L3089).
    lockfile = _load(env, "conformance_shared_peer")
    asserts.equals(env, "state@1.0.0", _bound(lockfile, "ident-a", "state"))
    asserts.equals(env, "state@2.0.0", _bound(lockfile, "state-peer-any", "state"))

    # No package provides `state` to them, so they share the highest version every unprovided range
    # accepts (`PeerRanges::shared_version`, S5, LOCK L3106-L3133).
    cache = {}
    for key in ["ident-a", "state-peer-any"]:
        owner = lockfile.pkg_map[key]
        peer = [d for d in _dependency_ids(lockfile, owner) if lockfile.dependencies[d].name == "state"][0]
        asserts.equals(env, "state@1.0.0", _describe(lockfile, shared_version(lockfile, cache, owner, peer)), key)
    return unittest.end(env)

def _clean_test_impl(ctx):
    env = unittest.begin(ctx)

    # `clean_with_logger` (LOCKFILE L1236-L1436) copies the packages the root reaches, in the order
    # `Package::clone` and `Cloner::flush` visit them, and hoists again: `orphan` is dropped, and
    # every binding of the reached packages is kept.
    loaded = _load_text(
        '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "dependencies": {"a": "1.0.0"}}}, "packages": {' +
        '"a": ["a@1.0.0", "", {"dependencies": {"b": "1.0.0"}}, "sha512-a"], "b": ["b@1.0.0", "", {}, "sha512-b"], ' +
        '"orphan": ["orphan@1.0.0", "", {}, "sha512-c"]}}',
    ).value
    asserts.equals(env, None, lockfile_resolve(loaded, hoist))
    cleaned = lockfile_clean(loaded, hoist)
    asserts.equals(env, None, cleaned.error)
    asserts.equals(env, ["a", "b", "x"], sorted([p.name for p in cleaned.value.packages]))
    asserts.equals(env, "b@1.0.0", _bound(cleaned.value, "a", "b"))

    conflict = _load(env, "dependency_conflict")
    asserts.equals(env, None, lockfile_resolve(conflict, hoist))
    cleaned = lockfile_clean(conflict, hoist).value
    asserts.equals(env, "b@1.0.0", _bound(cleaned, "y/x", "b"))
    asserts.equals(env, "b@2.0.0", _bound(cleaned, "y", "b"))
    return unittest.end(env)

dedupe_test = unittest.make(_dedupe_test_impl)
row_evidence_test = unittest.make(_row_evidence_test_impl)
workspaces_test = unittest.make(_workspaces_test_impl)
unresolved_test = unittest.make(_unresolved_test_impl)
unbound_test = unittest.make(_unbound_test_impl)
duplicate_path_test = unittest.make(_duplicate_path_test_impl)
unlinked_key_test = unittest.make(_unlinked_key_test_impl)
version_peers_test = unittest.make(_version_peers_test_impl)
clean_test = unittest.make(_clean_test_impl)

def bun_lockfile_test_suite(name):
    unittest.suite(
        name,
        dedupe_test,
        row_evidence_test,
        workspaces_test,
        unresolved_test,
        unbound_test,
        duplicate_path_test,
        unlinked_key_test,
        version_peers_test,
        clean_test,
    )
