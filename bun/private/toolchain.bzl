"""Implementation of the `bun_toolchain` rule."""

load(":providers.bzl", "BunInfo")

def _bun_toolchain_impl(ctx):
    bun = ctx.file.bun
    tool_files = [bun]

    default = DefaultInfo(
        files = depset(tool_files),
        runfiles = ctx.runfiles(files = tool_files),
    )

    return [
        default,
        platform_common.ToolchainInfo(
            buninfo = BunInfo(
                bun = bun,
                version = ctx.attr.version,
                tool_files = tool_files,
            ),
        ),
        platform_common.TemplateVariableInfo({"BUN_BIN": bun.path}),
    ]

bun_toolchain = rule(
    implementation = _bun_toolchain_impl,
    doc = """\
Defines a Bun toolchain. Its `ToolchainInfo` has a `buninfo` field holding `BunInfo`.

It also provides the Make variable `BUN_BIN`, the path of Bun relative to the
execution root. A genrule that lists `@rules_bun//bun/toolchain:execution_type`
in `toolchains` can write `$(BUN_BIN)` in `cmd`. Only this expansion is
promised: Bazel does not document that the toolchain's files become inputs of
the genrule, so running Bun from a genrule this way is not verified.
""",
    attrs = {
        "bun": attr.label(
            doc = "The Bun executable.",
            mandatory = True,
            allow_single_file = True,
            cfg = "exec",
        ),
        "version": attr.string(
            doc = "Bun version of the executable.",
            mandatory = True,
        ),
    },
)

def _bun_target_toolchain_impl(ctx):
    bun = ctx.file.bun
    tool_files = [bun]

    return [
        DefaultInfo(
            files = depset(tool_files),
            runfiles = ctx.runfiles(files = tool_files),
        ),
        platform_common.ToolchainInfo(
            buninfo = BunInfo(
                bun = bun,
                version = ctx.attr.version,
                tool_files = tool_files,
            ),
        ),
    ]

bun_target_toolchain = rule(
    implementation = _bun_target_toolchain_impl,
    doc = """\
Defines a Bun toolchain for `@rules_bun//bun/toolchain:target_type`, the Bun that
`bun_binary` and `bun_test` run on the target platform. Its `ToolchainInfo` has a
`buninfo` field holding `BunInfo`. Register it with a `toolchain()` whose
`target_compatible_with` names the platform the Bun runs on:

    bun_target_toolchain(name = "my_bun", bun = "@my_bun//:bun", version = "1.4.4")

    toolchain(
        name = "my_bun_toolchain",
        target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64"],
        toolchain = ":my_bun",
        toolchain_type = "@rules_bun//bun/toolchain:target_type",
    )
""",
    attrs = {
        "bun": attr.label(
            doc = "The Bun executable, built for the target platform.",
            mandatory = True,
            allow_single_file = True,
        ),
        "version": attr.string(
            doc = "Bun version of the executable.",
            mandatory = True,
        ),
    },
)
