"""Unit tests for `//bun/private:versions.bzl`."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:platforms.bzl", "BUN_ARCHIVES")
load("//bun/private:versions.bzl", "TOOL_VERSIONS")

def _platforms_test_impl(ctx):
    env = unittest.begin(ctx)

    # Written out by hand, so that a platform missing from the table fails too (FR-005).
    platforms = ["darwin-aarch64", "darwin-x64", "linux-aarch64", "linux-aarch64-musl", "linux-x64", "linux-x64-musl", "windows-x64"]
    asserts.equals(env, platforms, sorted(BUN_ARCHIVES), "BUN_ARCHIVES does not list every Bun release archive")
    for version, integrity in TOOL_VERSIONS.items():
        asserts.equals(
            env,
            platforms,
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

def _known_versions_test_impl(ctx):
    env = unittest.begin(ctx)

    for version in ["1.4.2", "1.4.4"]:
        asserts.true(
            env,
            version in TOOL_VERSIONS,
            "Bun {} is not a known version".format(version),
        )

    # The 1.4.2 entry stays as feature 001 recorded it from 1.4.2's SHASUMS256.txt (feature 004
    # FR-003), plus the musl archives converted from the same file (feature 005 research E1); no
    # test fetches 1.4.2 any more (research G3).
    asserts.equals(
        env,
        {
            "darwin-aarch64": "sha256-kJh6OhbX21VtiGrD1VHnttPt8KHPQ6yu1iLoZ2vh0S8=",
            "darwin-x64": "sha256-gFINfhdSYwjJGF0mFnmsbSd5jTgDoOn3/5Ehq4r/sBI=",
            "linux-aarch64": "sha256-VDKLvC2cjgyfiSxUTWbFeoO4QTnjSQnl7oF1jxrI/ac=",
            "linux-aarch64-musl": "sha256-cXYLbI6jBiO4GkkHy4FdSOLqJm8uc+dRU0pEoGB5UN8=",
            "linux-x64": "sha256-NjaPrvdSeHXV/6UuU81IAhdB8qg+tiCKjdZAaNQiqRM=",
            "linux-x64-musl": "sha256-SDXspZ1tpw9GdPVkL25Fncrat3NpWy7Zki0TEFeYl0I=",
            "windows-x64": "sha256-zkwXSXsvKXEqmdPVPwKN4ozULjusuFiVmefwAOSbZAU=",
        },
        TOOL_VERSIONS["1.4.2"],
    )

    return unittest.end(env)

platforms_test = unittest.make(_platforms_test_impl)
integrity_format_test = unittest.make(_integrity_format_test_impl)
known_versions_test = unittest.make(_known_versions_test_impl)

def versions_test_suite(name):
    """Checks the known Bun versions and their integrity for exactly the supported platforms.

    Args:
        name: Name of the test suite.
    """
    unittest.suite(name, platforms_test, integrity_format_test, known_versions_test)
