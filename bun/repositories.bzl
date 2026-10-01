"""Repository rules that fetch Bun releases and declare their toolchains.

Most users should use the `bun` module extension from `//bun:extensions.bzl`
instead of calling these directly.
"""

load(
    "//bun/private:repositories.bzl",
    _bun_register_toolchains = "bun_register_toolchains",
    _bun_repositories = "bun_repositories",
)

bun_repositories = _bun_repositories
bun_register_toolchains = _bun_register_toolchains
