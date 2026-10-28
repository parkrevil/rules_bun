"""Unit tests of URL recognition and credentials (feature 005 P1, RFC 3986)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:urls.bzl", "has_credentials", "is_download_url")

def _has_credentials_test_impl(ctx):
    env = unittest.begin(ctx)
    for text in [
        "https://user:token@host/x",
        "https://token@host/x",
        "https://@host/x",
        "git+https://user:token@host/r.git",
        "git+ssh://git:secret@host/r.git",
        # A URL after a package name, as slot 0 and override selectors write it.
        "a@https://user:token@host/a.tgz",
        # Every URL of a text is checked, not only the first.
        "https://safe/x https://u:SECRET@host/a",
        "https://safe/?next=https://u:SECRET@host/a",
    ]:
        asserts.true(env, has_credentials(text), text)
    for text in [
        # An SSH user name is an identity; SSH authenticates with keys.
        "git+ssh://git@github.com/o/r.git",
        "g@git+ssh://git@host/r.git#abc",
        "ssh://git@host/r.git",
        "https://host/a@1.0.0.tgz",
        "https://host?x=a@b",
        # Not a URL: no scheme before ://, or prose.
        "literal :// contact alice@example.com",
        "u:SECRET@host/a",
        "1.0.0",
    ]:
        asserts.false(env, has_credentials(text), text)
    return unittest.end(env)

def _is_download_url_test_impl(ctx):
    env = unittest.begin(ctx)
    for text in [
        "https://registry.npmjs.org/a/-/a-1.0.0.tgz",
        "http://127.0.0.1:4873/a/-/a-1.0.0.tgz",
        # RFC 3986 3.1: the scheme is case-insensitive.
        "HTTPS://registry.npmjs.org/a",
        "Http://host:8080/@scope%2fs/-/s-1.0.0.tgz",
        "https://[::1]:4873/a.tgz",
        "https://host",
    ]:
        asserts.true(env, is_download_url(text), text)
    for text in [
        "u:SECRET@host/a",
        "https://u:SECRET@host/a",
        "https://@host/a",
        "git+https://host/r.git",
        "https:///a",
        "https://host/a b",
        "ftp://host/a",
        "",
        # RFC 3986 3.2.2, 3.2.3, 2.1: a host, digits for a port, two hex digits after %.
        "https://:443/a.tgz",
        "https://host:abc/a.tgz",
        "https://host/%zz",
        "https://ho st/a",
    ]:
        asserts.false(env, is_download_url(text), text)
    return unittest.end(env)

has_credentials_test = unittest.make(_has_credentials_test_impl)
is_download_url_test = unittest.make(_is_download_url_test_impl)

def urls_test_suite(name):
    """Checks URL recognition.

    Args:
        name: Name of the test suite.
    """
    unittest.suite(name, has_credentials_test, is_download_url_test)
