"""Normalization of `package.json` overrides to the form `bun.lock` records (FR-006, research R9).

bun.com (`pm/overrides`): "When a `package.json` has both fields, Bun uses only `"overrides"` and
does not read `"resolutions"`"; `overrides` accepts the npm object form, the pnpm `>` form and a
parent with a version range, `resolutions` Yarn's path form (with `**`); "Bun supports only one
parent level. It ignores `a>b>c`, `a/b/c`, and deeper object nesting with a warning." Each form
maps to the nested object form the lockfile records, as the fixtures the pinned Bun wrote show; a
form no fixture pins is an error rather than a guess. A value `$<name>` stands for the specifier
the root declares for `<name>`, else the one every workspace that declares `<name>` declares, as
Bun reads it (feature 006 T177, T179). Errors are returned as values.
"""

load(":bun_install_types.bzl", "BEHAVIOR", "dependency_sort_key")
load(":lockfile.bzl", "DEPENDENCY_KINDS", "split_key")

_FORMS = ('use a form bun.com documents in pm/overrides that rules_bun reads: "b", "a>b", ' +
          '"a@<range>>b" or {"a": {".": ..., "b": ...}} in "overrides", "b", "a/b" or "**/a/**/b" in "resolutions"')

def _error(message):
    return struct(value = None, error = message)

def _unread(file, field, key):
    return _error('{}: the {} entry "{}" has a form rules_bun cannot compare with bun.lock; {}'.format(file, field, key, _FORMS))

def _path(field, key):
    """The package names of a rule key, or `None` for a form rules_bun does not read."""
    if field == "overrides":
        return key.split(">")
    segments = split_key(key)
    if "**" not in segments:
        return segments
    if len(segments) == 4 and segments[0] == "**" and segments[2] == "**" and "**" not in [segments[1], segments[3]]:
        return [segments[1], segments[3]]
    return None

# The root's dependency maps in the order `Package::parse` reads them, with their behavior.
_ROOT_GROUPS = [
    ("dependencies", BEHAVIOR.PROD),
    ("devDependencies", BEHAVIOR.DEV),
    ("optionalDependencies", BEHAVIOR.OPTIONAL),
    ("peerDependencies", BEHAVIOR.PEER),
]

def _declared(manifest, name):
    """`declared_dependency`: the first string specifier of `name` in a workspace's four maps.

    Bun: src/install/lockfile/OverrideMap.rs L1373–L1380 @ bun-v1.4.4
    """
    for kind in DEPENDENCY_KINDS:
        dependencies = manifest.get(kind)
        if type(dependencies) == "dict" and type(dependencies.get(name)) == "string":
            return dependencies[name]
    return None

def _root_declared(manifest, name):
    """The specifier of the root package's first dependency named `name`, as Bun lists them.

    `Package::parse` reads the four maps in order; an `optionalDependencies` entry replaces the
    first earlier entry of its name, a name only in `peerDependenciesMeta` (`"optional": true`) is an
    optional peer `"*"`, and the list is sorted by `Dependency::cmp` (dev, optional, prod, then peer
    entries) before the overrides read the first entry of the name (feature 006 T179).

    Bun: src/install/lockfile/OverrideMap.rs L1286–L1297 @ bun-v1.4.4
    Bun: src/install/lockfile/Package.rs L2642–L2700, L2467–L2484, L3326–L3388 @ bun-v1.4.4
    """
    found = []
    for kind, behavior in _ROOT_GROUPS:
        dependencies = manifest.get(kind)
        if type(dependencies) != "dict" or type(dependencies.get(name)) != "string":
            continue
        dependency = struct(behavior = behavior, name = name, literal = dependencies[name])

        # "duplicate dependencies are allowed in optionalDependencies" (Package.rs L2473–L2483).
        if behavior == BEHAVIOR.OPTIONAL and found:
            found[0] = dependency
        else:
            found.append(dependency)
    meta = manifest.get("peerDependenciesMeta")
    optional = type(meta) == "dict" and type(meta.get(name)) == "dict" and meta[name].get("optional") == True
    if optional and not [d for d in found if d.behavior == BEHAVIOR.PEER]:
        found.append(struct(behavior = BEHAVIOR.PEER | BEHAVIOR.OPTIONAL, name = name, literal = "*"))
    if not found:
        return None
    return sorted(found, key = dependency_sort_key)[0].literal

def _reference(value, manifest, members):
    """The specifier an override value stands for: `value`, or for `$<name>` the declared one.

    A `$<name>` reference is the specifier the root declares for `<name>` (`_root_declared`), else
    the one every workspace that declares `<name>` declares; Bun ignores the rule, with a warning,
    when nothing declares it or the workspaces declare different specifiers (feature 006 T177, T179).

    Bun: src/install/lockfile/OverrideMap.rs L1278–L1335, L1405–L1452 @ bun-v1.4.4

    Returns:
        The specifier, or `None` for a rule Bun ignores.
    """
    if not value.startswith("$"):
        return value
    name = value[1:]
    declared = _root_declared(manifest, name)
    if declared != None:
        return declared
    found = None
    for member in members:
        declared = _declared(member, name)
        if declared == None:
            continue
        if found != None and found != declared:
            return None
        found = declared
    return found

def normalize_overrides(manifest, file, members = []):
    """The overrides of a root `package.json`, in the nested form `bun.lock` records.

    Args:
        manifest: The decoded `package.json`.
        file: The file's name, for errors.
        members: The decoded `package.json` of each workspace member, for `$<name>` references.

    Returns:
        `struct(value, error)`; `value` maps a package (or `<parent>`, `<parent>@<range>`) to a
        version or to a map of the overridden dependencies under that parent.
    """
    if "overrides" in manifest:
        field = "overrides"
    elif "resolutions" in manifest:
        field = "resolutions"
    else:
        return struct(value = {}, error = None)
    rules = manifest[field]
    if type(rules) != "dict":
        return _error('{}: "{}" is not an object; {}'.format(file, field, _FORMS))

    result = {}
    for key, value in rules.items():
        if field == "overrides" and type(value) == "dict":
            children = {}
            for child_key, child_value in value.items():
                # An object one level deeper: Bun ignores it with a warning ("Bun currently only
                # supports one level of nested", OverrideMap.rs L902-L905, L1173-L1180; T177).
                if type(child_value) == "dict":
                    continue
                if type(child_value) != "string":
                    return _unread(file, field, key)
                child_value = _reference(child_value, manifest, members)
                if child_value != None:
                    children[child_key] = child_value
            if not children:
                continue
            if type(result.get(key, {})) != "dict":
                return _unread(file, field, key)
            result[key] = dict(result.get(key, {}), **children)
            continue
        if type(value) != "string":
            return _unread(file, field, key)
        value = _reference(value, manifest, members)
        if value == None:
            continue
        path = _path(field, key)
        if path == None:
            return _unread(file, field, key)
        if len(path) == 1:
            if path[0] in result:
                return _unread(file, field, key)
            result[path[0]] = value
        elif len(path) == 2:
            parent = result.setdefault(path[0], {})
            if type(parent) != "dict":
                return _unread(file, field, key)
            parent[path[1]] = value

        # Deeper chains: ignored, as Bun ignores them.
    return struct(value = result, error = None)
