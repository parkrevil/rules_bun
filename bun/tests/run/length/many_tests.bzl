"""Test-only rule that writes many passing test files with long names."""

def _many_tests_impl(ctx):
    files = []
    for i in range(ctx.attr.count):
        # A 90-character base name: "t", a 3-digit index, "_" and padding.
        name = "t{}_{}".format(str(i + 1000)[1:], "x" * 85)
        f = ctx.actions.declare_file("{}/{}.test.ts".format(ctx.label.name, name))
        ctx.actions.write(f, 'import { test } from "bun:test";\ntest("passes", () => {});\n')
        files.append(f)
    return [DefaultInfo(files = depset(files))]

many_tests = rule(
    implementation = _many_tests_impl,
    doc = "Writes `count` passing test files, each with a 90-character base name.",
    attrs = {
        "count": attr.int(
            doc = "Number of test files.",
            mandatory = True,
        ),
    },
)
