load("//bun:repositories.bzl", "bun_register_toolchains")
load("//bun/private:semver.bzl", "max_version")

_DEFAULT_NAME = "bun"

bun_toolchain = tag_class(attrs = {
    "name": attr.string(default = _DEFAULT_NAME),
    "bun_version": attr.string(mandatory = True),
    "integrity": attr.string_dict(),
})

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
        versions = sorted(declared.keys())
        if len(versions) > 1:
            selected = max_version(versions)

            print("NOTE: bun 툴체인 {} 에 여러 버전 {} 이 있어 {} 를 선택했다.".format(
                name,
                versions,
                selected,
            ))
        else:
            selected = versions[0]

        bun_register_toolchains(
            name = name,
            bun_version = selected,
            integrity = declared[selected],
        )

    return module_ctx.extension_metadata(reproducible = True)

bun = module_extension(
    implementation = _toolchain_extension,
    tag_classes = {"toolchain": bun_toolchain},
    os_dependent = False,
    arch_dependent = False,
)
