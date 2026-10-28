"""Repository rule that declares a toolchain target for every Bun platform."""

load(":platforms.bzl", "BUN_ARCHIVES", "archive_constraint_sets")

def _toolchains_repo_impl(repository_ctx):
    build_content = ""

    for platform in BUN_ARCHIVES:
        for compatible_with in archive_constraint_sets(platform):
            build_content += """
toolchain(
    name = "{platform}_toolchain",
    exec_compatible_with = {compatible_with},
    toolchain = "@{user_repo}_{platform}//:bun_toolchain",
    toolchain_type = "@rules_bun//bun/toolchain:execution_type",
)

toolchain(
    name = "{platform}_target_toolchain",
    target_compatible_with = {compatible_with},
    toolchain = "@{user_repo}_{platform}//:bun_target_toolchain",
    toolchain_type = "@rules_bun//bun/toolchain:target_type",
)
""".format(
                platform = platform,
                user_repo = repository_ctx.attr.user_repository_name,
                compatible_with = compatible_with,
            )

    repository_ctx.file("BUILD.bazel", build_content)

    return repository_ctx.repo_metadata(reproducible = True)

toolchains_repo = repository_rule(
    _toolchains_repo_impl,
    attrs = {
        "user_repository_name": attr.string(mandatory = True),
    },
)
