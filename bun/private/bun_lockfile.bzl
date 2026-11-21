"""Bun's text-lockfile loader and the lockfile passes after it, carried over from bun-v1.4.4.

Research Part 2 S1-S6: `parse_into_binary_lockfile` (src/install/lockfile/bun.lock.rs) turns the
rows of `bun.lock` into packages, dependencies and resolutions; `Lockfile::resolve` hoists until no
peer is bound late; `clean_with_logger` copies the packages the root reaches and hoists again
(src/install/lockfile.rs). The loader reads `bun.lock` through `lockfile.bzl`, which checks each
field it hands over (research Part 4).

The lockfile is a struct of lists and dicts that the passes change in place, as Bun's `Lockfile`:
`packages` and `dependencies` are lists indexed by package and dependency IDs, `resolutions[i]` is
the package of dependency `i` or `INVALID`. Names stand in for Bun's name hashes.

Starlark has no `while` and no recursion: each Bun loop is a `for` over a bound, and hoisting is a
function the caller passes in (`bun_tree.bzl` loads this file).
"""

load(
    ":bun_install_types.bzl",
    "BEHAVIOR",
    "RESOLUTION_TAG",
    "VERSION_TAG",
    "behavior_is_bundled",
    "behavior_is_optional",
    "behavior_is_optional_peer",
    "behavior_is_peer",
    "behavior_is_workspace",
    "dependency_parse",
    "dependency_sort_key",
    "dependency_version",
    "is_safe_install_folder_name",
    "repository_with_resolved",
    "resolution_eql",
    "resolution_from_text_lockfile",
    "resolution_order",
    "resolution_satisfies_dependency_version",
    "split_name_and_maybe_version",
    "version_tag_infer",
)
load(":bun_semver.bzl", "parse_query", "parse_version", "query_intersects", "query_is_star", "query_satisfies")
load(":platforms.bzl", "package_platforms")

# `invalid_package_id`.
INVALID = -1

# Starlark has no `while`; Bun's open loops are bounded by this.
_LIMIT = 1 << 30

# `RowEvidence` (LOCK L1521-L1542), in its order.
_UNBOUND = 0
_ROOT_DEPENDENCY = 1
_WALKED = 2
_WALKED_TO_ROOT = 3
_REFUSED = 4
_OWN_ENTRY = 5
_UNPROVIDED = 6

# `WORKSPACE_DEPENDENCY_GROUPS` (LOCK L1478-L1483).
_GROUPS = [
    ("dependencies", BEHAVIOR.PROD),
    ("devDependencies", BEHAVIOR.DEV),
    ("optionalDependencies", BEHAVIOR.OPTIONAL),
    ("peerDependencies", BEHAVIOR.PEER),
]

def _refusal(file, where, message):
    """A lockfile Bun refuses to load (FR-004): the label, where, and Bun's own message.

    Bun: src/install/lockfile/bun.lock.rs L1806–L1811 @ bun-v1.4.4
    """
    return struct(value = None, error = "{}: Bun 1.4.4 refuses to load this lockfile ({}): {}".format(file, where, message))

def _failure(file, message):
    """A dependency the loader cannot resolve: the label and Bun's message.

    Bun: src/install/lockfile/bun.lock.rs L3302–L3345 @ bun-v1.4.4
    """
    return struct(value = None, error = "{}: {}".format(file, message))

def is_valid(pkg_id):
    """Whether a package ID is one, not `invalid_package_id`.

    Bun: src/install_types/resolver_hooks.rs L32–L32 @ bun-v1.4.4

    Args:
        pkg_id: A package ID or `INVALID`.

    Returns:
        Whether it names a package.
    """
    return pkg_id != INVALID

def _meta(info, is_workspace):
    """`Meta` of a row: `os`, `cpu`, `libc` (LOCK L2593-L2604); a workspace has none.

    Bun: src/install/lockfile/bun.lock.rs L2593–L2604 @ bun-v1.4.4
    Bun: src/install/lockfile/Package/Meta.rs L51–L66 @ bun-v1.4.4

    Each field is read by `negatable_from_json_value` through the adapter's `package_platforms`
    (`platforms.bzl`), which adds npm's reading for the target values Bun does not name (T112).
    """
    if is_workspace or info == None:
        return struct(os = package_platforms("os", None), arch = package_platforms("cpu", None), libc = 0)
    return struct(
        os = package_platforms("os", info.os if info.os else None),
        arch = package_platforms("cpu", info.cpu if info.cpu else None),
        libc = package_platforms("libc", info.libc if info.libc else None),
    )

def _package(name, resolution, off, length, meta, key = "", entry = None):
    """`Package`: its dependencies and resolutions share one `[off, off + len)` slice.

    Bun: src/install/lockfile/Package.rs L244–L282 @ bun-v1.4.4
    """
    return struct(
        name = name,
        resolution = resolution,
        dependencies = struct(off = off, len = length),
        meta = meta,
        key = key,
        entry = entry,
    )

def _dependency(name, version, behavior):
    """`Dependency`.

    Bun: src/install_types/resolver_hooks.rs L517–L528 @ bun-v1.4.4
    """
    return struct(name = name, version = version, behavior = behavior)

def dependency_ids(lockfile, pkg_id):
    """The dependency IDs of a package, `DependencySlice::begin()..end()`.

    Bun: src/install_types/resolver_hooks.rs L133–L140 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        pkg_id: A package ID.

    Returns:
        The range of its dependency IDs.
    """
    deps = lockfile.packages[pkg_id].dependencies
    return range(deps.off, deps.off + deps.len)

# --- CatalogMap ----------------------------------------------------------------------------------

def _parse_catalog(catalog, rows, file, where):
    """`parse_catalog`: one catalog's `name: version` rows.

    Bun: src/install/lockfile/bun.lock.rs L1727–L1795 @ bun-v1.4.4
    """
    for name, version in rows.items():
        if not name:
            return _refusal(file, where, "Expected a non-empty string")
        if type(version) != "string":
            return _refusal(file, where, "Expected a string")
        parsed = dependency_parse(name, version)
        if parsed == None:
            return _refusal(file, where, "Invalid catalog version")
        catalog[name] = _dependency(name, parsed, 0)
    return None

def _catalog_find(catalogs, catalog_name, dep_name):
    """`CatalogMap::find`: the default catalog is `""` and `default`, the one named first.

    Bun: src/install/lockfile/CatalogMap.rs L54–L115 @ bun-v1.4.4
    """
    has_default = len(catalogs.default) > 0
    has_groups = len(catalogs.groups) > 0
    if not has_default and not has_groups:
        return None

    def in_group(name):
        """The entry of `dep_name` in the catalog group `name`, or None.

        Bun: src/install/lockfile/CatalogMap.rs L83–L96 @ bun-v1.4.4
        """
        if not has_groups or name not in catalogs.groups:
            return None
        return catalogs.groups[name].get(dep_name)

    in_default = catalogs.default.get(dep_name) if has_default else None
    if catalog_name == "":
        return in_default if in_default != None else in_group("default")
    found = in_group(catalog_name)
    if found == None and catalog_name == "default":
        return in_default
    return found

def catalogs_resolve_range(lockfile, dependency):
    """`CatalogMap::resolve_range`: a `catalog:` dependency's catalog entry, else its own version.

    Bun: src/install/lockfile/CatalogMap.rs L195–L207 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        dependency: A dependency.

    Returns:
        The version the dependency asks for.
    """
    if dependency.version.tag != VERSION_TAG.CATALOG:
        return dependency.version
    entry = _catalog_find(lockfile.catalogs, dependency.version.catalog, dependency.name)
    return entry.version if entry != None else dependency.version

def _strip_reference(dependency):
    """`CatalogMap::strip_reference`: outside the root and workspaces, `catalog:` resolves nothing.

    Bun: src/install/lockfile/CatalogMap.rs L209–L237 @ bun-v1.4.4
    """
    if dependency.version.tag != VERSION_TAG.CATALOG:
        return dependency
    literal = dependency.version.literal
    if not behavior_is_peer(dependency.behavior):
        return _dependency(dependency.name, dependency_version(VERSION_TAG.UNINITIALIZED, literal), dependency.behavior)
    star = struct(name = dependency.name, version = parse_query("*"), is_alias = False)
    return _dependency(dependency.name, dependency_version(VERSION_TAG.NPM, literal, npm = star), dependency.behavior | BEHAVIOR.OPTIONAL)

# --- OverrideMap ---------------------------------------------------------------------------------

def _parse_package_segment(segment):
    """`parse_package_segment`: `name` or `name@range` of an override key; `None` if invalid.

    Bun: src/install/lockfile/override_selector.rs L25–L52 @ bun-v1.4.4
    """
    if not segment:
        return None
    name, version = split_name_and_maybe_version(segment)
    if not name:
        return None
    if name.startswith("@") and "/" not in name:
        return None
    selected = version or ""
    if selected.startswith("npm:"):
        rest = selected[len("npm:"):]
        if not rest or version_tag_infer(rest) == VERSION_TAG.NPM:
            selected = rest
    if not selected and len(segment) > len(name):
        return None
    return struct(name = name, range = selected)

def _lockfile_range(name, text, is_target):
    """`lockfile_range`: the range of an override selector; `None` if it selects nothing.

    Bun: src/install/lockfile/OverrideMap.rs L1081–L1116 @ bun-v1.4.4
    """
    if not text:
        return dependency_version(VERSION_TAG.UNINITIALIZED, "")
    version = dependency_parse(name, text)
    if version == None:
        return None
    if version.tag == VERSION_TAG.NPM and (is_target or not version.npm.is_alias):
        return version
    if version.tag == VERSION_TAG.CATALOG and is_target:
        return version
    return None

def _put_lockfile_rule(overrides, parent, target, value):
    """`OverrideMap::put_lockfile_rule` with `push_scoped`.

    Bun: src/install/lockfile/OverrideMap.rs L671–L737 @ bun-v1.4.4
    Bun: src/install/lockfile/OverrideMap.rs L644–L668 @ bun-v1.4.4
    """
    target_range = _lockfile_range(target.name, target.range, True)
    if target_range == None:
        return False
    parent_dep = None
    if parent != None:
        parent_version = _lockfile_range(parent.name, parent.range, False)
        if parent_version == None:
            return False
        parent_dep = _dependency(parent.name, parent_version, 0)
    is_flat = parent_dep == None and target_range.tag == VERSION_TAG.UNINITIALIZED
    version = dependency_parse(target.name, value)
    if version == None:
        return False
    dep = _dependency(target.name, version, 0)
    if is_flat:
        overrides.map[target.name] = dep
        return True
    rule = struct(parent = parent_dep, target_range = target_range, dep = dep)
    if target.name in overrides.scoped_names:
        for i, existing in enumerate(overrides.scoped):
            same_parent = (existing.parent == None and parent_dep == None) or (
                existing.parent != None and parent_dep != None and
                existing.parent.name == parent_dep.name and existing.parent.version.literal == parent_dep.version.literal
            )
            if existing.dep.name == target.name and same_parent and existing.target_range.literal == target_range.literal:
                overrides.scoped[i] = rule
                return True
    else:
        overrides.scoped_names[target.name] = True
    overrides.scoped.append(rule)
    return True

def _parse_overrides(overrides, rows, file):
    """The `overrides` object (LOCK L1934–L2035).

    Bun: src/install/lockfile/bun.lock.rs L1934–L2035 @ bun-v1.4.4
    """
    for name, value in rows.items():
        where = "overrides \"{}\"".format(name)
        if not name:
            return _refusal(file, "overrides", "Expected a non-empty string")
        if type(value) == "string":
            if not _put_lockfile_rule(overrides, None, struct(name = name, range = ""), value):
                return _refusal(file, where, "Invalid override version")
            continue
        if type(value) != "dict":
            return _refusal(file, where, "Expected a string or an object")
        parent = _parse_package_segment(name)
        if parent == None:
            return _refusal(file, where, "Invalid override key")
        for child_key, child_value in value.items():
            if type(child_value) != "string":
                return _refusal(file, where, "Expected a string")
            if child_key == ".":
                rule_parent, rule_target = None, parent
            else:
                rule_target = _parse_package_segment(child_key)
                if rule_target == None:
                    return _refusal(file, where, "Invalid override key")
                rule_parent = parent
            if not _put_lockfile_rule(overrides, rule_parent, rule_target, child_value):
                return _refusal(file, where, "Invalid override version")
    return None

def overrides_has_rule_for_name(lockfile, name):
    """`OverrideMap::has_rule_for_name`.

    Bun: src/install/lockfile/OverrideMap.rs L446–L449 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        name: A package name.

    Returns:
        Whether a flat or scoped override names it.
    """
    return name in lockfile.overrides.map or name in lockfile.overrides.scoped_names

def overrides_contains_name(lockfile, name):
    """`OverrideMap::contains_name`: a flat override of that name.

    Bun: src/install/lockfile/OverrideMap.rs L422–L434 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        name: A package name.

    Returns:
        Whether a flat override names it.
    """
    return name in lockfile.overrides.map

def _is_npm_alias(version):
    """`is_npm_alias`.

    Bun: src/install/lockfile/OverrideMap.rs L74–L77 @ bun-v1.4.4
    """
    return version.tag == VERSION_TAG.NPM and version.npm.is_alias

def _range_selects(selector, declared):
    """`range_selects` with `Selects::Overlapping`: the key's range overlaps the declared one.

    Bun: src/install/lockfile/OverrideMap.rs L88–L114 @ bun-v1.4.4
    """
    if selector.tag == VERSION_TAG.NPM and declared.tag == VERSION_TAG.NPM:
        return (
            selector.npm.is_alias == declared.npm.is_alias and
            (not selector.npm.is_alias or selector.npm.name == declared.npm.name) and
            query_intersects(selector.npm.version, declared.npm.version)
        )
    if selector.tag == VERSION_TAG.CATALOG and declared.tag == VERSION_TAG.CATALOG:
        a, b = selector.catalog, declared.catalog
        return a == b or (a in ["", "default"] and b in ["", "default"])
    return False

def _cmp_range_text(lhs, rhs):
    """`cmp_range_text`: by the parents' range texts, then the targets'.

    Bun: src/install/lockfile/OverrideMap.rs L116–L128 @ bun-v1.4.4
    """
    if (lhs.parent != None and rhs.parent != None and
        lhs.parent.version.tag == VERSION_TAG.NPM and rhs.parent.version.tag == VERSION_TAG.NPM):
        a, b = lhs.parent.version.literal, rhs.parent.version.literal
        if a != b:
            return -1 if a < b else 1
    a, b = lhs.target_range.literal, rhs.target_range.literal
    if a == b:
        return 0
    return -1 if a < b else 1

def package_version(lockfile, pkg_id):
    """`Lockfile::package_version`: an npm version, or a workspace's version.

    Bun: src/install/lockfile.rs L831–L843 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        pkg_id: A package ID.

    Returns:
        The version, or `None` for a package without one.
    """
    resolution = lockfile.packages[pkg_id].resolution
    if resolution.tag == RESOLUTION_TAG.NPM:
        return resolution.value
    if resolution.tag == RESOLUTION_TAG.WORKSPACE:
        return lockfile.workspace_versions.get(lockfile.packages[pkg_id].name)
    return None

def _owner_package_id(lockfile, dep_id):
    """`OverrideMap::owner_package_id`: the package whose dependencies hold `dep_id`.

    Bun: src/install/lockfile/OverrideMap.rs L392–L419 @ bun-v1.4.4
    """
    owners = lockfile.cache.get("owners")
    if owners == None:
        owners = {}
        for pkg_id in range(len(lockfile.packages)):
            for d in dependency_ids(lockfile, pkg_id):
                owners.setdefault(d, pkg_id)
        lockfile.cache["owners"] = owners
    return owners.get(dep_id, INVALID)

def _scoped_rule_for(lockfile, dep_id, name, declared):
    """`OverrideMap::scoped_rule_for`: the most specific scoped rule for a dependency.

    Bun: src/install/lockfile/OverrideMap.rs L307–L375 @ bun-v1.4.4
    Bun: src/install/lockfile/OverrideMap.rs L377–L390 @ bun-v1.4.4
    """
    best = None
    best_tier = 0
    owner = None
    for rule in lockfile.overrides.scoped:
        has_target_range = rule.target_range.tag != VERSION_TAG.UNINITIALIZED
        if rule.dep.name != name or (not has_target_range and _is_npm_alias(declared)):
            continue
        tier = 0
        if rule.parent != None:
            if owner == None:
                owner_id = _owner_package_id(lockfile, dep_id)
                owner = (lockfile.packages[owner_id].name, package_version(lockfile, owner_id)) if is_valid(owner_id) else False
            if owner == False or owner[0] != rule.parent.name:
                continue
            if rule.parent.version.tag == VERSION_TAG.NPM:
                if owner[1] == None or not query_satisfies(rule.parent.version.npm.version, owner[1]):
                    continue
                tier = 4
            else:
                tier = 2
        if has_target_range:
            if best != None and best_tier > tier + 1:
                continue
            if not _range_selects(rule.target_range, declared):
                continue
            tier += 1
        if best == None or tier > best_tier or (tier == best_tier and _cmp_range_text(rule, best) < 0):
            best, best_tier = rule, tier
    return best

def is_overridden_dependency(lockfile, dep_id):
    """`Lockfile::is_overridden_dependency` (`OverrideMap::lookup`).

    Bun: src/install/lockfile.rs L1145–L1148 @ bun-v1.4.4
    Bun: src/install/lockfile/OverrideMap.rs L234–L297 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        dep_id: A dependency ID.

    Returns:
        Whether an override applies to the dependency.
    """
    dependency = lockfile.dependencies[dep_id]
    overrides = lockfile.overrides
    if overrides.scoped and dependency.name in overrides.scoped_names:
        if _scoped_rule_for(lockfile, dep_id, dependency.name, dependency.version) != None:
            return True
    return dependency.name in overrides.map and not _is_npm_alias(dependency.version)

# --- package index -------------------------------------------------------------------------------

def _index_insert(lockfile, name, pkg_id):
    """`package_index::Entry::insert` and `get_or_put_id`: ordered by descending resolution.

    Bun: src/install/lockfile.rs L3205–L3226 @ bun-v1.4.4
    Bun: src/install/lockfile.rs L2713–L2729 @ bun-v1.4.4
    """
    ids = lockfile.package_index.get(name)
    if ids == None:
        lockfile.package_index[name] = [pkg_id]
        return
    resolution = lockfile.packages[pkg_id].resolution
    at = len(ids)
    for i, existing in enumerate(ids):
        if resolution_order(resolution, lockfile.packages[existing].resolution) > 0:
            at = i
            break
    ids.insert(at, pkg_id)

def _append_package_dedupe(lockfile, package):
    """`Lockfile::append_package_dedupe`: a package with an existing resolution is that package.

    Bun: src/install/lockfile.rs L2684–L2711 @ bun-v1.4.4
    """
    for existing in lockfile.package_index.get(package.name, []):
        if resolution_eql(package.resolution, lockfile.packages[existing].resolution):
            return existing
    pkg_id = len(lockfile.packages)
    lockfile.packages.append(package)
    _index_insert(lockfile, package.name, pkg_id)
    return pkg_id

# --- parse_append_dependencies --------------------------------------------------------------------

def _parse_append_dependencies(lockfile, obj, unresolved_rows, bundled, member_rows, catalogs_apply, file, where):
    """`parse_append_dependencies`: one package's dependencies, sorted, appended.

    Bun: src/install/lockfile/bun.lock.rs L3347–L3543 @ bun-v1.4.4

    Args:
        lockfile: The lockfile being loaded.
        obj: `struct(groups, optional_peers, unresolved)` of a workspace or a row's info.
        unresolved_rows: Receives the optional dependencies `obj` lists as `unresolved`.
        bundled: `(row key, bundled keys)` for a `packages` row, else `None`.
        member_rows: For the root only: the workspaces, each added as a workspace dependency.
        catalogs_apply: Whether `catalog:` dependencies keep their reference.
        file: The lockfile's label.
        where: The owner, for errors.

    Returns:
        `struct(value = (off, len), error)`.
    """
    optional_peers = {name: True for name in obj.optional_peers}
    unresolved_names = list(obj.unresolved)
    off = len(lockfile.dependencies)
    added = []
    for group_name, group_behavior in _GROUPS:
        for name, version_str in obj.groups.get(group_name, {}).items():
            if type(version_str) != "string":
                return _refusal(file, where, "Expected a string")
            behavior = group_behavior
            if group_behavior == BEHAVIOR.PEER and name in optional_peers:
                behavior = behavior | BEHAVIOR.OPTIONAL
            version = dependency_parse(name, version_str)
            if version == None:
                return _refusal(file, where, "Invalid dependency version")
            dep = _dependency(name, version, behavior)
            if not catalogs_apply:
                dep = _strip_reference(dep)
            if bundled != None and bundled[0] + "/" + name in bundled[1]:
                dep = _dependency(dep.name, dep.version, dep.behavior | BEHAVIOR.BUNDLED)
            added.append(dep)
    for row in (member_rows or []):
        added.append(_dependency(row.name, dependency_version(VERSION_TAG.WORKSPACE, "", workspace = row.path), BEHAVIOR.WORKSPACE))

    # `Dependency::cmp`: behavior group, then name (LOCK L3522-L3528).
    lockfile.dependencies.extend(sorted(added, key = dependency_sort_key))
    end = len(lockfile.dependencies)

    # After the sort, which decides each dependency's ID (LOCK L3530-L3537).
    if unresolved_names:
        for dep_id in range(off, end):
            dep = lockfile.dependencies[dep_id]
            if behavior_is_optional(dep.behavior) and dep.name in unresolved_names:
                unresolved_rows.append(dep_id)
    return struct(value = (off, end - off), error = None)

def _workspace_obj(workspace):
    """The object of the root or a workspace that `parse_append_dependencies` reads.

    Bun: src/install/lockfile/bun.lock.rs L2225–L2235 @ bun-v1.4.4
    Bun: src/install/lockfile/bun.lock.rs L2284–L2294 @ bun-v1.4.4
    """
    return struct(
        groups = {name: getattr(workspace, name) for name, _ in _GROUPS},
        optional_peers = workspace.optional_peers,
        unresolved = workspace.unresolved,
    )

def _row_obj(entry):
    """The info object of a `packages` row that `parse_append_dependencies` reads.

    Bun: src/install/lockfile/bun.lock.rs L2565–L2587 @ bun-v1.4.4
    """
    return struct(
        groups = {
            "dependencies": entry.dependencies,
            "devDependencies": entry.dev_dependencies,
            "optionalDependencies": entry.optional_dependencies,
            "peerDependencies": entry.peers,
        },
        optional_peers = entry.optional_peers,
        unresolved = entry.unresolved,
    )

# --- PkgMap::find_resolution ---------------------------------------------------------------------

def _find_resolution(pkg_map, pkg_path, dep_name, bundled_pkgs):
    """`PkgMap::find_resolution`: the walk from `<path>/<dep>` up to `<dep>`, and its evidence.

    Bun: src/install/lockfile/bun.lock.rs L1573–L1662 @ bun-v1.4.4

    Returns:
        `struct(id, evidence, error)`; `error` is `InvalidPackageKey` or `Unresolvable`.
    """
    prefix = pkg_path + "/"
    offset = len(pkg_path) + 1
    at_bundle_root = False
    for _ in range(len(prefix) + 2):
        res_path = prefix[:offset] + dep_name
        found = pkg_map.get(res_path)
        if found != None:
            if offset == len(pkg_path) + 1:
                evidence = _OWN_ENTRY
            elif offset == 0:
                evidence = _WALKED_TO_ROOT
            else:
                evidence = _WALKED
            return struct(id = found, evidence = evidence, error = None)
        if offset == 0 or at_bundle_root:
            return struct(id = None, evidence = None, error = "Unresolvable")
        head = prefix[:offset - 1]
        if bundled_pkgs != None:
            at_bundle_root = head in bundled_pkgs
        slash = head.rfind("/")
        if slash == -1:
            offset = 0
            continue

        # might be a scoped package
        at = head.rfind("@")
        if at == -1:
            offset = slash + 1
            continue
        if at > slash:
            break
        next_slash = prefix[:slash].rfind("/")
        if next_slash == -1:
            if at != 0:
                return struct(id = None, evidence = None, error = "InvalidPackageKey")
            offset = 0
            continue
        if next_slash > at:
            # there's a scoped package but it exists farther up
            offset = slash + 1
            continue
        if next_slash + 1 != at:
            break
        offset = at
    return struct(id = None, evidence = None, error = "InvalidPackageKey")

# --- version-based peers -------------------------------------------------------------------------

def _peer_candidate_name(dependency, version):
    """`peer_candidate_name_hash`: the package name the version-based scan looks for.

    Bun: src/install/lockfile/bun.lock.rs L3208–L3223 @ bun-v1.4.4
    """
    if version.tag == VERSION_TAG.NPM:
        return version.npm.name
    if version.tag == VERSION_TAG.DIST_TAG:
        return version.dist_tag.name
    if version.tag == VERSION_TAG.GIT:
        return version.git.package_name
    if version.tag == VERSION_TAG.GITHUB:
        return version.github.package_name
    if version.tag == VERSION_TAG.TARBALL:
        return version.tarball.package_name
    return dependency.name

def version_based_peer_range(lockfile, dependency):
    """`version_based_peer_range`: the range and name a peer is bound by, or `None` for the walk.

    Bun: src/install/lockfile/bun.lock.rs L3172–L3206 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        dependency: A dependency.

    Returns:
        `(range, name)`, or `None` for a dependency the path walk binds.
    """
    b = dependency.behavior
    if not behavior_is_peer(b) or behavior_is_optional_peer(b) or behavior_is_bundled(b):
        return None
    version = catalogs_resolve_range(lockfile, dependency)
    name = _peer_candidate_name(dependency, version)
    overridable = not behavior_is_workspace(b) and (dependency.version.tag != VERSION_TAG.NPM or not dependency.version.npm.is_alias)
    override_name = dependency.name if dependency.version.tag == VERSION_TAG.CATALOG else name
    if overridable and overrides_has_rule_for_name(lockfile, override_name):
        return None
    return version, name

def resolve_peer_dep_by_range(lockfile, version, name, is_candidate = None):
    """`resolve_peer_dep_by_range`: the first package of the name, by descending version, in range.

    Bun: src/install/lockfile/bun.lock.rs L3225–L3241 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        version: The range.
        name: The package name.
        is_candidate: A filter of package IDs, or `None` for every package.

    Returns:
        A package ID, or `None`.
    """
    for pkg_id in lockfile.package_index.get(name, []):
        if (resolution_satisfies_dependency_version(lockfile.packages[pkg_id].resolution, version) and
            (is_candidate == None or is_candidate(pkg_id))):
            return pkg_id
    return None

def resolve_peer_dep_version_based(lockfile, dependency, is_candidate = None):
    """`resolve_peer_dep_version_based`: a required peer by its range, not by the tree.

    Bun: src/install/lockfile/bun.lock.rs L3045–L3085 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        dependency: A dependency.
        is_candidate: A filter of package IDs, or `None`.

    Returns:
        A package ID, or `None`.
    """
    found = version_based_peer_range(lockfile, dependency)
    if found == None:
        return None
    return resolve_peer_dep_by_range(lockfile, found[0], found[1], is_candidate)

def linked_workspace_path(lockfile, name, version):
    """`linked_workspace_path`: the path of the workspace an npm range of its name links.

    Bun: src/install/lockfile.rs L2218–L2256 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        name: The package name.
        version: The range (`Query::Group`).

    Returns:
        The workspace path, or `None`.
    """
    path = lockfile.workspace_paths.get(name)
    if path == None:
        return None
    if query_is_star(version):
        return path
    workspace_version = lockfile.workspace_versions.get(name)
    if workspace_version == None:
        return None
    return path if query_satisfies(version, workspace_version) else None

def may_stay_unresolved(dependency):
    """`may_stay_unresolved`: an optional or peer dependency.

    Bun: src/install/lockfile/bun.lock.rs L3297–L3300 @ bun-v1.4.4

    Args:
        dependency: A dependency.

    Returns:
        Whether a fresh install may leave it unresolved.
    """
    return dependency.behavior & (BEHAVIOR.OPTIONAL | BEHAVIOR.PEER) != 0

def _dependency_resolution_failure(file, dependency, pkg_path):
    """`dependency_resolution_failure`.

    Bun: src/install/lockfile/bun.lock.rs L3302–L3345 @ bun-v1.4.4
    """
    b = dependency.behavior
    if b & BEHAVIOR.DEV:
        kind = "dev"
    elif b & BEHAVIOR.OPTIONAL:
        kind = "optional"
    elif b & BEHAVIOR.PEER:
        kind = "peer"
    elif b & BEHAVIOR.WORKSPACE:
        kind = "workspace"
    else:
        kind = "prod"
    if pkg_path != None:
        message = "Failed to resolve {} dependency '{}' for package '{}'".format(kind, dependency.name, pkg_path)
    else:
        message = "Failed to resolve root {} dependency '{}'".format(kind, dependency.name)
    return _failure(file, message + "; run `bun install` to rewrite bun.lock")

# --- parse_into_binary_lockfile ------------------------------------------------------------------

# `Tag::digest_len` of each algorithm `Tag::parse` names (integrity.rs L8-L11, L326-L335).
_DIGEST_LEN = {"sha1": 20, "sha256": 32, "sha384": 48, "sha512": 64}

# `STANDARD_ALPHABET_CHARS` (base64/lib.rs L416-L417).
_BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

# `u8::is_ascii_whitespace` other than the space: tab, line feed, form feed, carriage return.
_ASCII_WHITESPACE = ["\t", "\n", "\f", "\r"]

# `crate::repository::MAX_RESOLVED_TAG_LEN` (repository.rs L107).
_MAX_RESOLVED_TAG_LEN = 256

_SAFE_TAG_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_."

def _integrity_tag_parse(buf):
    """`Tag::parse`: the algorithm before the first `-` among the first 7 bytes, and its end.

    Bun: src/install/integrity.rs L307–L324 @ bun-v1.4.4
    """
    i = buf[:7].find("-")
    if i == -1 or len(buf) <= i + 1:
        return None, 0
    if buf[:i] not in _DIGEST_LEN:
        return None, 0
    return buf[:i], i + 1

def _integrity_parse_entry(buf):
    """`Integrity::parse_entry`: the entry's algorithm, or None where Bun reads `Tag::UNKNOWN`.

    Bun: src/install/integrity.rs L99–L164 @ bun-v1.4.4
    Bun: src/base64/lib.rs L548–L641 @ bun-v1.4.4

    The digest is checked as `STANDARD_NO_PAD`'s `calc_size_for_slice` and `decode` check it:
    its length is not 1 more than a multiple of 4, it decodes to at most the algorithm's digest
    length (a shorter one is accepted), each character is in the standard alphabet, and the bits
    after the last whole byte are zero. The decoded bytes are not needed: the ruleset downloads
    with the lockfile's text (feature 003 FR-021).
    """
    if len(buf) < len("sha256-"):
        return None
    tag, offset = _integrity_tag_parse(buf)
    if tag == None:
        return None
    expected_len = _DIGEST_LEN[tag]
    s = buf[offset:]
    question = s.find("?")
    if question != -1:
        s = s[:question]
    digits = s.rstrip("=")
    leftover = len(digits) % 4
    if leftover == 1:
        return None
    if len(digits) // 4 * 3 + leftover * 3 // 4 > expected_len:
        return None
    for c in digits.elems():
        if c not in _BASE64:
            return None
    unused = leftover * 6 % 8
    if unused and _BASE64.index(digits[-1]) % (1 << unused) != 0:
        return None
    return tag

def _integrity_is_supported(text):
    """`Integrity::parse` then `Tag::is_supported`: some whitespace-separated entry parses.

    Bun: src/install/integrity.rs L88–L97 @ bun-v1.4.4
    Bun: src/install/integrity.rs L290–L293 @ bun-v1.4.4

    `parse` keeps the strongest entry; it is supported exactly when one entry has an algorithm.
    """
    for c in _ASCII_WHITESPACE:
        text = text.replace(c, " ")
    for entry in text.split(" "):
        if _integrity_parse_entry(entry) != None:
            return True
    return False

def _parse_integrity(text, version, file, where):
    """`parse_integrity`: a refusal for a value that is neither empty nor supported, from v2.

    Bun: src/install/lockfile/bun.lock.rs L1688–L1711 @ bun-v1.4.4

    Before lockfileVersion 2 Bun warns and drops the value; the ruleset reads no integrity of a
    row it does not fetch, and an npm row's integrity it does not verify is refused when it
    downloads (feature 003 FR-021).
    """
    if not text or _integrity_is_supported(text) or version < 2:
        return None
    return _refusal(file, where, "Unsupported or malformed integrity hash")

def _is_safe_resolved_tag(resolved):
    """`is_safe_resolved_tag`: one path component of letters, digits, `-`, `_`, `.`.

    Bun: src/install/repository.rs L114–L123 @ bun-v1.4.4
    """
    if not resolved or len(resolved) > _MAX_RESOLVED_TAG_LEN or resolved[0] == "-":
        return False
    if resolved in [".", ".."]:
        return False
    for c in resolved.elems():
        if c not in _SAFE_TAG_CHARS:
            return False
    return True

def _row_tail(lockfile, res, entry, file, key):
    """The integrity and `.bun-tag` slots of a row, refused where Bun refuses them (T147).

    Bun: src/install/lockfile/bun.lock.rs L2636–L2735 @ bun-v1.4.4

    An npm row's integrity is slot 3 (`read_lockfile` checks that it is a string, L2640–L2648);
    a git or GitHub row's tag is the slot after the info object, then an optional integrity, which
    a tarball row has right after its info object. The values decide no binding.
    """
    if res.tag == RESOLUTION_TAG.NPM:
        return _parse_integrity(entry.integrity, lockfile.version, file, 'packages "{}" slot 3'.format(key))
    i = 0
    if res.tag in [RESOLUTION_TAG.GIT, RESOLUTION_TAG.GITHUB]:
        where = 'packages "{}" slot 2'.format(key)
        if i >= len(entry.tail):
            return _refusal(file, where, "Missing git dependency tag")
        bun_tag = entry.tail[i]
        i += 1
        if type(bun_tag) != "string":
            return _refusal(file, where, "Expected a string")
        enforce_safe_tag = res.tag == RESOLUTION_TAG.GITHUB or lockfile.version >= 2
        if len(bun_tag) > _MAX_RESOLVED_TAG_LEN or (enforce_safe_tag and not _is_safe_resolved_tag(bun_tag)):
            return _refusal(file, where, "Invalid git dependency tag")
    if res.tag in [RESOLUTION_TAG.LOCAL_TARBALL, RESOLUTION_TAG.REMOTE_TARBALL, RESOLUTION_TAG.GIT, RESOLUTION_TAG.GITHUB]:
        if i < len(entry.tail) and type(entry.tail[i]) == "string":
            return _parse_integrity(entry.tail[i], lockfile.version, file, 'packages "{}" slot {}'.format(key, i + 2))
    return None

def load_lockfile(lock, file):
    """`parse_into_binary_lockfile` up to `tag_workspace_links`: packages, then resolutions.

    Bun: src/install/lockfile/bun.lock.rs L1797–L3034 @ bun-v1.4.4

    `Lockfile::resolve` (L3036-L3039) is `lockfile_resolve`, which the caller runs with the hoister.

    Args:
        lock: The value of `read_lockfile`.
        file: The lockfile's label, for errors.

    Returns:
        `struct(value, error)`; `value` is the lockfile.
    """
    lockfile = struct(
        file = file,
        version = lock.version,
        packages = [],
        dependencies = [],
        resolutions = [],
        package_index = {},
        workspace_paths = {},
        workspace_versions = {},
        overrides = struct(map = {}, scoped = [], scoped_names = {}),
        catalogs = struct(default = {}, groups = {}),
        pkg_map = {},
        trees = [],
        hoisted_dependencies = [],
        patched = getattr(lock, "patched", []),
        cache = {},
    )

    error = _parse_overrides(lockfile.overrides, lock.overrides, file)
    if error:
        return error
    error = _parse_catalog(lockfile.catalogs.default, lock.catalog, file, "catalog")
    if error:
        return error
    for group_name, rows in lock.catalogs.items():
        if not group_name:
            return _refusal(file, "catalogs", "Expected a non-empty string")
        if type(rows) != "dict":
            return _refusal(file, "catalogs \"{}\"".format(group_name), "Expected an object")
        error = _parse_catalog(lockfile.catalogs.groups.setdefault(group_name, {}), rows, file, "catalogs \"{}\"".format(group_name))
        if error:
            return error

    # The workspaces: the last row of each name, in the order of `workspace_paths` (L2108-L2192).
    root_workspace = None
    member_rows = []
    for path, workspace in lock.workspaces.items():
        if path == "":
            root_workspace = workspace
            continue
        name = workspace.name
        if type(name) != "string" or not name:
            return _refusal(file, "workspace \"{}\"".format(path), "Expected a string name property")
        row = struct(path = path, name = name, workspace = workspace)
        if name in lockfile.workspace_paths:
            member_rows[list(lockfile.workspace_paths.keys()).index(name)] = row
        else:
            member_rows.append(row)
        lockfile.workspace_paths[name] = path
        if workspace.version != None:
            parsed = parse_version(workspace.version)
            if not parsed.valid:
                return _refusal(file, "workspace \"{}\"".format(path), "Invalid semver version")
            lockfile.workspace_versions[name] = parsed.version_min
    if root_workspace == None:
        return _refusal(file, "workspaces", "Expected root package")

    if type(root_workspace.name) != "string":
        return _refusal(file, "workspace \"\"", "Expected a string")
    unresolved_rows = []
    result = _parse_append_dependencies(lockfile, _workspace_obj(root_workspace), unresolved_rows, None, member_rows, True, file, "the workspace \"\"")
    if result.error:
        return result
    off, length = result.value
    root_name = root_workspace.name
    lockfile.packages.append(_package(root_name, struct(tag = RESOLUTION_TAG.ROOT, value = None), off, length, _meta(None, True)))
    _index_insert(lockfile, root_name, 0)

    # The `workspaceOnly` packages (L2263-L2305). On lockfileVersion 0 there are none: a member is a
    # package only through its `packages` row (L2263), which `lockfile.bzl` refuses (feature 006
    # ID-11), so the version-0 branches of the rows (L2479, L2553) are not reached and the
    # workspaces' own resolutions (L2859) have no workspace to resolve.
    workspace_only = member_rows if lockfile.version != 0 else []
    for row in workspace_only:
        result = _parse_append_dependencies(lockfile, _workspace_obj(row.workspace), unresolved_rows, None, None, True, file, "the workspace \"{}\"".format(row.path))
        if result.error:
            return result
        off, length = result.value
        package = _package(row.name, struct(tag = RESOLUTION_TAG.WORKSPACE, value = row.path), off, length, _meta(None, True), key = row.name)
        lockfile.pkg_map[row.name] = _append_package_dedupe(lockfile, package)
    members = range(1, 1 + len(workspace_only))

    # The bundle roots (L2323-L2358).
    bundled_pkgs = {key: True for key in lock.keys if lock.entries[key].bundled}

    for key in lock.keys:
        entry = lock.entries[key]
        where = "packages \"{}\"".format(key)
        if not entry.resolution:
            return _refusal(file, where, "Invalid package resolution")
        name = entry.name
        if name and not is_safe_install_folder_name(name):
            return _refusal(file, where, "invalid package name")
        parsed = resolution_from_text_lockfile(entry.resolution)
        if parsed.error:
            return _refusal(file, where, "Unexpected resolution")
        res = parsed.value

        if res.tag == RESOLUTION_TAG.WORKSPACE:
            if key in lockfile.pkg_map:
                # This workspace package is already in the map, as a `workspaceOnly` package.
                continue
            matched = None
            for workspace_pkg_id in members:
                if resolution_eql(res, lockfile.packages[workspace_pkg_id].resolution):
                    matched = workspace_pkg_id
                    break
            if matched == None:
                return _refusal(file, where, "Unknown workspace")
            lockfile.pkg_map[key] = matched
            continue

        if res.tag == RESOLUTION_TAG.ROOT:
            off, length = len(lockfile.dependencies), 0
        else:
            result = _parse_append_dependencies(lockfile, _row_obj(entry), unresolved_rows, (key, bundled_pkgs), None, False, file, where)
            if result.error:
                return result
            off, length = result.value
        refusal = _row_tail(lockfile, res, entry, file, key)
        if refusal:
            return refusal
        if res.tag in [RESOLUTION_TAG.GIT, RESOLUTION_TAG.GITHUB]:
            res = struct(tag = res.tag, value = repository_with_resolved(res.value, ""))
        info = struct(os = entry.os, cpu = entry.cpu, libc = entry.libc)
        package = _package(name, res, off, length, _meta(info, False), key = key, entry = entry)
        pkg_id = _append_package_dedupe(lockfile, package)

        # Each workspace was registered under its name; a root dependency of the same name replaces
        # it at that key, unless that dependency is a folder (L2748-L2760).
        existing = lockfile.pkg_map.get(key)
        if existing != None and not (res.tag != RESOLUTION_TAG.FOLDER and existing in members and lockfile.packages[existing].name == key):
            return _refusal(file, "packages key \"{}\"".format(key), "Duplicate package path")
        lockfile.pkg_map[key] = pkg_id

    lockfile.resolutions.extend([INVALID] * len(lockfile.dependencies))
    error = _resolve_rows(lockfile, lock, members, bundled_pkgs, file)
    if error:
        return error

    # The install that wrote bun.lock did not resolve these (L3027-L3031).
    for dep_id in unresolved_rows:
        lockfile.resolutions[dep_id] = INVALID

    tag_workspace_links(lockfile)
    return struct(value = lockfile, error = None)

def _resolve_rows(lockfile, lock, members, bundled_pkgs, file):
    """The resolutions of the root's, the workspaces' and each row's dependencies (S2).

    Bun: src/install/lockfile/bun.lock.rs L2765–L3025 @ bun-v1.4.4
    """
    packages = lockfile.packages
    dependencies = lockfile.dependencies
    resolutions = lockfile.resolutions
    pkg_map = lockfile.pkg_map

    def linked_member(dep):
        """The workspace member a peer's range matches, which the loader links the peer to, or None.

        Bun: src/install/lockfile/bun.lock.rs L2793–L2807 @ bun-v1.4.4
        """
        found = version_based_peer_range(lockfile, dep)
        if found == None or found[0].tag != VERSION_TAG.NPM:
            return None
        if linked_workspace_path(lockfile, found[1], found[0].npm.version) == None:
            return None
        for pkg_id in members:
            if packages[pkg_id].name == found[1]:
                return pkg_id
        return None

    def peer_by_version(dep):
        """The package a peer binds to by version, as hoisting binds it again later.

        Bun: src/install/lockfile/bun.lock.rs L2809–L2819 @ bun-v1.4.4
        """
        return resolve_peer_dep_version_based(lockfile, dep)

    def own_peer(dep):
        """A peer's own binding: the member its range matches, else the package by version.

        Bun: src/install/lockfile/bun.lock.rs L2820–L2820 @ bun-v1.4.4
        """
        member = linked_member(dep)
        return member if member != None else peer_by_version(dep)

    # first the root dependencies are resolved (L2822-L2855)
    for dep_id in dependency_ids(lockfile, 0):
        dep = dependencies[dep_id]
        named = pkg_map.get(dep.name)
        if behavior_is_workspace(dep.behavior) and not (named != None and named in members):
            bound = None
            for pkg_id in members:
                if packages[pkg_id].name == dep.name:
                    bound = pkg_id
                    break
            if bound == None:
                bound = named
        else:
            bound = own_peer(dep)
            if bound == None:
                bound = named
        if bound == None:
            if may_stay_unresolved(dep):
                continue
            return _dependency_resolution_failure(file, dep, None)
        resolutions[dep_id] = bound

    # then workspace dependencies are resolved (L2859-L2921)
    for pkg_id in members:
        workspace_name = packages[pkg_id].name

        # If a root dependency of the same name has this workspace's key, the workspace's
        # dependencies are printed under `./<name>`.
        unlinked = pkg_map.get(workspace_name) != pkg_id
        prefix = "./" if unlinked else ""
        for dep_id in dependency_ids(lockfile, pkg_id):
            dep = dependencies[dep_id]
            res_id = own_peer(dep)
            if res_id == None:
                res_id = pkg_map.get(prefix + workspace_name + "/" + dep.name)
            if res_id == None:
                res_id = pkg_map.get(dep.name)
            if res_id == None:
                if unlinked or may_stay_unresolved(dep):
                    continue
                return _dependency_resolution_failure(file, dep, workspace_name)
            resolutions[dep_id] = res_id

    # then each package dependency (L2923-L3025)
    bound_by = [_UNBOUND] * len(dependencies)
    root_dep_names = {dependencies[d].name: True for d in dependency_ids(lockfile, 0)}
    for key in lock.keys:
        pkg_id = pkg_map.get(key)
        if pkg_id == None:
            return _refusal(file, "packages key \"{}\"".format(key), "InvalidPackagesObject")
        res = packages[pkg_id].resolution
        if pkg_id == 0 or (res.tag == RESOLUTION_TAG.WORKSPACE and pkg_map.get(packages[pkg_id].name) == pkg_id):
            # The dependencies of the root and of this workspace were already resolved above.
            continue
        for dep_id in dependency_ids(lockfile, pkg_id):
            dep = dependencies[dep_id]

            # A stripped `catalog:` edge stays unresolved, as in a fresh install.
            if dep.version.tag == VERSION_TAG.UNINITIALIZED:
                continue

            # A registry package's peer prefers a published version in range over a workspace.
            by_version = own_peer(dep) if res.tag == RESOLUTION_TAG.WORKSPACE else peer_by_version(dep)
            if by_version != None:
                resolutions[dep_id] = by_version
                continue
            found = _find_resolution(pkg_map, key, dep.name, bundled_pkgs if behavior_is_optional_peer(dep.behavior) else None)
            if found.error == "InvalidPackageKey":
                return _refusal(file, "packages key \"{}\"".format(key), "Invalid package path")
            if found.error == "Unresolvable":
                if behavior_is_optional_peer(dep.behavior):
                    bound_by[dep_id] = _UNPROVIDED
                    resolutions[dep_id] = INVALID
                if may_stay_unresolved(dep):
                    continue
                return _dependency_resolution_failure(file, dep, key)
            evidence = found.evidence
            own_entry = evidence == _OWN_ENTRY
            if evidence == _WALKED_TO_ROOT and behavior_is_peer(dep.behavior) and dep.name in root_dep_names:
                evidence = _ROOT_DEPENDENCY
            elif (behavior_is_optional_peer(dep.behavior) and not own_entry and
                  not resolution_satisfies_dependency_version(packages[found.id].resolution, catalogs_resolve_range(lockfile, dep))):
                evidence = _REFUSED
            if bound_by[dep_id] > evidence:
                continue
            bound_by[dep_id] = evidence
            resolutions[dep_id] = found.id
    return None

def tag_workspace_links(lockfile):
    """`Lockfile::tag_workspace_links`: a dependency bound to a workspace becomes a workspace edge.

    Bun: src/install/lockfile.rs L2313–L2429 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile; its dependencies are replaced in place.
    """
    packages = lockfile.packages
    dependencies = lockfile.dependencies
    resolutions = lockfile.resolutions
    if not any([p.resolution.tag in [RESOLUTION_TAG.ROOT, RESOLUTION_TAG.WORKSPACE] for p in packages[1:]]) and 0 not in resolutions:
        return
    root_rows = dependency_ids(lockfile, 0) if packages else []
    local_rows = {}
    for pkg_id in range(len(packages)):
        if packages[pkg_id].resolution.tag in [RESOLUTION_TAG.ROOT, RESOLUTION_TAG.WORKSPACE]:
            for d in dependency_ids(lockfile, pkg_id):
                local_rows[d] = True
    for dep_id in range(len(dependencies)):
        pkg_id = resolutions[dep_id]
        if not is_valid(pkg_id):
            continue
        dep = dependencies[dep_id]
        res = packages[pkg_id].resolution

        # The root package's path.
        if res.tag == RESOLUTION_TAG.ROOT and dep.version.tag == VERSION_TAG.WORKSPACE:
            dep = _dependency(dep.name, dependency_version(VERSION_TAG.WORKSPACE, dep.version.literal, workspace = "."), dep.behavior)
            dependencies[dep_id] = dep
        if res.tag != RESOLUTION_TAG.WORKSPACE:
            continue
        is_peer = behavior_is_peer(dep.behavior)
        is_optional_peer = behavior_is_optional_peer(dep.behavior)
        if dep.version.tag == VERSION_TAG.WORKSPACE and is_peer and not is_optional_peer and dep_id not in local_rows:
            reparsed = dependency_parse(dep.name, dep.version.literal)
            if reparsed != None and reparsed.tag == VERSION_TAG.NPM:
                dep = _dependency(dep.name, reparsed, dep.behavior)
                dependencies[dep_id] = dep
        tag = dep.version.tag
        if tag == VERSION_TAG.WORKSPACE:
            linked = True
        elif tag == VERSION_TAG.NPM:
            linked = linked_workspace_path(lockfile, dep.version.npm.name, dep.version.npm.version) != None and (
                not is_peer or dep_id in local_rows or
                (not is_optional_peer and resolve_peer_dep_version_based(lockfile, dep) == None)
            )
        elif tag == VERSION_TAG.FOLDER:
            linked = dep_id in root_rows
        elif tag == VERSION_TAG.DIST_TAG:
            linked = dep_id in root_rows and dep.name in lockfile.workspace_paths and dep.version.dist_tag.name == dep.name
        else:
            linked = False
        if linked:
            dependencies[dep_id] = _dependency(dep.name, dependency_version(VERSION_TAG.WORKSPACE, dep.version.literal, workspace = res.value), dep.behavior)

def rebind_peers_to_printed_packages(lockfile):
    """`rebind_peers_to_printed_packages`: peers whose target no tree prints, bound as on reload.

    Bun: src/install/lockfile/bun.lock.rs L3243–L3295 @ bun-v1.4.4

    Args:
        lockfile: A hoisted lockfile; its resolutions change in place.
    """
    printed = {}
    for pkg_id in range(len(lockfile.packages)):
        if lockfile.packages[pkg_id].resolution.tag in [RESOLUTION_TAG.ROOT, RESOLUTION_TAG.WORKSPACE]:
            printed[pkg_id] = True
    for dep_id in lockfile.hoisted_dependencies:
        if is_valid(lockfile.resolutions[dep_id]):
            printed[lockfile.resolutions[dep_id]] = True
    for dep_id in range(len(lockfile.dependencies)):
        target = lockfile.resolutions[dep_id]
        dep = lockfile.dependencies[dep_id]
        if not is_valid(target) or target in printed or not behavior_is_peer(dep.behavior):
            continue
        printed_target = resolve_peer_dep_version_based(lockfile, dep, lambda pkg_id: pkg_id in printed)
        if printed_target != None:
            lockfile.resolutions[dep_id] = printed_target

def lockfile_resolve(lockfile, hoist):
    """`Lockfile::resolve`: hoist while a pass binds a peer late, then rebind unprinted peers.

    Bun: src/install/lockfile.rs L1615–L1625 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        hoist: `bun_tree.bzl`'s `hoist(lockfile)`, returning `struct(late_bound_peer, error)`.

    Returns:
        An error, or `None`.
    """
    for _ in range(_LIMIT):
        hoisted = hoist(lockfile)
        if hoisted.error:
            return hoisted.error
        if not hoisted.late_bound_peer:
            break
    rebind_peers_to_printed_packages(lockfile)
    return None

# --- reachable.rs --------------------------------------------------------------------------------

def _peer_provider(lockfile, owner, name):
    """`peer_provider`: the dependency of `owner` that provides `name` to the packages below it.

    Bun: src/install/lockfile/reachable.rs L190–L221 @ bun-v1.4.4
    """
    is_project = lockfile.packages[owner].resolution.tag in [RESOLUTION_TAG.ROOT, RESOLUTION_TAG.WORKSPACE]
    best = None
    for dep_id in dependency_ids(lockfile, owner):
        dep = lockfile.dependencies[dep_id]
        if dep.name != name:
            continue
        if behavior_is_peer(dep.behavior):
            provides = is_project and not behavior_is_optional_peer(dep.behavior)
        else:
            target = lockfile.resolutions[dep_id]
            provides = is_valid(target) and lockfile.packages[target].name == name

        # `min_by_key(is_peer)`: the first regular dependency, else the first peer.
        if provides and (best == None or (behavior_is_peer(lockfile.dependencies[best].behavior) and not behavior_is_peer(dep.behavior))):
            best = dep_id
    return best

def _packages_without_peer_provider(lockfile, name):
    """`packages_without_peer_provider`: the packages no provider of `name` is at or above.

    Bun: src/install/lockfile/reachable.rs L223–L254 @ bun-v1.4.4
    """
    provided = {}
    stack = [pkg_id for pkg_id in range(len(lockfile.packages)) if _peer_provider(lockfile, pkg_id, name) != None]
    for pkg_id in stack:
        provided[pkg_id] = True
    for _ in range(_LIMIT):
        if not stack:
            break
        pkg_id = stack.pop()
        for row in dependency_ids(lockfile, pkg_id):
            target = lockfile.resolutions[row]
            if not behavior_is_peer(lockfile.dependencies[row].behavior) and is_valid(target) and target not in provided:
                provided[target] = True
                stack.append(target)
    return {pkg_id: True for pkg_id in range(len(lockfile.packages)) if pkg_id not in provided}

def _packages_reached_without_peer_provider(lockfile, name):
    """`packages_reached_without_peer_provider`: reached from the root without passing a provider.

    Bun: src/install/lockfile/reachable.rs L256–L284 @ bun-v1.4.4
    """
    seen = {0: True}
    reached = {}
    stack = [0]
    for _ in range(_LIMIT):
        if not stack:
            break
        pkg_id = stack.pop()
        if _peer_provider(lockfile, pkg_id, name) != None:
            continue
        reached[pkg_id] = True
        for row in dependency_ids(lockfile, pkg_id):
            target = lockfile.resolutions[row]
            if not behavior_is_peer(lockfile.dependencies[row].behavior) and is_valid(target) and target not in seen:
                seen[target] = True
                stack.append(target)
    return reached

def _collect(lockfile, name):
    """`PeerRanges::collect`: who lacks a provider of `name`, and the distinct unprovided ranges.

    Bun: src/install/lockfile/bun.lock.rs L3135–L3169 @ bun-v1.4.4
    """
    missing = _packages_without_peer_provider(lockfile, name)
    somewhere = _packages_reached_without_peer_provider(lockfile, name)
    rows = {}
    for owner in range(len(lockfile.packages)):
        if owner not in somewhere or lockfile.packages[owner].resolution.tag != RESOLUTION_TAG.NPM:
            continue
        for dep_id in dependency_ids(lockfile, owner):
            found = version_based_peer_range(lockfile, lockfile.dependencies[dep_id])
            if found != None and found[1] == name and found[0].tag == VERSION_TAG.NPM:
                # One row per distinct range text (Bun keys them by its hash).
                rows.setdefault(found[0].literal, dep_id)
    return missing, sorted(rows.values())

def shared_version(lockfile, cache, owner, dep_id):
    """`PeerRanges::shared_version`: the highest version every unprovided range on the name accepts.

    Bun: src/install/lockfile/bun.lock.rs L3102–L3133 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        cache: A dict kept for one lockfile (`PeerRangeCache`).
        owner: The package whose peer it is.
        dep_id: The peer dependency.

    Returns:
        A package ID, or `INVALID` when no package provides none (or nothing is shared).
    """
    found = version_based_peer_range(lockfile, lockfile.dependencies[dep_id])
    if found == None:
        return INVALID
    version, name = found
    candidates = lockfile.package_index.get(name, [])
    if len(candidates) < 2:
        return INVALID
    if name not in cache:
        cache[name] = _collect(lockfile, name)
    missing, rows = cache[name]
    if owner not in missing:
        return INVALID
    for pkg_id in candidates:
        resolution = lockfile.packages[pkg_id].resolution
        if not resolution_satisfies_dependency_version(resolution, version):
            continue
        if all([resolution_satisfies_dependency_version(resolution, catalogs_resolve_range(lockfile, lockfile.dependencies[row])) for row in rows]):
            return pkg_id
    return INVALID

def is_weak_peer(lockfile, dep_id, target):
    """`Lockfile::is_weak_peer`: an optional peer, or a peer bound outside its range, not overridden.

    Bun: src/install/lockfile.rs L845–L858 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile.
        dep_id: A dependency ID.
        target: The package it is bound to.

    Returns:
        Whether the dependency must not keep its target alive.
    """
    dependency = lockfile.dependencies[dep_id]
    if not behavior_is_peer(dependency.behavior) or behavior_is_optional_peer(dependency.behavior):
        return behavior_is_peer(dependency.behavior)
    version = catalogs_resolve_range(lockfile, dependency)
    if version.tag != VERSION_TAG.NPM:
        return False
    target_version = package_version(lockfile, target)
    if target_version == None or query_satisfies(version.npm.version, target_version):
        return False
    return not is_overridden_dependency(lockfile, dep_id)

def _held_at_load(lockfile):
    """`Lockfile::mark_loaded_packages`: the packages a dependency other than a weak peer holds.

    Bun: src/install/lockfile.rs L2296–L2311 @ bun-v1.4.4
    """
    held = {}
    for dep_id in range(len(lockfile.dependencies)):
        target = lockfile.resolutions[dep_id]
        if is_valid(target) and not is_weak_peer(lockfile, dep_id, target):
            held[target] = True
    return held

def _clone_dependency(dependency):
    """`Dependency::clone_in`: a workspace edge keeps its path; any other literal is parsed again.

    Bun: src/install/dependency.rs L185–L239 @ bun-v1.4.4
    """
    if dependency.version.tag == VERSION_TAG.WORKSPACE:
        return dependency
    version = dependency_parse(dependency.name, dependency.version.literal, dependency.version.tag)
    if version == None:
        version = dependency_version(VERSION_TAG.UNINITIALIZED, dependency.version.literal)
    return _dependency(dependency.name, version, dependency.behavior)

def _clone_package(old, new, cloner, old_id):
    """`Package::clone`: copy one package and its dependencies; queue the targets not yet copied.

    Bun: src/install/lockfile/Package.rs L423–L566 @ bun-v1.4.4
    """
    package = old.packages[old_id]
    prev_len = len(new.dependencies)
    old_ids = dependency_ids(old, old_id)
    for dep_id in old_ids:
        new.dependencies.append(_clone_dependency(old.dependencies[dep_id]))
        new.resolutions.append(INVALID)
    new_id = len(new.packages)
    new.packages.append(_package(package.name, package.resolution, prev_len, len(old_ids), package.meta, package.key, package.entry))
    _index_insert(new, package.name, new_id)
    cloner.mapping[old_id] = new_id
    for i, dep_id in enumerate(old_ids):
        old_resolution = old.resolutions[dep_id]
        if not is_valid(old_resolution):
            continue
        pending = (old_resolution, prev_len + i)

        # A weak peer must not keep its target alive. It's bound in `flush`.
        if is_weak_peer(old, dep_id, old_resolution) and old_resolution in cloner.held_at_load:
            cloner.weak_peers.append(pending)
            continue
        mapped = cloner.mapping.get(old_resolution, INVALID)
        if is_valid(mapped):
            new.resolutions[prev_len + i] = mapped
        else:
            cloner.clone_queue.append(pending)
    return new_id

def _peer_on_last_copy(old, new, cloner):
    """`Cloner::peer_on_last_copy`: a required weak peer whose target was the last of its name.

    Bun: src/install/lockfile.rs L1540–L1555 @ bun-v1.4.4
    """
    for i, (old_resolution, resolve_id) in enumerate(cloner.weak_peers):
        if (not is_valid(cloner.mapping.get(old_resolution, INVALID)) and
            not behavior_is_optional_peer(new.dependencies[resolve_id].behavior) and
            not new.package_index.get(old.packages[old_resolution].name)):
            last = cloner.weak_peers.pop()
            if i < len(cloner.weak_peers):
                cloner.weak_peers[i] = last
            return (old_resolution, resolve_id)
    return None

def lockfile_clean(lockfile, hoist):
    """`clean_lockfile`: `tag_workspace_links`, then `clean_with_logger` of a frozen install.

    Bun: src/install/PackageManager/install_with_manager.rs L2378–L2410 @ bun-v1.4.4
    Bun: src/install/lockfile.rs L1236–L1436 @ bun-v1.4.4
    Bun: src/install/lockfile.rs L1557–L1608 @ bun-v1.4.4

    The copy keeps the overrides, catalogs and workspaces; trusted dependencies, scripts and
    patched dependencies decide no link. With a frozen lockfile `flush` reports no moved row, so
    no second clean runs (L1409-L1421).

    Args:
        lockfile: A loaded and resolved lockfile.
        hoist: `bun_tree.bzl`'s `hoist`.

    Returns:
        `struct(value, error)`; `value` is the new lockfile.
    """
    held_at_load = _held_at_load(lockfile)
    tag_workspace_links(lockfile)
    new = struct(
        file = lockfile.file,
        version = lockfile.version,
        packages = [],
        dependencies = [],
        resolutions = [],
        package_index = {},
        workspace_paths = dict(lockfile.workspace_paths),
        workspace_versions = dict(lockfile.workspace_versions),
        overrides = lockfile.overrides,
        catalogs = lockfile.catalogs,
        pkg_map = {},
        trees = [],
        hoisted_dependencies = [],
        patched = lockfile.patched,
        cache = {},
    )
    cloner = struct(mapping = {}, clone_queue = [], weak_peers = [], held_at_load = held_at_load)

    # Step 1. Recreate the lockfile with only the packages that are still alive.
    if not lockfile.packages:
        return struct(value = new, error = None)
    _clone_package(lockfile, new, cloner, 0)

    # `Cloner::flush` (L1559-L1580).
    for _ in range(_LIMIT):
        if cloner.clone_queue:
            to_clone = cloner.clone_queue.pop()
        else:
            to_clone = _peer_on_last_copy(lockfile, new, cloner)
            if to_clone == None:
                break
        old_resolution, resolve_id = to_clone
        mapped = cloner.mapping.get(old_resolution, INVALID)
        if is_valid(mapped):
            new.resolutions[resolve_id] = mapped
            continue
        new.resolutions[resolve_id] = _clone_package(lockfile, new, cloner, old_resolution)
    for old_resolution, resolve_id in cloner.weak_peers:
        mapped = cloner.mapping.get(old_resolution, INVALID)
        if is_valid(mapped):
            new.resolutions[resolve_id] = mapped
    cloner.weak_peers.clear()

    for key, old_id in lockfile.pkg_map.items():
        mapped = cloner.mapping.get(old_id, INVALID)
        if is_valid(mapped):
            new.pkg_map[key] = mapped
    error = lockfile_resolve(new, hoist)
    if error:
        return struct(value = None, error = error)
    return struct(value = new, error = None)
