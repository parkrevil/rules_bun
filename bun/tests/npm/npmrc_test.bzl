"""Unit tests of `//bun/private:npmrc.bzl` (research R11, FR-019, FR-020)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:npmrc.bzl", "has_credentials", "has_userinfo", "package_url", "read_npmrc")

_NPMRC = """\
# a comment
; another comment

registry = https://mirror.example/npm/
@scope:registry=https://scoped.example/
//mirror.example/npm/:_authToken=SECRET-TOKEN
_auth=SECRET-AUTH
_authToken=SECRET-TOKEN-2
_password=SECRET-PASSWORD
username=SECRET-USER
certfile=/secret/cert.pem
keyfile=/secret/key.pem
save-exact=true
"""

def _read_test_impl(ctx):
    env = unittest.begin(ctx)
    result = read_npmrc(_NPMRC, "//:.npmrc")
    asserts.equals(env, None, result.error)
    asserts.equals(env, "https://mirror.example/npm/", result.value.registry)
    asserts.equals(env, {"@scope": "https://scoped.example/"}, result.value.scopes)

    # Nothing credential-related is kept (FR-020).
    text = repr(result.value)
    for secret in ["SECRET", "/secret/"]:
        asserts.false(env, secret in text, "{} kept in {}".format(secret, text))

    empty = read_npmrc("", "//:.npmrc")
    asserts.equals(env, None, empty.value.registry)
    asserts.equals(env, {}, empty.value.scopes)
    return unittest.end(env)

def _url_test_impl(ctx):
    env = unittest.begin(ctx)
    npmrc = read_npmrc(_NPMRC, "//:.npmrc").value
    asserts.equals(env, "https://scoped.example/@scope/s/-/s-1.0.0.tgz", package_url(npmrc, "@scope/s", "1.0.0", ""))
    asserts.equals(env, "https://mirror.example/npm/a/-/a-1.0.0.tgz", package_url(npmrc, "a", "1.0.0", ""))
    asserts.equals(env, "https://mirror.example/npm/@other/o/-/o-2.0.0.tgz", package_url(npmrc, "@other/o", "2.0.0", ""))
    asserts.equals(env, "http://full.example/a.tgz", package_url(npmrc, "a", "1.0.0", "http://full.example/a.tgz"))

    none = read_npmrc("", "//:.npmrc").value
    asserts.equals(env, "https://registry.npmjs.org/a/-/a-1.0.0.tgz", package_url(none, "a", "1.0.0", ""))
    asserts.equals(env, "https://registry.npmjs.org/@scope/s/-/s-1.0.0.tgz", package_url(None, "@scope/s", "1.0.0", ""))
    return unittest.end(env)

def _userinfo_test_impl(ctx):
    env = unittest.begin(ctx)
    cases = {
        "registry": "registry=https://user:SECRET-TOKEN@mirror.example/npm/\n",
        "@scope:registry": "registry=https://mirror.example/\n@scope:registry = https://SECRET-TOKEN@scoped.example/\n",
    }
    for key, text in cases.items():
        result = read_npmrc(text, "//:.npmrc")
        asserts.equals(env, None, result.value)
        asserts.equals(
            env,
            "//:.npmrc: the {} URL holds user information (credentials before an @); give credentials through Bazel's downloader (--credential_helper or .netrc) instead".format(key),
            result.error,
        )
        asserts.false(env, "SECRET" in (result.error or ""), "the credential is echoed: {}".format(result.error))

    # An @ after the host belongs to the path, not to the user information.
    path = read_npmrc("registry=https://mirror.example/npm/@scope/\n", "//:.npmrc")
    asserts.equals(env, None, path.error)
    return unittest.end(env)

def _has_userinfo_test_impl(ctx):
    env = unittest.begin(ctx)

    # The authority (after `://`, before `/`, `?` or `#`) holds an @; an empty user counts (spec
    # Edge Cases).
    for url in [
        "https://user:token@host/x",
        "https://@host/x",
        "https://user@host",
        "git+https://user:token@host/r.git",
    ]:
        asserts.true(env, has_userinfo(url), "{} holds user information".format(url))

    # An @ after the authority belongs to the path, query or fragment.
    for url in [
        "https://host/a@1.0.0.tgz",
        "https://host?x=a@b",
        "https://host#a@b",
        "https://host:8080/x",
    ]:
        asserts.false(env, has_userinfo(url), "{} holds no user information".format(url))
    return unittest.end(env)

def _has_credentials_test_impl(ctx):
    env = unittest.begin(ctx)

    # Any user information of an http(s) URL may be a token; a password is a secret in any scheme.
    for url in [
        "https://user:token@host/x",
        "https://token@host/x",
        "https://@host/x",
        "git+https://user:token@host/r.git",
        "git+ssh://git:secret@host/r.git",
        # A URL after a package name, as slot 0 and override selectors write it.
        "a@https://user:token@host/a.tgz",
    ]:
        asserts.true(env, has_credentials(url), "{} holds credentials".format(url))

    # An SSH user name is an identity; SSH authenticates with keys (feature 005, P1).
    for url in [
        "git+ssh://git@github.com/o/r.git",
        "ssh://git@host/r.git",
        "https://host/a@1.0.0.tgz",
        "git+ssh://host/r.git",
        "g@git+ssh://git@host/r.git#abc",
    ]:
        asserts.false(env, has_credentials(url), "{} holds no credentials".format(url))
    return unittest.end(env)

has_credentials_test = unittest.make(_has_credentials_test_impl)
read_test = unittest.make(_read_test_impl)
has_userinfo_test = unittest.make(_has_userinfo_test_impl)
url_test = unittest.make(_url_test_impl)
userinfo_test = unittest.make(_userinfo_test_impl)

def npmrc_test_suite(name):
    unittest.suite(name, read_test, url_test, userinfo_test, has_userinfo_test, has_credentials_test)
