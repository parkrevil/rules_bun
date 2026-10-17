"""Test-only rule for a toolchain that carries no data."""

def _empty_toolchain_impl(_ctx):
    return [platform_common.ToolchainInfo()]

empty_toolchain = rule(
    implementation = _empty_toolchain_impl,
    doc = "Provides an empty `ToolchainInfo`, for toolchain types whose toolchains only select an execution platform.",
)
