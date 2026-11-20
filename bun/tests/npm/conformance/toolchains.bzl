"""The Bun 1.4.2 target toolchains of the second conformance oracle (feature 006 US5, research R10)."""

load("//bun/private:platforms.bzl", "BUN_ARCHIVES", "archive_constraint_sets")

def bun_1_4_2_toolchains(name, constraint):
    """Declares one `//bun/toolchain:target_type` toolchain per Bun 1.4.2 archive.

    Each has the constraints `@bun_toolchains` gives that archive's target toolchain plus
    `constraint`, so only a platform with `constraint` selects it.

    Args:
        name: Prefix of the toolchain targets' names.
        constraint: The label of the `bun_version` constraint value.
    """
    for platform in BUN_ARCHIVES:
        for constraint_set in archive_constraint_sets(platform):
            native.toolchain(
                name = "{}_{}{}_target_toolchain".format(name, platform, "_" + constraint_set.libc if constraint_set.libc else ""),
                target_compatible_with = constraint_set.constraints + [constraint],
                toolchain = "@bun_1_4_2_{}//:bun_target_toolchain".format(platform),
                toolchain_type = "//bun/toolchain:target_type",
            )
