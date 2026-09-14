"""Public API for rules_bun.

Rules that run Bun declare `BUN_TOOLCHAIN_TYPE` in `toolchains` and read the
executable from `ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo`, a `BunInfo`.
"""

load("//bun/private:providers.bzl", _BunInfo = "BunInfo")

BUN_TOOLCHAIN_TYPE = Label("//bun/toolchain:execution_type")

BunInfo = _BunInfo
