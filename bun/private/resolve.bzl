"""The adapter from Bun's isolated store to the hub's instances and links (feature 006 research R4).

The adapter of research R4 runs Bun's own stages, carried over from bun-v1.4.4 in Bun's order
(research R2): the text-lockfile loader (`bun_lockfile.bzl`), `Lockfile::resolve` with the hoister
(`bun_tree.bzl`), `clean`, and the isolated linker's `build_store` (`bun_isolated_store.bzl`) once
per platform class (`platforms.bzl`, research R3). It then maps the store's entries to the output the
hub has consumed since feature 003, `struct(instances, links, members)`:

- an instance is a store entry: a package with the packages its transitive peers bind to; an
  entry reached on several platform classes is one instance, its edges the union of theirs, each
  edge the store has on some of those classes only carrying the platform tuples of those
  (`edge_conditions`, which the hub turns into `select()`);
- a link is a root's or a workspace's dependency, with the instances it reaches on every platform
  (`closure`) and those it reaches on some (`optional`, instance ID -> the `[os, cpu, libc]`
  platform tuples it is reached on, which `npm_repositories.bzl` turns into `select()`), and its
  root, one instance, or one per platform class where the store binds it to different entries
  (`roots`, feature 006 BC-12);
- `members` are the links to workspaces, which the hub links as the members' targets.

An entry rules_bun does not fetch (FR-010) is linked like any other, so its dependencies get
instances (BC-8); its `status` makes the hub fail analysis of it (ID-4). Errors are returned as values.
"""

load(":bun_install_types.bzl", "RESOLUTION_TAG", "behavior_is_peer")
load(":bun_isolated_store.bzl", "build_store")
load(":bun_lockfile.bzl", "load_lockfile", "lockfile_clean", "lockfile_resolve")
load(":bun_tree.bzl", "hoist")
load(":platforms.bzl", "platform_bits", "platform_classes", "platform_tuples")

_ALGORITHMS = ["sha256", "sha384", "sha512"]

# Bazel's target-name characters (concepts/labels) without `/`, for the instance IDs of entries
# whose resolution is no version.
_NAME_CHARACTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!%-@^_\"#$&'()*+,;<=>?[]{|}~."

_LIMIT = 1 << 30

# A holder a class does not reach: no links, no members.
_NO_HOLDER = struct(links = {}, members = {})

def _error(message):
    """This is the adapter: an error as a value."""
    return struct(value = None, error = message)

def unsupported_reason(entry, patched):
    """Why rules_bun does not fetch an entry (feature 003 FR-010, research R13), or `None`.

    This is the adapter: rules_bun's own rule, which Bun does not have.

    Args:
        entry: A lockfile entry.
        patched: The `name@version` keys of `patchedDependencies`.

    Returns:
        An English reason, or `None` for an entry rules_bun fetches.
    """
    if entry.kind == "file":
        return "it is a file: dependency, which rules_bun does not fetch"
    if entry.kind == "tarball":
        return "it is a tarball URL dependency ({}), which rules_bun does not fetch; depend on the package from a registry".format(entry.resolution)
    if entry.kind == "unsupported":
        return "its resolution {} is not a registry version, which rules_bun does not fetch".format(entry.resolution)
    if "{}@{}".format(entry.name, entry.version) in patched:
        return "it is patched (patchedDependencies), and rules_bun does not apply patches"
    if not entry.integrity:
        return "bun.lock records no integrity for it, so its download cannot be verified"
    algorithm = entry.integrity.partition("-")[0]
    if algorithm not in _ALGORITHMS:
        return "its integrity uses {}; rules_bun verifies sha256, sha384 and sha512 only".format(algorithm)
    return None

def _target_safe(text):
    """This is the adapter: an instance ID's characters, as on `main`."""
    return "".join([c if c in _NAME_CHARACTERS else "_" for c in text.elems()])

def _holder_path(lockfile, pkg_id):
    """This is the adapter: the workspace path (`""` for the root) of a root or workspace package."""
    resolution = lockfile.packages[pkg_id].resolution
    if resolution.tag == RESOLUTION_TAG.ROOT:
        return ""
    if resolution.tag == RESOLUTION_TAG.WORKSPACE:
        return resolution.value
    return None

def _entry_key(entry):
    """This is the adapter: an entry's identity across platform classes, its package and peers."""
    peers = sorted([(name, peer[1]) for name, peer in entry.peers.items()])
    return (entry.pkg_id, tuple(peers))

def _class_graph(lockfile, store):
    """This is the adapter: one class's holders and instance edges, by entry key.

    Returns:
        `struct(holders, nodes)`: `holders` maps a workspace path to `struct(links, members)`
        (alias -> entry key, alias -> member path); `nodes` maps an entry key to `struct(edges,
        members, peers)`.
    """
    entries = store.entries
    keys = [_entry_key(entry) for entry in entries]
    holders = {}
    nodes = {}
    for entry_id, entry in enumerate(entries):
        path = _holder_path(lockfile, entry.pkg_id)
        links = {}
        members = {}
        peers = {}
        for alias, (target, dep_id) in entry.dependencies.items():
            target_path = _holder_path(lockfile, entries[target].pkg_id)
            if target_path != None:
                members[alias] = target_path
            else:
                links[alias] = keys[target]
            if behavior_is_peer(lockfile.dependencies[dep_id].behavior):
                peers[alias] = True
        if path != None:
            # The root's directory, or the directory of the workspace the root declares; a
            # workspace reached otherwise keeps the first entry's links.
            dep_id = entry.dep_id
            declared = entry_id == 0 or (dep_id >= 0 and lockfile.dependencies[dep_id].behavior & 32 != 0)
            if declared or path not in holders:
                holders[path] = struct(links = links, members = members)
            continue
        nodes[keys[entry_id]] = struct(edges = links, members = members, peers = peers)
    return struct(holders = holders, nodes = nodes)

def _reached(graph, root):
    """This is the adapter: the entry keys reachable from `root` in one class."""
    seen = {root: True}
    queue = [root]
    for i in range(_LIMIT):
        if i >= len(queue):
            break
        for target in graph.nodes[queue[i]].edges.values():
            if target not in seen:
                seen[target] = True
                queue.append(target)
    return seen

def _hex16(value):
    """This is the adapter: `value` as 16 lowercase hexadecimal digits, Bun's `{:016x}`."""
    digits = []
    for _ in range(16):
        digits.append("0123456789abcdef"[value % 16])
        value //= 16
    return "".join(reversed(digits))

def _ids(lockfile, keys, statuses, hash_fn):
    """Entry key -> instance ID and peer hash.

    This is the adapter: the ID is `name@version__<h>[__<n>]` as on `main`, `<h>` the hash of the
    entry's transitive peers and `<n>` numbering entries whose hashes collide; the ID of an instance
    the hub cannot use keeps only target-name characters, as on `main`. The peer hash names the
    entry's store directory as Bun's isolated store names it, `<name>@<version>+<peer hash>`, or
    no hash for an entry without peers (`PeerHash::NONE`). Bun hashes the peers' names and
    resolutions with Wyhash; the adapter hashes the same text with `hash_fn` and adds `<n>`, so two
    entries of one hub never share a directory (feature 006 BC-11). Bun's hash of an entry without
    peers that is a tarball (its integrity) is not carried: rules_bun does not fetch tarballs (ID-4).

    Bun: src/install/isolated_install/Store.rs L450–L466 @ bun-v1.4.4
    Bun: src/install/isolated_install.rs L1353–L1386 @ bun-v1.4.4

    Returns:
        `struct(ids, peer_hashes)`, each keyed by entry key.
    """
    groups = {}
    for key in keys:
        package = lockfile.packages[key[0]]
        name_version = "{}@{}".format(package.name, package.entry.version)
        encoding = json.encode([[name, _label(lockfile, pkg_id)] for name, pkg_id in key[1]])
        groups.setdefault(name_version, {}).setdefault(hash_fn(encoding) % 4294967296, []).append((encoding, key))
    ids = {}
    peer_hashes = {}
    for name_version, by_hash in groups.items():
        for h, group in by_hash.items():
            group = sorted(group)
            for n, (_, key) in enumerate(group):
                suffix = "" if len(group) == 1 else "__{}".format(n)
                prefix = name_version if statuses[key] == "ok" else _target_safe(name_version)
                ids[key] = "{}__{}{}".format(prefix, h, suffix)
                peer_hashes[key] = _hex16(n * 4294967296 + h) if key[1] else ""
    return struct(ids = ids, peer_hashes = peer_hashes)

def _label(lockfile, pkg_id):
    """This is the adapter: a package's `name@<resolution>` for messages and IDs."""
    package = lockfile.packages[pkg_id]
    return "{}@{}".format(package.name, package.entry.version if package.entry else package.resolution.value)

def _differing_member(held):
    """This is the adapter: the first alias whose member link is not the same in every one of `held`."""
    aliases = sorted({alias: True for h in held for alias in h.members.keys()}.keys())
    for alias in aliases:
        if len({h.members.get(alias): True for h in held}) != 1:
            return alias
    return None

def class_member_conflict(graphs, file, describe):
    """The error for a workspace-member link that differs by platform class, or `None`.

    This is the adapter: the hub links a member by path on every platform (feature 006 BC-4), so
    an entry's or a holder's member link must be the same on every class the entry or holder
    exists on, or it would apply on every platform, and an alias bound to a member on one class and
    to a package on another would be linked as both. The pinned Bun writes no such lockfile: a
    workspace row has no `os`, `cpu` or `libc` (LOCK L2593–L2604), so no class disables a member,
    and a peer the lookup binds to a member on one class only is part of the entry's key (research
    R4 "Bindings that differ by platform class"); this check keeps the merge from hiding one, with
    the error an entry's alias bound by platform gets (BC-12).

    Args:
        graphs: The `_class_graph` of each platform class.
        file: The lockfile's name, for errors.
        describe: Entry key -> the package, for errors.

    Returns:
        An English error, or `None`.
    """
    error = "{}: the store links \"{}\" of {} to different packages on different platforms, which rules_bun cannot express"
    paths = sorted({path: True for graph in graphs for path in graph.holders.keys()}.keys())
    for path in paths:
        alias = _differing_member([graph.holders.get(path, _NO_HOLDER) for graph in graphs])
        if alias != None:
            return error.format(file, alias, 'the workspace "{}"'.format(path) if path else "the root workspace")
    keys = sorted({key: True for graph in graphs for key in graph.nodes.keys()}.keys())
    for key in keys:
        alias = _differing_member([graph.nodes[key] for graph in graphs if key in graph.nodes])
        if alias != None:
            return error.format(file, alias, describe(key))
    return None

def resolve(lockfile, file = "bun.lock", hash_fn = hash):
    """Resolves a read lockfile into package instances and per-workspace links.

    This is the adapter of research R4: Bun's stages in Bun's order, then the hub's shape.

    Args:
        lockfile: The `value` of `read_lockfile`.
        file: The lockfile's name, for errors.
        hash_fn: The hash of an instance's peer bindings; `hash` except in tests.

    Returns:
        `struct(value, error)`; `value` is `struct(instances, links, members)`: `instances` maps an
        instance ID to `struct(id, name, version, store_name, peer_hash, key, edges, edge_conditions,
        dependency_keys, peers, members, status, unfetched)` (`peer_hash`: 16 hexadecimal digits
        naming the entry's transitive peer bindings, or `""` without peers; `edges`: alias ->
        instance ID; `edge_conditions`: alias of `edges` -> the `[os, cpu, libc]` tuples the edge
        holds on, for an edge the store has on some of the instance's classes only; `dependency_keys`: alias ->
        the `bun.lock` key of the package an ordinary dependency links; `peers`: the aliases of
        `edges` that are peers; `members`: alias -> the path of a workspace it links; `status`:
        `ok`, or why the instance cannot be used; `unfetched`: whether that is because rules_bun
        does not fetch it, feature 006 ID-4), `links` maps a workspace path (`""` for the root) to
        alias -> `struct(alias, root, roots, closure, optional)` (`root`: the instance ID the
        alias links, or `None` when that differs by platform; then `roots` maps each root's ID to
        the `[os, cpu, libc]` tuples it is the root on, else it is empty), and `members` maps a
        workspace path to alias -> the path of each workspace it links.
    """
    loaded = load_lockfile(lockfile, file)
    if loaded.error:
        return loaded
    error = lockfile_resolve(loaded.value, hoist)
    if error:
        return _error(error)
    cleaned = lockfile_clean(loaded.value, hoist)
    if cleaned.error:
        return cleaned
    bun = cleaned.value

    classes = platform_classes(bun)
    graphs = []
    for platforms in classes:
        store = build_store(bun, platform_bits(platforms[0]))
        if store.error:
            return _error(store.error)
        graphs.append(_class_graph(bun, store.value))
    conflict = class_member_conflict(graphs, file, lambda key: _label(bun, key[0]))
    if conflict:
        return _error(conflict)

    # Instances: entries merged over the classes by package and peers. An edge the store has on
    # some of an entry's classes only (an optional dependency disabled on the others, research R3)
    # keeps those classes, so it is linked only there (T101).
    nodes = {}
    for index, graph in enumerate(graphs):
        for key, node in graph.nodes.items():
            merged = nodes.setdefault(key, struct(edges = {}, members = {}, peers = {}, classes = [], edge_classes = {}))
            merged.classes.append(index)
            for alias, target in node.edges.items():
                if merged.edges.setdefault(alias, target) != target:
                    return _error("{}: the store links \"{}\" of {} to different packages on different platforms, which rules_bun cannot express".format(file, alias, _label(bun, key[0])))
                merged.edge_classes.setdefault(alias, []).append(index)
            merged.members.update(node.members)
            merged.peers.update(node.peers)
    patched = getattr(lockfile, "patched", [])
    statuses = {key: unsupported_reason(bun.packages[key[0]].entry, patched) or "ok" for key in nodes}
    named = _ids(bun, sorted(nodes.keys()), statuses, hash_fn)
    ids = named.ids
    instances = {}
    for key, node in nodes.items():
        package = bun.packages[key[0]]
        entry = package.entry
        instance_id = ids[key]
        instances[instance_id] = struct(
            id = instance_id,
            name = package.name,
            version = entry.version,
            store_name = "{}@{}".format(package.name.replace("/", "+"), entry.version),
            peer_hash = named.peer_hashes[key],
            key = package.key,
            edges = {alias: ids[target] for alias, target in node.edges.items()},
            dependency_keys = {alias: bun.packages[target[0]].key for alias, target in node.edges.items() if alias not in node.peers},
            peers = sorted([alias for alias in node.edges.keys() if alias in node.peers]),
            edge_conditions = {
                alias: _conditions([t for index in indexes for t in classes[index]])
                for alias, indexes in node.edge_classes.items()
                if len(indexes) != len(node.classes)
            },
            members = dict(node.members),
            status = statuses[key],
            # Every status this adapter sets is an entry rules_bun does not fetch (ID-4).
            unfetched = statuses[key] != "ok",
        )

    # Links: each holder's dependencies, with what they reach on each platform. A holder's alias
    # the store binds to different entries on different platform classes (a peer provider that is
    # disabled on some, research R4 "Bindings that differ by platform class") has one root per
    # class, which the hub selects by platform (feature 006 BC-12).
    tuples_of = [platforms for platforms in classes]
    all_tuples = len(platform_tuples())
    links = {path: {} for path in lockfile.workspaces.keys()}
    members = {path: {} for path in lockfile.workspaces.keys()}
    roots = {}
    reach = {}
    for index, graph in enumerate(graphs):
        for path, holder in graph.holders.items():
            members.setdefault(path, {}).update(holder.members)
            for alias, root in holder.links.items():
                roots.setdefault((path, alias), {}).setdefault(root, []).extend(tuples_of[index])
                for key in _reached(graph, root):
                    reach.setdefault((path, alias), {}).setdefault(key, []).extend(tuples_of[index])
    for (path, alias), by_root in roots.items():
        closure = []
        optional = {}
        for key, platforms in reach[(path, alias)].items():
            if len(platforms) == all_tuples:
                closure.append(ids[key])
            else:
                optional[ids[key]] = _conditions(platforms)
        if len(by_root) == 1:
            link = struct(alias = alias, root = ids[by_root.keys()[0]], roots = {}, closure = sorted(closure), optional = optional)
        else:
            link = struct(alias = alias, root = None, roots = {ids[key]: _conditions(platforms) for key, platforms in by_root.items()}, closure = sorted(closure), optional = optional)
        links.setdefault(path, {})[alias] = link
    return struct(value = struct(instances = instances, links = links, members = members), error = None)

def _conditions(platforms):
    """This is the adapter: platform tuples as the sorted `[os, cpu, libc]` lists the hub selects by."""
    return sorted([list(p) for p in platforms], key = lambda p: [str(v) for v in p])
