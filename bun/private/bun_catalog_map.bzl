"""Bun's catalogs, carried over from bun-v1.4.4 (feature 007, research R4, R5).

`CatalogMap.rs` holds the catalogs a root `package.json` declares: the default catalog (the
singular `catalog`) and the named groups of `catalogs`, `catalogs.default` among them.
`catalog_parse_append` reads them from one object of the root, as `Package::parse` calls it
(`root_catalogs` in `bun_package.bzl`); `catalog_find`, `catalogs_resolve_range` and
`catalog_strip_reference` look `catalog:` dependencies up in them, for the lockfile loader
(`bun_lockfile.bzl`, which reads `bun.lock`'s catalogs with `_parse_catalog`) and the hoisting
(`bun_tree.bzl`).

The catalogs are `struct(default, groups)`: `default` maps a name to its `Dependency`, `groups` a
catalog name to such a map. Names stand in for Bun's name hashes. Errors are returned as values.
"""

load(
    ":bun_install_types.bzl",
    "BEHAVIOR",
    "VERSION_TAG",
    "behavior_is_peer",
    "dependency_parse",
    "dependency_version",
    "new_dependency",
)
load(":bun_semver.bzl", "parse_query")

def catalog_find(catalogs, catalog_name, dep_name):
    """`CatalogMap::find`: the default catalog is `""` and `default`, the one named first.

    Bun: src/install/lockfile/CatalogMap.rs L54–L115 @ bun-v1.4.4

    Args:
        catalogs: `struct(default, groups)`.
        catalog_name: The catalog a `catalog:` reference names, `""` for `catalog:`.
        dep_name: The dependency's name.

    Returns:
        The entry's `Dependency`, or `None`.
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
    entry = catalog_find(lockfile.catalogs, dependency.version.catalog, dependency.name)
    return entry.version if entry != None else dependency.version

def catalog_strip_reference(dependency):
    """`CatalogMap::strip_reference`: outside the root and workspaces, `catalog:` resolves nothing.

    Bun: src/install/lockfile/CatalogMap.rs L209–L237 @ bun-v1.4.4

    Args:
        dependency: A dependency of a package.

    Returns:
        The dependency, its `catalog:` version replaced.
    """
    if dependency.version.tag != VERSION_TAG.CATALOG:
        return dependency
    literal = dependency.version.literal
    if not behavior_is_peer(dependency.behavior):
        return new_dependency(dependency.name, dependency_version(VERSION_TAG.UNINITIALIZED, literal), dependency.behavior)
    star = struct(name = dependency.name, version = parse_query("*"), is_alias = False)
    return new_dependency(dependency.name, dependency_version(VERSION_TAG.NPM, literal, npm = star), dependency.behavior | BEHAVIOR.OPTIONAL)

def _get_or_put_group(catalogs, catalog_name):
    """`CatalogMap::get_or_put_group`: `""` is the default catalog.

    Bun: src/install/lockfile/CatalogMap.rs L239–L261 @ bun-v1.4.4
    """
    if not catalog_name:
        return catalogs.default
    return catalogs.groups.setdefault(catalog_name, {})

def catalog_parse_append(catalogs, obj, file):
    """`CatalogMap::parse_append`: the `catalog` and `catalogs` of one object of the root.

    `found_any` is whether the object holds either key, whatever its value. A name in both
    `catalog` and `catalogs.default` is an error, as Bun then installs nothing.

    Bun: src/install/lockfile/CatalogMap.rs L285–L342 @ bun-v1.4.4

    Args:
        catalogs: `struct(default, groups)`, changed in place.
        obj: The decoded root `package.json`, or its `workspaces` value (any JSON value).
        file: The `package.json`'s name, for errors.

    Returns:
        `struct(found_any, error)`.
    """
    found_any = False
    if type(obj) != "dict":
        return struct(found_any = found_any, error = None)
    if "catalog" in obj:
        found_any = True
        error = _parse_append_group(_get_or_put_group(catalogs, ""), obj["catalog"], file)
        if error:
            return struct(found_any = found_any, error = error)
    if "catalogs" in obj:
        found_any = True
        if type(obj["catalogs"]) == "dict":
            for catalog_name, catalog in obj["catalogs"].items():
                error = _parse_append_group(_get_or_put_group(catalogs, catalog_name), catalog, file)
                if error:
                    return struct(found_any = found_any, error = error)

    # `default` is only fed by the singular `catalog` object; `catalogs.default` lands in `groups`.
    default_group = obj["catalogs"].get("default") if type(obj.get("catalogs")) == "dict" else None
    if catalogs.default and type(default_group) == "dict":
        for dep_name in default_group:
            if dep_name in catalogs.default:
                return struct(found_any = found_any, error = '{}: "{}" is defined in both "catalog" and "catalogs.default"; keep one of them'.format(file, dep_name))
    return struct(found_any = found_any, error = None)

def _parse_append_group(group, catalog, file):
    """`parse_append_group`: one catalog's `name: version` entries; a non-string value is skipped.

    Bun: src/install/lockfile/CatalogMap.rs L344–L396 @ bun-v1.4.4
    """
    if type(catalog) != "dict":
        return None
    for dep_name, value in catalog.items():
        if type(value) != "string":
            continue
        version = dependency_parse(dep_name, value)
        if version == None:
            return '{}: the catalog entry "{}": "{}" is an invalid dependency version'.format(file, dep_name, value)
        if dep_name in group:
            return '{}: the catalog entry "{}" is a duplicate catalog'.format(file, dep_name)
        group[dep_name] = new_dependency(dep_name, version, 0)
    return None
