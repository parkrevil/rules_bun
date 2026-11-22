"""Bun's isolated store, carried over from `src/install/isolated_install.rs` at bun-v1.4.4.

Research Part 2 S8: `build_store` turns a cleaned lockfile into the store of an isolated install
for one platform. Its first pass walks the dependency graph depth-first from the root, creating a
node per place a package is reached and resolving each peer up the chain of nodes; its second
pass makes nodes with the same package and the same peers one entry. An entry's `dependencies`
(dependency name -> entry) are the links of FR-008's graph. `store_inputs` computes once the parts
of it that read no platform, for the adapter, which builds a store per platform class (research
R13).

Not carried over (research Part 2): hidden and public hoisting (`claim_hidden_hoist`,
`public_hoist_pattern`; ID-3, no default pattern), `peer_hash` and `entry_hash` (directory names),
the workspace filter and `packages_to_install` (a default install selects everything), and the
`Wyhash` of an early-dedupe context, which is the exact tuple it hashes here.

Bun's sets: a node's transitive peers are ordered by package name and keep the first of a name
(`TransitivePeerOrderedArraySetCtx`); an entry's dependencies keep the first of a name
(`DependenciesOrderedArraySetCtx`), here in the order they are added, where Bun keeps them sorted
by name. The members are the same; only their order differs, and no consumer reads it.

An entry's `nested_folder` (ISO L1404, L1424) is not kept: the installer reads it to link a nested
folder package through the package containing it instead of installing it (ISO L2365-L2390), which
changes no entry and no link (research Part 2, "Not carried over").
"""

load(
    ":bun_install_types.bzl",
    "LIBC_ALL",
    "RESOLUTION_TAG",
    "VERSION_TAG",
    "behavior_is_peer",
    "behavior_is_placed",
    "behavior_is_workspace",
    "dependency_features",
    "dependency_sort_key",
    "meta_is_disabled",
    "tag_is_local_package",
)
load(
    ":bun_lockfile.bzl",
    "INVALID",
    "dependency_ids",
    "is_overridden_dependency",
    "is_valid",
    "overrides_contains_name",
    "shared_version",
)
load(":bun_tree.bzl", "is_filtered_dependency_or_workspace")

_LIMIT = 1 << 30

def _dependency_is_contained_folder(lockfile, declarer, dependency):
    """`dependency_is_contained_folder`: a `file:` path relative to the package declaring it.

    Bun: src/install/isolated_install.rs L392–L405 @ bun-v1.4.4
    """
    if tag_is_local_package(declarer.tag) or dependency.version.tag != VERSION_TAG.FOLDER:
        return False
    return not overrides_contains_name(lockfile, dependency.name)

def contained_folders(lockfile):
    """`contained_folders`: contained-folder dependencies, and the packages only those reach.

    Bun: src/install/isolated_install.rs L407–L451 @ bun-v1.4.4

    Args:
        lockfile: A cleaned lockfile.

    Returns:
        `(contained dependency IDs, nested folder package IDs)` as dicts.
    """
    packages = lockfile.packages
    contained = {}
    nested = {pkg_id: True for pkg_id in range(len(packages)) if packages[pkg_id].resolution.tag == RESOLUTION_TAG.FOLDER}
    if not nested:
        return contained, nested
    inside_a_package = {}
    for pkg_id in range(len(packages)):
        for dep_id in dependency_ids(lockfile, pkg_id):
            target = lockfile.resolutions[dep_id]
            if not is_valid(target) or packages[target].resolution.tag != RESOLUTION_TAG.FOLDER:
                continue
            if _dependency_is_contained_folder(lockfile, packages[pkg_id].resolution, lockfile.dependencies[dep_id]):
                contained[dep_id] = True
                inside_a_package[target] = True
            elif not behavior_is_peer(lockfile.dependencies[dep_id].behavior):
                nested.pop(target, None)

    # The hoisted tree binds an optional peer to a folder whose path only its declarer can follow.
    return contained, {pkg_id: True for pkg_id in nested if pkg_id in inside_a_package}

def _leaking_peers(lockfile, peer_names, is_filtered, is_contained_folder):
    """Per package, the peer names its closure does not provide (the fixpoint of ISO L561-L672).

    Bun: src/install/isolated_install.rs L561–L672 @ bun-v1.4.4
    """
    packages = lockfile.packages
    dependencies = lockfile.dependencies
    resolutions = lockfile.resolutions
    leaking = [{} for _ in packages]
    if not peer_names:
        return leaking

    # The runtime child of a peer edge is whichever package an ancestor's dependency with that name
    # resolves to, so resolutions are indexed by dependency name.
    peer_targets = {}
    for dep_id in range(len(dependencies)):
        target = resolutions[dep_id]
        name = dependencies[dep_id].name
        if is_valid(target) and name in peer_names:
            targets = peer_targets.setdefault(name, [])
            if target not in targets:
                targets.append(target)

    own_peers = [{} for _ in packages]
    provides = [{} for _ in packages]
    for pkg_id in range(len(packages)):
        for dep_id in dependency_ids(lockfile, pkg_id):
            dep = dependencies[dep_id]
            if dep.name not in peer_names:
                continue
            if behavior_is_peer(dep.behavior):
                own_peers[pkg_id][dep.name] = True
            elif not is_contained_folder(dep_id) and not is_filtered(dep_id, pkg_id):
                provides[pkg_id][dep.name] = True

    for _ in range(_LIMIT):
        changed = False
        for pkg_id in range(len(packages)):
            scratch = dict(own_peers[pkg_id])
            for dep_id in dependency_ids(lockfile, pkg_id):
                dep = dependencies[dep_id]
                if behavior_is_peer(dep.behavior):
                    for child in peer_targets.get(dep.name, []):
                        scratch.update(leaking[child])
                elif is_valid(resolutions[dep_id]):
                    scratch.update(leaking[resolutions[dep_id]])
            for name in provides[pkg_id]:
                scratch.pop(name, None)
            if sorted(scratch.keys()) != sorted(leaking[pkg_id].keys()):
                leaking[pkg_id] = scratch
                changed = True
        if not changed:
            break
    return leaking

def _sorted_peers(node):
    """A node's transitive peers in their set's order: by package name (`OrderedArraySet::slice`).

    Bun: src/install/isolated_install/Store.rs L209–L211 @ bun-v1.4.4
    """
    return [node.peers[name] for name in sorted(node.peers.keys())]

def _insert_peer(lockfile, node, peer):
    """`OrderedArraySet::insert` with `TransitivePeerOrderedArraySetCtx`: one per package name.

    Bun: src/install/isolated_install/Store.rs L234–L245 @ bun-v1.4.4
    Bun: src/install/isolated_install/Store.rs L635–L655 @ bun-v1.4.4
    """
    node.peers.setdefault(lockfile.packages[peer[1]].name, peer)

def _peers_eql(lhs, rhs):
    """`OrderedArraySet::eql` with `TransitivePeerOrderedArraySetCtx`: the same packages.

    Bun: src/install/isolated_install/Store.rs L218–L232 @ bun-v1.4.4
    Bun: src/install/isolated_install/Store.rs L636–L639 @ bun-v1.4.4
    """
    if len(lhs) != len(rhs):
        return False
    for name, peer in lhs.items():
        other = rhs.get(name)
        if other == None or other[1] != peer[1]:
            return False
    return True

def _named(lockfile, node, name):
    """`dependencies_named`: the node's dependencies of a name, in their order.

    Bun: src/install/isolated_install.rs L471–L492 @ bun-v1.4.4
    """
    return [ids for ids in node.dependencies if lockfile.dependencies[ids[0]].name == name]

def store_inputs(lockfile, platforms):
    """What `build_store` reads that is the same on each of `platforms`, computed once for all.

    Bun builds one store per install, for its one platform; the adapter builds one per platform
    class (research R3) from one lockfile, and this computes once what each of those builds would
    compute again (research R13, T183): the contained folders (ISO L407–L451); the peer names
    whose leaks `_leaking_peers` follows (ISO L573–L578); the workspace dependencies the root's
    folder does not place (`is_unlinked_member`, ISO L717–L720); each package's dependency IDs in
    `DepSorter` order (ISO L978–L994) and the peers its features omit (`is_omitted_peer`,
    ISO L998–L1003); and the answer of `is_filtered_dependency_or_workspace` (ISO L1035–L1044)
    wherever it is the same on each platform. That function reads the platform only through
    `Meta::is_disabled` of the dependency's package (TREE L1313–L1405), so a dependency with no
    package, or on a package `Meta::is_disabled` answers alike on each platform with the target
    `libc` and with every `libc` (`Libc::for_dependency`), gets one answer on all of them.

    Bun: src/install/isolated_install.rs L407–L451 @ bun-v1.4.4
    Bun: src/install/isolated_install.rs L573–L578 @ bun-v1.4.4
    Bun: src/install/isolated_install.rs L717–L720 @ bun-v1.4.4
    Bun: src/install/isolated_install.rs L978–L1003 @ bun-v1.4.4
    Bun: src/install/isolated_install.rs L1035–L1044 @ bun-v1.4.4

    Args:
        lockfile: A cleaned lockfile (`lockfile_clean`).
        platforms: The `struct(cpu, os, libc)` bit sets of the targets `build_store` is called for.

    Returns:
        `struct(contained, nested_folders, peer_names, peer_dependencies, workspace_dependencies,
        unlinked_members, dependency_ids, omitted_peers, filtered)`: `peer_names` holds names;
        `peer_dependencies`, `workspace_dependencies` and `unlinked_members` hold dependency IDs;
        `dependency_ids` and `omitted_peers` are per package ID, a list and a dict of dependency
        IDs; `filtered` is per package ID a dict from the ID of a dependency it declares to the
        filter's answer on every one of `platforms`.
    """
    packages = lockfile.packages
    dependencies = lockfile.dependencies
    contained, nested_folders = contained_folders(lockfile)

    # The peer and workspace dependencies (`Behavior::is_peer`, `Behavior::is_workspace`), and the
    # names of the peers.
    peer_dependencies = {}
    workspace_dependencies = {}
    peer_names = {}
    for dep_id in range(len(dependencies)):
        dep = dependencies[dep_id]
        if behavior_is_peer(dep.behavior):
            peer_dependencies[dep_id] = True
            peer_names[dep.name] = True
        if behavior_is_workspace(dep.behavior):
            workspace_dependencies[dep_id] = True

    # A workspace member is not linked into the root's `node_modules` when one of the root's own
    # dependencies has the same name.
    root_folder = None
    if lockfile.trees:
        tree = lockfile.trees[0]
        root_folder = {d: True for d in lockfile.hoisted_dependencies[tree.dependencies.off:tree.dependencies.off + tree.dependencies.len]}
    unlinked_members = {dep_id: True for dep_id in workspace_dependencies if root_folder != None and dep_id not in root_folder}

    # Per `os`, `cpu` and `libc` of a package: whether `Meta::is_disabled` answers alike on each
    # platform, in both of `Libc::for_dependency`'s readings.
    alike = {}
    sorted_ids = []
    omitted_peers = []
    filtered = []
    for pkg_id in range(len(packages)):
        dep_ids = sorted(dependency_ids(lockfile, pkg_id), key = lambda d: dependency_sort_key(dependencies[d]))
        sorted_ids.append(dep_ids)
        features = dependency_features(packages[pkg_id].resolution.tag)
        omitted_peers.append({
            dep_id: True
            for dep_id in dep_ids
            if dep_id in peer_dependencies and not behavior_is_placed(dependencies[dep_id].behavior, features)
        })
        answers = {}
        for dep_id in dep_ids:
            target = lockfile.resolutions[dep_id]
            if is_valid(target):
                meta = packages[target].meta
                key = (meta.os, meta.arch, meta.libc)
                if key not in alike:
                    alike[key] = len({
                        (meta_is_disabled(meta, p.cpu, p.os, p.libc), meta_is_disabled(meta, p.cpu, p.os, LIBC_ALL)): True
                        for p in platforms
                    }) == 1
                if not alike[key]:
                    continue
            answers[dep_id] = is_filtered_dependency_or_workspace(lockfile, dep_id, pkg_id, platforms[0])
        filtered.append(answers)
    return struct(
        contained = contained,
        nested_folders = nested_folders,
        peer_names = peer_names,
        peer_dependencies = peer_dependencies,
        workspace_dependencies = workspace_dependencies,
        unlinked_members = unlinked_members,
        dependency_ids = sorted_ids,
        omitted_peers = omitted_peers,
        filtered = filtered,
    )

def build_store(lockfile, platform, inputs = None):
    """`build_store` of an install that selects everything, for one platform.

    Bun: src/install/isolated_install.rs L510–L1484 @ bun-v1.4.4
    Bun: src/install/isolated_install.rs L494–L508 @ bun-v1.4.4

    Args:
        lockfile: A cleaned lockfile (`lockfile_clean`).
        platform: `struct(cpu, os, libc)` bit sets of the target.
        inputs: The `store_inputs` of `lockfile` for platforms that include `platform`; computed
            for `platform` alone when `None`.

    Returns:
        `struct(value, error)`; `value` is `struct(nodes, entries, leaking_peers)`: each entry is
        `struct(node_id, pkg_id, dep_id, dependencies, parents, peers)`, `dependencies` mapping a
        dependency name to `(entry ID, dependency ID)`; entry 0 is the root.
    """
    packages = lockfile.packages
    dependencies = lockfile.dependencies
    resolutions = lockfile.resolutions
    peer_range_cache = {}
    if inputs == None:
        inputs = store_inputs(lockfile, [platform])
    contained, nested_folders, unlinked_members = inputs.contained, inputs.nested_folders, inputs.unlinked_members
    peer_dependencies, workspace_dependencies = inputs.peer_dependencies, inputs.workspace_dependencies

    def is_contained_folder(dep_id):
        """Whether the dependency `dep_id` is a folder its declarer contains.

        Bun: src/install/isolated_install.rs L544–L544 @ bun-v1.4.4
        """
        return dep_id in contained

    def is_filtered(dep_id, parent_pkg_id):
        """Whether the store leaves out the dependency `dep_id` of `parent_pkg_id` on `platform`.

        Bun: src/install/isolated_install.rs L1035–L1044 @ bun-v1.4.4
        """
        answer = inputs.filtered[parent_pkg_id].get(dep_id)
        if answer == None:
            answer = is_filtered_dependency_or_workspace(lockfile, dep_id, parent_pkg_id, platform)
        return answer

    peer_names = inputs.peer_names
    leaking_peers = _leaking_peers(lockfile, peer_names, is_filtered, is_contained_folder)
    peer_order = list(peer_names.keys())

    root_declares_workspace = {}
    for dep_id in dependency_ids(lockfile, 0):
        if not behavior_is_workspace(dependencies[dep_id].behavior) or not is_valid(resolutions[dep_id]):
            continue
        if is_filtered(dep_id, 0):
            continue
        root_declares_workspace[resolutions[dep_id]] = True

    nodes = []
    early_dedupe = {}
    node_queue = [(INVALID, INVALID, 0)]

    def resolve_up(start, name):
        """The package an ancestor of `start` (or `start`) provides `name` with, for the context.

        Bun: src/install/isolated_install.rs L829–L856 @ bun-v1.4.4
        """
        curr = start
        for _ in range(len(nodes) + 1):
            if curr == INVALID:
                break
            for dep_id, pkg_id in _named(lockfile, nodes[curr], name):
                if not is_contained_folder(dep_id):
                    return pkg_id
            for peer in _sorted_peers(nodes[curr]):
                if not peer[2] and dependencies[peer[0]].name == name:
                    return peer[1]
            curr = nodes[curr].parent_id
        return INVALID

    # First pass: create full dependency tree with resolved peers (ISO L728-L1240).
    for _ in range(_LIMIT):
        if not node_queue:
            break
        parent_id, entry_dep_id, entry_pkg_id = node_queue.pop()

        # check for cycles
        skip = False
        curr = parent_id
        for _ in range(len(nodes) + 1):
            if curr == INVALID:
                break
            if nodes[curr].pkg_id == entry_pkg_id:
                dep_id = nodes[curr].dep_id
                if dep_id == INVALID and entry_dep_id == INVALID:
                    nodes[parent_id].nodes.append(curr)
                    skip = True
                    break
                if dep_id == INVALID or entry_dep_id == INVALID:
                    # one is the root package, one is a dependency on the root package
                    break
                curr_dep, entry_dep = dependencies[dep_id], dependencies[entry_dep_id]
                if curr_dep.name == entry_dep.name and behavior_is_workspace(curr_dep.behavior) == behavior_is_workspace(entry_dep.behavior):
                    nodes[parent_id].nodes.append(curr)
                    skip = True
                    break
            curr = nodes[curr].parent_id
        if skip:
            continue

        node_id = len(nodes)

        # the dependencies of workspace packages and of the root are pulled in once
        skip_dependencies = entry_pkg_id == 0 and entry_dep_id != INVALID

        if entry_dep_id != INVALID:
            entry_dep = dependencies[entry_dep_id]

            # A `workspace:` reference does not own the workspace's dependencies when the root also
            # declares that workspace; the root-declared entry does.
            if entry_dep.version.tag == VERSION_TAG.WORKSPACE and not behavior_is_workspace(entry_dep.behavior) and entry_pkg_id in root_declares_workspace:
                skip_dependencies = True

            # Two would-be nodes with the same package and the same ancestor resolution of each
            # leaking peer become the same entry (ISO L801-L937).
            if entry_dep.version.tag == VERSION_TAG.WORKSPACE or not peer_names or not leaking_peers[entry_pkg_id]:
                ctx = ()
            else:
                ctx = tuple([(name, resolve_up(parent_id, name)) for name in peer_order if name in leaking_peers[entry_pkg_id]])
            key = (entry_pkg_id, ctx)
            dedupe_node_id = early_dedupe.get(key)
            if dedupe_node_id == None:
                early_dedupe[key] = node_id
            else:
                dedupe_dep_id = nodes[dedupe_node_id].dep_id
                deduped = dedupe_dep_id != INVALID
                if deduped:
                    dedupe_dep = dependencies[dedupe_dep_id]
                    is_ws_a = dedupe_dep.version.tag == VERSION_TAG.WORKSPACE
                    is_ws_b = entry_dep.version.tag == VERSION_TAG.WORKSPACE
                    if dedupe_dep.name != entry_dep.name or is_ws_a != is_ws_b:
                        deduped = False
                    elif is_ws_a and behavior_is_workspace(dedupe_dep.behavior) != behavior_is_workspace(entry_dep.behavior):
                        deduped = False
                if deduped:
                    # The skipped subtree would have walked up through this ancestor chain marking
                    # each node with its leaking peers.
                    for peer in _sorted_peers(nodes[dedupe_node_id]) if nodes[dedupe_node_id].peers else []:
                        name = dependencies[peer[0]].name
                        curr = parent_id
                        for _ in range(len(nodes) + 1):
                            if curr == INVALID:
                                break
                            if any([not is_contained_folder(d) for d, _ in _named(lockfile, nodes[curr], name)]):
                                break

                            # A package is never its own peer.
                            if nodes[curr].pkg_id != peer[1]:
                                _insert_peer(lockfile, nodes[curr], peer)
                            curr = nodes[curr].parent_id
                    nodes[parent_id].nodes.append(dedupe_node_id)
                    continue

        nodes.append(struct(pkg_id = entry_pkg_id, dep_id = entry_dep_id, parent_id = parent_id, nodes = [], dependencies = [], peers = {}))
        if parent_id != INVALID:
            nodes[parent_id].nodes.append(node_id)
        if skip_dependencies:
            continue

        node = nodes[node_id]
        queue_mark = len(node_queue)
        peer_dep_ids = []

        # Under `--omit=peer` the copy an ancestor provides is installed anyway, and is linked.
        omitted_peers = inputs.omitted_peers[entry_pkg_id]

        filtered = inputs.filtered[entry_pkg_id]
        for dep_id in inputs.dependency_ids[entry_pkg_id]:
            if dep_id not in omitted_peers and (filtered[dep_id] if dep_id in filtered else is_filtered(dep_id, entry_pkg_id)):
                continue
            pkg_id = resolutions[dep_id]
            if dep_id not in peer_dependencies:
                if dep_id not in unlinked_members:
                    node.dependencies.append((dep_id, pkg_id))
                node_queue.append((node_id, dep_id, pkg_id))
                continue
            peer_dep_ids.append(dep_id)

        for peer_dep_id in peer_dep_ids:
            peer_dep = dependencies[peer_dep_id]
            best_version = shared_version(lockfile, peer_range_cache, entry_pkg_id, peer_dep_id)
            if not is_valid(best_version):
                best_version = resolutions[peer_dep_id]
            if peer_dep_id in omitted_peers or best_version in nested_folders:
                best_version = INVALID

            # Go through the peer's parents looking for a package with the same name; else the
            # current best version. A package can satisfy its own peers.
            resolved, auto_installed = best_version, True
            visited = []
            curr = node_id
            for _ in range(len(nodes) + 1):
                if curr == INVALID:
                    break
                found = None
                for dep_id, pkg_id in _named(lockfile, nodes[curr], peer_dep.name):
                    # It's private to the ancestor; a package's own folder still satisfies its peer.
                    if curr != node_id and is_contained_folder(dep_id):
                        continue

                    # As in `hoist_dependency`, no other package stands in for an overridden peer.
                    if (curr != node_id and is_valid(best_version) and
                        packages[pkg_id].name != packages[best_version].name and
                        is_overridden_dependency(lockfile, peer_dep_id)):
                        found = (best_version, True)
                    else:
                        found = (pkg_id, False)
                    break
                if found == None:
                    for peer in _sorted_peers(nodes[curr]):
                        if dependencies[peer[0]].name != peer_dep.name:
                            continue

                        # A transitive peer with the same name has already passed through this node.
                        if not peer[2]:
                            found = (peer[1], False)
                        elif not is_valid(best_version):
                            found = (INVALID, True)
                        elif best_version == peer[1]:
                            found = (peer[1], True)
                        else:
                            # Choose the best version and mark every remaining parent.
                            for _ in range(len(nodes) + 1):
                                if curr == INVALID:
                                    break
                                visited.append(curr)
                                curr = nodes[curr].parent_id
                            found = (best_version, True)
                        break
                if found != None:
                    resolved, auto_installed = found
                    break
                visited.append(curr)
                curr = nodes[curr].parent_id

            if not is_valid(resolved):
                # no parent provides the peer, and it is optional or omitted
                continue
            for visited_id in visited:
                # A package is never its own peer.
                if nodes[visited_id].pkg_id == resolved:
                    continue
                _insert_peer(lockfile, nodes[visited_id], (peer_dep_id, resolved, auto_installed))
            if visited:
                # no visited parent means the node satisfied its own peer
                node.dependencies.append((peer_dep_id, resolved))
                node_queue.append((node_id, peer_dep_id, resolved))

        # node_queue is a stack: the first child pushed is popped first
        children = node_queue[queue_mark:]
        for _ in children:
            node_queue.pop()
        node_queue.extend(reversed(children))

    # Second pass: deduplicate nodes when the package and the peer set match an entry
    # (ISO L1251-L1470).
    entries = []
    dedupe = {}
    entry_queue = [(0, INVALID)]
    for i in range(_LIMIT):
        if i >= len(entry_queue):
            break
        node_id, entry_parent_id = entry_queue[i]
        node = nodes[node_id]
        pkg_id = node.pkg_id
        found_existing = pkg_id in dedupe
        matched = False
        if found_existing:
            curr_dep_id = node.dep_id
            for info in dedupe[pkg_id]:
                if (info.dep_id == INVALID or curr_dep_id == INVALID) and info.dep_id != curr_dep_id:
                    continue
                if info.dep_id != INVALID and curr_dep_id != INVALID:
                    curr_dep, existing_dep = dependencies[curr_dep_id], dependencies[info.dep_id]
                    if (existing_dep.version.tag == VERSION_TAG.WORKSPACE and curr_dep.version.tag == VERSION_TAG.WORKSPACE and
                        behavior_is_workspace(existing_dep.behavior) != behavior_is_workspace(curr_dep.behavior)):
                        continue
                if (not info.peers and not node.peers) or _peers_eql(info.peers, node.peers):
                    # dedupe! depend on the already created entry
                    entries[info.entry_id].parents.append(entry_parent_id)
                    if curr_dep_id == INVALID or curr_dep_id not in workspace_dependencies:
                        entries[entry_parent_id].dependencies.setdefault(dependencies[curr_dep_id].name, (info.entry_id, curr_dep_id))
                    matched = True
                    break
        else:
            dedupe[pkg_id] = []
        if matched:
            continue

        new_entry_id = len(entries)
        entries.append(struct(node_id = node_id, pkg_id = pkg_id, dep_id = node.dep_id, dependencies = {}, parents = [entry_parent_id], peers = node.peers))

        # skip implicit workspace dependencies on the root
        if entry_parent_id != INVALID and node.dep_id != INVALID and node.dep_id not in workspace_dependencies:
            entries[entry_parent_id].dependencies.setdefault(dependencies[node.dep_id].name, (new_entry_id, node.dep_id))
        dedupe[pkg_id].append(struct(entry_id = new_entry_id, dep_id = node.dep_id, peers = node.peers))
        for child in node.nodes:
            entry_queue.append((child, new_entry_id))

    return struct(value = struct(nodes = nodes, entries = entries, leaking_peers = leaking_peers), error = None)
