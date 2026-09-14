"""Toolchain rule that provides a Bun executable."""

load("//bun/private:providers.bzl", "BunInfo")

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
    ]

bun_toolchain = rule(
    implementation = _bun_toolchain_impl,
    doc = "Defines a Bun toolchain. Its `ToolchainInfo` has a `buninfo` field holding `BunInfo`.",
    attrs = {
        "bun": attr.label(
            doc = "The Bun executable.",
            mandatory = True,
            allow_single_file = True,
        ),
        "version": attr.string(
            doc = "Bun version of the executable.",
            mandatory = True,
        ),
    },
)
