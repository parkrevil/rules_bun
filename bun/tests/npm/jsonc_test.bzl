"""Unit tests for `//bun/private:jsonc.bzl` (FR-007, research L1)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:jsonc.bzl", "jsonc_decode")

def _decoded(env, text):
    result = jsonc_decode(text, "bun.lock")
    asserts.equals(env, None, result.error)
    return result.value

def _comments_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, {"a": 1}, _decoded(env, '// leading\n{"a": 1} // trailing'))
    asserts.equals(env, {"a": 1, "b": 2}, _decoded(env, '{"a": 1, /* inline */ "b": 2}'))
    asserts.equals(env, {"a": [1, 2]}, _decoded(env, '{"a": [1, /* a\nmultiline\ncomment */ 2]}'))
    asserts.equals(env, [], _decoded(env, "[] // no newline at the end"))
    return unittest.end(env)

def _trailing_commas_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, {"a": 1}, _decoded(env, '{"a": 1,}'))
    asserts.equals(env, {"a": [1, 2]}, _decoded(env, '{"a": [1, 2,],}'))
    asserts.equals(env, {"a": {"b": []}}, _decoded(env, '{\n  "a": {\n    "b": [\n    ],\n  },\n}\n'))
    asserts.equals(env, [1], _decoded(env, "[1, // comment after the comma\n]"))
    return unittest.end(env)

def _strings_kept_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, {"u": "http://x/y // z"}, _decoded(env, '{"u": "http://x/y // z"}'))
    asserts.equals(env, ["/* not a comment */"], _decoded(env, '["/* not a comment */"]'))
    asserts.equals(env, [",}", ",]"], _decoded(env, '[",}", ",]"]'))
    return unittest.end(env)

def _escapes_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, ['a " // still a string'], _decoded(env, '["a \\" // still a string"]'))
    asserts.equals(env, ["back\\", 1], _decoded(env, '["back\\\\", // comment\n 1]'))
    asserts.equals(env, ['\\"'], _decoded(env, '["\\\\\\""]'))
    return unittest.end(env)

def _errors_test_impl(ctx):
    env = unittest.begin(ctx)
    for text in ['{"a": 1 /* never closed', '{"a": "never closed}', "{not json}"]:
        result = jsonc_decode(text, "some/dir/bun.lock")
        asserts.equals(env, None, result.value)
        asserts.true(env, result.error != None and "some/dir/bun.lock" in result.error, "error names the file: {}".format(result.error))
    return unittest.end(env)

comments_test = unittest.make(_comments_test_impl)
trailing_commas_test = unittest.make(_trailing_commas_test_impl)
strings_kept_test = unittest.make(_strings_kept_test_impl)
escapes_test = unittest.make(_escapes_test_impl)
errors_test = unittest.make(_errors_test_impl)

def jsonc_test_suite(name):
    unittest.suite(
        name,
        comments_test,
        trailing_commas_test,
        strings_kept_test,
        escapes_test,
        errors_test,
    )
