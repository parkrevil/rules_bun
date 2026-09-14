"""Module extension that registers Bun toolchains.

Every module may request a Bun version under the default name, `bun`.
When several versions are requested under the same name, the highest one is used.
Only the root module may request toolchains under another name.

Example:

    bun = use_extension("@parkrevil_rules_bun//bun:extensions.bzl", "bun")
    bun.toolchain(bun_version = "1.4.2")
    use_repo(bun, "bun_toolchains")

    register_toolchains("@bun_toolchains//:all")
"""

load("//bun:repositories.bzl", "bun_register_toolchains")
load("//bun/private:semver.bzl", "max_version")

_DEFAULT_NAME = "bun"

bun_toolchain = tag_class(
    doc = "Requests a Bun toolchain.",
    attrs = {
        "name": attr.string(
            doc = "Base name of the generated repositories. Only the root module may change it.",
            default = _DEFAULT_NAME,
        ),
        "bun_version": attr.string(
            doc = "Bun version to download, such as `1.4.2`.",
            mandatory = True,
        ),
        "integrity": attr.string_dict(
            doc = """\
Subresource Integrity of each release archive, keyed by platform
(`linux-x64`, `linux-aarch64`, `darwin-x64`, `darwin-aarch64`, `windows-x64`).
Required for every platform when rules_bun does not know `bun_version`.
""",
        ),
    },
)

def _toolchain_extension(module_ctx):
    registrations = {}
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            if toolchain.name != _DEFAULT_NAME and not mod.is_root:
                fail(
                    "루트 모듈만 Bun 툴체인의 기본 이름을 바꿀 수 있다. " +
                    "외부 저장소 전역 이름 공간의 충돌을 막기 위한 제약이다.",
                )
            registrations.setdefault(toolchain.name, {})
            registrations[toolchain.name][toolchain.bun_version] = toolchain.integrity

    for name, declared in registrations.items():
        selected = max_version(declared.keys())

        bun_register_toolchains(
            name = name,
            bun_version = selected,
            integrity = declared[selected],
        )

    return module_ctx.extension_metadata(reproducible = True)

bun = module_extension(
    implementation = _toolchain_extension,
    doc = "Registers the Bun toolchains requested with `bun.toolchain`.",
    tag_classes = {"toolchain": bun_toolchain},
    os_dependent = False,
    arch_dependent = False,
)
