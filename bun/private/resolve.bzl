"""Static resolution of `bun.lock` entries into package instances (research R2).

A dependency `D` of the entry at key `K` resolves to the first of `K/D`, `parent(K)/D`, ..., `D`
that the lockfile lists; a workspace named `N` starts at `N/D`. A peer resolves to the instance the
dependent provides: one of its own dependencies or resolved peers. An instance's identity is its
`name@version` and its edge map, where an ordinary edge is recorded by the lockfile key it resolves
to and a peer edge by the peer's identity, so two entries of one `name@version` whose edges differ
are distinct instances. Errors are returned as values, not raised.
"""

load(":lockfile.bzl", "DEPENDENCY_KINDS", "split_key")

# Starlark has no `while`; loops over a worklist are bounded by this.
_LIMIT = 1 << 30

def _error(message):
    return struct(value = None, error = message)

def walk_key(entries, segments, dep):
    """Returns the lockfile key a dependency resolves to by the hoisted-tree walk.

    Args:
        entries: The lockfile's `packages` keys (any mapping with `in`).
        segments: The dependent's key split into package names (`split_key`), or the workspace's
            start: `[]` for the root, `[<name>]` for a member.
        dep: The dependency's name, or its alias.

    Returns:
        The first existing key of `<segments>/<dep>`, `<parent>/<dep>`, ..., `<dep>`, or `None`.
    """
    for i in range(len(segments), -1, -1):
        key = "/".join(segments[:i] + [dep])
        if key in entries:
            return key
    return None

_ALGORITHMS = ["sha256", "sha384", "sha512"]

# Bazel's target-name characters (concepts/labels) without `/`, for the instance IDs of entries
# whose resolution is no version.
_NAME_CHARACTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!%-@^_\"#$&'()*+,;<=>?[]{|}~."

def unsupported_reason(entry, patched):
    """Why rules_bun does not fetch an entry (FR-010, research R13), or `None`.

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
    return "".join([c if c in _NAME_CHARACTERS else "_" for c in text.elems()])

def _ordinary(entry):
    names = dict(entry.dependencies)
    names.update(entry.optional_dependencies)
    return names

def _ordinary_edges(entries, key, entry, file):
    """`(edges, error)`: alias -> lockfile key of each ordinary dependency of `entry`."""
    edges = {}
    segments = split_key(key)
    for dep in sorted(_ordinary(entry).keys()):
        target = walk_key(entries, segments, dep)
        if target == None:
            if dep in entry.optional_dependencies:
                continue
            return None, "{}: the packages entry \"{}\" depends on \"{}\", which no key of the walk from it lists; run `bun install` to rewrite bun.lock".format(file, key, dep)
        if entries[target].kind == "workspace":
            continue
        edges[dep] = target
    return edges, None

def _missing_peer(peer, context):
    return ('its peer dependency "{peer}" is provided neither by the package that depends on it nor ' +
            'by the workspace "{context}", and bun.lock lists no version of "{peer}" there; add ' +
            '"{peer}" to that workspace\'s package.json and run `bun install`').format(peer = peer, context = context)

def _siblings(entries, children, provided, file, patched, context, plain, virtual = {}, fallback = {}):
    """Resolves the instances of one dependent's ordinary dependencies.

    A peer resolves to what the dependent provides (a sibling, or one of the dependent's resolved
    peers); otherwise an optional peer is absent, and any other resolves in the workspace context
    (research R2): to the instance the walk from the workspace's start key finds.

    Args:
        entries: The lockfile entries.
        children: List of `(alias, key)` in sorted alias order.
        provided: Peer name -> identity of the dependent's resolved peers.
        file: The lockfile's name, for errors.
        patched: The `name@version` keys of `patchedDependencies`.
        context: The path of the workspace the dependent is reached from (`""` for the root).
        plain: Identity -> the identity without workspace context; updated with the new nodes.
        virtual: For a workspace's own dependencies only: peer name -> the key the walk from the
            workspace's start finds for each peer name the workspace does not declare. These are
            resolved alongside the children as the workspace context's fallbacks.
        fallback: Peer name -> identity of the workspace context's instance for that name.

    Returns:
        `(nodes, error)`; `nodes` maps an alias to `struct(identity, plain, key, name, version,
        encoding, peers, status, context)`, `peers` mapping a peer name to the identity it resolves
        to; `encoding` is the edge map without workspace context.
    """
    keys = {alias: key for alias, key in children}
    for alias, key in virtual.items():
        keys.setdefault(alias, key)
    declared = {alias: True for alias, _ in children}

    def via_sibling(alias, entry, peer):
        """Whether `peer` of the sibling `alias` resolves to a sibling of this call."""
        if peer in _ordinary(entry) or peer == alias or peer not in keys:
            return False
        if peer in declared:
            return True
        return peer not in provided and peer not in entry.optional_peers and peer not in fallback

    done = {}
    back = {}
    pending = sorted(keys.keys())
    for _ in range(len(pending) + 1):
        if not pending:
            break
        ready = []
        for alias in pending:
            entry = entries[keys[alias]]
            if all([p in done or not via_sibling(alias, entry, p) for p in entry.peers]):
                ready.append(alias)
        if not ready:
            # A peer cycle among siblings: the first pending one records the others by key.
            ready = [pending[0]]
        for alias in ready:
            key = keys[alias]
            entry = entries[key]
            reason = unsupported_reason(entry, patched)
            if reason:
                # Not fetched, so its dependencies are not followed.
                edges, peer_names = {}, []
            else:
                edges, error = _ordinary_edges(entries, key, entry, file)
                if error:
                    return None, error
                peer_names = sorted(entry.peers.keys())
            encoded = [[dep, "k:" + target] for dep, target in edges.items()]
            encoded_plain = list(encoded)
            peers = {}
            missing = None
            for peer in peer_names:
                target = None
                if via_sibling(alias, entry, peer):
                    if peer in done:
                        target = done[peer].identity
                    else:
                        back.setdefault(alias, []).append(peer)
                        encoded.append([peer, "k:" + keys[peer]])
                        encoded_plain.append([peer, "k:" + keys[peer]])
                elif peer in _ordinary(entry) or peer == alias:
                    continue
                elif peer in provided:
                    target = provided[peer]
                elif peer in entry.optional_peers:
                    continue
                elif peer in fallback:
                    target = fallback[peer]
                elif missing == None:
                    missing = _missing_peer(peer, context)
                if target != None:
                    peers[peer] = target
                    encoded.append([peer, "i:" + target])
                    encoded_plain.append([peer, "i:" + plain[target]])
            if missing:
                # An instance missing a peer cannot be used, so nothing of it is followed.
                reason = missing
                encoded, encoded_plain, peers, back[alias] = [], [], {}, []
            encoding = json.encode(sorted(encoded_plain))
            name_version = "{}@{}".format(entry.name, entry.version)
            identity = "{} {} @{}".format(name_version, json.encode(sorted(encoded)), context)
            plain[identity] = name_version + " " + encoding
            done[alias] = struct(
                identity = identity,
                plain = plain[identity],
                key = key,
                name = entry.name,
                version = entry.version,
                encoding = encoding,
                peers = peers,
                status = reason or "ok",
                context = context,
            )
        pending = [alias for alias in pending if alias not in done]
    for alias, peers in back.items():
        for peer in peers:
            done[alias].peers[peer] = done[peer].identity
    return done, None

def _workspace_children(lockfile, path):
    """`(children, members, error)` of a workspace.

    `children` are its package dependencies as `(alias, key)`, `members` maps alias -> member path of
    its `workspace:` dependencies.
    """
    workspace = lockfile.workspaces[path]
    start = [] if path == "" else [workspace.name]
    declared = {}
    for kind in DEPENDENCY_KINDS:
        declared.update(getattr(workspace, kind))
    children = []
    members = {}
    for alias in sorted(declared.keys()):
        key = walk_key(lockfile.entries, start, alias)
        if key == None:
            return None, None, "the workspace \"{}\" declares \"{}\", which bun.lock lists no entry for; run `bun install` and commit bun.lock".format(path, alias)
        if lockfile.entries[key].kind == "workspace":
            members[alias] = lockfile.entries[key].version
            continue
        children.append((alias, key))
    return children, members, None

def _ids(nodes, hash_fn):
    """Identity -> instance ID: `name@version__<h>`, plus `__<n>` when two edge maps hash alike.

    Two instances with one edge map differ only by the workspace contexts their peers resolved in;
    the sorted contexts order them.
    """
    groups = {}
    for node in nodes.values():
        name_version = "{}@{}".format(node.name, node.version)
        groups.setdefault(name_version, {}).setdefault(hash_fn(node.encoding) % 4294967296, []).append(node)
    ids = {}
    for name_version, by_hash in groups.items():
        for h, group in by_hash.items():
            group = sorted(group, key = lambda node: (node.encoding, getattr(node, "contexts", "")))
            for n, node in enumerate(group):
                suffix = "" if len(group) == 1 else "__{}".format(n)
                prefix = name_version if node.status == "ok" else _target_safe(name_version)
                ids[node.identity] = "{}__{}{}".format(prefix, h, suffix)
    return ids

def _closure(edges, restrictions, root, root_condition):
    """The instances reachable from `root`, unconditionally and behind platform conditions.

    An optional dependency on a package whose entry has `os`, `cpu` or `libc` holds only where
    those match (research R8; feature 004 research R11); every instance reached through it
    inherits the condition.

    Args:
        edges: Instance ID -> alias -> instance ID.
        restrictions: Instance ID -> alias -> `[os, cpu, libc]` of each platform-restricted optional
            edge.
        root: The link's root instance ID.
        root_condition: The condition of the root itself: `[]` or `[[os, cpu, libc]]`.

    Returns:
        `(closure, optional)`: the sorted IDs reached unconditionally, and ID -> the conditions it
        is reached under, each a sorted list of `[os, cpu, libc]` requirements that must all hold.
    """
    reached = {}
    queue = [(root, root_condition)]
    for i in range(_LIMIT):
        if i >= len(queue):
            break
        node, condition = queue[i]
        conditions = reached.setdefault(node, [])
        if [] in conditions or condition in conditions:
            continue
        conditions.append(condition)
        for alias, target in edges[node].items():
            requirement = restrictions[node].get(alias)
            following = condition
            if requirement != None and requirement not in condition:
                following = sorted(condition + [requirement])
            queue.append((target, following))
    closure = sorted([i for i, conditions in reached.items() if [] in conditions])
    optional = {i: sorted(conditions) for i, conditions in reached.items() if [] not in conditions}
    return closure, optional

def _restriction(entry):
    """`[os, cpu, libc]` of an entry restricted to platforms, or `None`."""
    return [entry.os, entry.cpu, entry.libc] if entry.os or entry.cpu or entry.libc else None

def resolve(lockfile, file = "bun.lock", hash_fn = hash):
    """Resolves a read lockfile into package instances and per-workspace links.

    Args:
        lockfile: The `value` of `read_lockfile`.
        file: The lockfile's name, for errors.
        hash_fn: The hash of an encoded edge map; `hash` except in tests.

    Returns:
        `struct(value, error)`; `value` is `struct(instances, links, members)`: `instances` maps an
        instance ID to `struct(id, name, version, store_name, key, edges, dependency_keys, peers,
        status)` (`edges`: alias -> instance ID; `dependency_keys`: alias -> the lockfile key each
        ordinary dependency resolves to; `peers`: the aliases of `edges` that are peers; `status`:
        `ok`, or why the instance cannot be used),
        `links` maps a workspace path (`""` for the root) to alias -> `struct(alias, root,
        closure, optional)` (`closure`: the sorted IDs reachable from `root` on every platform;
        `optional`: ID -> the platform conditions it is reached under, research R8), and `members`
        maps a workspace path to alias -> the path of each workspace member it depends on
        (`workspace:`, research R7).
    """
    entries = lockfile.entries
    patched = getattr(lockfile, "patched", [])
    peer_names = sorted({peer: True for entry in entries.values() for peer in entry.peers}.keys())
    plain = {}
    pool = {}
    nodes = {}
    edges = {}
    dependency_keys = {}
    queue = []
    workspace_links = {}
    fallbacks = {}

    def register(node):
        # A context's fallback instance becomes an instance once a peer edge reaches it.
        worklist = [node]
        for _ in range(_LIMIT):
            if not worklist:
                break
            node = worklist.pop()
            if node.identity in nodes:
                continue
            nodes[node.identity] = node
            queue.append(node.identity)
            worklist.extend([pool[t] for t in node.peers.values() if t not in nodes])

    members = {}
    for path in sorted(lockfile.workspaces.keys()):
        children, members[path], error = _workspace_children(lockfile, path)
        if error:
            return _error("{}: {}".format(file, error))
        start = [] if path == "" else [lockfile.workspaces[path].name]
        declared = {alias: True for alias, _ in children}
        declared.update(members[path])
        virtual = {}
        for peer in peer_names:
            key = walk_key(entries, start, peer)
            if peer not in declared and key != None and entries[key].kind != "workspace":
                virtual[peer] = key
        siblings, error = _siblings(entries, children, {}, file, patched, path, plain, virtual = virtual)
        if error:
            return _error(error)
        for node in siblings.values():
            pool[node.identity] = node
        fallbacks[path] = {peer: siblings[peer].identity for peer in peer_names if peer in siblings}
        for alias, _ in children:
            register(siblings[alias])
        workspace_links[path] = {alias: siblings[alias].identity for alias, _ in children}

    for i in range(_LIMIT):
        if i >= len(queue):
            break
        node = nodes[queue[i]]
        entry = entries[node.key]
        if node.status != "ok":
            edges[node.identity] = {}
            dependency_keys[node.identity] = {}
            continue
        ordinary, error = _ordinary_edges(entries, node.key, entry, file)
        if error:
            return _error(error)
        dependency_keys[node.identity] = ordinary
        siblings, error = _siblings(entries, sorted(ordinary.items()), node.peers, file, patched, node.context, plain, fallback = fallbacks[node.context])
        if error:
            return _error(error)
        for child in siblings.values():
            pool[child.identity] = child
        for child in siblings.values():
            register(child)
        node_edges = {alias: child.identity for alias, child in siblings.items()}
        node_edges.update(node.peers)
        edges[node.identity] = node_edges

    # Each workspace context was resolved on its own; nodes whose whole reachable graph is equal
    # are one instance (partition refinement, starting from the identity without context).
    identities = sorted(nodes.keys())
    labels = {}
    classes = {i: labels.setdefault(nodes[i].plain + " " + nodes[i].status, len(labels)) for i in identities}
    for _ in range(len(identities) + 1):
        refined = {}
        following = {}
        for identity in identities:
            signature = json.encode([classes[identity], sorted([[a, classes[t]] for a, t in edges[identity].items()])])
            following[identity] = refined.setdefault(signature, len(refined))
        stable = len(refined) == len(labels)
        classes, labels = following, refined
        if stable:
            break
    members_of = {}
    for identity in identities:
        members_of.setdefault(classes[identity], []).append(identity)
    representatives = {}
    for group in members_of.values():
        node = nodes[group[0]]
        representatives[group[0]] = struct(
            identity = group[0],
            name = node.name,
            version = node.version,
            encoding = node.encoding,
            status = node.status,
            key = node.key,
            contexts = json.encode(sorted({nodes[i].context: True for i in group}.keys())),
        )
    representative_ids = _ids(representatives, hash_fn)
    ids = {identity: representative_ids[members_of[classes[identity]][0]] for identity in identities}
    nodes_by_id = {ids[identity]: representatives[identity] for identity in representatives}
    id_edges = {ids[identity]: {alias: ids[target] for alias, target in edges[identity].items()} for identity in representatives}
    restrictions = {}
    for identity, node in representatives.items():
        entry = entries[node.key]
        restrictions[ids[identity]] = {}
        for alias, target in id_edges[ids[identity]].items():
            if alias in entry.optional_dependencies:
                requirement = _restriction(entries[nodes_by_id[target].key])
                if requirement != None:
                    restrictions[ids[identity]][alias] = requirement
    instances = {}
    for identity, node in representatives.items():
        instance_id = ids[identity]
        instances[instance_id] = struct(
            id = instance_id,
            name = node.name,
            version = node.version,
            store_name = "{}@{}".format(node.name.replace("/", "+"), node.version),
            key = node.key,
            edges = id_edges[instance_id],
            dependency_keys = dependency_keys[identity],
            peers = sorted(nodes[identity].peers.keys()),
            status = node.status,
        )
    links = {}
    for path, aliases in workspace_links.items():
        links[path] = {}
        optional_declared = lockfile.workspaces[path].optionalDependencies
        for alias, identity in aliases.items():
            root = ids[identity]
            requirement = _restriction(entries[nodes[identity].key]) if alias in optional_declared else None
            closure, optional = _closure(id_edges, restrictions, root, [requirement] if requirement else [])
            links[path][alias] = struct(alias = alias, root = root, closure = closure, optional = optional)
    return struct(value = struct(instances = instances, links = links, members = members), error = None)
