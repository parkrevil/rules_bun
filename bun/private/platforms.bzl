"""The one platform table of rules_bun (feature 005 research R5, FR-004).

npm's `os`, `cpu` and `libc` values and Bun's release archives, mapped to Bazel constraints. Bun
toolchain registration (`toolchains_repo.bzl`, `repositories.bzl`) and npm package selection
(`npm_repositories.bzl`) both derive from it.
"""

load(":bun_install_types.bzl", "LIBC_ALL", "meta_is_disabled", "negatable_from_json_value", "platform_value")

# Bun's "every value" of an absent `os` and `cpu` field.
_ALL_OS = negatable_from_json_value("os", None)
_ALL_CPU = negatable_from_json_value("cpu", None)

# npm `os` and `cpu` values -> `@platforms` constraint names (@platforms 1.1.0 `os/BUILD` and
# `cpu/BUILD`). A value not listed, such as `sunos`, matches no Bazel platform.
NPM_OS = {
    "aix": "aix",
    "android": "android",
    "darwin": "macos",
    "freebsd": "freebsd",
    "linux": "linux",
    "netbsd": "netbsd",
    "openbsd": "openbsd",
    "win32": "windows",
}

NPM_CPU = {
    "arm": "arm",
    "arm64": "aarch64",
    "ia32": "x86_32",
    "riscv64": "riscv64",
    "s390x": "s390x",
    "x64": "x86_64",
}

# npm `libc` values -> constraint values of //bun/platforms/libc (feature 004 research R11).
NPM_LIBC = {
    "glibc": str(Label("//bun/platforms/libc:glibc")),
    "musl": str(Label("//bun/platforms/libc:musl")),
}

# Each Bun release archive (`bun-<archive>.zip`), in npm vocabulary; `libc` is `None` off Linux.
BUN_ARCHIVES = {
    "linux-x64": struct(os = "linux", cpu = "x64", libc = "glibc"),
    "linux-aarch64": struct(os = "linux", cpu = "arm64", libc = "glibc"),
    "linux-x64-musl": struct(os = "linux", cpu = "x64", libc = "musl"),
    "linux-aarch64-musl": struct(os = "linux", cpu = "arm64", libc = "musl"),
    "darwin-x64": struct(os = "darwin", cpu = "x64", libc = None),
    "darwin-aarch64": struct(os = "darwin", cpu = "arm64", libc = None),
    "windows-x64": struct(os = "win32", cpu = "x64", libc = None),
}

_UNCONSTRAINED = str(Label("//bun/platforms/libc:unconstrained"))

def archive_constraint_sets(archive):
    """The constraint lists a Bun toolchain of one release archive is registered with.

    A glibc archive serves Linux platforms with `//bun/platforms/libc:glibc` and those without the
    libc constraint (its default, `:unconstrained`); a musl archive serves `:musl`. The libc is
    always explicit, so resolution does not depend on the registration order of toolchains.

    Args:
        archive: A key of `BUN_ARCHIVES`.

    Returns:
        `struct(libc, constraints)` per toolchain: `libc` names the libc constraint value for a
        glibc archive's two toolchains (`glibc`, `unconstrained`) and is `None` otherwise.
    """
    meta = BUN_ARCHIVES[archive]
    base = ["@platforms//os:" + NPM_OS[meta.os], "@platforms//cpu:" + NPM_CPU[meta.cpu]]
    if meta.libc == "glibc":
        return [
            struct(libc = "glibc", constraints = base + [NPM_LIBC["glibc"]]),
            struct(libc = "unconstrained", constraints = base + [_UNCONSTRAINED]),
        ]
    if meta.libc:
        return [struct(libc = None, constraints = base + [NPM_LIBC[meta.libc]])]
    return [struct(libc = None, constraints = base)]

def platform_tuples():
    """The target platforms the hub tells apart, as `(os, cpu, libc)` npm values (research R3).

    This is the adapter of research R3 (ID-2): Bun installs for one platform, so it has no list of
    platforms; rules_bun resolves for every platform its hub's `select()` tells apart.

    They are the `select()` branches of the hub's links (`npm_repositories.bzl`): every `NPM_OS`
    alone and with each `NPM_CPU`, on Linux each of those also with each `NPM_LIBC` value; and the
    default branch, a platform that maps to no npm value. `None` is a value the platform does not
    set. The store is computed per class of these (`platform_classes`).

    Returns:
        List of tuples.
    """
    tuples = []
    for os in sorted(NPM_OS.keys()):
        for libc in [None] + (sorted(NPM_LIBC.keys()) if os == "linux" else []):
            tuples.append((os, None, libc))
            for cpu in sorted(NPM_CPU.keys()):
                tuples.append((os, cpu, libc))
    tuples.append((None, None, None))
    return tuples

def platform_bits(platform):
    """The `--cpu`, `--os` and `--libc` bit sets Bun's filter compares a tuple with.

    Bun: src/install/PackageManager/PackageManagerOptions.rs L1174–L1176 @ bun-v1.4.4

    Args:
        platform: A `platform_tuples()` tuple.

    Returns:
        `struct(cpu, os, libc)`.
    """
    os, cpu, libc = platform
    return struct(cpu = platform_value("cpu", cpu), os = platform_value("os", os), libc = platform_value("libc", libc))

def platform_classes(lockfile):
    """The platform tuples grouped by what `Meta::is_disabled` leaves out (research R3).

    Bun: src/install/lockfile/Package/Meta.rs L70–L74 @ bun-v1.4.4

    The isolated linker's only platform input is `is_disabled`, through
    `is_filtered_dependency_or_workspace` (TREE L1336-L1358), with the target `libc` for optional
    dependencies and every libc for the others (`Libc::for_dependency`); tuples where it disables
    the same packages in both readings get the same store.

    Args:
        lockfile: A cleaned lockfile.

    Returns:
        List of classes, each a list of tuples, in `platform_tuples()` order.
    """
    restricted = [
        (pkg_id, package.meta)
        for pkg_id, package in enumerate(lockfile.packages)
        if package.meta.os != _ALL_OS or package.meta.arch != _ALL_CPU or package.meta.libc != 0
    ]
    classes = {}
    for platform in platform_tuples():
        bits = platform_bits(platform)
        key = tuple([
            (pkg_id, meta_is_disabled(meta, bits.cpu, bits.os, bits.libc), meta_is_disabled(meta, bits.cpu, bits.os, LIBC_ALL))
            for pkg_id, meta in restricted
        ])
        classes.setdefault(key, []).append(platform)
    return list(classes.values())
