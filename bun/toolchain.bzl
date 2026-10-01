"""Toolchain rule that provides a Bun executable."""

load("//bun/private:toolchain.bzl", _bun_toolchain = "bun_toolchain")

bun_toolchain = _bun_toolchain
