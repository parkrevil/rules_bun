"""Module extension that registers Bun toolchains.

Every module may request a Bun version under the default name, `bun`.
When several versions are requested under the same name, the highest one is used.
Only the root module may request toolchains under another name.

Example:

    bun = use_extension("@rules_bun//bun:extensions.bzl", "bun")
    bun.toolchain(bun_version = "1.4.2")
    use_repo(bun, "bun_toolchains")

    register_toolchains("@bun_toolchains//:all")
"""

load(
    "//bun/private:extensions.bzl",
    _bun = "bun",
    _bun_toolchain = "bun_toolchain",
)

bun = _bun
bun_toolchain = _bun_toolchain
