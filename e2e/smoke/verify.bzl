"""Rule that runs the registered Bun toolchain to check rules_bun as an external module."""

load("@rules_bun//bun:defs.bzl", "BUN_TOOLCHAIN_TYPE")

_WRITE_VERSION = "await Bun.write(Bun.argv[Bun.argv.length - 1], Bun.version + \"\\n\")"

def _impl(ctx):
    bun = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo.bun
    out = ctx.actions.declare_file(ctx.label.name + ".txt")

    args = ctx.actions.args()
    args.add("-e", _WRITE_VERSION)
    args.add(out)

    ctx.actions.run(
        executable = bun,
        arguments = [args],
        outputs = [out],
        tools = [bun],
        mnemonic = "BunVersion",
        progress_message = "Bun 버전 확인 중 %{label}",
    )
    return [DefaultInfo(files = depset([out]))]

verify_toolchain = rule(
    implementation = _impl,
    toolchains = [BUN_TOOLCHAIN_TYPE],
)
