"""Implementation of the `bun` module extension."""

load(":repositories.bzl", "bun_register_toolchains")
load(":semver.bzl", "max_version")

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
                    "Only the root module may change the name of a Bun toolchain, " +
                    "because the generated repositories share one global namespace.",
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
