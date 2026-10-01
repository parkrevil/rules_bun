"""Repository rule that declares a toolchain target for every Bun platform."""

# Platforms that Bun publishes release archives for, with their Bazel constraints.
PLATFORMS = {
    "linux-x64": struct(
        compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    ),
    "linux-aarch64": struct(
        compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:aarch64",
        ],
    ),
    "darwin-x64": struct(
        compatible_with = [
            "@platforms//os:macos",
            "@platforms//cpu:x86_64",
        ],
    ),
    "darwin-aarch64": struct(
        compatible_with = [
            "@platforms//os:macos",
            "@platforms//cpu:aarch64",
        ],
    ),
    "windows-x64": struct(
        compatible_with = [
            "@platforms//os:windows",
            "@platforms//cpu:x86_64",
        ],
    ),
}

def _toolchains_repo_impl(repository_ctx):
    build_content = ""

    for platform, meta in PLATFORMS.items():
        build_content += """
toolchain(
    name = "{platform}_toolchain",
    exec_compatible_with = {compatible_with},
    toolchain = "@{user_repo}_{platform}//:bun_toolchain",
    toolchain_type = "@rules_bun//bun/toolchain:execution_type",
)
""".format(
            platform = platform,
            user_repo = repository_ctx.attr.user_repository_name,
            compatible_with = meta.compatible_with,
        )

    repository_ctx.file("BUILD.bazel", build_content)

    return repository_ctx.repo_metadata(reproducible = True)

toolchains_repo = repository_rule(
    _toolchains_repo_impl,
    attrs = {
        "user_repository_name": attr.string(mandatory = True),
    },
)
