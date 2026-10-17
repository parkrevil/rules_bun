"""Toolchain rules that provide a Bun executable."""

load(
    "//bun/private:toolchain.bzl",
    _bun_target_toolchain = "bun_target_toolchain",
    _bun_toolchain = "bun_toolchain",
)

bun_toolchain = _bun_toolchain
bun_target_toolchain = _bun_target_toolchain
