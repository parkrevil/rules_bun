"""Unit tests of the generated-target naming rule (FR-012, FR-018, contracts/public-api.md)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:lockfile.bzl", "read_lockfile")
load("//bun/private:npm_names.bzl", "bin_targets", "target_name")

def _target_name_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, "run_tool", target_name("run tool"))
    asserts.equals(env, "run_tool2", target_name("run:tool2"))
    asserts.equals(env, "@scope/s", target_name("@scope/s"))
    asserts.equals(env, "a.b-c_d~e!f(g)'*", target_name("a.b-c_d~e!f(g)'*"))
    asserts.equals(env, "_x_", target_name("\tx\\"))
    return unittest.end(env)

def _bins_test_impl(ctx):
    env = unittest.begin(ctx)
    result = bin_targets("weird-bin@1.0.0", {"run tool": "a.js", "run:tool2": "b.js"})
    asserts.equals(env, None, result.error)
    asserts.equals(env, {"run_tool": "a.js", "run_tool2": "b.js"}, result.value)

    # A string bin is named after the package without its scope (the reader writes it so).
    lock = read_lockfile(json.encode({
        "lockfileVersion": 2,
        "workspaces": {"": {"name": "inline", "dependencies": {"@scope/tool": "1.0.0"}}},
        "packages": {"@scope/tool": ["@scope/tool@1.0.0", "", {"bin": "cli.js"}, "sha512-AAAA"]},
    }), "inline/bun.lock")
    asserts.equals(env, None, lock.error)
    result = bin_targets("@scope/tool@1.0.0", lock.value.entries["@scope/tool"].bin)
    asserts.equals(env, {"tool": "cli.js"}, result.value)
    return unittest.end(env)

def _collision_test_impl(ctx):
    env = unittest.begin(ctx)
    result = bin_targets("clash@1.0.0", {"a b": "x.js", "a:b": "y.js"})
    asserts.equals(env, None, result.value)
    for part in ["clash@1.0.0", '"a b"', '"a:b"', '"a_b"']:
        asserts.true(env, part in (result.error or ""), "{} in {}".format(part, result.error))
    return unittest.end(env)

target_name_test = unittest.make(_target_name_test_impl)
bins_test = unittest.make(_bins_test_impl)
collision_test = unittest.make(_collision_test_impl)

def naming_test_suite(name):
    unittest.suite(name, target_name_test, bins_test, collision_test)
