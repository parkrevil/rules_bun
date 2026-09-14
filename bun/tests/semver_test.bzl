"""Unit tests for `//bun/private:semver.bzl`."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:semver.bzl", "max_version", "version_key")

def _ordering_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "1.10.0", max_version(["1.4.2", "1.10.0"]))
    asserts.equals(env, "1.10.0", max_version(["1.10.0", "1.4.2"]))
    asserts.equals(env, "2.0.0", max_version(["2.0.0", "1.99.99"]))
    asserts.equals(env, "1.4.10", max_version(["1.4.2", "1.4.10"]))

    asserts.equals(env, "1.4", max_version(["1.4", "1.3.9"]))
    asserts.equals(env, "1.4.2.1", max_version(["1.4.2", "1.4.2.1"]))

    asserts.equals(env, "1.4.2", max_version(["1.4.2"]))

    return unittest.end(env)

def _prerelease_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "1.4.2", max_version(["1.4.2-canary.1", "1.4.2"]))
    asserts.equals(env, "1.4.2", max_version(["1.4.2", "1.4.2-canary.1"]))

    asserts.equals(env, "1.4.2-canary.2", max_version(["1.4.2-canary.2", "1.4.2-canary.1"]))
    asserts.equals(env, "1.4.2-canary.2", max_version(["1.4.2-canary.1", "1.4.2-canary.2"]))

    asserts.equals(env, "1.5.0-canary.1", max_version(["1.4.2", "1.5.0-canary.1"]))

    return unittest.end(env)

def _key_shape_test_impl(ctx):
    env = unittest.begin(ctx)

    release, is_stable, prerelease = version_key("1.4.2")
    asserts.equals(env, [1, 4, 2, 0], release)
    asserts.equals(env, 1, is_stable)
    asserts.equals(env, "", prerelease)

    release, is_stable, prerelease = version_key("1.4.2-canary.7")
    asserts.equals(env, [1, 4, 2, 0], release)
    asserts.equals(env, 0, is_stable)
    asserts.equals(env, "canary.7", prerelease)

    return unittest.end(env)

ordering_test = unittest.make(_ordering_test_impl)
prerelease_test = unittest.make(_prerelease_test_impl)
key_shape_test = unittest.make(_key_shape_test_impl)

def semver_test_suite(name):
    unittest.suite(
        name,
        ordering_test,
        prerelease_test,
        key_shape_test,
    )
