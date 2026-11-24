"""Unit tests for the manifest comparison of `//bun/private:workspaces.bzl` (FR-006, research R9)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun/private:bun_package.bzl", "root_catalogs")
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

# Feature 007's corpus projects of US1 (research R7), each written by the pinned Bun.
_US1_PROJECTS = [
    "conformance_override_ignored_values",
    "conformance_override_child_values",
    "conformance_resolution_ignored_values",
    "conformance_override_skipped_keys",
    "conformance_resolution_skipped_keys",
    "conformance_override_comments",
    "conformance_override_dot_only",
    "conformance_override_flat_and_scoped",
    "conformance_override_target_range",
    "conformance_resolution_globs",
    "conformance_override_selectors",
    "conformance_resolution_pnpm",
]

# Feature 007's corpus projects of US2 (research R7).
_US2_PROJECTS = [
    "conformance_catalog_top_and_nested",
    "conformance_catalog_no_workspaces",
    "conformance_catalog_non_string",
]

def _compare(project, edit = None):
    return compare_manifests(_lockfile(project), _manifests(project, edit), "bun.lock")

def _equal_test_impl(ctx):
    env = unittest.begin(ctx)
    for project in ["basic", "workspace", "catalog", "overrides_top", "overrides_object", "overrides_gt", "overrides_range", "overrides_path", "overrides_glob", "overrides_both", "overrides_deep", "conformance_override_forms", "conformance_override_root_ref", "conformance_catalog_default", "conformance_peer_meta_only", "conformance_optional_duplicate"] + _US1_PROJECTS + _US2_PROJECTS:
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

def _manifest_forms_test_impl(ctx):
    env = unittest.begin(ctx)

    # Feature 006 T182: the manifests are read as `Package::parse` lists them. A name only in
    # `peerDependenciesMeta` with `"optional": true` is a peer `"*"` of the root and of a workspace
    # (fixtures/conformance_peer_meta_only); the root keeps only the `optionalDependencies` entry of
    # a name it also declares in `dependencies` or `devDependencies`, while a workspace keeps both
    # (fixtures/conformance_optional_duplicate). Both lockfiles are the pinned Bun's.
    asserts.equals(env, None, _compare("conformance_peer_meta_only").error)
    asserts.equals(env, None, _compare("conformance_optional_duplicate").error)

    # `"optional": false` adds no peer, so the lockfile's `"q": "*"` is not declared.
    _expect_error(env, _compare("conformance_peer_meta_only", _set("", "peerDependenciesMeta", "q", {"optional": False})), ["./package.json", "peerDependencies", '"q"', '"*"'])
    _expect_error(env, _compare("conformance_peer_meta_only", _set("packages/w", "peerDependenciesMeta", "q", None)), ["packages/w/package.json", "peerDependencies", '"q"'])

    # Without the optional entry, the root's `dependencies` and `devDependencies` ones stay.
    _expect_error(env, _compare("conformance_optional_duplicate", _set("", "optionalDependencies", "l", None)), ["./package.json", '"l"', '"file:./l1"'])
    _expect_error(env, _compare("conformance_optional_duplicate", _set("", "optionalDependencies", "m", None)), ["./package.json", "devDependencies", '"m"', '"file:./m1"'])

    # A workspace's two entries are both compared.
    _expect_error(env, _compare("conformance_optional_duplicate", _set("packages/w", "dependencies", "l", None)), ["packages/w/package.json", "dependencies", '"l"', '"file:../../l1"'])
    _expect_error(env, _compare("conformance_optional_duplicate", _set("packages/w", "optionalDependencies", "l", "file:../../l1")), ["packages/w/package.json", "optionalDependencies", '"l"'])
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

def _catalog_missing_test_impl(ctx):
    env = unittest.begin(ctx)

    # Feature 006 T176: Bun writes no key for an optional or peer `catalog:` dependency the catalog
    # has no entry for, of the root or a workspace, in the default or a named catalog, and installs
    # (fixtures/conformance_catalog_missing); the comparison accepts it, so it is left unlinked (BC-3).
    asserts.equals(env, None, _compare("conformance_catalog_missing").error)

    # Bun refuses a `dependencies` or `devDependencies` one ("<name>@catalog: not in catalog",
    # `tdd-log.md` T176), so the comparison still fails, naming the file, the kind and the entry.
    for kind in ["dependencies", "devDependencies"]:
        for spec in ["catalog:", "catalog:nope"]:
            catalog = {"packages": [], "catalog": {"q": "1.0.0"}}
            text = json.encode({"lockfileVersion": 2, "workspaces": {"": {"name": "x", kind: {"r": spec}}}, "catalog": {"q": "1.0.0"}, "packages": {}})
            manifests = {"": struct(file = "./package.json", value = {"name": "x", "workspaces": catalog, kind: {"r": spec}})}
            _expect_error(env, compare_manifests(read_lockfile(text, "bun.lock").value, manifests, "bun.lock"), ["./package.json", kind, '"r"', spec])
    return unittest.end(env)

def _overrides_test_impl(ctx):
    env = unittest.begin(ctx)
    _expect_error(env, _compare("overrides_gt", _set("", "overrides", "a>b", "1.0.0")), ["./package.json", 'overrides "a>b" is "1.0.0", but bun.lock records "2.0.0"'])
    _expect_error(env, _compare("basic", _set("", "overrides", "b", "2.0.0")), ["./package.json", 'overrides "b": "2.0.0" is not in bun.lock'])
    return unittest.end(env)

def _inline(rules, recorded):
    """Compares a root with `rules` (its `overrides` or `resolutions`) with a lockfile recording `recorded`.

    Both declare `a` and `q` at 1.0.0, as the corpus projects of research R7; `recorded` is the
    lockfile's `overrides` (`None`: no key).
    """
    dependencies = {"a": "1.0.0", "q": "1.0.0"}
    lock = {"lockfileVersion": 3, "workspaces": {"": {"name": "x", "dependencies": dependencies}}, "packages": {}}
    if recorded != None:
        lock["overrides"] = recorded
    manifest = dict({"name": "x", "dependencies": dependencies}, **rules)
    return compare_manifests(read_lockfile(json.encode(lock), "bun.lock").value, {"": struct(file = "./package.json", value = manifest)}, "bun.lock")

def _override_forms_test_impl(ctx):
    env = unittest.begin(ctx)

    # Feature 007 (BC-1 to BC-8): each form the pinned Bun reads, next to the lockfile it writes for
    # it (research R2), passes; each case is its form's own red on main's comparison (T017).
    cases = []
    for field in ["overrides", "resolutions"]:
        # BC-1: rules Bun skips with a warning: a non-string, "" or "-" value, an empty key, a
        # patch: value, a key Bun's selector parser rejects. "a>b>c" in overrides and "a//b",
        # "a/b/c" in resolutions pass on main too, which ignores chains deeper than one parent.
        for value in [2, True, None, ["2.0.0"], "", "-"]:
            cases.append(({field: {"b": value}}, None))
        for value in ["", "-"]:
            cases.append(({field: {"a": {"b": value}} if field == "overrides" else {"a/b": value}}, None))
        cases.append(({field: {"": "2.0.0"}}, None))
        cases.append(({field: {"q": "patch:q@1.0.0#patches/q.patch"}}, None))
        for key in ["@s", "b@", "a//b", "a/**", "a>b>c", "a/b/c"]:
            cases.append(({field: {key: "2.0.0"}}, None))
    cases += [
        ({"overrides": {"a": {"b": 2}}}, None),
        # BC-4: comment keys.
        ({"overrides": {"//": "x", "// y": "z", "a": {"//": "x", "b": "2.0.0"}}}, {"a": {"b": "2.0.0"}}),
        # BC-2: a "."-only object is the flat rule.
        ({"overrides": {"b": {".": "2.0.0"}}}, {"b": "2.0.0"}),
        # BC-3: a target with a range.
        ({"overrides": {"b@^1.0.0": "2.0.0"}}, {"b@^1.0.0": {".": "2.0.0"}}),
        # BC-5: resolutions globs.
        ({"resolutions": {"**/q": "2.0.0"}}, {"q": "2.0.0"}),
        ({"resolutions": {"a/**/b": "2.0.0"}}, {"a": {"b": "2.0.0"}}),
        # BC-7: one selector parser for both fields (research Part 6 D1 for "a > b").
        ({"overrides": {"a/b": "2.0.0"}}, {"a": {"b": "2.0.0"}}),
        ({"overrides": {"**/b": "2.0.0"}}, {"b": "2.0.0"}),
        ({"resolutions": {"a>b": "2.0.0"}}, {"a": {"b": "2.0.0"}}),
        ({"overrides": {"a > b": "2.0.0"}}, {"a > b": "2.0.0"}),
        ({"overrides": {"a> b": "2.0.0"}}, {"a": {"b": "2.0.0"}}),
        ({"overrides": {"q@>=1.0.0": "2.0.0"}}, {"q@>=1.0.0": {".": "2.0.0"}}),
        ({"overrides": {"a@>=1>b": "2.0.0"}}, {"a@>=1": {"b": "2.0.0"}}),
        ({"overrides": {"q@npm:^1.0.0": "2.0.0"}}, {"q@^1.0.0": {".": "2.0.0"}}),
        # BC-8: a flat rule next to rules scoped under its name.
        ({"overrides": {"a": "1.0.0", "a>b": "2.0.0"}}, {"a": {".": "1.0.0", "b": "2.0.0"}}),
        # Passing on main too.
        ({"overrides": {"a": {".": "1.0.0", "b": "2.0.0"}}}, {"a": {".": "1.0.0", "b": "2.0.0"}}),
        ({"overrides": {"q@^1.0.0": {".": "2.0.0"}}}, {"q@^1.0.0": {".": "2.0.0"}}),
        ({"resolutions": {"**/a/**/b": "2.0.0"}}, {"a": {"b": "2.0.0"}}),
        ({"resolutions": {"//": "x", "// y": "z", "b": "2.0.0"}}, {"b": "2.0.0"}),
    ]
    for rules, recorded in cases:
        asserts.equals(env, None, _inline(rules, recorded).error, json.encode(rules))
    return unittest.end(env)

def _replace(field, key, value):
    """An edit of the root's `field` that sets `key` to `value`."""

    def edit(path, manifest):
        if path:
            return None
        rules = dict(manifest[field])
        rules[key] = value
        return dict(manifest, **{field: rules})

    return edit

def _only_field(field, value):
    """An edit of the root that leaves `field`, set to `value`, as its only overrides field."""

    def edit(path, manifest):
        if path:
            return None
        manifest = {k: v for k, v in manifest.items() if k not in ["overrides", "resolutions"]}
        manifest[field] = value
        return manifest

    return edit

def _override_stale_test_impl(ctx):
    env = unittest.begin(ctx)

    # US1-7, SC-002, FR-006: a rule Bun applies changed after the install, or one added to a field
    # whose rules Bun all skips, fails with the file, the field, the rule and the remedy.
    for project, edit, difference in [
        ("conformance_override_ignored_values", _replace("overrides", "b", "2.0.0"), 'overrides "b": "2.0.0" is not in bun.lock'),
        ("conformance_override_child_values", _replace("overrides", "b", "2.0.0"), 'overrides "b": "2.0.0" is not in bun.lock'),
        ("conformance_resolution_ignored_values", _replace("resolutions", "b", "2.0.0"), 'resolutions "b": "2.0.0" is not in bun.lock'),
        ("conformance_override_skipped_keys", _replace("overrides", "b", "2.0.0"), 'overrides "b": "2.0.0" is not in bun.lock'),
        ("conformance_resolution_skipped_keys", _replace("resolutions", "b", "2.0.0"), 'resolutions "b": "2.0.0" is not in bun.lock'),
        ("conformance_override_comments", _replace("overrides", "a", {"//": "child comment", "b": "1.0.0"}), 'overrides "a>b" is "1.0.0", but bun.lock records "2.0.0"'),
        ("conformance_override_dot_only", _replace("overrides", "b", {".": "1.0.0"}), 'overrides "b" is "1.0.0", but bun.lock records "2.0.0"'),
        ("conformance_override_flat_and_scoped", _replace("overrides", "a>b", "1.0.0"), 'overrides "a>b" is "1.0.0", but bun.lock records "2.0.0"'),
        ("conformance_override_target_range", _replace("overrides", "b@^1.0.0", "1.0.0"), 'overrides "b@^1.0.0" is "1.0.0", but bun.lock records "2.0.0"'),
        ("conformance_resolution_globs", _replace("resolutions", "**/q", "1.0.0"), 'resolutions "q" is "1.0.0", but bun.lock records "2.0.0"'),
        ("conformance_override_selectors", _replace("overrides", "q@>=1.0.0", "1.0.0"), 'overrides "q@>=1.0.0" is "1.0.0", but bun.lock records "2.0.0"'),
        ("conformance_resolution_pnpm", _replace("resolutions", "a>b", "1.0.0"), 'resolutions "a>b" is "1.0.0", but bun.lock records "2.0.0"'),
    ]:
        result = _compare(project, edit)
        asserts.true(env, result.error != None, project + ": a difference is reported")
        for text in ["./package.json: ", difference, _REMEDY]:
            asserts.true(env, result.error != None and text in result.error, "{}: {} in: {}".format(project, text, result.error))

    # A field that is not an object: Bun refuses the project, so the remedy is not `bun install`
    # (`not_an_object`, OverrideMap.rs L1140-L1150; research R6).
    for field, value in [("overrides", "x"), ("resolutions", [])]:
        result = _compare("conformance_override_dot_only", _only_field(field, value))
        expected = './package.json: "{}" expects a map of package names to versions, which Bun requires; make it an object'.format(field)
        asserts.equals(env, expected, result.error, field)
    return unittest.end(env)

def _root(change):
    """An edit of the root manifest: `change(manifest)` returns the new one."""

    def edit(path, manifest):
        return None if path else change(dict(manifest))

    return edit

def _catalog_where_test_impl(ctx):
    env = unittest.begin(ctx)

    # Feature 007 (FR-007, BC-6): the root's catalogs are those Bun reads (Package.rs L3418-L3440).
    def compare(manifest, lock):
        lock = dict({"lockfileVersion": 2, "packages": {}}, **lock)
        lock["workspaces"] = {"": {"name": "x", "dependencies": manifest["dependencies"]}}
        return compare_manifests(read_lockfile(json.encode(lock), "bun.lock").value, {"": struct(file = "./package.json", value = dict(manifest, name = "x"))}, "bun.lock")

    for manifest, lock, form in [
        # US2-1: the workspaces object's catalog; the top level's catalog and catalogs are not read.
        ({"workspaces": {"packages": [], "catalog": {"b": "2.0.0"}}, "catalog": {"b": "1.0.0", "q": "2.0.0"}, "catalogs": {"g": {"q": "1.0.0"}}, "dependencies": {"b": "catalog:"}}, {"catalog": {"b": "2.0.0"}}, "US2-1"),
        # US2-2: no workspaces field, so no catalog.
        ({"catalog": {"b": "2.0.0"}, "dependencies": {"a": "1.0.0"}}, {}, "US2-2"),
        # US2-3: a workspaces array, so the top level's (passing on main too).
        ({"workspaces": [], "catalog": {"b": "1.0.0"}, "dependencies": {"b": "catalog:"}}, {"catalog": {"b": "1.0.0"}}, "US2-3"),
        # BC-6: an entry whose value is not a string is skipped.
        ({"workspaces": {"packages": [], "catalog": {"b": "2.0.0", "q": 1}}, "dependencies": {"b": "catalog:"}}, {"catalog": {"b": "2.0.0"}}, "BC-6"),
    ]:
        asserts.equals(env, None, compare(manifest, lock).error, form)

    # Without workspaces, a `catalog:` reference names no entry, since Bun reads no catalog (spec
    # Edge Cases, BC-6).
    result = compare({"catalog": {"b": "2.0.0"}, "dependencies": {"b": "catalog:"}}, {})
    for text in ["./package.json", '"b"', "names no entry of the default catalog", _REMEDY]:
        asserts.true(env, result.error != None and text in result.error, "{} in: {}".format(text, result.error))

    # A catalog Bun does not read may change without a stale lockfile.
    asserts.equals(env, None, _compare("conformance_catalog_top_and_nested", _root(lambda m: dict(m, catalog = {"b": "3.0.0"}))).error)

    # Each catalog project with its catalogs changed after the install fails (FR-006).
    for project, change, difference in [
        ("conformance_catalog_top_and_nested", lambda m: dict(m, workspaces = dict(m["workspaces"], catalog = {"b": "1.0.0"})), 'catalog "b" is "1.0.0", but bun.lock records "2.0.0"'),
        ("conformance_catalog_no_workspaces", lambda m: dict(m, workspaces = []), 'catalog "b": "2.0.0" is not in bun.lock'),
        ("conformance_catalog_non_string", lambda m: dict(m, workspaces = dict(m["workspaces"], catalog = {"b": "2.0.0", "q": "1.0.0"})), 'catalog "q": "1.0.0" is not in bun.lock'),
    ]:
        result = _compare(project, _root(change))
        for text in ["./package.json: ", difference, _REMEDY]:
            asserts.true(env, result.error != None and text in result.error, "{}: {} in: {}".format(project, text, result.error))
    return unittest.end(env)

def _root_catalogs(catalog, catalogs):
    """The catalogs `root_catalogs` reads from a root whose `workspaces` object holds them."""
    return root_catalogs({"workspaces": {"catalog": catalog, "catalogs": catalogs}}, "./package.json").value

def _resolve_catalog_test_impl(ctx):
    env = unittest.begin(ctx)
    catalogs = _root_catalogs({"b": "1.0.0"}, {"two": {"q": "2.0.0"}})
    asserts.equals(env, "1.0.0", resolve_catalog("b", "catalog:", catalogs).value)
    asserts.equals(env, "2.0.0", resolve_catalog("q", "catalog:two", catalogs).value)
    asserts.equals(env, "1.0.0", resolve_catalog("b", "1.0.0", catalogs).value)
    missing = resolve_catalog("q", "catalog:", catalogs)
    asserts.equals(env, None, missing.value)
    asserts.true(env, '"q"' in missing.error and "catalog:" in missing.error, missing.error)

    # Feature 006 T180: `catalog:` and `catalog:default` name one catalog, looked up under both
    # spellings, the one the reference names first (`CatalogMap::locate`, CatalogMap.rs L48-L100;
    # fixtures/conformance_catalog_default, which the pinned Bun writes and installs).
    both = _root_catalogs({"b": "1.0.0"}, {"default": {"q": "2.0.0"}, "two": {"r": "3.0.0"}})
    asserts.equals(env, "2.0.0", resolve_catalog("q", "catalog:", both).value)
    asserts.equals(env, "1.0.0", resolve_catalog("b", "catalog:default", both).value)
    asserts.equals(env, "1.0.0", resolve_catalog("b", "catalog:", both).value)
    asserts.equals(env, "2.0.0", resolve_catalog("q", "catalog:default", both).value)
    for spec in ["catalog:", "catalog:default"]:
        missing = resolve_catalog("r", spec, both)
        asserts.equals(env, None, missing.value, spec)
        asserts.true(env, '"r"' in missing.error and spec in missing.error, missing.error)
    asserts.equals(env, None, resolve_catalog("b", "catalog:two", both).value)
    return unittest.end(env)

equal_test = unittest.make(_equal_test_impl)
dependencies_test = unittest.make(_dependencies_test_impl)
manifest_forms_test = unittest.make(_manifest_forms_test_impl)
catalogs_test = unittest.make(_catalogs_test_impl)
catalog_missing_test = unittest.make(_catalog_missing_test_impl)
overrides_test = unittest.make(_overrides_test_impl)
override_forms_test = unittest.make(_override_forms_test_impl)
override_stale_test = unittest.make(_override_stale_test_impl)
catalog_where_test = unittest.make(_catalog_where_test_impl)
resolve_catalog_test = unittest.make(_resolve_catalog_test_impl)

def compare_test_suite(name):
    unittest.suite(name, equal_test, dependencies_test, manifest_forms_test, catalogs_test, catalog_missing_test, overrides_test, override_forms_test, override_stale_test, catalog_where_test, resolve_catalog_test)
