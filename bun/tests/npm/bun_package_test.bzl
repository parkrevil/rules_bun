"""Unit tests for `//bun/private:bun_package.bzl` (feature 006 T182).

Each case is what the pinned Bun 1.4.4 writes for the manifest (`tdd-log.md` T182, research E22).
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:bun_install_types.bzl", "BEHAVIOR")
load("//bun/private:bun_package.bzl", "package_dependencies", "workspace_groups")

_PEER_OPTIONAL = BEHAVIOR.PEER | BEHAVIOR.OPTIONAL

def _listed(manifest, is_main):
    return [(d.behavior, d.name, d.literal) for d in package_dependencies(manifest, is_main)]

def _written(manifest, is_main):
    return workspace_groups(package_dependencies(manifest, is_main))

def _duplicates_test_impl(ctx):
    env = unittest.begin(ctx)
    manifest = {
        "dependencies": {"a": "1.0.0", "b": "file:./b1"},
        "devDependencies": {"e": "file:./c1"},
        "optionalDependencies": {"b": "file:./b2", "e": "file:./c2"},
    }

    # The root replaces the earlier entry by the optional one (Package.rs L2473-L2483), sorted
    # dev, optional, prod (`Dependency::cmp`).
    asserts.equals(env, [
        (BEHAVIOR.OPTIONAL, "b", "file:./b2"),
        (BEHAVIOR.OPTIONAL, "e", "file:./c2"),
        (BEHAVIOR.PROD, "a", "1.0.0"),
    ], _listed(manifest, True))
    asserts.equals(env, {
        "dependencies": {"a": "1.0.0"},
        "devDependencies": {},
        "optionalDependencies": {"b": "file:./b2", "e": "file:./c2"},
        "peerDependencies": {},
    }, _written(manifest, True))

    # A workspace keeps every entry (`Features::WORKSPACE`).
    asserts.equals(env, {
        "dependencies": {"a": "1.0.0", "b": "file:./b1"},
        "devDependencies": {"e": "file:./c1"},
        "optionalDependencies": {"b": "file:./b2", "e": "file:./c2"},
        "peerDependencies": {},
    }, _written(manifest, False))

    # A duplicate without an optional entry is kept, with Bun's warning, dev first.
    both = {"dependencies": {"b": "file:./b1"}, "devDependencies": {"b": "file:./b2"}}
    asserts.equals(env, [(BEHAVIOR.DEV, "b", "file:./b2"), (BEHAVIOR.PROD, "b", "file:./b1")], _listed(both, True))

    # Of three, the optional entry replaces the first (the `dependencies` one).
    three = dict(both, optionalDependencies = {"b": "file:./b3"})
    asserts.equals(env, [(BEHAVIOR.DEV, "b", "file:./b2"), (BEHAVIOR.OPTIONAL, "b", "file:./b3")], _listed(three, True))
    return unittest.end(env)

def _peers_meta_test_impl(ctx):
    env = unittest.begin(ctx)
    manifest = {
        "dependencies": {"b": "file:./b1"},
        "peerDependencies": {"s": "^1.0.0"},
        "peerDependenciesMeta": {"b": {"optional": True}, "p": {"optional": True}, "r": {"optional": False}, "s": {"optional": True}},
    }
    for is_main in [True, False]:
        # A name only in the meta is an optional peer "*", also where a dependency has the name;
        # `"optional": false` adds none; a listed peer named in the meta is optional (L3302-L3383).
        asserts.equals(env, [
            (BEHAVIOR.PROD, "b", "file:./b1"),
            (_PEER_OPTIONAL, "b", "*"),
            (_PEER_OPTIONAL, "p", "*"),
            (_PEER_OPTIONAL, "s", "^1.0.0"),
        ], _listed(manifest, is_main))

        # An optional peer is written under `peerDependencies` only (`write_workspace_deps`).
        asserts.equals(env, {
            "dependencies": {"b": "file:./b1"},
            "devDependencies": {},
            "optionalDependencies": {},
            "peerDependencies": {"b": "*", "p": "*", "s": "^1.0.0"},
        }, _written(manifest, is_main))
    return unittest.end(env)

duplicates_test = unittest.make(_duplicates_test_impl)
peers_meta_test = unittest.make(_peers_meta_test_impl)

def bun_package_test_suite(name):
    unittest.suite(name, duplicates_test, peers_meta_test)
