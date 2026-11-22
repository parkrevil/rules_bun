"""The dependencies of a root or workspace `package.json` as Bun lists them, carried over from bun-v1.4.4.

`Package::parse` (src/install/lockfile/Package.rs) reads a manifest's dependency maps into the
package's dependency list, which `bun.lock` records per workspace (`write_workspace_deps`) and the
overrides read for `$<name>` (feature 006 T179, T182). Only what the list holds is carried over:
each entry's behavior, name and literal specifier. Values are kept as the manifest writes them, so
the comparison with `bun.lock` still names a value Bun would not read.
"""

load(":bun_install_types.bzl", "BEHAVIOR", "dependency_sort_key")

# The dependency groups `Package::parse` reads, in its order (`dependency_groups`), with their
# behavior; the root also has `workspaces`, which `bun.lock` does not record as dependencies.
_GROUPS = [
    ("dependencies", BEHAVIOR.PROD),
    ("devDependencies", BEHAVIOR.DEV),
    ("optionalDependencies", BEHAVIOR.OPTIONAL),
    ("peerDependencies", BEHAVIOR.PEER),
]

def package_dependencies(manifest, is_main):
    """The dependency list `Package::parse` builds for the root or a workspace member.

    The maps are read in `_GROUPS` order. Only the root (`Features::MAIN`) checks duplicates: there
    an `optionalDependencies` entry replaces the first earlier entry of its name ("duplicate
    dependencies are allowed in optionalDependencies") and any other duplicate is kept, with a
    warning; a workspace (`Features::WORKSPACE`) keeps every entry. A `peerDependencies` entry named
    in `peerDependenciesMeta` with `"optional": true` is an optional peer, and each such name no
    `peerDependencies` entry consumed becomes an optional peer `"*"`. The list is sorted by
    `Dependency::cmp`.

    Bun: src/install/lockfile/Package.rs L2642–L2660, L2664–L2700 @ bun-v1.4.4
    Bun: src/install/lockfile/Package.rs L2465–L2520 @ bun-v1.4.4
    Bun: src/install/lockfile/Package.rs L3302–L3349, L3352–L3383, L3385–L3388 @ bun-v1.4.4
    Bun: src/install_types/resolver_hooks.rs L1240–L1264 @ bun-v1.4.4

    Args:
        manifest: The decoded `package.json`.
        is_main: Whether it is the root's (`Features::MAIN`) rather than a member's.

    Returns:
        A list of `struct(behavior, name, literal)`, `literal` the manifest's value.
    """
    optional_peers = {}
    meta = manifest.get("peerDependenciesMeta")
    if type(meta) == "dict":
        for name, value in meta.items():
            if type(value) == "dict" and value.get("optional") == True:
                optional_peers[name] = None

    dependencies = []
    seen = {}
    for kind, behavior in _GROUPS:
        group = manifest.get(kind)
        if type(group) != "dict":
            continue
        for name, literal in group.items():
            dependency = struct(behavior = behavior, name = name, literal = literal)
            if is_main and behavior != BEHAVIOR.PEER:
                if name in seen and behavior == BEHAVIOR.OPTIONAL:
                    for i, earlier in enumerate(dependencies):
                        if earlier.name == name:
                            dependencies[i] = dependency
                            break
                    continue
                seen[name] = None
            if behavior == BEHAVIOR.PEER and name in optional_peers:
                optional_peers.pop(name)
                dependency = struct(behavior = behavior | BEHAVIOR.OPTIONAL, name = name, literal = literal)
            dependencies.append(dependency)
    for name in optional_peers:
        dependencies.append(struct(behavior = BEHAVIOR.PEER | BEHAVIOR.OPTIONAL, name = name, literal = "*"))
    return sorted(dependencies, key = dependency_sort_key)

def workspace_groups(dependencies):
    """The four maps `bun.lock` records for a workspace's dependency list.

    A dependency is written under each group its behavior intersects, an optional peer under
    `peerDependencies` only (`write_workspace_deps`).

    Bun: src/install/lockfile/bun.lock.rs L1184–L1233, L1478–L1483 @ bun-v1.4.4

    Args:
        dependencies: The list `package_dependencies` returns.

    Returns:
        A dict from each of the four map names to the map of name to literal.
    """
    groups = {}
    for kind, behavior in _GROUPS:
        written = {}
        for dependency in dependencies:
            if not dependency.behavior & behavior:
                continue
            if behavior == BEHAVIOR.OPTIONAL and dependency.behavior & BEHAVIOR.PEER:
                continue
            written[dependency.name] = dependency.literal
        groups[kind] = written
    return groups
