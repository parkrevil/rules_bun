"""Public API for rules_bun.

Rules that run Bun declare `BUN_TOOLCHAIN_TYPE` in `toolchains` and read the
executable from `ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo`, a `BunInfo`.
Every action that runs Bun passes `toolchain = BUN_TOOLCHAIN_TYPE`, so it runs on
the execution platform the toolchain was resolved for:

    load("@rules_bun//bun:defs.bzl", "BUN_TOOLCHAIN_TYPE")

    def _impl(ctx):
        buninfo = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo
        ctx.actions.run(
            executable = buninfo.bun,
            tools = buninfo.tool_files,
            toolchain = BUN_TOOLCHAIN_TYPE,
            ...
        )

    my_rule = rule(implementation = _impl, toolchains = [BUN_TOOLCHAIN_TYPE])
"""

load("//bun/private:providers.bzl", _BunInfo = "BunInfo")

BUN_TOOLCHAIN_TYPE = Label("//bun/toolchain:execution_type")

BunInfo = _BunInfo
