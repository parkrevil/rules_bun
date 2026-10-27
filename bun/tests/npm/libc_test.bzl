"""Unit tests of npm's `libc` rule as the hub applies it (feature 004 research R11, FR-013)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:npm_repositories.bzl", "libc_matches")

def _libc_matches_test_impl(ctx):
    env = unittest.begin(ctx)

    # No `libc`: every platform.
    asserts.true(env, libc_matches([], "linux", "musl"))
    asserts.true(env, libc_matches([], "darwin", None))

    # npm defines libc only on Linux.
    asserts.false(env, libc_matches(["glibc"], "darwin", None))
    asserts.false(env, libc_matches(["glibc"], "win32", None))
    asserts.false(env, libc_matches(["glibc"], None, None))

    # A Linux platform without the libc constraint carries every variant.
    asserts.true(env, libc_matches(["glibc"], "linux", None))
    asserts.true(env, libc_matches(["musl"], "linux", None))

    # npm-install-checks `checkList`: a listed value, a `!` value, `any`.
    asserts.true(env, libc_matches(["glibc"], "linux", "glibc"))
    asserts.false(env, libc_matches(["glibc"], "linux", "musl"))
    asserts.true(env, libc_matches(["!musl"], "linux", "glibc"))
    asserts.false(env, libc_matches(["!musl"], "linux", "musl"))
    asserts.true(env, libc_matches(["any"], "linux", "musl"))
    asserts.true(env, libc_matches(["glibc", "musl"], "linux", "musl"))
    return unittest.end(env)

_libc_matches_test = unittest.make(_libc_matches_test_impl)

def libc_test_suite(name):
    """Checks npm's `libc` rule.

    Args:
        name: Name of the test suite.
    """
    unittest.suite(name, _libc_matches_test)
