"""Reader of `bun.lock` (FR-007, research R1 and Part 3).

It reads exactly the accesses research Part 3 lists; each line that reads a lockfile key or slot
carries the access's ID (`# L<n>`), so the inventory can be matched to the code (SC-007). Errors
are returned as values, not raised.
"""

load(":jsonc.bzl", "jsonc_decode")

SUPPORTED_VERSIONS = [1, 2, 3]

DEPENDENCY_KINDS = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"]

def _error(message):
    return struct(value = None, error = message)

def split_key(key):
    """Splits a `packages` key into package names, keeping `@scope/name` together (research R2).

    Args:
        key: A key such as `c/b` or `@s/a/@s/b`.

    Returns:
        List of package names: `["c", "b"]`, `["@s/a", "@s/b"]`.
    """
    parts = key.split("/")
    segments = []
    scope = None
    for part in parts:
        if scope != None:
            segments.append(scope + "/" + part)
            scope = None
        elif part.startswith("@"):
            scope = part
        else:
            segments.append(part)
    if scope != None:
        segments.append(scope)
    return segments

def split_spec(spec):
    """Splits `<name>@<resolution>` at the `@` after the name (a scope's `@` is part of the name).

    Args:
        spec: Slot 0 of a lockfile entry.

    Returns:
        `(name, resolution)`, or `None` when `spec` holds no such `@`.
    """
    at = spec.find("@", 1)
    if at == -1:
        return None
    return spec[:at], spec[at + 1:]

def _kind(resolution):
    if resolution.startswith("workspace:"):
        return "workspace"
    if resolution.startswith("file:"):
        return "file"
    if resolution.startswith("http://") or resolution.startswith("https://"):
        return "tarball"
    if ":" in resolution or "/" in resolution or "#" in resolution:
        return "unsupported"
    return "npm"

def _strings(value):
    """A string or a list of strings as a list (`os`, `cpu`, `libc`: a string when one value).

    Bun reads the strings of a list and nothing else (`negatable_from_json_value`, npm.rs
    L850-L865), so other values give no entry.
    """
    if type(value) == "string":
        return [value]
    if type(value) == "list":
        return [item for item in value if type(item) == "string"]
    return []

def _names(value, file, owner, field):
    """`(names, error)` of `optionalPeers` or `unresolved`: a list of strings (LOCK L3372-L3400).

    The value is not printed: the reader has not checked it.
    """
    if value == None:
        return [], None
    if type(value) != "list" or any([type(item) != "string" for item in value]):
        return None, "{}: {} has a field \"{}\" that is not a list of strings; run `bun install` to rewrite bun.lock".format(file, owner, field)
    return list(value), None

def _dependencies(value, file, owner, field):
    """`(map, error)` of a dependency map: an object whose values are strings (LOCK L3405-L3426).

    Bun refuses another value ("Expected an object", "Expected a string"); the value is not printed.
    """
    if value == None:
        return {}, None
    if type(value) != "dict":
        return None, "{}: {} has a field \"{}\" that is not an object; run `bun install` to rewrite bun.lock".format(file, owner, field)
    for name, version in value.items():
        if type(version) != "string":
            return None, "{}: {} has a field \"{}\" whose entry \"{}\" is not a string; run `bun install` to rewrite bun.lock".format(file, owner, field, name)
    return dict(value), None

def _bin(name, value):
    """`bin` as a name-to-path map; a string `bin` is named after the package without its scope."""
    if value == None:
        return {}
    if type(value) == "string":
        return {name.split("/")[-1]: value}
    return dict(value)

def _entry(key, entry, file):
    if type(entry) != "list" or len(entry) == 0 or type(entry[0]) != "string":  # L7, L9
        return _error("{}: the packages entry \"{}\" does not start with a \"<name>@<resolution>\" string".format(file, key))
    spec = split_spec(entry[0])  # L9, L21
    if spec == None:
        return _error("{}: the packages entry \"{}\" has slot 0 \"{}\", which is not \"<name>@<resolution>\"".format(file, key, entry[0]))
    name, resolution = spec
    segments = split_key(key)  # L8
    kind = _kind(resolution)
    url = ""
    integrity = ""
    info = {}
    if kind == "npm":
        if len(entry) != 4:
            return _error("{}: the npm entry \"{}\" has {} slots, not 4".format(file, key, len(entry)))
        for slot, expected in [(1, "string"), (2, "dict"), (3, "string")]:
            if type(entry[slot]) != expected:
                return _error("{}: slot {} of the npm entry \"{}\" is a {}, not a {}".format(file, slot, key, type(entry[slot]), expected))
        url = entry[1]  # L10
        info = entry[2]  # L11
        integrity = entry[3]  # L12
    elif kind == "workspace":
        pass  # L22: ["<name>@workspace:<path>"]
    elif not resolution.startswith("root:"):
        # Every other resolution has its info object in slot 1 (LOCK L2557-L2591); rules_bun does not
        # fetch these (FR-010), but the dependencies they declare are linked (BC-8).
        if len(entry) < 2 or type(entry[1]) != "dict":
            return _error("{}: the packages entry \"{}\" has no info object in slot 1; run `bun install` to rewrite bun.lock".format(file, key))
        info = entry[1]  # L31

    owner = "the packages entry \"{}\"".format(key)
    unresolved, error = _names(info.get("unresolved"), file, owner, "unresolved")  # L23
    if error:
        return _error(error)
    optional_peers, error = _names(info.get("optionalPeers"), file, owner, "optionalPeers")  # L14
    if error:
        return _error(error)
    maps = {}
    for field in DEPENDENCY_KINDS:
        maps[field], error = _dependencies(info.get(field), file, owner, field)  # L13, L14, L32
        if error:
            return _error(error)
    bundled = info.get("bundled")  # L26: Bun skips a value that is not a boolean (LOCK L2351).
    return struct(
        value = struct(
            key = key,
            segments = segments,
            alias = segments[-1],
            kind = kind,
            name = name,
            version = resolution[len("workspace:"):] if kind == "workspace" else resolution,
            resolution = resolution,
            url = url,
            integrity = integrity,
            dependencies = maps["dependencies"],  # L13
            dev_dependencies = maps["devDependencies"],  # L32
            optional_dependencies = maps["optionalDependencies"],  # L13
            peers = maps["peerDependencies"],  # L14
            optional_peers = optional_peers,  # L14
            unresolved = unresolved,  # L23
            bundled = bundled == True,  # L26
            os = _strings(info.get("os")),  # L15
            cpu = _strings(info.get("cpu")),  # L15
            libc = _strings(info.get("libc")),  # Written by Bun 1.4.4 (canary C-LIBC)
            bin = _bin(name, info.get("bin")),  # L16
        ),
        error = None,
    )

def read_lockfile(text, file):
    """Reads a `bun.lock`.

    Args:
        text: The file's text.
        file: The file's name, for error messages.

    Returns:
        `struct(value, error)`; `value` is `struct(version, workspaces, entries, keys, overrides,
        catalog, catalogs, patched)`: `workspaces` maps a member path (`""` for the root) to
        `struct(path, name, version, unresolved, optional_peers, <dependency kinds>)`, `entries`
        maps a `packages` key to an entry struct (data-model "Lockfile model"), `keys` lists the
        `packages` keys in the order of the file, `overrides`, `catalog` and `catalogs` are the
        top-level maps as written, and `patched` lists the `name@version` keys of
        `patchedDependencies`.
    """
    decoded = jsonc_decode(text, file)  # L1
    if decoded.error:
        return _error("{}; run `bun install` to rewrite bun.lock".format(decoded.error))
    lock = decoded.value
    if type(lock) != "dict":
        return _error("{}: the lockfile is not a JSON object; run `bun install` to rewrite bun.lock".format(file))
    version = lock.get("lockfileVersion")  # L2
    if version not in SUPPORTED_VERSIONS:
        return _error(
            ("{}: lockfileVersion {} is not supported; rules_bun reads lockfileVersion 1, 2 and 3, " +
             "the versions Bun 1.4.4 writes: run `bun install` with Bun 1.4.4 and commit bun.lock").format(file, version),
        )

    # Bun refuses a `configVersion` that is not a number, or is a fraction or below 0 (LOCK
    # L1860-L1869, ConfigVersion.rs `from_expr`), and a `trustedDependencies` that is not an array
    # of strings (LOCK L1871-L1888); neither decides a binding, and the value is not printed (T125).
    # Canary C-ROOTFIELDS pins the form the pinned Bun writes for each (T130).
    config_version = lock.get("configVersion")  # L34
    if config_version != None and (type(config_version) not in ["int", "float"] or config_version < 0 or config_version != int(config_version)):
        return _error("{}: Bun 1.4.4 refuses to load this lockfile (the field \"configVersion\"): Invalid \"configVersion\". Expected a number".format(file))
    trusted = lock.get("trustedDependencies")  # L35
    if trusted != None and type(trusted) != "list":
        return _error("{}: Bun 1.4.4 refuses to load this lockfile (the field \"trustedDependencies\"): Expected an array".format(file))
    if [name for name in (trusted or []) if type(name) != "string"]:
        return _error("{}: Bun 1.4.4 refuses to load this lockfile (an entry of the field \"trustedDependencies\"): Expected a string".format(file))

    # Bun refuses a lockfile whose containers are not objects (LOCK L1899-L1906, L1934-L1941,
    # L2037-L2063, L2100-L2116, L2309-L2318); the value is not printed.
    for field in ["patchedDependencies", "overrides", "catalog", "catalogs", "packages"]:  # L20, L18, L19, L7
        if lock.get(field) != None and type(lock[field]) != "dict":
            return _error("{}: the field \"{}\" is not an object; run `bun install` to rewrite bun.lock".format(file, field))

    # Bun refuses a patch path that is not a string (LOCK L1908-L1915); the value is not printed.
    for key, path in (lock.get("patchedDependencies") or {}).items():  # L20
        if type(path) != "string":
            return _error("{}: the patch of \"{}\" in \"patchedDependencies\" is not a string; run `bun install` to rewrite bun.lock".format(file, key))
    if type(lock.get("workspaces")) != "dict":  # L3
        return _error("{}: the lockfile has no \"workspaces\" object; run `bun install` to rewrite bun.lock".format(file))

    workspaces = {}
    for path, workspace in lock["workspaces"].items():  # L3, L4
        owner = "the workspace \"{}\"".format(path)
        if type(workspace) != "dict":
            return _error("{}: {} is not an object; run `bun install` to rewrite bun.lock".format(file, owner))
        fields = {}
        for kind in DEPENDENCY_KINDS:
            fields[kind], error = _dependencies(workspace.get(kind), file, owner, kind)  # L3, L6
            if error:
                return _error(error)
        workspace_version = workspace.get("version")  # L28
        if workspace_version != None and type(workspace_version) != "string":
            return _error("{}: {} has a field \"version\" that is not a string; run `bun install` to rewrite bun.lock".format(file, owner))
        unresolved, error = _names(workspace.get("unresolved"), file, owner, "unresolved")  # L24
        if error:
            return _error(error)
        optional_peers, error = _names(workspace.get("optionalPeers"), file, owner, "optionalPeers")  # L33
        if error:
            return _error(error)
        workspaces[path] = struct(
            path = path,
            name = workspace.get("name", ""),  # L5
            version = workspace_version,
            unresolved = unresolved,
            optional_peers = optional_peers,
            **fields
        )

    entries = {}
    keys = []
    for key, entry in lock.get("packages", {}).items():  # L7
        result = _entry(key, entry, file)
        if result.error:
            return result
        entries[key] = result.value
        keys.append(key)  # L29: the rows in the order Bun wrote them
    return struct(
        value = struct(
            version = version,
            workspaces = workspaces,
            entries = entries,
            keys = keys,
            overrides = dict(lock.get("overrides", {})),  # L18
            catalog = dict(lock.get("catalog", {})),  # L19
            catalogs = dict(lock.get("catalogs", {})),  # L19
            patched = sorted(lock.get("patchedDependencies", {}).keys()),  # L20
        ),
        error = None,
    )
