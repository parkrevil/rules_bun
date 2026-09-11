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
    attrs = {
        "bun": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "version": attr.string(mandatory = True),
    },
)
