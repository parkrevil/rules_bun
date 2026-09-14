"""Repository rule that declares a toolchain target for every Bun platform."""

load(":platforms.bzl", "PLATFORMS")

def _toolchains_repo_impl(repository_ctx):
    build_content = ""

    for platform, meta in PLATFORMS.items():
        build_content += """
toolchain(
    name = "{platform}_toolchain",
    exec_compatible_with = {compatible_with},
    toolchain = "@{user_repo}_{platform}//:bun_toolchain",
    toolchain_type = "@parkrevil_rules_bun//bun/toolchain:execution_type",
)
""".format(
            platform = platform,
            user_repo = repository_ctx.attr.user_repository_name,
            compatible_with = meta.compatible_with,
        )

    repository_ctx.file("BUILD.bazel", build_content)

    if not hasattr(repository_ctx, "repo_metadata"):
        return None
    return repository_ctx.repo_metadata(reproducible = True)

toolchains_repo = repository_rule(
    _toolchains_repo_impl,
    attrs = {
        "user_repository_name": attr.string(mandatory = True),
    },
)
