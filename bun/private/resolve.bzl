"""The adapter from Bun's isolated store to the hub's instances and links (feature 006 research R4).

The adapter of research R4 runs Bun's own stages, carried over from bun-v1.4.4 in Bun's order
(research R2): the text-lockfile loader (`bun_lockfile.bzl`), `Lockfile::resolve` with the hoister
(`bun_tree.bzl`), `clean`, and the isolated linker's `build_store` (`bun_isolated_store.bzl`) once
per platform class (`platforms.bzl`, research R3). It then maps the store's entries to the output the
hub has consumed since feature 003, `struct(instances, links, members)`:

- an instance is a store entry: a package with the packages its transitive peers bind to; an
  entry reached on several platform classes is one instance, its edges the union of theirs, each
  edge the store has on some of those classes only carrying the platform tuples of those
  (`edge_conditions`), and a dependency the store binds to different entries on different classes
  carrying each entry with its tuples (`edge_targets`, feature 006 BC-16), which the hub turns
  into `select()`;
- a link is a root's or a workspace's dependency, with the instances it reaches on every platform
  (`closure`) and those it reaches on some (`optional`, instance ID -> the `[os, cpu, libc]`
  platform tuples it is reached on, which `npm_repositories.bzl` turns into `select()`), and its
  root, one instance, or one per platform class where the store binds it to different entries
  (`roots`, feature 006 BC-12); every dependency the root or a workspace declares has a link, as
  the hub's naming rule gives each its target, and one the store links on no class has no root and
  reaches nothing (T111);
- `members` are the links to workspaces, which the hub links as the members' targets.

An entry rules_bun does not fetch (FR-010) is linked like any other, so its dependencies get
instances (BC-8); its `status` makes the hub fail analysis of it (ID-4). Errors are returned as values.
"""

load(":bun_install_types.bzl", "RESOLUTION_TAG", "behavior_is_optional", "behavior_is_peer")
load(":bun_isolated_store.bzl", "build_store")
load(":bun_lockfile.bzl", "dependency_ids", "is_valid", "load_lockfile", "lockfile_clean", "lockfile_resolve")
load(":bun_tree.bzl", "hoist")
load(":lockfile.bzl", "DEPENDENCY_KINDS")
load(":platforms.bzl", "platform_bits", "platform_classes")

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
    if entry.kind == "local_tarball":
        return "it is a local tarball dependency ({}), which rules_bun does not fetch; depend on the package from a registry".format(entry.resolution)
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

def _reached(edges, roots):
    """This is the adapter: the classes of each entry key reachable from `roots` in each class.

    One walk serves every platform class: each class is a bit, an edge carries the classes whose
    store has it, and a key is reached in a class when a path of that class's edges leads to it,
    so the classes a key is reached in are propagated along the edges until nothing grows.

    Args:
        edges: Entry key -> list of `(target key, class mask)`.
        roots: Entry key -> the classes it is the root in.

    Returns:
        Entry key -> the classes it is reached in, as a bit mask.
    """
    reached = dict(roots)
    queue = list(roots.keys())
    for i in range(_LIMIT):
        if i >= len(queue):
            break
        mask = reached[queue[i]]
        for target, edge_mask in edges[queue[i]]:
            old = reached.get(target, 0)
            new = old | (mask & edge_mask)
            if new != old:
                reached[target] = new
                queue.append(target)
    return reached

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
    the hub cannot use keeps only target-name characters, as on `main`, and `<n>` also numbers such
    instances whose `name@version` differ only in other characters (`foo@file:a/b`,
    `foo@file:a_b`), so each has its own ID (feature 006 T178). The peer hash names the
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
        prefix = name_version if statuses[key] == "ok" else _target_safe(name_version)
        encoding = json.encode([[name, _label(lockfile, pkg_id)] for name, pkg_id in key[1]])
        groups.setdefault(prefix, {}).setdefault(hash_fn(encoding) % 4294967296, []).append((encoding, key))
    ids = {}
    peer_hashes = {}
    for prefix, by_hash in groups.items():
        for h, group in by_hash.items():
            group = sorted(group)
            for n, (_, key) in enumerate(group):
                suffix = "" if len(group) == 1 else "__{}".format(n)
                ids[key] = "{}__{}{}".format(prefix, h, suffix)
                peer_hashes[key] = _hex16(n * 4294967296 + h) if key[1] else ""
    return struct(ids = ids, peer_hashes = peer_hashes)

def _label(lockfile, pkg_id):
    """This is the adapter: a package's `name@<resolution>` for messages and IDs."""
    package = lockfile.packages[pkg_id]
    return "{}@{}".format(package.name, package.entry.version if package.entry else package.resolution.value)

def _declared_key(lockfile, bun, holders, path, alias, patched):
    """This is the adapter: the `bun.lock` key of the package a holder's declared dependency names its bins after.

    The package is the one the cleaned lockfile binds the holder's dependency of that name to
    (`resolutions[dep_id]`, LOCK L2923–L3023), whether or not the store links it on a platform
    class; a link the store makes on no class names its bin targets after it (T111). An optional
    dependency under `unresolved` is bound to no package (LOCK L3027–L3031, feature 006 BC-1);
    `main` linked it to the row its lookup finds (`_hoisted_key`) and generated that row's bin
    targets, so its link names its bins after that row, and no target name `main` generated is
    gone (FR-014, SC-005, T169).

    Args:
        lockfile: The `value` of `read_lockfile`.
        bun: The cleaned lockfile.
        holders: Workspace path -> the package ID of the root or the workspace.
        path: The holder's workspace path.
        alias: The dependency's name.
        patched: The `name@version` keys of `patchedDependencies`.

    Returns:
        The key, or `None` when the dependency resolves to no package, to a workspace, or to an
        entry rules_bun does not fetch (whose bins get no target, as for a root that is one).
    """
    if path not in holders:
        return None
    for dep_id in dependency_ids(bun, holders[path]):
        dependency = bun.dependencies[dep_id]
        if dependency.name != alias:
            continue
        pkg_id = bun.resolutions[dep_id]
        if not is_valid(pkg_id):
            if behavior_is_optional(dependency.behavior) and alias in lockfile.workspaces[path].unresolved:
                return _hoisted_key(lockfile, path, alias, patched)
            return None
        if _holder_path(bun, pkg_id) != None:
            return None
        package = bun.packages[pkg_id]
        if package.entry == None or unsupported_reason(package.entry, patched):
            return None
        return package.key
    return None

def _hoisted_key(lockfile, path, alias, patched):
    """This is the adapter: the `bun.lock` key `main` linked a workspace's dependency to.

    `main` looked the dependency up as its hoisted-tree walk did: `<workspace name>/<alias>`, then
    `<alias>` (for the root only `<alias>`), the first key that exists.

    Args:
        lockfile: The `value` of `read_lockfile`.
        path: The workspace path, `""` for the root.
        alias: The dependency's name.
        patched: The `name@version` keys of `patchedDependencies`.

    Returns:
        The key, or `None` when no key exists or its entry is a workspace or an entry rules_bun does
        not fetch.
    """
    start = [lockfile.workspaces[path].name] if path else []
    for i in range(len(start), -1, -1):
        key = "/".join(start[:i] + [alias])
        if key in lockfile.entries:
            entry = lockfile.entries[key]
            if entry.kind == "workspace" or unsupported_reason(entry, patched):
                return None
            return key
    return None

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
        edge_targets, dependency_keys, peers, members, status, unfetched)` (`peer_hash`: 16
        hexadecimal digits naming the entry's transitive peer bindings, or `""` without peers;
        `edges`: alias -> instance ID, for a dependency the store binds to one entry;
        `edge_conditions`: alias of `edges` -> the `[os, cpu, libc]` tuples the edge holds on, for
        an edge the store has on some of the instance's classes only; `edge_targets`: alias ->
        instance ID -> the tuples the alias links that instance on, for a dependency the store
        binds to different entries on different classes, which is not in `edges`;
        `dependency_keys`: alias -> the `bun.lock` key of the package an ordinary dependency links;
        `peers`: the aliases of `edges` and `edge_targets` that are peers; `members`: alias -> the
        path of a workspace it links; `status`:
        `ok`, or why the instance cannot be used; `unfetched`: whether that is because rules_bun
        does not fetch it, feature 006 ID-4), `links` maps a workspace path (`""` for the root) to
        alias -> `struct(alias, root, roots, closure, optional, key)` for each package the workspace
        declares (`root`: the instance ID the alias links, or `None` when that differs by platform
        or the store links it on no platform class; then `roots` maps each root's ID to the `[os,
        cpu, libc]` tuples it is the root on, else it is empty; `key`: the `bun.lock` key of the
        package it links, whose `bin` entries name its bin targets, the row `main` linked it to
        for an optional dependency under `unresolved`, or `None` for none or one rules_bun does
        not fetch), and `members` maps a workspace path to alias -> the path of each
        workspace it links.
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
    # keeps those classes, so it is linked only there (T101). A dependency the store binds to
    # different entries on different classes (a peer below it that a disabled package provides on
    # some, research R4 "An entry's alias") keeps each entry with its classes, so each is linked
    # only there (BC-16). Those entries are one package: an ordinary dependency has one resolution
    # (`resolutions[dep_id]`, LOCK L2923-L3023), and a peer's package is part of the entry's key
    # (ISO L1097-L1176), so the dependency's `bun.lock` key is the same on every class.
    nodes = {}
    for index, graph in enumerate(graphs):
        for key, node in graph.nodes.items():
            merged = nodes.setdefault(key, struct(targets = {}, members = {}, peers = {}, classes = []))
            merged.classes.append(index)
            for alias, target in node.edges.items():
                merged.targets.setdefault(alias, {}).setdefault(target, []).append(index)
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
            edges = {alias: ids[by_target.keys()[0]] for alias, by_target in node.targets.items() if len(by_target) == 1},
            dependency_keys = {alias: bun.packages[by_target.keys()[0][0]].key for alias, by_target in node.targets.items() if alias not in node.peers},
            peers = sorted([alias for alias in node.targets.keys() if alias in node.peers]),
            edge_conditions = {
                alias: _conditions([t for index in by_target.values()[0] for t in classes[index]])
                for alias, by_target in node.targets.items()
                if len(by_target) == 1 and len(by_target.values()[0]) != len(node.classes)
            },
            edge_targets = {
                alias: {ids[target]: _conditions([t for index in indexes for t in classes[index]]) for target, indexes in by_target.items()}
                for alias, by_target in node.targets.items()
                if len(by_target) > 1
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
    every_class = (1 << len(graphs)) - 1
    edge_masks = {
        key: [(target, _mask(indexes)) for by_target in node.targets.values() for target, indexes in by_target.items()]
        for key, node in nodes.items()
    }
    by_mask = {}

    def conditions(mask):
        """The `select` conditions of the platforms of the classes in `mask`, made once per mask.

        This is the adapter (research R4): Bun links for one platform, the hub for each class.
        """
        if mask not in by_mask:
            by_mask[mask] = _conditions([t for index, platforms in enumerate(classes) if mask & (1 << index) for t in platforms])
        return by_mask[mask]

    links = {path: {} for path in lockfile.workspaces.keys()}
    members = {path: {} for path in lockfile.workspaces.keys()}
    roots = {}
    for index, graph in enumerate(graphs):
        for path, holder in graph.holders.items():
            members.setdefault(path, {}).update(holder.members)
            for alias, root in holder.links.items():
                by_root = roots.setdefault((path, alias), {})
                by_root[root] = by_root.get(root, 0) | (1 << index)
    for (path, alias), by_root in sorted(roots.items()):
        if len({key[0]: True for key in by_root.keys()}) > 1:
            # Per-platform roots are one package under other peer bindings, so the link's bins
            # and fetch status are the same on every platform. Roots of different packages need a
            # holder's alias whose lockfile row differs from the one the lookup finds above it,
            # which the pinned Bun does not write (research R4, T097).
            holder = 'the workspace "{}"'.format(path) if path else "the root workspace"
            return _error("{}: the store links \"{}\" of {} to different packages on different platforms, which rules_bun cannot express".format(file, alias, holder))
        closure = []
        optional = {}
        for key, mask in _reached(edge_masks, by_root).items():
            if mask == every_class:
                closure.append(ids[key])
            else:
                optional[ids[key]] = conditions(mask)
        root_key = sorted(by_root.keys())[0]
        bins_key = bun.packages[root_key[0]].key if statuses[root_key] == "ok" else None
        if len(by_root) == 1:
            link = struct(alias = alias, root = ids[root_key], roots = {}, closure = sorted(closure), optional = optional, key = bins_key)
        else:
            link = struct(alias = alias, root = None, roots = {ids[key]: conditions(mask) for key, mask in by_root.items()}, closure = sorted(closure), optional = optional, key = bins_key)
        links.setdefault(path, {})[alias] = link

    # A dependency the root or a workspace declares that the store links on no platform class (an
    # optional or, BC-7, non-optional package no platform matches; an optional dependency under
    # `unresolved`, BC-1; an optional or peer dependency without a key, BC-3, BC-5) still has its
    # link, as the hub's naming rule gives every declared package its target: it reaches nothing,
    # as an optional link does on a platform its package does not match (T111).
    holder_ids = {}
    for pkg_id in range(len(bun.packages)):
        path = _holder_path(bun, pkg_id)
        if path != None and path not in holder_ids:
            holder_ids[path] = pkg_id
    for path, workspace in sorted(lockfile.workspaces.items()):
        declared = {alias: True for kind in DEPENDENCY_KINDS for alias in getattr(workspace, kind).keys()}
        for alias in sorted(declared.keys()):
            if alias in links[path] or alias in members.get(path, {}):
                continue
            key = _declared_key(lockfile, bun, holder_ids, path, alias, patched)
            links[path][alias] = struct(alias = alias, root = None, roots = {}, closure = [], optional = {}, key = key)
    return struct(value = struct(instances = instances, links = links, members = members), error = None)

def _mask(indexes):
    """This is the adapter: class indexes as a bit mask."""
    mask = 0
    for index in indexes:
        mask = mask | (1 << index)
    return mask

def _conditions(platforms):
    """This is the adapter: platform tuples as the sorted `[os, cpu, libc]` lists the hub selects by."""
    return sorted([list(p) for p in platforms], key = lambda p: [str(v) for v in p])
