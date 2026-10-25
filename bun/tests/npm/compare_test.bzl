"""Unit tests for the manifest comparison of `//bun/private:workspaces.bzl` (FR-006, research R9)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun/private:lockfile.bzl", "read_lockfile")
load("//bun/private:workspaces.bzl", "compare_manifests", "resolve_catalog")

_REMEDY = "run `bun install` and commit bun.lock"

def _manifests(project, edit = None):
    """The decoded manifests of a fixture project by member path, each edited by `edit`."""
    result = RESULTS[project]
    texts = dict(result["members"])
    texts[""] = result["manifest"]
    manifests = {}
    for path, text in texts.items():
        value = json.decode(text)
        if edit:
            value = edit(path, value) or value
        manifests[path] = struct(file = "{}/package.json".format(path or "."), value = value)
    return manifests

def _lockfile(project):
    """The reader's value for a fixture project, as a struct tree (as the extension sees it)."""
    return read_lockfile(_text(project), "bun.lock").value

def _text(project):
    return json.encode(_plain_lock(RESULTS[project]["lockfile"]["value"]))

def _plain_lock(value):
    """Rebuilds lockfile JSON text from the reader's output, enough for the comparison."""
    workspaces = {}
    for path, workspace in value["workspaces"].items():
        workspaces[path] = {k: workspace[k] for k in ["name", "dependencies", "devDependencies", "optionalDependencies", "peerDependencies"]}
    lock = {"lockfileVersion": value["version"], "workspaces": workspaces, "packages": {}}
    for key in ["overrides", "catalog", "catalogs"]:
        if value.get(key):
            lock[key] = value[key]
    return lock

def _compare(project, edit = None):
    return compare_manifests(_lockfile(project), _manifests(project, edit))

def _equal_test_impl(ctx):
    env = unittest.begin(ctx)
    for project in ["basic", "workspace", "catalog", "overrides_top", "overrides_object", "overrides_gt", "overrides_range", "overrides_path", "overrides_glob", "overrides_both", "overrides_deep"]:
        asserts.equals(env, None, _compare(project).error, project)
    return unittest.end(env)

def _expect_error(env, result, texts):
    asserts.true(env, result.error != None, "a difference is reported")
    if result.error:
        for text in texts + [_REMEDY]:
            asserts.true(env, text in result.error, "{} in: {}".format(text, result.error))

def _set(path_wanted, field, key, value):
    def edit(path, manifest):
        if path != path_wanted:
            return None
        manifest = dict(manifest)
        manifest[field] = dict(manifest.get(field, {}))
        if value == None:
            manifest[field].pop(key)
        else:
            manifest[field][key] = value
        return manifest

    return edit

def _dependencies_test_impl(ctx):
    env = unittest.begin(ctx)
    _expect_error(env, _compare("basic", _set("", "dependencies", "added", "1.0.0")), ["./package.json", '"added"', '"1.0.0"'])
    _expect_error(env, _compare("basic", _set("", "dependencies", "a", "2.0.0")), ["./package.json", '"a"', '"2.0.0"', '"1.0.0"'])
    _expect_error(env, _compare("basic", _set("", "dependencies", "a", None)), ["./package.json", '"a"'])
    _expect_error(env, _compare("workspace", _set("packages/w1", "devDependencies", "single-bin", "2.0.0")), ["packages/w1/package.json", '"single-bin"'])
    _expect_error(env, _compare("workspace", _set("packages/w1", "peerDependencies", "state", "2.0.0")), ["packages/w1/package.json", '"state"'])
    _expect_error(env, _compare("workspace", _set("packages/w1", "optionalDependencies", "native-linux-x64", None)), ["packages/w1/package.json", '"native-linux-x64"'])
    return unittest.end(env)

def _catalogs_test_impl(ctx):
    env = unittest.begin(ctx)

    def change_catalog(path, manifest):
        if path:
            return None
        manifest = dict(manifest)
        manifest["workspaces"] = dict(manifest["workspaces"], catalog = {"b": "2.0.0"})
        return manifest

    def change_named(path, manifest):
        if path:
            return None
        manifest = dict(manifest)
        manifest["workspaces"] = dict(manifest["workspaces"], catalogs = {"two": {"q": "1.0.0"}})
        return manifest

    _expect_error(env, _compare("catalog", change_catalog), ["./package.json", '"b"', '"2.0.0"', '"1.0.0"'])
    _expect_error(env, _compare("catalog", change_named), ["./package.json", '"two"', '"q"'])
    _expect_error(env, _compare("catalog", _set("", "dependencies", "r", "catalog:missing")), ["./package.json", '"r"', "catalog:missing"])
    return unittest.end(env)

def _overrides_test_impl(ctx):
    env = unittest.begin(ctx)
    _expect_error(env, _compare("overrides_gt", _set("", "overrides", "a>b", "1.0.0")), ["./package.json", '"a"', '"b"'])
    _expect_error(env, _compare("basic", _set("", "overrides", "b", "2.0.0")), ["./package.json", '"b"'])
    return unittest.end(env)

def _resolve_catalog_test_impl(ctx):
    env = unittest.begin(ctx)
    catalogs = struct(catalog = {"b": "1.0.0"}, catalogs = {"two": {"q": "2.0.0"}})
    asserts.equals(env, "1.0.0", resolve_catalog("b", "catalog:", catalogs).value)
    asserts.equals(env, "2.0.0", resolve_catalog("q", "catalog:two", catalogs).value)
    asserts.equals(env, "1.0.0", resolve_catalog("b", "1.0.0", catalogs).value)
    missing = resolve_catalog("q", "catalog:", catalogs)
    asserts.equals(env, None, missing.value)
    asserts.true(env, '"q"' in missing.error and "catalog:" in missing.error, missing.error)
    return unittest.end(env)

equal_test = unittest.make(_equal_test_impl)
dependencies_test = unittest.make(_dependencies_test_impl)
catalogs_test = unittest.make(_catalogs_test_impl)
overrides_test = unittest.make(_overrides_test_impl)
resolve_catalog_test = unittest.make(_resolve_catalog_test_impl)

def compare_test_suite(name):
    unittest.suite(name, equal_test, dependencies_test, catalogs_test, overrides_test, resolve_catalog_test)
