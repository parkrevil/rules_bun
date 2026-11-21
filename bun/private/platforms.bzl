"""The one platform table of rules_bun (feature 005 research R5, FR-004).

npm's `os`, `cpu` and `libc` values and Bun's release archives, mapped to Bazel constraints. Bun
toolchain registration (`toolchains_repo.bzl`, `repositories.bzl`) and npm package selection
(`npm_repositories.bzl`) both derive from it.
"""

load(":bun_install_types.bzl", "LIBC_ALL", "meta_is_disabled", "negatable_from_json_value", "platform_names", "platform_value")

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

def _npm_only(kind, table):
    """The values of `table` Bun does not name, each with its own bit above Bun's."""
    return {name: 1 << (16 + i) for i, name in enumerate([n for n in sorted(table.keys()) if n not in platform_names(kind)])}

# The npm values `NPM_OS` and `NPM_CPU` map that Bun's `negatable_names!` tables do not name
# (`netbsd`, `riscv64`): Bun refuses such a `--os` or `--cpu` (CLI L37-L64), so no Bun behavior
# exists for a target with one (research R3, T112).
_NPM_ONLY = {"cpu": _npm_only("cpu", NPM_CPU), "libc": {}, "os": _npm_only("os", NPM_OS)}

def npm_only_names(kind):
    """The npm values the hub selects on that Bun does not name.

    This is the adapter (ID-2): `NPM_OS` and `NPM_CPU` map them to `@platforms` constraints, and
    Bun has no behavior for a target with one (research R3, T112).

    Args:
        kind: `os`, `cpu` or `libc`.

    Returns:
        The sorted names.
    """
    return sorted(_NPM_ONLY[kind].keys())

def _check_list(value, values):
    """npm's `os` and `cpu` rule: npm-install-checks `checkList` (v9.0.0, `lib/index.js` at fcba600c2e4d).

    This is the adapter: npm's rule, which `main` applied to every value (`git show
    main:bun/private/platforms.bzl` `check_list`). A sole `any` matches; a `!<v>` equal to `value`
    fails; otherwise a positive entry equal to `value` matches, and a list of negated entries only
    matches everything else.
    """
    if values == ["any"]:
        return True
    negated = 0
    match = False
    for entry in values:
        if entry.startswith("!"):
            negated += 1
            if entry[1:] == value:
                return False
        elif entry == value:
            match = True
    return match or negated == len(values)

def package_platforms(kind, value):
    """The bit set a package's `os`, `cpu` or `libc` field allows on the hub's target platforms.

    This is the adapter (ID-2): Bun's `negatable_from_json_value` decides every value Bun names;
    for each value the hub selects on that Bun does not name (`npm_only_names`), on which Bun has no
    behavior, the field is read as npm's `checkList` reads it, as on `main` (research R3, T112). An
    absent field allows every value.

    Args:
        kind: `os`, `cpu` or `libc`.
        value: The field's JSON value: a string, a list, or `None` when the field is absent.

    Returns:
        The bit set.
    """
    bits = negatable_from_json_value(kind, value)
    values = [value] if type(value) == "string" else [item for item in value if type(item) == "string"] if type(value) == "list" else []
    for name, bit in _NPM_ONLY[kind].items():
        if value == None or _check_list(name, values):
            bits |= bit
    return bits

# The "every value" of an absent `os` and `cpu` field.
_ALL_OS = package_platforms("os", None)
_ALL_CPU = package_platforms("cpu", None)

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

    A value Bun does not name that the hub selects on gets its own bit (`npm_only_names`), which
    `package_platforms` sets as npm's rule does (T112).

    Args:
        platform: A `platform_tuples()` tuple.

    Returns:
        `struct(cpu, os, libc)`.
    """
    os, cpu, libc = platform
    return struct(
        cpu = _NPM_ONLY["cpu"].get(cpu) or platform_value("cpu", cpu),
        os = _NPM_ONLY["os"].get(os) or platform_value("os", os),
        libc = platform_value("libc", libc),
    )

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
