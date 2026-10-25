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
    """A string or a list of strings as a list (`os`, `cpu`: a string when one value)."""
    if value == None:
        return []
    if type(value) == "string":
        return [value]
    return list(value)

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

    # Every other kind is unsupported (FR-010): only slot 0 is read, as Part 3 lists no other slot.
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
            dependencies = dict(info.get("dependencies", {})),  # L13
            optional_dependencies = dict(info.get("optionalDependencies", {})),  # L13
            peers = dict(info.get("peerDependencies", {})),  # L14
            optional_peers = list(info.get("optionalPeers", [])),  # L14
            os = _strings(info.get("os")),  # L15
            cpu = _strings(info.get("cpu")),  # L15
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
        `struct(value, error)`; `value` is `struct(version, workspaces, entries, overrides,
        catalog, catalogs, patched)`: `workspaces` maps a member path (`""` for the root) to
        `struct(path, name, <dependency kinds>)`, `entries` maps a `packages` key to an entry
        struct (data-model "Lockfile model"), `overrides`, `catalog` and `catalogs` are the top-level
        maps as written, and `patched` lists the `name@version` keys of `patchedDependencies`.
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
             "the versions Bun 1.4.2 writes: run `bun install` with Bun 1.4.2 and commit bun.lock").format(file, version),
        )

    workspaces = {}
    for path, workspace in lock.get("workspaces", {}).items():  # L3, L4
        fields = {kind: dict(workspace.get(kind, {})) for kind in DEPENDENCY_KINDS}  # L3, L6
        workspaces[path] = struct(path = path, name = workspace.get("name", ""), **fields)  # L5

    entries = {}
    for key, entry in lock.get("packages", {}).items():  # L7
        result = _entry(key, entry, file)
        if result.error:
            return result
        entries[key] = result.value
    return struct(
        value = struct(
            version = version,
            workspaces = workspaces,
            entries = entries,
            overrides = dict(lock.get("overrides", {})),  # L18
            catalog = dict(lock.get("catalog", {})),  # L19
            catalogs = dict(lock.get("catalogs", {})),  # L19
            patched = sorted(lock.get("patchedDependencies", {}).keys()),  # L20
        ),
        error = None,
    )
