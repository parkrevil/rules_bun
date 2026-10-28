"""Repository rule that declares the toolchain targets of every Bun platform (research R5).

One execution and one target `toolchain()` per constraint set of `archive_constraint_sets`: named
`<platform>_toolchain` and `<platform>_target_toolchain`, and for a glibc archive
`<platform>_<libc>_toolchain` and `<platform>_<libc>_target_toolchain` (`glibc`, `unconstrained`).
"""

load(":platforms.bzl", "BUN_ARCHIVES", "archive_constraint_sets")

def _toolchains_repo_impl(repository_ctx):
    build_content = ""

    for platform in BUN_ARCHIVES:
        for constraint_set in archive_constraint_sets(platform):
            build_content += """
toolchain(
    name = "{name}_toolchain",
    exec_compatible_with = {compatible_with},
    toolchain = "@{user_repo}_{platform}//:bun_toolchain",
    toolchain_type = "@rules_bun//bun/toolchain:execution_type",
)

toolchain(
    name = "{name}_target_toolchain",
    target_compatible_with = {compatible_with},
    toolchain = "@{user_repo}_{platform}//:bun_target_toolchain",
    toolchain_type = "@rules_bun//bun/toolchain:target_type",
)
""".format(
                name = platform + ("_" + constraint_set.libc if constraint_set.libc else ""),
                platform = platform,
                user_repo = repository_ctx.attr.user_repository_name,
                compatible_with = constraint_set.constraints,
            )

    repository_ctx.file("BUILD.bazel", build_content)

    return repository_ctx.repo_metadata(reproducible = True)

toolchains_repo = repository_rule(
    _toolchains_repo_impl,
    attrs = {
        "user_repository_name": attr.string(mandatory = True),
    },
)
