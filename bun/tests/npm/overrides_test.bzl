"""Unit tests for `//bun/private:overrides.bzl` (FR-006, research R9)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun/private:overrides.bzl", "normalize_overrides")

def _normalize(manifest):
    result = normalize_overrides(manifest, "inline/package.json")
    return json.decode(json.encode(result))

def _fixtures_test_impl(ctx):
    env = unittest.begin(ctx)
    for project in ["overrides_top", "overrides_object", "overrides_gt", "overrides_range", "overrides_path", "overrides_glob", "overrides_both", "overrides_deep"]:
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
        ({"overrides": {"a": {"b": {"c": "1.0.0"}}}}, "a"),
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

def overrides_test_suite(name):
    unittest.suite(name, fixtures_test, precedence_test, dropped_test, scoped_test, unpinned_test)
