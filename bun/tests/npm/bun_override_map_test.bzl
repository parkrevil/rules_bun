"""Unit tests for `//bun/private:bun_override_map.bzl` (feature 007, research R1, R2, R3, R9).

Each expectation is read from Bun's source at bun-v1.4.4 (`override_selector.rs`,
`OverrideMap.rs`); the fixture cases are the rules of the lockfiles the pinned Bun wrote. The
cases of `overrides_test.bzl`, which tested the normalization this module replaces, are taken over
as rules: `fixtures_test`, `precedence`, `dropped`, `scoped` and `reference` below.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun/private:bun_override_map.bzl", "SELECTOR_ERROR", "override_map_changed", "override_map_parse_append", "parse_selector")

_FILE = "inline/package.json"

def _selector(key):
    """`parse_selector`'s result as `[[parent name, range] or None, [target name, range]]` or the error."""
    result = parse_selector(key)
    if result == None:
        return "not written"
    if result.error:
        return result.error
    parent = result.value.parent
    target = result.value.target
    return [[parent.name, parent.range] if parent != None else None, [target.name, target.range]]

def _rules(manifest, members = []):
    """The rules `override_map_parse_append` builds, as plain values, or its error.

    Returns:
        `{"map": {name: value literal}, "scoped": [[parent name, parent range literal, target
        name, target range literal, value literal]]}`, `None` for a rule without a parent.
    """
    result = override_map_parse_append(manifest, _FILE, members)
    if result == None:
        return "not written"
    if result.error:
        return {"error": result.error}
    overrides = result.value
    scoped = []
    for rule in overrides.scoped:
        scoped.append([
            rule.parent.name if rule.parent != None else None,
            rule.parent.version.literal if rule.parent != None else None,
            rule.dep.name,
            rule.target_range.literal,
            rule.dep.version.literal,
        ])
    names = sorted({rule.dep.name: None for rule in overrides.scoped}.keys())
    if sorted(overrides.scoped_names.keys()) != names:
        return {"scoped_names": sorted(overrides.scoped_names.keys()), "expected": names}
    return {"map": {name: dep.version.literal for name, dep in overrides.map.items()}, "scoped": scoped}

def _map(manifest, members = []):
    result = override_map_parse_append(manifest, _FILE, members)
    return result.value if result != None else None

def _changed(declared, recorded):
    subject = override_map_changed(_map(declared), _map(recorded))
    return [subject.rule, subject.declared, subject.recorded] if subject != None else None

def _flat(**rules):
    return {"map": rules, "scoped": []}

_NONE = {"map": {}, "scoped": []}

def _parse_selector_test_impl(ctx):
    env = unittest.begin(ctx)
    for key, expected in [
        # A name, with an optional range (SELECTOR L29-L52); an `npm:` range is the range (L41-L47).
        ("b", [None, ["b", ""]]),
        ("@s/b", [None, ["@s/b", ""]]),
        ("b@^1.0.0", [None, ["b", "^1.0.0"]]),
        ("b@npm:^1.0.0", [None, ["b", "^1.0.0"]]),
        # An `npm:` alias keeps the prefix (L41-L43).
        ("b@npm:other@^1.0.0", [None, ["b", "npm:other@^1.0.0"]]),
        # pnpm: the first `>` not after a space, `|`, `@` or `:` (L72-L82); segments trimmed (L85-L86).
        ("a>b", [["a", ""], ["b", ""]]),
        ("a> b", [["a", ""], ["b", ""]]),
        ("a@^1.0.0>b", [["a", "^1.0.0"], ["b", ""]]),
        ("a@>=1>b", [["a", ">=1"], ["b", ""]]),
        ("@s/a>@s/b", [["@s/a", ""], ["@s/b", ""]]),
        # A `>` after a space or `@` is no delimiter: a Yarn path of one segment (research Part 6 D1).
        ("a > b", [None, ["a > b", ""]]),
        ("q@>=1.0.0", [None, ["q", ">=1.0.0"]]),
        # Yarn paths: `**` segments dropped, a scope joined to its name (L108-L165).
        ("a/b", [["a", ""], ["b", ""]]),
        ("**/b", [None, ["b", ""]]),
        ("a/**/b", [["a", ""], ["b", ""]]),
        ("**/a/**/b", [["a", ""], ["b", ""]]),
        ("@s/a/b", [["@s/a", ""], ["b", ""]]),
        ("**/@s/a/**/@s/b", [["@s/a", ""], ["@s/b", ""]]),
        # In `name@npm:@scope/other@^1` the `/` belongs to the alias (L136-L143).
        ("a@npm:@s/b@^1.0.0/c", [["a", "npm:@s/b@^1.0.0"], ["c", ""]]),
        # A comment key is its own name (L55-L63).
        ("//x", [None, ["//x", ""]]),
        # Errors (L17-L23).
        ("", SELECTOR_ERROR.EMPTY_NAME),
        ("@s", SELECTOR_ERROR.INVALID_NAME),
        ("b@", SELECTOR_ERROR.EMPTY_RANGE),
        ("a>b>c", SELECTOR_ERROR.TOO_DEEP),
        ("a/b/c", SELECTOR_ERROR.TOO_DEEP),
        ("a//b", SELECTOR_ERROR.EMPTY_NAME),
        ("a/**", SELECTOR_ERROR.EMPTY_NAME),
        ("a>", SELECTOR_ERROR.EMPTY_NAME),
        ("@s>b", SELECTOR_ERROR.INVALID_NAME),
        ("a>b@", SELECTOR_ERROR.EMPTY_RANGE),
    ]:
        asserts.equals(env, expected, _selector(key), key)
    return unittest.end(env)

def _parse_skipped_test_impl(ctx):
    env = unittest.begin(ctx)

    # BC-1: what Bun skips with a warning is no rule; the applied rule next to it stays.
    for manifest, expected in [
        # A non-string value: at the top (L867-L880), under a parent (L906-L916), in resolutions (L982-L992).
        ({"overrides": {"b": 2, "c": True, "d": None, "e": ["2.0.0"], "f": "2.0.0"}}, _flat(f = "2.0.0")),
        ({"overrides": {"a": {"b": 2, "c": True, "d": None, "e": ["2.0.0"], "f": "2.0.0"}}}, {"map": {}, "scoped": [["a", "", "f", "", "2.0.0"]]}),
        ({"resolutions": {"b": 2, "c": True, "d": None, "e": ["2.0.0"], "a": {"b": "2.0.0"}, "f": "2.0.0"}}, _flat(f = "2.0.0")),
        # "" and "-" (L1257-L1275), either field, either level.
        ({"overrides": {"b": "", "c": "-", "a": {"b": "", "c": "-"}, "f": "2.0.0"}}, _flat(f = "2.0.0")),
        ({"resolutions": {"b": "", "c": "-", "a/b": "", "a/c": "-", "f": "2.0.0"}}, _flat(f = "2.0.0")),
        # An empty key (L853-L860, L969-L976).
        ({"overrides": {"": "2.0.0", "f": "2.0.0"}}, _flat(f = "2.0.0")),
        ({"resolutions": {"": "2.0.0", "f": "2.0.0"}}, _flat(f = "2.0.0")),
        # A patch: value (L1031-L1042).
        ({"overrides": {"q": "patch:q@1.0.0#patches/q.patch", "a": {"b": "patch:b@1.0.0#p.patch"}, "f": "2.0.0"}}, _flat(f = "2.0.0")),
        ({"resolutions": {"q": "patch:q@1.0.0#patches/q.patch", "f": "2.0.0"}}, _flat(f = "2.0.0")),
        # Keys the selector parser rejects (L1152-L1190).
        ({"overrides": {"@s": "2.0.0", "b@": "2.0.0", "a//b": "2.0.0", "a/**": "2.0.0", "a>b>c": "2.0.0", "a/b/c": "2.0.0", "f": "2.0.0"}}, _flat(f = "2.0.0")),
        ({"resolutions": {"@s": "2.0.0", "b@": "2.0.0", "a//b": "2.0.0", "a/**": "2.0.0", "a>b>c": "2.0.0", "a/b/c": "2.0.0", "f": "2.0.0"}}, _flat(f = "2.0.0")),
        # An object key the segment parser rejects, a child with a parent, a deeper object (L889-L916, L934-L946).
        ({"overrides": {"@s": {"b": "2.0.0"}, "a": {"x>b": "2.0.0", "c/b": "2.0.0", "b": {"c": "1.0.0"}}, "f": "2.0.0"}}, _flat(f = "2.0.0")),
        # A parent range or target range that is no selector range (L1081-L1087, L1192-L1245).
        ({"overrides": {"a@latest>b": "2.0.0", "b@latest": "2.0.0", "a@latest": {"b": "2.0.0"}, "f": "2.0.0"}}, _flat(f = "2.0.0")),
        # `"//"` keys at both levels (BC-4; L206-L209, L862-L864, L894-L896, L977-L979).
        ({"overrides": {"//": "x", "// y": "z", "a": {"//": "x", "b": "2.0.0"}}}, {"map": {}, "scoped": [["a", "", "b", "", "2.0.0"]]}),
        ({"resolutions": {"//": "x", "// y": "z", "b": "2.0.0"}}, _flat(b = "2.0.0")),
    ]:
        asserts.equals(env, expected, _rules(manifest), json.encode(manifest))
    return unittest.end(env)

def _parse_forms_test_impl(ctx):
    env = unittest.begin(ctx)
    for manifest, expected in [
        # BC-2: `"."` is the rule of the parent's own selector (L918-L927).
        ({"overrides": {"q": {".": "1.2.3"}}}, _flat(q = "1.2.3")),
        ({"overrides": {"a": {".": "1.0.0", "b": "2.0.0"}}}, {"map": {"a": "1.0.0"}, "scoped": [["a", "", "b", "", "2.0.0"]]}),
        # BC-3: a target with a range is scoped, with no parent (L1044-L1068).
        ({"overrides": {"q@^1.0.0": "1.2.3"}}, {"map": {}, "scoped": [[None, None, "q", "^1.0.0", "1.2.3"]]}),
        ({"overrides": {"q@^1.0.0": {".": "1.2.3"}}}, {"map": {}, "scoped": [[None, None, "q", "^1.0.0", "1.2.3"]]}),
        # BC-5: `**` segments in resolutions.
        ({"resolutions": {"**/q": "1.2.3"}}, _flat(q = "1.2.3")),
        ({"resolutions": {"a/**/q": "1.2.3"}}, {"map": {}, "scoped": [["a", "", "q", "", "1.2.3"]]}),
        ({"resolutions": {"**/a/**/q": "1.2.3"}}, {"map": {}, "scoped": [["a", "", "q", "", "1.2.3"]]}),
        # BC-7: one selector parser for both fields (L997-L1020).
        ({"overrides": {"a/b": "2.0.0"}}, {"map": {}, "scoped": [["a", "", "b", "", "2.0.0"]]}),
        ({"overrides": {"**/b": "2.0.0"}}, _flat(b = "2.0.0")),
        ({"resolutions": {"a>b": "2.0.0"}}, {"map": {}, "scoped": [["a", "", "b", "", "2.0.0"]]}),
        ({"overrides": {"a > b": "2.0.0"}}, {"map": {"a > b": "2.0.0"}, "scoped": []}),
        ({"overrides": {"a> b": "2.0.0"}}, {"map": {}, "scoped": [["a", "", "b", "", "2.0.0"]]}),
        ({"overrides": {"q@>=1.0.0": "2.0.0"}}, {"map": {}, "scoped": [[None, None, "q", ">=1.0.0", "2.0.0"]]}),
        ({"overrides": {"a@>=1>b": "2.0.0"}}, {"map": {}, "scoped": [["a", ">=1", "b", "", "2.0.0"]]}),
        ({"overrides": {"q@npm:^1.0.0": "2.0.0"}}, {"map": {}, "scoped": [[None, None, "q", "^1.0.0", "2.0.0"]]}),
        # BC-8: a flat rule and a rule scoped under its name.
        ({"overrides": {"a": "1.0.0", "a>b": "2.0.0"}}, {"map": {"a": "1.0.0"}, "scoped": [["a", "", "b", "", "2.0.0"]]}),
        # A later rule with the same selector replaces the earlier (`put`, `push_scoped` L644-L668).
        ({"overrides": {"b": "1.0.0", "**/b": "2.0.0"}}, _flat(b = "2.0.0")),
        ({"overrides": {"a>b": "1.0.0", "a/b": "2.0.0", "a@^1.0.0>b": "3.0.0"}}, {"map": {}, "scoped": [["a", "", "b", "", "2.0.0"], ["a", "^1.0.0", "b", "", "3.0.0"]]}),
        ({"overrides": {"a>b": "1.0.0", "a": {"b": "2.0.0"}}}, {"map": {}, "scoped": [["a", "", "b", "", "2.0.0"]]}),
        ({"overrides": {"q@^1.0.0": "1.0.0", "q@^2.0.0": "2.0.0", "q": {".": "3.0.0"}}}, {"map": {"q": "3.0.0"}, "scoped": [[None, None, "q", "^1.0.0", "1.0.0"], [None, None, "q", "^2.0.0", "2.0.0"]]}),
    ]:
        asserts.equals(env, expected, _rules(manifest), json.encode(manifest))
    return unittest.end(env)

def _parse_field_test_impl(ctx):
    env = unittest.begin(ctx)

    # `Field::of` (L166-L170): "overrides" wins whenever present; neither field: no rules.
    asserts.equals(env, _flat(b = "2.0.0"), _rules({"overrides": {"b": "2.0.0"}, "resolutions": {"b": "1.0.0", "a/c": "1.0.0"}}))
    asserts.equals(env, _NONE, _rules({}))
    asserts.equals(env, _NONE, _rules({"overrides": {}}))

    # A field that is not an object is refused (`not_an_object` L1140-L1150, research R6), also a
    # `null` "overrides" next to a "resolutions" object (`Field::of` finds the property).
    for manifest, field in [
        ({"overrides": "x"}, "overrides"),
        ({"resolutions": []}, "resolutions"),
        ({"overrides": None, "resolutions": {"b": "2.0.0"}}, "overrides"),
    ]:
        result = _rules(manifest)
        error = result.get("error", "") if type(result) == "dict" else ""
        for text in [_FILE + ":", '"{}" expects a map of package names to versions'.format(field), "make it an object"]:
            asserts.true(env, text in error, "{} in: {}".format(text, error))
        asserts.false(env, "bun install" in error, error)
    return unittest.end(env)

def _fixtures_test_impl(ctx):
    env = unittest.begin(ctx)

    # The rules of each fixture's `package.json` are those of the lockfile the pinned Bun wrote for it.
    for project, expected in [
        ("overrides_top", _flat(b = "2.0.0")),
        ("overrides_object", {"map": {"a": "1.0.0"}, "scoped": [["a", "", "b", "", "2.0.0"]]}),
        ("overrides_gt", {"map": {}, "scoped": [["a", "", "b", "", "2.0.0"]]}),
        ("overrides_range", {"map": {}, "scoped": [["a", "^1.0.0", "b", "", "2.0.0"]]}),
        ("overrides_path", {"map": {}, "scoped": [["a", "", "b", "", "2.0.0"]]}),
        ("overrides_glob", {"map": {}, "scoped": [["a", "", "b", "", "2.0.0"]]}),
        ("overrides_both", _flat(b = "2.0.0")),
        ("overrides_deep", _NONE),
        ("conformance_override_forms", _flat(b = "file:./b")),
        ("conformance_override_root_ref", _flat(c = "file:./b2")),
        ("conformance_peer_meta_only", _flat(c = "*")),
        ("conformance_optional_duplicate", _flat(c = "file:./m2")),
    ]:
        result = RESULTS[project]
        members = [json.decode(result["members"][path]) for path in sorted(result["members"].keys())]
        asserts.equals(env, expected, _rules(json.decode(result["manifest"]), members), project)
    return unittest.end(env)

def _dropped_test_impl(ctx):
    env = unittest.begin(ctx)

    # "It ignores a>b>c, a/b/c, and deeper object nesting with a warning" (bun.com pm/overrides).
    asserts.equals(env, _flat(b = "2.0.0"), _rules({"overrides": {"a>b>c": "1.0.0", "b": "2.0.0"}}))
    asserts.equals(env, _NONE, _rules({"resolutions": {"a/b/c": "1.0.0"}}))

    # Feature 006 T177: an object nested in a parent's object (OverrideMap.rs L902-L905).
    asserts.equals(env, _NONE, _rules({"overrides": {"a": {"b": {"c": "1.0.0"}}}}))
    asserts.equals(env, {"map": {}, "scoped": [["a", "", "b", "", "2.0.0"]]}, _rules({"overrides": {"a": {"b": "2.0.0", "x": {"y": "1.0.0"}}}}))
    return unittest.end(env)

def _scoped_test_impl(ctx):
    env = unittest.begin(ctx)
    expected = {"map": {}, "scoped": [["@s/a", "", "@s/b", "", "2.0.0"]]}
    asserts.equals(env, expected, _rules({"overrides": {"@s/a>@s/b": "2.0.0"}}))
    asserts.equals(env, expected, _rules({"resolutions": {"@s/a/@s/b": "2.0.0"}}))
    asserts.equals(env, expected, _rules({"resolutions": {"**/@s/a/**/@s/b": "2.0.0"}}))
    asserts.equals(env, {"map": {}, "scoped": [["@s/a", "^1.0.0", "b", "", "2.0.0"]]}, _rules({"overrides": {"@s/a@^1.0.0>b": "2.0.0"}}))
    asserts.equals(env, _flat(**{"@s/b": "2.0.0"}), _rules({"overrides": {"@s/b": "2.0.0"}}))

    # Forms `overrides_test.bzl` refused, read as Bun reads them (BC-1, BC-5).
    asserts.equals(env, _flat(b = "1.0.0"), _rules({"resolutions": {"**/b": "1.0.0"}}))
    asserts.equals(env, _NONE, _rules({"overrides": {"a": ["1.0.0"]}}))
    return unittest.end(env)

def _reference_test_impl(ctx):
    env = unittest.begin(ctx)

    # Feature 006 T177: `$<name>` is the specifier the root declares for <name>.
    root = {"dependencies": {"b": "file:./b"}, "devDependencies": {"q": "2.0.0"}, "overrides": {"b": "$b", "a": {"q": "$q"}}}
    asserts.equals(env, {"map": {"b": "file:./b"}, "scoped": [["a", "", "q", "", "2.0.0"]]}, _rules(root))

    # Feature 006 T179: the root's first dependency of that name as `Package::parse` sorts them
    # (OverrideMap.rs L1286-L1297); each case is what the pinned Bun writes (feature 006 `tdd-log.md` T179).
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
        asserts.equals(env, _flat(c = written), _rules(dict(declared, overrides = {"c": "$b"})), json.encode(declared))

    # A workspace's is the first of its four maps (`declared_dependency`, OverrideMap.rs L1373-L1380).
    member = [{"dependencies": {"b": "file:./b1"}, "devDependencies": {"b": "file:./b2"}}]
    asserts.equals(env, _flat(c = "file:./b1"), _rules({"overrides": {"c": "$b"}}, member))

    # Else the one every workspace that declares <name> declares (`workspace_ref_literal`, L1405-L1452).
    members = [{"dependencies": {"b": "1.0.0"}}, {}, {"peerDependencies": {"b": "1.0.0"}}]
    asserts.equals(env, _flat(b = "1.0.0"), _rules({"overrides": {"b": "$b"}}, members))

    # Bun skips the rule when nothing declares <name> or the workspaces disagree (L1310-L1333).
    asserts.equals(env, _NONE, _rules({"overrides": {"b": "$b"}}))
    disagree = [{"dependencies": {"b": "1.0.0"}}, {"dependencies": {"b": "2.0.0"}}]
    asserts.equals(env, _NONE, _rules({"resolutions": {"b": "$b"}}, disagree))
    return unittest.end(env)

def _changed_test_impl(ctx):
    env = unittest.begin(ctx)

    # Equal rules built in different orders are unchanged (`sort` L553-L579, then pairwise).
    one = {"overrides": {"b": "1.0.0", "c": "2.0.0", "a>b": "2.0.0", "q@^1.0.0": "3.0.0", "a@^1.0.0>b": "4.0.0"}}
    other = {"overrides": {"a@^1.0.0>b": "4.0.0", "q@^1.0.0": "3.0.0", "a>b": "2.0.0", "c": "2.0.0", "b": "1.0.0"}}
    asserts.equals(env, None, _changed(one, other))
    asserts.equals(env, None, _changed({}, {}))

    # A different count of flat or scoped rules: the rule only one side holds (L509-L511).
    asserts.equals(env, ["c", "2.0.0", None], _changed({"overrides": {"b": "1.0.0", "c": "2.0.0"}}, {"overrides": {"b": "1.0.0"}}))
    asserts.equals(env, ["c", None, "2.0.0"], _changed({"overrides": {"b": "1.0.0"}}, {"overrides": {"b": "1.0.0", "c": "2.0.0"}}))
    asserts.equals(env, ["a>b", "2.0.0", None], _changed({"overrides": {"a>b": "2.0.0"}}, {}))
    asserts.equals(env, ["q@^1.0.0", None, "1.0.0"], _changed({}, {"overrides": {"q@^1.0.0": "1.0.0"}}))

    # An equal count with one differing literal: that pair (L523-L550).
    asserts.equals(env, ["b", "1.0.0", "2.0.0"], _changed({"overrides": {"b": "1.0.0"}}, {"overrides": {"b": "2.0.0"}}))
    asserts.equals(env, ["a@^1.0.0>b@^1.0.0", "1.0.0", "2.0.0"], _changed({"overrides": {"a@^1.0.0>b@^1.0.0": "1.0.0"}}, {"overrides": {"a@^1.0.0>b@^1.0.0": "2.0.0"}}))

    # An equal count with different rules: the first in `sort` order, which one side lacks.
    asserts.equals(env, ["b", "1.0.0", None], _changed({"overrides": {"b": "1.0.0"}}, {"overrides": {"c": "1.0.0"}}))
    asserts.equals(env, ["a@^1.0.0>b", None, "1.0.0"], _changed({"overrides": {"a@^2.0.0>b": "1.0.0"}}, {"overrides": {"a@^1.0.0>b": "1.0.0"}}))

    # The first differing pair in `sort` order: flat rules first, then scoped rules without a
    # parent, then by parent name, parent range, target name and target range.
    asserts.equals(env, ["z", "1.0.0", "2.0.0"], _changed({"overrides": {"a>b": "1.0.0", "z": "1.0.0"}}, {"overrides": {"a>b": "2.0.0", "z": "2.0.0"}}))
    asserts.equals(env, ["q@^1.0.0", "1.0.0", "2.0.0"], _changed({"overrides": {"a>b": "1.0.0", "q@^1.0.0": "1.0.0"}}, {"overrides": {"a>b": "2.0.0", "q@^1.0.0": "2.0.0"}}))
    asserts.equals(env, ["a>b", "1.0.0", "2.0.0"], _changed({"overrides": {"a>c": "1.0.0", "a>b": "1.0.0"}}, {"overrides": {"a>c": "2.0.0", "a>b": "2.0.0"}}))
    asserts.equals(env, ["a>b@^1.0.0", "1.0.0", "2.0.0"], _changed({"overrides": {"a>b@^2.0.0": "1.0.0", "a>b@^1.0.0": "1.0.0"}}, {"overrides": {"a>b@^2.0.0": "2.0.0", "a>b@^1.0.0": "2.0.0"}}))
    return unittest.end(env)

parse_selector_test = unittest.make(_parse_selector_test_impl)
parse_skipped_test = unittest.make(_parse_skipped_test_impl)
parse_forms_test = unittest.make(_parse_forms_test_impl)
parse_field_test = unittest.make(_parse_field_test_impl)
fixtures_test = unittest.make(_fixtures_test_impl)
dropped_test = unittest.make(_dropped_test_impl)
scoped_test = unittest.make(_scoped_test_impl)
reference_test = unittest.make(_reference_test_impl)
changed_test = unittest.make(_changed_test_impl)

def bun_override_map_test_suite(name):
    unittest.suite(
        name,
        parse_selector_test,
        parse_skipped_test,
        parse_forms_test,
        parse_field_test,
        fixtures_test,
        dropped_test,
        scoped_test,
        reference_test,
        changed_test,
    )
