"""The one platform table of rules_bun (feature 005 research R5, FR-004).

npm's `os`, `cpu` and `libc` values and Bun's release archives, mapped to Bazel constraints. Bun
toolchain registration (`toolchains_repo.bzl`, `repositories.bzl`) and npm package selection
(`npm_repositories.bzl`) both derive from it.
"""

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
