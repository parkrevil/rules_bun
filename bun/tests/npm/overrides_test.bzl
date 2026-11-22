"""Unit tests for `//bun/private:overrides.bzl` (FR-006, research R9)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun/private:overrides.bzl", "normalize_overrides")

def _normalize(manifest):
    result = normalize_overrides(manifest, "inline/package.json")
    return json.decode(json.encode(result))

def _fixtures_test_impl(ctx):
    env = unittest.begin(ctx)
    for project in ["overrides_top", "overrides_object", "overrides_gt", "overrides_range", "overrides_path", "overrides_glob", "overrides_both", "overrides_deep", "conformance_override_forms", "conformance_override_root_ref", "conformance_peer_meta_only", "conformance_optional_duplicate"]:
        lockfile = RESULTS[project]["lockfile"]["value"]
        result = _normalize(json.decode(RESULTS[project]["manifest"]))
        asserts.equals(env, None, result["error"], project)
        asserts.equals(env, lockfile["overrides"], result["value"], project)
    return unittest.end(env)

def _precedence_test_impl(ctx):
    env = unittest.begin(ctx)

    # "When a package.json has both fields, Bun uses only "overrides"" (bun.com pm/overrides).
    result = _normalize({"overrides": {"b": "2.0.0"}, "resolutions": {"b": "1.0.0", "a/c": "1.0.0"}})
    asserts.equals(env, {"b": "2.0.0"}, result["value"])
    asserts.equals(env, {}, _normalize({})["value"])
    return unittest.end(env)

def _dropped_test_impl(ctx):
    env = unittest.begin(ctx)

    # "It ignores a>b>c, a/b/c, and deeper object nesting with a warning" (bun.com pm/overrides);
    # the lockfile of overrides_deep records no overrides.
    asserts.equals(env, {"b": "2.0.0"}, _normalize({"overrides": {"a>b>c": "1.0.0", "b": "2.0.0"}})["value"])
    asserts.equals(env, {}, _normalize({"resolutions": {"a/b/c": "1.0.0"}})["value"])

    # Feature 006 T177: an object nested in a parent's object is ignored, as Bun ignores it
    # ("Bun currently only supports one level of nested", OverrideMap.rs L902-L905); the lockfile
    # of conformance_override_forms records no rule for it.
    asserts.equals(env, {}, _normalize({"overrides": {"a": {"b": {"c": "1.0.0"}}}})["value"])
    asserts.equals(env, {"a": {"b": "2.0.0"}}, _normalize({"overrides": {"a": {"b": "2.0.0", "x": {"y": "1.0.0"}}}})["value"])
    return unittest.end(env)

def _reference_test_impl(ctx):
    env = unittest.begin(ctx)

    # Feature 006 T177: `$<name>` is the specifier the root declares for <name>, as the lockfile
    # records it (conformance_override_forms: "$b" with "b": "file:./b" is written "file:./b").
    root = {"dependencies": {"b": "file:./b"}, "devDependencies": {"q": "2.0.0"}, "overrides": {"b": "$b", "a": {"q": "$q"}}}
    asserts.equals(env, {"b": "file:./b", "a": {"q": "2.0.0"}}, normalize_overrides(root, "inline/package.json").value)

    # Feature 006 T179: the root's is that of its parsed package's first dependency of that name
    # (`ctx.root_package.dependencies`, OverrideMap.rs L1286-L1297): sorted dev, optional, prod,
    # then peer entries (`Behavior::cmp`, resolver_hooks.rs L275-L297; Package.rs L3385-L3388), an
    # `optionalDependencies` duplicate replacing the earlier entry (Package.rs L2473-L2483), a name
    # only in `peerDependenciesMeta` read as "*" (Package.rs L3352-L3383). Each case is what the
    # pinned Bun writes (`tdd-log.md` T179; fixtures/conformance_override_root_ref is the first).
    for declared, written in [
        ({"dependencies": {"b": "file:./b1"}, "devDependencies": {"b": "file:./b2"}}, "file:./b2"),
        ({"dependencies": {"b": "file:./b1"}, "optionalDependencies": {"b": "file:./b2"}}, "file:./b2"),
        ({"devDependencies": {"b": "file:./b1"}, "optionalDependencies": {"b": "file:./b2"}}, "file:./b2"),
        ({"dependencies": {"b": "file:./b1"}, "devDependencies": {"b": "file:./b2"}, "optionalDependencies": {"b": "file:./b3"}}, "file:./b2"),
        ({"peerDependenciesMeta": {"b": {"optional": True}}}, "*"),
        ({"dependencies": {"b": "file:./b1"}, "peerDependenciesMeta": {"b": {"optional": True}}}, "file:./b1"),
        ({"dependencies": {"b": "file:./b1"}, "peerDependencies": {"b": "file:./b2"}}, "file:./b1"),
        ({"dependencies": {"b": "file:./b1"}, "peerDependencies": {"b": "file:./b2"}, "peerDependenciesMeta": {"b": {"optional": True}}}, "file:./b1"),
        ({"peerDependencies": {"b": "file:./b2"}}, "file:./b2"),
    ]:
        manifest = dict(declared, overrides = {"c": "$b"})
        asserts.equals(env, {"c": written}, normalize_overrides(manifest, "inline/package.json").value, json.encode(declared))

    # A workspace's is the first of its four maps (`declared_dependency`, OverrideMap.rs L1373-L1380).
    member = [{"dependencies": {"b": "file:./b1"}, "devDependencies": {"b": "file:./b2"}}]
    asserts.equals(env, {"c": "file:./b1"}, normalize_overrides({"overrides": {"c": "$b"}}, "inline/package.json", member).value)

    # Else the one every workspace that declares <name> declares (`workspace_ref_literal`, L1405-L1452).
    members = [{"dependencies": {"b": "1.0.0"}}, {}, {"peerDependencies": {"b": "1.0.0"}}]
    asserts.equals(env, {"b": "1.0.0"}, normalize_overrides({"overrides": {"b": "$b"}}, "inline/package.json", members).value)

    # Bun ignores the rule when nothing declares <name> or the workspaces disagree (L1310-L1333).
    asserts.equals(env, {}, normalize_overrides({"overrides": {"b": "$b"}}, "inline/package.json").value)
    disagree = [{"dependencies": {"b": "1.0.0"}}, {"dependencies": {"b": "2.0.0"}}]
    asserts.equals(env, {}, normalize_overrides({"resolutions": {"b": "$b"}}, "inline/package.json", disagree).value)
    return unittest.end(env)

def _scoped_test_impl(ctx):
    env = unittest.begin(ctx)
    expected = {"@s/a": {"@s/b": "2.0.0"}}
    asserts.equals(env, expected, _normalize({"overrides": {"@s/a>@s/b": "2.0.0"}})["value"])
    asserts.equals(env, expected, _normalize({"resolutions": {"@s/a/@s/b": "2.0.0"}})["value"])
    asserts.equals(env, expected, _normalize({"resolutions": {"**/@s/a/**/@s/b": "2.0.0"}})["value"])
    asserts.equals(env, {"@s/a@^1.0.0": {"b": "2.0.0"}}, _normalize({"overrides": {"@s/a@^1.0.0>b": "2.0.0"}})["value"])
    asserts.equals(env, {"@s/b": "2.0.0"}, _normalize({"overrides": {"@s/b": "2.0.0"}})["value"])
    return unittest.end(env)

def _unpinned_test_impl(ctx):
    env = unittest.begin(ctx)
    for manifest, form in [
        ({"resolutions": {"**/b": "1.0.0"}}, "**/b"),
        ({"overrides": {"a": ["1.0.0"]}}, "a"),
    ]:
        result = _normalize(manifest)
        asserts.equals(env, None, result["value"])
        asserts.true(env, "inline/package.json" in result["error"], result["error"])
        asserts.true(env, '"{}"'.format(form) in result["error"], "names the form: " + result["error"])
    return unittest.end(env)

fixtures_test = unittest.make(_fixtures_test_impl)
precedence_test = unittest.make(_precedence_test_impl)
dropped_test = unittest.make(_dropped_test_impl)
scoped_test = unittest.make(_scoped_test_impl)
unpinned_test = unittest.make(_unpinned_test_impl)
reference_test = unittest.make(_reference_test_impl)

def overrides_test_suite(name):
    unittest.suite(name, fixtures_test, precedence_test, dropped_test, scoped_test, unpinned_test, reference_test)
