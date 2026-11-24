"""Unit tests for `//bun/private:bun_package.bzl` (feature 006 T182, feature 007 US2).

Each case is what the pinned Bun 1.4.4 writes for the manifest (`tdd-log.md` T182, research E22),
or, for `root_catalogs`, what Bun's source at bun-v1.4.4 reads (Package.rs L3418-L3440,
CatalogMap.rs L285-L396).
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:bun_install_types.bzl", "BEHAVIOR")
load("//bun/private:bun_package.bzl", "package_dependencies", "root_catalogs", "workspace_groups")

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

def _catalogs(manifest):
    """`root_catalogs`' value as `{"default": {name: literal}, "groups": {group: {name: literal}}}`, or its error."""
    result = root_catalogs(manifest, "inline/package.json")
    if result == None:
        return "not written"
    if result.error:
        return {"error": result.error}
    return {
        "default": {name: dep.version.literal for name, dep in result.value.default.items()},
        "groups": {group: {name: dep.version.literal for name, dep in deps.items()} for group, deps in result.value.groups.items()},
    }

def _root_catalogs_test_impl(ctx):
    env = unittest.begin(ctx)
    top = {"catalog": {"b": "1.0.0", "q": "2.0.0"}, "catalogs": {"g": {"q": "1.0.0"}}}
    top_read = {"default": {"b": "1.0.0", "q": "2.0.0"}, "groups": {"g": {"q": "1.0.0"}}}
    none = {"default": {}, "groups": {}}
    for manifest, expected in [
        # A workspaces object holding catalog: only its catalogs; the top level's are ignored (US2-1).
        (dict(top, workspaces = {"packages": [], "catalog": {"b": "2.0.0"}}), {"default": {"b": "2.0.0"}, "groups": {}}),
        # Holding only catalogs: only those.
        (dict(top, workspaces = {"catalogs": {"h": {"b": "2.0.0"}}}), {"default": {}, "groups": {"h": {"b": "2.0.0"}}}),
        # Holding neither: the top level's.
        (dict(top, workspaces = {"packages": []}), top_read),
        # A workspaces array, or null, holds neither: the top level's (US2-3; research R4).
        (dict(top, workspaces = []), top_read),
        (dict(top, workspaces = None), top_read),
        # No workspaces field: none (US2-2).
        (top, none),
        # Entries whose value is not a string are skipped (BC-6; CatalogMap.rs L356-L358); the
        # group itself exists (L304-L306).
        ({"workspaces": {"catalog": {"b": "2.0.0", "q": 1, "r": None, "s": ["1.0.0"]}}}, {"default": {"b": "2.0.0"}, "groups": {}}),
        ({"workspaces": {"catalogs": {"g": {"q": 1}}}}, {"default": {}, "groups": {"g": {}}}),
        # catalogs.default is the group "default" (L300-L307).
        ({"workspaces": {"catalogs": {"default": {"q": "1.0.0"}}}}, {"default": {}, "groups": {"default": {"q": "1.0.0"}}}),
    ]:
        asserts.equals(env, expected, _catalogs(manifest), json.encode(manifest))

    # A name in both catalog and catalogs.default is an error, and Bun installs nothing (L310-L339).
    result = _catalogs({"workspaces": {"catalog": {"q": "1.0.0"}, "catalogs": {"default": {"q": "2.0.0"}}}})
    error = result.get("error", "") if type(result) == "dict" else ""
    for text in ["inline/package.json:", '"q" is defined in both "catalog" and "catalogs.default"']:
        asserts.true(env, text in error, "{} in: {}".format(text, error))
    return unittest.end(env)

duplicates_test = unittest.make(_duplicates_test_impl)
peers_meta_test = unittest.make(_peers_meta_test_impl)
root_catalogs_test = unittest.make(_root_catalogs_test_impl)

def bun_package_test_suite(name):
    unittest.suite(name, duplicates_test, peers_meta_test, root_catalogs_test)
