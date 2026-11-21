"""Unit tests for `//bun/private:lockfile.bzl` (FR-007, research R1, Part 3)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun/private:lockfile.bzl", "read_lockfile")
load("//bun/private:resolve.bzl", "resolve")

def _plain(value):
    return json.decode(json.encode(value))

def _lockfile(env, project):
    result = RESULTS[project]["lockfile"]
    asserts.equals(env, None, result["error"])
    return result["value"]

def _read(text):
    return _plain(read_lockfile(text, "inline/bun.lock"))

def _inline(entries, version = 2):
    return '{"lockfileVersion": %d, "workspaces": {"": {"name": "x"}}, "packages": {%s}}' % (version, entries)

def _versions_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, 1, _lockfile(env, "version1")["version"])
    asserts.equals(env, 2, _lockfile(env, "basic")["version"])
    asserts.equals(env, 3, _lockfile(env, "overrides_gt")["version"])
    for version in [0, 4]:
        result = _read(_inline("", version))
        asserts.equals(env, None, result["value"])
        asserts.true(env, "inline/bun.lock" in result["error"], result["error"])
        asserts.true(env, "lockfileVersion {}".format(version) in result["error"], result["error"])
        asserts.true(env, "bun install" in result["error"], "names the remedy: " + result["error"])
    return unittest.end(env)

def _config_version_test_impl(ctx):
    env = unittest.begin(ctx)

    # The pinned Bun re-saved the hoisted fixture with configVersion 0 (hoisted installs); it reads
    # as the same lockfile with configVersion 1 (Edge Cases, T127).
    text = RESULTS["hoisted"]["text"]
    asserts.true(env, '"configVersion": 0,' in text, "the hoisted fixture has configVersion 0")
    asserts.equals(env, None, RESULTS["hoisted"]["lockfile"]["error"])
    asserts.equals(env, _read(text.replace('"configVersion": 0,', '"configVersion": 1,')), _read(text))

    # Bun reads a whole number above 1 as 1 and 1.0 as 1 (ConfigVersion.rs `from_expr`, T125), and
    # takes an array of strings as `trustedDependencies` (LOCK L1871-L1888).
    for accepted in ['"configVersion": 2,', '"configVersion": 1.0,', '"configVersion": 0, "trustedDependencies": ["a"],']:
        asserts.equals(env, _read(text), _read(text.replace('"configVersion": 0,', accepted)), accepted)
    return unittest.end(env)

def _invalid_test_impl(ctx):
    env = unittest.begin(ctx)
    result = _read('{"lockfileVersion": 2,, }')
    asserts.equals(env, None, result["value"])
    asserts.true(env, "inline/bun.lock" in result["error"], result["error"])
    return unittest.end(env)

def _workspaces_test_impl(ctx):
    env = unittest.begin(ctx)
    workspaces = _lockfile(env, "workspace")["workspaces"]
    asserts.equals(env, ["", "packages/w1", "packages/w2"], sorted(workspaces.keys()))
    w1 = workspaces["packages/w1"]
    asserts.equals(env, "packages/w1", w1["path"])
    asserts.equals(env, "w1", w1["name"])
    asserts.equals(env, {"a": "1.0.0", "p": "1.0.0", "p-user": "1.0.0", "q": "2.0.0", "w2": "workspace:*"}, w1["dependencies"])
    asserts.equals(env, {"single-bin": "1.0.0"}, w1["devDependencies"])
    asserts.equals(env, {"native-linux-x64": "1.0.0"}, w1["optionalDependencies"])
    asserts.equals(env, {"state": "1.0.0"}, w1["peerDependencies"])
    root = workspaces[""]
    asserts.equals(env, {"a": "1.0.0", "aliased": "npm:b@2.0.0", "q": "catalog:"}, root["dependencies"])
    asserts.equals(env, {}, root["devDependencies"])
    return unittest.end(env)

def _entries_test_impl(ctx):
    env = unittest.begin(ctx)
    basic = _lockfile(env, "basic")["entries"]

    a = basic["a"]
    asserts.equals(env, "a", a["key"])
    asserts.equals(env, ["a"], a["segments"])
    asserts.equals(env, "a", a["alias"])
    asserts.equals(env, "npm", a["kind"])
    asserts.equals(env, "a", a["name"])
    asserts.equals(env, "1.0.0", a["version"])
    asserts.true(env, a["url"].endswith("/a/-/a-1.0.0.tgz"), a["url"])
    asserts.true(env, a["integrity"].startswith("sha512-"), a["integrity"])
    asserts.equals(env, {"b": "^1.0.0"}, a["dependencies"])

    asserts.equals(env, ["c", "b"], basic["c/b"]["segments"])
    asserts.equals(env, "b", basic["c/b"]["alias"])
    asserts.equals(env, "2.0.0", basic["c/b"]["version"])

    native = basic["native"]
    asserts.equals(env, 6, len(native["optional_dependencies"]))
    asserts.equals(env, {}, native["dependencies"])
    asserts.equals(env, ["darwin"], basic["native-darwin-arm64"]["os"])
    asserts.equals(env, ["arm64"], basic["native-darwin-arm64"]["cpu"])
    asserts.equals(env, ["!win32"], basic["negated-not-win"]["os"])
    asserts.equals(env, [], basic["a"]["os"])
    asserts.equals(env, ["glibc"], basic["native-linux-x64"]["libc"])
    asserts.equals(env, ["musl"], basic["native-linux-x64-musl"]["libc"])
    asserts.equals(env, [], basic["native-darwin-arm64"]["libc"])

    p = basic["p"]
    asserts.equals(env, {"q": "^1.0.0 || ^2.0.0", "r": "^1.0.0"}, p["peers"])
    asserts.equals(env, ["r"], p["optional_peers"])

    asserts.equals(env, {"single-bin": "cli.ts"}, basic["single-bin"]["bin"])
    asserts.equals(env, {"s-other": "bin/other.mjs", "s-tool": "bin/tool.js"}, basic["@scope/s"]["bin"])
    asserts.equals(env, "@scope/s", basic["@scope/s"]["name"])
    asserts.equals(env, {}, basic["dirbin"]["bin"])

    jsx = _lockfile(env, "jsx")["entries"]
    asserts.equals(env, "", jsx["react"]["url"])
    asserts.equals(env, {"react": "^19.2.0"}, jsx["react-dom"]["peers"])
    return unittest.end(env)

def _kinds_test_impl(ctx):
    env = unittest.begin(ctx)
    workspace = _lockfile(env, "workspace")["entries"]
    asserts.equals(env, "workspace", workspace["w2"]["kind"])
    asserts.equals(env, "w2", workspace["w2"]["name"])
    asserts.equals(env, "packages/w2", workspace["w2"]["version"])
    aliased = workspace["aliased"]
    asserts.equals(env, "aliased", aliased["alias"])
    asserts.equals(env, "b", aliased["name"])
    asserts.equals(env, "2.0.0", aliased["version"])
    asserts.equals(env, "npm", aliased["kind"])

    unsupported = _lockfile(env, "unsupported")["entries"]
    asserts.equals(env, "file", unsupported["local"]["kind"])
    asserts.equals(env, "tarball", unsupported["tb"]["kind"])
    asserts.equals(env, "b", unsupported["tb"]["name"])
    asserts.equals(env, "", unsupported["tb"]["integrity"])
    asserts.equals(env, "", unsupported["nointegrity"]["integrity"])

    # The info object in slot 1 of a `file:` or tarball-URL entry is read (L31, feature 006 BC-8:
    # Bun links its dependencies); no integrity is read, because rules_bun fetches neither.
    rows = _read(_inline(
        '"local": ["local@file:local", {"dependencies": {"b": "1.0.0"}}], ' +
        '"tb": ["b@http://example.com/b.tgz", {"dependencies": {"b": "1.0.0"}}, "sha512-x"]',
    ))["value"]["entries"]
    for key in ["local", "tb"]:
        asserts.equals(env, {"b": "1.0.0"}, rows[key]["dependencies"], key)
        asserts.equals(env, "", rows[key]["integrity"], key)

    git = _read(_inline('"g": ["g@git+https://example.com/g.git#abc", {}, "abc"]'))["value"]["entries"]["g"]
    asserts.equals(env, "unsupported", git["kind"])
    asserts.equals(env, "git+https://example.com/g.git#abc", git["resolution"])
    return unittest.end(env)

def _scoped_keys_test_impl(ctx):
    env = unittest.begin(ctx)
    entries = _read(_inline(
        '"@s/a": ["@s/a@1.0.0", "", {}, "sha512-x"], "@s/a/@s/b": ["@s/b@1.0.0", "", {"os": ["linux", "darwin"]}, "sha512-y"]',
    ))["value"]["entries"]
    nested = entries["@s/a/@s/b"]
    asserts.equals(env, ["@s/a", "@s/b"], nested["segments"])
    asserts.equals(env, "@s/b", nested["alias"])
    asserts.equals(env, "@s/b", nested["name"])
    asserts.equals(env, ["linux", "darwin"], nested["os"])
    return unittest.end(env)

def _bad_slot_test_impl(ctx):
    env = unittest.begin(ctx)
    result = _read(_inline('"a": ["a@1.0.0", 7, {}, "sha512-x"]'))
    asserts.equals(env, None, result["value"])
    asserts.true(env, "\"a\"" in result["error"] and "slot 1" in result["error"], result["error"])
    return unittest.end(env)

def _extra_slots_test_impl(ctx):
    env = unittest.begin(ctx)

    # Feature 006 T149, BC-18: Bun reads an npm row's slots by index and ignores any after slot 3
    # (LOCK L2433-L2669); the pinned Bun loads each of these rows (`tdd-log.md` T149).
    for extra in ['"x"', "5", '{"dependencies": {"zz": "1"}}', "null", '[], true, "y"']:
        text = '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "dependencies": {"a": "1.0.0"}}}, "packages": {"a": ["a@1.0.0", "", {"dependencies": {}}, "%s", %s]}}' % (_VALID512, extra)
        read = read_lockfile(text, "inline/bun.lock")
        asserts.equals(env, None, read.error, extra)
        if read.error:
            continue
        entry = read.value.entries["a"]
        asserts.equals(env, _VALID512, entry.integrity, extra)
        asserts.equals(env, {}, entry.dependencies, extra)
        asserts.equals(env, None, resolve(read.value, "inline/bun.lock").error, extra)
    return unittest.end(env)

def _statuses(resolution):
    """Instance name -> status of a resolution."""
    return {i["name"]: i["status"] for i in resolution["instances"].values()}

def _resolved_inline(entry):
    text = '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "dependencies": {"g": "1"}}}, "packages": {"g": %s}}' % entry
    lockfile = read_lockfile(text, "inline/bun.lock")
    return _plain(resolve(lockfile.value, "inline/bun.lock"))["value"]

def _unsupported_test_impl(ctx):
    env = unittest.begin(ctx)
    statuses = _statuses(RESULTS["unsupported"]["resolution"]["value"])
    asserts.equals(env, "ok", statuses["a"])
    asserts.true(env, "file:" in statuses["local"], statuses["local"])
    tarball = [s for name, s in statuses.items() if name == "b" and s != "ok"]
    asserts.equals(env, 1, len(tarball), "the tarball-URL entry tb names b")
    if tarball:
        asserts.true(env, "tarball URL" in tarball[0] and "/b/-/b-1.0.0.tgz" in tarball[0], tarball[0])
    asserts.true(env, "no integrity" in statuses["nointegrity"], statuses["nointegrity"])
    asserts.true(env, "patchedDependencies" in statuses["r"], statuses["r"])
    asserts.equals(env, ["r@1.0.0"], RESULTS["unsupported"]["lockfile"]["value"]["patched"])

    git = _statuses(_resolved_inline('["g@git+https://example.com/g.git#abc", {}, "abc"]'))["g"]
    asserts.true(env, "git+https://example.com/g.git#abc" in git, git)
    sha1 = _statuses(_resolved_inline('["g@1.0.0", "", {}, "sha1-abc="]'))["g"]
    asserts.true(env, "sha1" in sha1 and "sha256, sha384 and sha512" in sha1, sha1)
    return unittest.end(env)

def _workspace_inline(workspace, entries = ""):
    return '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "packages/w": %s}, "packages": {%s}}' % (workspace, entries)

def _refused(env, text, *fragments):
    """Asserts that reading `text` fails naming the label and each fragment, printing no value."""
    result = _read(text)
    asserts.equals(env, None, result["value"])
    error = result["error"] or ""
    asserts.true(env, "inline/bun.lock" in error, error)
    for fragment in fragments:
        asserts.true(env, fragment in error, "names {}: {}".format(fragment, error))
    asserts.false(env, "SECRET" in error, "prints no unchecked value: " + error)

def _unresolved_test_impl(ctx):
    env = unittest.begin(ctx)

    # L23, L24 (research Part 4): `unresolved` of an entry and of a workspace, as Bun wrote them.
    unresolved = _lockfile(env, "conformance_unresolved")
    asserts.equals(env, ["state"], unresolved["entries"]["opt-user"].get("unresolved"))
    asserts.equals(env, ["b"], unresolved["workspaces"][""].get("unresolved"))
    asserts.equals(env, ["q"], unresolved["workspaces"]["packages/w"].get("unresolved"))
    asserts.equals(env, [], _lockfile(env, "basic")["entries"]["a"].get("unresolved"))

    # A name that is no optional dependency is read as written; the loader ignores it, as Bun's
    # `parse_append_dependencies` does (LOCK L3531-L3537).
    entry = _read(_inline('"a": ["a@1.0.0", "", {"dependencies": {"b": "1.0.0"}, "unresolved": ["b", "zz"]}, "sha512-x"]'))
    asserts.equals(env, None, entry["error"])
    asserts.equals(env, ["b", "zz"], entry["value"]["entries"]["a"].get("unresolved"))

    # Malformed: Bun refuses it ("Expected an array", "Expected a string", LOCK L3376-L3391).
    _refused(env, _inline('"a": ["a@1.0.0", "", {"unresolved": "SECRET"}, "sha512-x"]'), "\"a\"", "unresolved")
    _refused(env, _inline('"a": ["a@1.0.0", "", {"unresolved": ["b", {"SECRET": 1}]}, "sha512-x"]'), "\"a\"", "unresolved")
    _refused(env, _workspace_inline('{"name": "w", "unresolved": {"SECRET": 1}}'), "packages/w", "unresolved")
    return unittest.end(env)

def _bundled_test_impl(ctx):
    env = unittest.begin(ctx)

    # L26: `bundled: true` marks an entry of a bundled dependency (LOCK L2351).
    bundled = _lockfile(env, "conformance_bundled")["entries"]
    asserts.equals(env, True, bundled["bundler/b"].get("bundled"))
    asserts.equals(env, False, bundled["bundler"].get("bundled"))

    # Bun skips a `bundled` that is not a boolean (`let Some(&Boolean(bundled)) = … else continue`).
    other = _read(_inline('"a": ["a@1.0.0", "", {"bundled": "yes"}, "sha512-x"]'))
    asserts.equals(env, None, other["error"])
    asserts.equals(env, False, other["value"]["entries"]["a"].get("bundled"))
    return unittest.end(env)

def _workspace_fields_test_impl(ctx):
    env = unittest.begin(ctx)

    # L28: a workspace's `version` (LOCK L2162-L2191); `None` when absent.
    workspaces = _read(_workspace_inline('{"name": "w", "version": "1.5.0"}'))["value"]["workspaces"]
    asserts.equals(env, "1.5.0", workspaces["packages/w"].get("version"))
    asserts.equals(env, None, workspaces[""].get("version"))
    _refused(env, _workspace_inline('{"name": "w", "version": ["SECRET"]}'), "packages/w", "version")

    # L33: a workspace's `optionalPeers` (LOCK L3372-L3400 for the root and workspaces).
    peers = _read(_workspace_inline('{"name": "w", "peerDependencies": {"p": "1"}, "optionalPeers": ["p"]}'))["value"]
    asserts.equals(env, ["p"], peers["workspaces"]["packages/w"].get("optional_peers"))
    _refused(env, _workspace_inline('{"name": "w", "optionalPeers": "SECRET"}'), "packages/w", "optionalPeers")
    return unittest.end(env)

def _row_fields_test_impl(ctx):
    env = unittest.begin(ctx)

    # L29: the `packages` rows in the order Bun wrote them (LOCK L2929, L2993).
    asserts.equals(env, [
        "@scope/lib",
        "app",
        "b",
        "lib",
        "q",
        "x",
        "y",
        "./@scope/lib/b",
        "./lib/b",
        "./lib/y",
        "@scope/lib/b",
        "app/@scope/lib",
        "app/lib",
        "./lib/y/x",
        "app/@scope/lib/b",
        "app/lib/b",
        "app/lib/y",
        "app/lib/y/x",
    ], _lockfile(env, "conformance_alias_workspace").get("keys"))

    # L31: the info object of a row that is not an npm version (LOCK L2557-L2591: index 1).
    rows = _read(_inline(
        '"local": ["local@file:local", {"dependencies": {"b": "1.0.0"}}], ' +
        '"tb": ["b@http://example.com/b.tgz", {"optionalDependencies": {"c": "1.0.0"}}, "sha512-x"]',
    ))["value"]["entries"]
    asserts.equals(env, {"b": "1.0.0"}, rows["local"]["dependencies"])
    asserts.equals(env, {"c": "1.0.0"}, rows["tb"]["optional_dependencies"])

    # L32: a row's `devDependencies` (LOCK L1478-L1483, WORKSPACE_DEPENDENCY_GROUPS).
    dev = _read(_inline('"local": ["local@file:local", {"devDependencies": {"d": "1.0.0"}}]'))["value"]["entries"]
    asserts.equals(env, {"d": "1.0.0"}, dev["local"].get("dev_dependencies"))
    return unittest.end(env)

def _dependency_maps_test_impl(ctx):
    env = unittest.begin(ctx)

    # L13, L14, L32 (an entry) and L3, L6 (a workspace): each dependency map is an object whose
    # values are strings, or Bun refuses the lockfile ("Expected an object", "Expected a string",
    # LOCK L3405-L3426).
    for field in ["dependencies", "optionalDependencies", "peerDependencies", "devDependencies"]:
        _refused(env, _inline('"a": ["a@1.0.0", "", {"%s": "SECRET"}, "sha512-x"]' % field), "\"a\"", field)
        _refused(env, _inline('"a": ["a@1.0.0", "", {"%s": ["SECRET"]}, "sha512-x"]' % field), "\"a\"", field)
        _refused(env, _inline('"a": ["a@1.0.0", "", {"%s": {"b": {"SECRET": 1}}}, "sha512-x"]' % field), "\"a\"", field, "\"b\"")
        _refused(env, _inline('"local": ["local@file:local", {"%s": {"b": ["SECRET"]}}]' % field), "\"local\"", field, "\"b\"")
        _refused(env, _workspace_inline('{"name": "w", "%s": "SECRET"}' % field), "packages/w", field)
        _refused(env, _workspace_inline('{"name": "w", "%s": {"b": 1}}' % field), "packages/w", field, "\"b\"")

    # As written, an empty map included.
    read = _read(_workspace_inline('{"name": "w", "dependencies": {}, "peerDependencies": {"p": "^1"}}'))
    asserts.equals(env, None, read["error"])
    asserts.equals(env, {"p": "^1"}, read["value"]["workspaces"]["packages/w"]["peerDependencies"])
    return unittest.end(env)

# Feature 006 T079: refusals of Bun 1.4.4's text-lockfile loader (LOCK L1727-L3543), each a text the
# pinned Bun refuses with that line's message (research Part 4, "Loader refusals"), and the
# fragments the ruleset's evaluation error names besides the label. A row's integrity is a valid
# sha512, so Bun reaches the line under test.
_LOADER_REFUSALS = [
    ("L1816", '{"workspaces": {"": {}}, "packages": {}}', ["lockfileVersion"]),
    ("L1829", '{"lockfileVersion": "2", "workspaces": {"": {"name": "x"}}, "packages": {}}', ["lockfileVersion"]),
    ("L1855", '{"lockfileVersion": 4, "workspaces": {"": {"name": "x"}}, "packages": {}}', ["lockfileVersion 4"]),
    ("L1864", '{"lockfileVersion": 2, "configVersion": "SECRET", "workspaces": {"": {"name": "x"}}, "packages": {}}', ['"configVersion"', "Expected a number"]),
    ("L1864", '{"lockfileVersion": 2, "configVersion": 1.5, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['"configVersion"', "Expected a number"]),
    ("L1864", '{"lockfileVersion": 2, "configVersion": -1, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['"configVersion"', "Expected a number"]),
    ("L1875", '{"lockfileVersion": 2, "trustedDependencies": "SECRET", "workspaces": {"": {"name": "x"}}, "packages": {}}', ['"trustedDependencies"', "Expected an array"]),
    ("L1884", '{"lockfileVersion": 2, "trustedDependencies": ["a", ["SECRET"]], "workspaces": {"": {"name": "x"}}, "packages": {}}', ['"trustedDependencies"', "Expected a string"]),
    ("L1946", '{"lockfileVersion": 2, "overrides": {"": "1.0.0"}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ["overrides", "Expected a non-empty string"]),
    ("L1968", '{"lockfileVersion": 2, "overrides": {"a": "ftp://example.com/a.tgz"}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['overrides "a"', "Invalid override version"]),
    ("L1978", '{"lockfileVersion": 2, "overrides": {"a": 1}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['overrides "a"', "Expected a string or an object"]),
    ("L1986", '{"lockfileVersion": 2, "overrides": {"@": {"b": "1.0.0"}}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['overrides "@"', "Invalid override key"]),
    ("L1992", '{"lockfileVersion": 2, "overrides": {"a": {"b": 1}}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['overrides "a"', "Expected a string"]),
    ("L2007", '{"lockfileVersion": 2, "overrides": {"a": {"@": "1.0.0"}}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['overrides "a"', "Invalid override key"]),
    ("L2027", '{"lockfileVersion": 2, "overrides": {"a": {"b": "ftp://example.com/b.tgz"}}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['overrides "a"', "Invalid override version"]),
    ("L1738", '{"lockfileVersion": 2, "catalog": {"": "1.0.0"}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ["catalog", "Expected a non-empty string"]),
    ("L1746", '{"lockfileVersion": 2, "catalog": {"a": 1}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ["catalog", "Expected a string"]),
    ("L1765", '{"lockfileVersion": 2, "catalog": {"a": "ftp://example.com/a.tgz"}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ["catalog", "Invalid catalog version"]),
    ("L2068", '{"lockfileVersion": 2, "catalogs": {"": {}}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ["catalogs", "Expected a non-empty string"]),
    ("L2076", '{"lockfileVersion": 2, "catalogs": {"g": 1}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['catalogs "g"', "Expected an object"]),
    ("L2138", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "w": {}}, "packages": {}}', ['workspace "w"', "Expected a string name property"]),
    ("L2146", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "w": {"name": 1}}, "packages": {}}', ['workspace "w"', "Expected a string name property"]),
    ("L2164", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "w": {"name": "w", "version": 1}}, "packages": {}}', ['workspace "w"', "version"]),
    ("L2181", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "w": {"name": "w", "version": "abc"}}, "packages": {}}', ['workspace "w"', "Invalid semver version"]),
    ("L2200", '{"lockfileVersion": 2, "workspaces": {"w": {"name": "w"}}, "packages": {}}', ["workspaces", "Expected root package"]),
    ("L2339", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": "SECRET"}}', ['"a"']),
    ("L2368", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": []}}', ['"a"']),
    ("L2380", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": [1]}}', ['"a"']),
    ("L2394", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a"]}}', ['"a"', "<name>@<resolution>"]),
    ("L2403", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["../a@1.0.0", "", {}, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a"', "invalid package name"]),
    ("L2427", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@^1.0.0", "", {}, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a"', "Unexpected resolution"]),
    ("L2434", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0"]}}', ['"a"', "slots"]),
    ("L2445", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", 1, {}, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a"', "slot 1"]),
    ("L2536", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@workspace:nope"]}}', ['"a"', "Unknown workspace"]),
    ("L2558", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@file:a"]}}', ['"a"', "slot 1"]),
    ("L2569", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", 1, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a"', "slot 2"]),
    ("L2640", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", {}]}}', ['"a"', "slots"]),
    ("L2643", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", {}, 1]}}', ['"a"', "slot 3"]),
    ("L2650", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", {}, "md5-AAAA"]}}', ['"a"', "Unsupported or malformed integrity hash"]),
    ("L2843", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "dependencies": {"b": "1.0.0"}}}, "packages": {}}', ["Failed to resolve root prod dependency 'b'"]),
    ("L2908", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "w": {"name": "w", "dependencies": {"b": "1.0.0"}}}, "packages": {}}', ["Failed to resolve prod dependency 'b' for package 'w'"]),
    ("L3000", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a@b/c": ["c@1.0.0", "", {"dependencies": {"d": "1.0.0"}}, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a@b/c"', "Invalid package path"]),
    ("L3010", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", {"dependencies": {"d": "1.0.0"}}, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ["Failed to resolve prod dependency 'd' for package 'a'"]),
    ("L3451", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "dependencies": {"b": "ftp://example.com/b.tgz"}}}, "packages": {}}', ['workspace ""', "Invalid dependency version"]),
]

# The containers the reader crashed on or accepted (`dict()` of a string, `.items()` of a list) and
# the root workspace's `name` (T079, red first).
_CONTAINER_REFUSALS = [
    ("L1901", '{"lockfileVersion": 2, "patchedDependencies": "SECRET", "workspaces": {"": {"name": "x"}}, "packages": {}}', ["patchedDependencies"]),
    ("L1910", '{"lockfileVersion": 2, "patchedDependencies": {"b@1.0.0": ["SECRET"]}, "workspaces": {"": {"name": "x"}}, "packages": {}}', ["patchedDependencies", '"b@1.0.0"', "string"]),
    ("L1936", '{"lockfileVersion": 2, "overrides": "SECRET", "workspaces": {"": {"name": "x"}}, "packages": {}}', ["overrides"]),
    ("L2039", '{"lockfileVersion": 2, "catalog": "SECRET", "workspaces": {"": {"name": "x"}}, "packages": {}}', ["catalog"]),
    ("L2058", '{"lockfileVersion": 2, "catalogs": "SECRET", "workspaces": {"": {"name": "x"}}, "packages": {}}', ["catalogs"]),
    ("L2101", '{"lockfileVersion": 2, "workspaces": ["SECRET"], "packages": {}}', ["workspaces"]),
    ("L2114", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "w": "SECRET"}, "packages": {}}', ['workspace "w"']),
    ("L2215", '{"lockfileVersion": 2, "workspaces": {"": {"name": 1}}, "packages": {}}', ['workspace ""', "Expected a string"]),
    ("L2313", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": ["SECRET"]}', ["packages"]),
]

# Feature 006 T139: JSON `null` where Bun 1.4.4's loader expects a value. Bun's `get` returns a
# present `null` as a value, so each check below refuses it as it refuses any other value of the
# wrong type (the pinned Bun refuses each text, `tdd-log.md` T139); the reader read a present `null`
# as a missing key and loaded these lockfiles.
_NULL_REFUSALS = [
    ("L1829", '{"lockfileVersion": null, "workspaces": {"": {"name": "x"}}, "packages": {}}', ["lockfileVersion"]),
    ("L1864", '{"lockfileVersion": 2, "configVersion": null, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['"configVersion"', "Expected a number"]),
    ("L1875", '{"lockfileVersion": 2, "trustedDependencies": null, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['"trustedDependencies"', "Expected an array"]),
    ("L2101", '{"lockfileVersion": 2, "workspaces": null, "packages": {}}', ["workspaces"]),
    ("L3408", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "dependencies": null}}, "packages": {}}', ['workspace ""', '"dependencies"']),
    ("L3408", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "devDependencies": null}}, "packages": {}}', ['workspace ""', '"devDependencies"']),
    ("L3408", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "optionalDependencies": null}}, "packages": {}}', ['workspace ""', '"optionalDependencies"']),
    ("L3408", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "peerDependencies": null}}, "packages": {}}', ['workspace ""', '"peerDependencies"']),
    ("L3377", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "optionalPeers": null}}, "packages": {}}', ['workspace ""', '"optionalPeers"']),
    ("L3377", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x", "unresolved": null}}, "packages": {}}', ['workspace ""', '"unresolved"']),
    ("L2215", '{"lockfileVersion": 2, "workspaces": {"": {"name": null}}, "packages": {}}', ['workspace ""', "Expected a string"]),
    ("L2114", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "packages/w": null}, "packages": {}}', ['workspace "packages/w"']),
    ("L2146", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "packages/w": {"name": null}}, "packages": {}}', ['workspace "packages/w"', "Expected a string name property"]),
    ("L2164", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "packages/w": {"name": "w", "version": null}}, "packages": {}}', ['workspace "packages/w"', '"version"']),
    ("L3408", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "packages/w": {"name": "w", "dependencies": null}}, "packages": {}}', ['workspace "packages/w"', '"dependencies"']),
    ("L3377", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "packages/w": {"name": "w", "optionalPeers": null}}, "packages": {}}', ['workspace "packages/w"', '"optionalPeers"']),
    ("L3377", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}, "packages/w": {"name": "w", "unresolved": null}}, "packages": {}}', ['workspace "packages/w"', '"unresolved"']),
    ("L3408", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", {"dependencies": null}, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a"', '"dependencies"']),
    ("L3408", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", {"devDependencies": null}, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a"', '"devDependencies"']),
    ("L3408", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", {"optionalDependencies": null}, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a"', '"optionalDependencies"']),
    ("L3408", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", {"peerDependencies": null}, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a"', '"peerDependencies"']),
    ("L3377", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", {"optionalPeers": null}, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a"', '"optionalPeers"']),
    ("L3377", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", {"unresolved": null}, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a"', '"unresolved"']),
    ("L2569", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": {"a": ["a@1.0.0", "", null, "sha512-g8tIRY2ykq6mNxa6KX1c24mIUo0ACIbke+sbVufFQnmrM5ypDzOfgXi9I5bjSggJj6fgMI8bzPl1HLd+ufWBwg=="]}}', ['"a"', "slot 2"]),
]

# The top-level containers the reader crashed on with a present `null` (`dict()` of `None`,
# `.items()` of `None`), naming no file (T139).
_NULL_CONTAINER_REFUSALS = [
    ("L1901", '{"lockfileVersion": 2, "patchedDependencies": null, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['"patchedDependencies"']),
    ("L1936", '{"lockfileVersion": 2, "overrides": null, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['"overrides"']),
    ("L2039", '{"lockfileVersion": 2, "catalog": null, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['"catalog"']),
    ("L2058", '{"lockfileVersion": 2, "catalogs": null, "workspaces": {"": {"name": "x"}}, "packages": {}}', ['"catalogs"']),
    ("L2313", '{"lockfileVersion": 2, "workspaces": {"": {"name": "x"}}, "packages": null}', ['"packages"']),
]

# Feature 006 T147: integrity digests and git tags Bun 1.4.4's loader refuses, each text one the
# pinned Bun refused with its line's message ("Ignoring lockfile", `tdd-log.md` T147). The digest is
# read as `Integrity::parse` reads it (integrity.rs L88–L164: standard base64 without padding, at
# most the algorithm's length, the bits after the last byte zero; base64/lib.rs L550–L641); the tag
# as `Repository::is_safe_resolved_tag` (repository.rs L107–L123), on every lockfile for a GitHub
# row and from lockfileVersion 2 for a git row, and its length on every lockfile.
_SHA = "0123456789abcdef0123456789abcdef01234567"
_VALID512 = "sha512-" + "A" * 86 + "=="

def _npm_row(integrity, version = 2):
    return '{"lockfileVersion": %d, "workspaces": {"": {"name": "x", "dependencies": {"a": "1.0.0"}}}, "packages": {"a": ["a@1.0.0", "", {}, %s]}}' % (version, json.encode(integrity))

def _git_row(slots, version = 2, github = False):
    spec = "github:o/r#" + _SHA if github else "git+https://example.com/g.git#" + _SHA
    row = json.encode(["g@" + spec, {}] + slots)
    return '{"lockfileVersion": %d, "workspaces": {"": {"name": "x", "dependencies": {"g": %s}}}, "packages": {"g": %s}}' % (version, json.encode(spec), row)

def _tarball_row(slots, version = 2):
    url = "https://example.com/t.tgz"
    row = json.encode(["t@" + url, {}] + slots)
    return '{"lockfileVersion": %d, "workspaces": {"": {"name": "x", "dependencies": {"t": %s}}}, "packages": {"t": %s}}' % (version, json.encode(url), row)

_INTEGRITY_REFUSALS = [
    ("L2650", _npm_row("sha512-AB"), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha512-AAAAA"), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha512-" + "A" * 85 + "!=="), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha512-" + "A" * 85 + "-=="), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha512-" + "A" * 85 + "_=="), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha512-" + "A" * 88), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha512-AA=A"), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha1-" + "a" * 40), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha512-"), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha512-A"), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha512-" + "A" * 85 + "B=="), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha256-" + "A" * 42 + "B="), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2650", _npm_row("sha512-" + "A" * 85 + "!==", version = 3), ['"a"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2733", _git_row([_SHA, "sha512-!!!!"]), ['"g"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2733", _git_row(["o-r-0123456", "md5-AAAA"], github = True), ['"g"', "slot 3", "Unsupported or malformed integrity hash"]),
    ("L2733", _tarball_row(["sha512-!!!!"]), ['"t"', "slot 2", "Unsupported or malformed integrity hash"]),
]

_GIT_TAG_REFUSALS = [
    ("L2674", _git_row([]), ['"g"', "slot 2", "Missing git dependency tag"]),
    ("L2674", _git_row([], version = 1, github = True), ['"g"', "slot 2", "Missing git dependency tag"]),
    ("L2685", _git_row([5]), ['"g"', "slot 2", "Expected a string"]),
    ("L2685", _git_row([None], version = 1), ['"g"', "slot 2", "Expected a string"]),
    ("L2707", _git_row([""]), ['"g"', "slot 2", "Invalid git dependency tag"]),
    ("L2707", _git_row(["-x"]), ['"g"', "slot 2", "Invalid git dependency tag"]),
    ("L2707", _git_row(["a/b"]), ['"g"', "slot 2", "Invalid git dependency tag"]),
    ("L2707", _git_row(["."]), ['"g"', "slot 2", "Invalid git dependency tag"]),
    ("L2707", _git_row([".."]), ['"g"', "slot 2", "Invalid git dependency tag"]),
    ("L2707", _git_row(["a b"]), ['"g"', "slot 2", "Invalid git dependency tag"]),
    ("L2707", _git_row(["a~b"]), ['"g"', "slot 2", "Invalid git dependency tag"]),
    ("L2707", _git_row(["a" * 257]), ['"g"', "slot 2", "Invalid git dependency tag"]),
    ("L2707", _git_row(["a" * 257], version = 1), ['"g"', "slot 2", "Invalid git dependency tag"]),
    ("L2707", _git_row([""], version = 1, github = True), ['"g"', "slot 2", "Invalid git dependency tag"]),
    ("L2707", _git_row(["a/b"], version = 1, github = True), ['"g"', "slot 2", "Invalid git dependency tag"]),
]

# The texts of the same forms the pinned Bun loads (T147).
_ROW_TAIL_ACCEPTED = [
    _npm_row(_VALID512),
    _npm_row("sha256-" + "A" * 43 + "="),
    _npm_row("sha1-" + "A" * 27 + "="),
    _npm_row("sha512-AAAA"),
    _npm_row("sha512-AA"),
    _npm_row("sha512-" + "A" * 86),
    _npm_row("sha512-" + "A" * 86 + "===="),
    _npm_row("sha512-AAAA?x!"),
    _npm_row("sha512-!!!! sha1-" + "A" * 27 + "="),
    _npm_row("sha512-!!!!\tsha256-" + "A" * 43 + "="),
    _npm_row("sha512-!!!!\nsha256-" + "A" * 43 + "="),
    _npm_row("sha512-!!!!\fsha256-" + "A" * 43 + "="),
    _npm_row("sha512-!!!!\rsha256-" + "A" * 43 + "="),
    _npm_row(" " + _VALID512),
    _npm_row(""),
    _npm_row("sha512-" + "A" * 85 + "!==", version = 1),
    _git_row([_SHA]),
    _git_row(["a" * 256]),
    _git_row([".x"]),
    _git_row([_SHA, 5]),
    _git_row([_SHA, _VALID512]),
    _git_row([_SHA, "sha512-!!!!"], version = 1),
    _git_row(["", "md5-AAAA"], version = 1),
    _git_row(["-x"], version = 1),
    _git_row(["a/b"], version = 1),
    _git_row([".."], version = 1),
    _git_row(["o-r-0123456"], github = True),
    _git_row(["o-r-0123456", "md5-AAAA"], version = 1, github = True),
    _tarball_row([]),
    _tarball_row([5]),
    _tarball_row([_VALID512]),
    _tarball_row(["sha512-!!!!"], version = 1),
]

def _load_error(text):
    read = read_lockfile(text, "inline/bun.lock")
    if read.error:
        return read.error
    return resolve(read.value, "inline/bun.lock").error

def _check_refusals(env, cases):
    for line, text, fragments in cases:
        error = _load_error(text) or ""
        asserts.true(env, error.startswith("inline/bun.lock: "), "{} names the label: {}".format(line, error))
        for fragment in fragments:
            asserts.true(env, fragment in error, "{} names {}: {}".format(line, fragment, error))
        asserts.false(env, "SECRET" in error, "{} prints no unchecked value: {}".format(line, error))

def _loader_refusals_test_impl(ctx):
    env = unittest.begin(ctx)
    _check_refusals(env, _LOADER_REFUSALS)
    return unittest.end(env)

def _container_refusals_test_impl(ctx):
    env = unittest.begin(ctx)
    _check_refusals(env, _CONTAINER_REFUSALS)
    return unittest.end(env)

def _null_refusals_test_impl(ctx):
    env = unittest.begin(ctx)
    _check_refusals(env, _NULL_REFUSALS)
    return unittest.end(env)

def _null_container_refusals_test_impl(ctx):
    env = unittest.begin(ctx)
    _check_refusals(env, _NULL_CONTAINER_REFUSALS)
    return unittest.end(env)

def _null_accepted_test_impl(ctx):
    env = unittest.begin(ctx)

    # Bun loads a present `null` where it reads only a value of one type and skips any other: `os`,
    # `cpu` and `libc` (`negatable_from_json_value`, npm.rs L850-L865: no value, so every platform),
    # `bin` and `bundled` (LOCK L2351); the reader reads each as a missing key (T139).
    plain = _read(_inline('"a": ["a@1.0.0", "", {}, "sha512-x"]'))
    for field in ["os", "cpu", "libc", "bin", "bundled"]:
        read = _read(_inline('"a": ["a@1.0.0", "", {"%s": null}, "sha512-x"]' % field))
        asserts.equals(env, plain, read, field)
    return unittest.end(env)

# Feature 006 T144: `bin` values the pinned Bun 1.4.4 loads (`tdd-log.md` T144). Bun reads `bin` with
# `Bin::parse_append` (bin.rs L193-L229): a string that is not empty gives one bin named after the
# package, an object gives its entries (`parse_append_object`, L231-L263), and any other value gives
# none. The reader crashed evaluation on a number, an array or a boolean (`dict(value)`).
_BIN_VALUES = [
    ('"cli.js"', {"a": "cli.js"}),
    ('""', {}),
    ("5", {}),
    ('["cli.js"]', {}),
    ("true", {}),
]

# An object's entry whose value is not a string is skipped, as npm's normalize-package-bin does
# (`parse_append_object`, bin.rs L237-L238); the reader kept it.
_BIN_OBJECTS = [
    ("{}", {}),
    ('{"p": 5}', {}),
    ('{"p": "cli.js", "q": 5}', {"p": "cli.js"}),
    ('{"p": "cli.js", "q": "x.js", "r": ["x.js"]}', {"p": "cli.js", "q": "x.js"}),
    ('{"p": "cli.js", "q": null}', {"p": "cli.js"}),
]

def _check_bins(env, cases):
    for value, expected in cases:
        read = _read(_inline('"a": ["a@1.0.0", "", {"bin": %s}, "sha512-x"]' % value))
        asserts.equals(env, None, read["error"], value)
        asserts.equals(env, expected, read["value"]["entries"]["a"]["bin"], value)

def _bin_values_test_impl(ctx):
    env = unittest.begin(ctx)
    _check_bins(env, _BIN_VALUES)
    return unittest.end(env)

def _bin_objects_test_impl(ctx):
    env = unittest.begin(ctx)
    _check_bins(env, _BIN_OBJECTS)
    return unittest.end(env)

def _integrity_refusals_test_impl(ctx):
    env = unittest.begin(ctx)
    _check_refusals(env, _INTEGRITY_REFUSALS)
    return unittest.end(env)

def _git_tag_refusals_test_impl(ctx):
    env = unittest.begin(ctx)
    _check_refusals(env, _GIT_TAG_REFUSALS)
    return unittest.end(env)

def _row_tail_accepted_test_impl(ctx):
    env = unittest.begin(ctx)
    for text in _ROW_TAIL_ACCEPTED:
        asserts.equals(env, None, _load_error(text), text)
    return unittest.end(env)

versions_test = unittest.make(_versions_test_impl)
config_version_test = unittest.make(_config_version_test_impl)
invalid_test = unittest.make(_invalid_test_impl)
workspaces_test = unittest.make(_workspaces_test_impl)
entries_test = unittest.make(_entries_test_impl)
kinds_test = unittest.make(_kinds_test_impl)
scoped_keys_test = unittest.make(_scoped_keys_test_impl)
bad_slot_test = unittest.make(_bad_slot_test_impl)
extra_slots_test = unittest.make(_extra_slots_test_impl)
unsupported_test = unittest.make(_unsupported_test_impl)
unresolved_test = unittest.make(_unresolved_test_impl)
bundled_test = unittest.make(_bundled_test_impl)
workspace_fields_test = unittest.make(_workspace_fields_test_impl)
row_fields_test = unittest.make(_row_fields_test_impl)
dependency_maps_test = unittest.make(_dependency_maps_test_impl)
loader_refusals_test = unittest.make(_loader_refusals_test_impl)
container_refusals_test = unittest.make(_container_refusals_test_impl)
null_refusals_test = unittest.make(_null_refusals_test_impl)
null_container_refusals_test = unittest.make(_null_container_refusals_test_impl)

null_accepted_test = unittest.make(_null_accepted_test_impl)
bin_values_test = unittest.make(_bin_values_test_impl)
bin_objects_test = unittest.make(_bin_objects_test_impl)
integrity_refusals_test = unittest.make(_integrity_refusals_test_impl)
git_tag_refusals_test = unittest.make(_git_tag_refusals_test_impl)
row_tail_accepted_test = unittest.make(_row_tail_accepted_test_impl)

def lockfile_test_suite(name):
    unittest.suite(
        name,
        versions_test,
        config_version_test,
        invalid_test,
        workspaces_test,
        entries_test,
        kinds_test,
        scoped_keys_test,
        bad_slot_test,
        extra_slots_test,
        unsupported_test,
        unresolved_test,
        bundled_test,
        workspace_fields_test,
        row_fields_test,
        dependency_maps_test,
        loader_refusals_test,
        container_refusals_test,
        null_refusals_test,
        null_container_refusals_test,
        null_accepted_test,
        bin_values_test,
        bin_objects_test,
        integrity_refusals_test,
        git_tag_refusals_test,
        row_tail_accepted_test,
    )
