"""Unit tests of the Subresource Integrity check of `bun.toolchain` integrity values (feature 005)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:sri.bzl", "is_sri")

def _is_sri_test_impl(ctx):
    env = unittest.begin(ctx)

    # The digest is the canonical standard base64 of exactly the algorithm's digest length
    # (W3C Subresource Integrity; Bazel's `integrity` attributes take this form).
    for value in [
        "sha256-NjaPrvdSeHXV/6UuU81IAhdB8qg+tiCKjdZAaNQiqRM=",
        "sha384-" + "A" * 64,
        "sha512-" + "A" * 86 + "==",
    ]:
        asserts.true(env, is_sri(value), value)

    for value in [
        "abc",
        "sha256-",
        "sha256-=",
        "sha512-A",
        "sha256-A=A",
        "md5-" + "A" * 22 + "==",
        "sha256-" + "A" * 44,  # 44 characters but no padding: 33 bytes
        "sha256-" + "A" * 42 + "B=",  # non-zero bits after the 32nd byte
        "sha512-" + "A" * 85 + "B==",
        "sha256-" + "A" * 43 + "!",
    ]:
        asserts.false(env, is_sri(value), value)
    return unittest.end(env)

is_sri_test = unittest.make(_is_sri_test_impl)

def sri_test_suite(name):
    """Checks `is_sri`.

    Args:
        name: Name of the test suite.
    """
    unittest.suite(name, is_sri_test)
