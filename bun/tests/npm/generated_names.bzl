"""The names of the targets `npm_link_all_packages` declares in a package (feature 006 T111, SC-005)."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

def _names_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, ctx.attr.expected, ctx.attr.names, "the targets npm_link_all_packages declares")
    asserts.equals(env, ctx.attr.expected_incompatible, ctx.attr.incompatible, "the targets incompatible with every platform")
    return unittest.end(env)

_names_test = unittest.make(
    _names_test_impl,
    attrs = {
        "expected": attr.string_list(),
        "expected_incompatible": attr.string_list(),
        "incompatible": attr.string_list(),
        "names": attr.string_list(),
    },
)

def generated_names_test(name, expected, expected_incompatible = []):
    """Checks the `node_modules/...` targets declared so far in this package.

    Call it after `npm_link_all_packages()`. A target whose `target_compatible_with` is
    `@platforms//:incompatible` on every platform (not a `select()`) is listed as incompatible.

    Args:
        name: Name of the test.
        expected: The expected target names.
        expected_incompatible: The expected names of the targets incompatible with every platform.
    """
    incompatible = str(Label("@platforms//:incompatible"))
    names = []
    never = []
    for target, rule in native.existing_rules().items():
        if not target.startswith("node_modules/"):
            continue
        names.append(target)
        compatible = rule.get("target_compatible_with")
        if type(compatible) in ("list", "tuple") and [str(c) for c in compatible] == [incompatible]:
            never.append(target)
    _names_test(
        name = name,
        names = sorted(names),
        expected = sorted(expected),
        incompatible = sorted(never),
        expected_incompatible = sorted(expected_incompatible),
    )
