"""Unit tests of the `glob` pattern matcher of `//bun/private:npm_repositories.bzl` (FR-033)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:npm_repositories.bzl", "glob_matches")

# (pattern, path, matches), from the `glob` documentation's wildcard rules.
_CASES = [
    ("file with space.js", "file with space.js", True),
    ("sub/BUILD.bazel", "sub/BUILD.bazel", True),
    ("sub/BUILD.bazel", "BUILD.bazel", False),
    ("*.js", "a:b.js", True),
    ("*.js", "sub/a.js", False),
    ("a*b*c", "aXbYc", True),
    ("a*b*c", "aXbY", False),
    ("**", "x/y/z.js", True),
    ("**/BUILD", "BUILD", True),
    ("**/BUILD", "x/y/BUILD", True),
    ("docs/**", "docs/a/b.md", True),
    ("docs/**", "other/a.md", False),
    ("x/**/y", "x/y", True),
    ("x/**/y", "x/a/b/y", True),
    # A hidden file: `*` and `**` match it, a compound pattern only when it starts with `.`.
    ("*", ".hidden", True),
    ("*.txt", ".a.txt", False),
    (".*.txt", ".a.txt", True),
    ("**", ".a/.b", True),
]

def _glob_test_impl(ctx):
    env = unittest.begin(ctx)
    for pattern, path, expected in _CASES:
        asserts.equals(env, expected, glob_matches(pattern, path), "{} against {}".format(pattern, path))
    return unittest.end(env)

glob_test = unittest.make(_glob_test_impl)

def glob_test_suite(name):
    unittest.suite(name, glob_test)
