"""Unit tests for `//bun/private:versions.bzl`."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:toolchains_repo.bzl", "PLATFORMS")
load("//bun/private:versions.bzl", "TOOL_VERSIONS")

def _platforms_test_impl(ctx):
    env = unittest.begin(ctx)

    for version, integrity in TOOL_VERSIONS.items():
        asserts.equals(
            env,
            sorted(PLATFORMS.keys()),
            sorted(integrity.keys()),
            "The integrity entries of Bun {} do not match the supported platforms exactly".format(version),
        )

    return unittest.end(env)

def _integrity_format_test_impl(ctx):
    env = unittest.begin(ctx)

    for version, integrity in TOOL_VERSIONS.items():
        for platform, value in integrity.items():
            asserts.true(
                env,
                value.startswith("sha256-"),
                "The integrity of Bun {} {} does not start with sha256-".format(version, platform),
            )

    return unittest.end(env)

platforms_test = unittest.make(_platforms_test_impl)
integrity_format_test = unittest.make(_integrity_format_test_impl)

def versions_test_suite(name):
    """Checks that every known Bun version has an integrity for exactly the supported platforms.

    Args:
        name: Name of the test suite.
    """
    unittest.suite(name, platforms_test, integrity_format_test)
