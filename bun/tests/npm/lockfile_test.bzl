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

    # Research Part 3 lists no slot after slot 0 of a `file:` or tarball-URL entry, so none is read.
    unread = _read(_inline(
        '"local": ["local@file:local", {"dependencies": {"b": "1.0.0"}}], ' +
        '"tb": ["b@http://example.com/b.tgz", {"dependencies": {"b": "1.0.0"}}, "sha512-x"]',
    ))["value"]["entries"]
    for key in ["local", "tb"]:
        asserts.equals(env, {}, unread[key]["dependencies"], key)
        asserts.equals(env, "", unread[key]["integrity"], key)

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

versions_test = unittest.make(_versions_test_impl)
config_version_test = unittest.make(_config_version_test_impl)
invalid_test = unittest.make(_invalid_test_impl)
workspaces_test = unittest.make(_workspaces_test_impl)
entries_test = unittest.make(_entries_test_impl)
kinds_test = unittest.make(_kinds_test_impl)
scoped_keys_test = unittest.make(_scoped_keys_test_impl)
bad_slot_test = unittest.make(_bad_slot_test_impl)
unsupported_test = unittest.make(_unsupported_test_impl)

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
        unsupported_test,
    )
