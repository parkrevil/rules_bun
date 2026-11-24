"""Bun's hoister and dependency filter, carried over from `src/install/lockfile/Tree.rs` at bun-v1.4.4.

Research Part 2 S4 and S7. `hoist` is `Lockfile::hoist::<Resolvable>`: it builds the trees that
`bun.lock` prints, rewriting the resolutions of peers on the way, and `bun_lockfile.bzl`'s
`lockfile_resolve` runs it until no peer is bound late. `is_filtered_dependency_or_workspace` is
the filter the isolated linker applies (S7). Only the `Resolvable` method is carried over: the
isolated linker reads the trees of `Lockfile::resolve`, never the `Filter` trees of the hoisted
linker (research Part 2, "Not carried over").

Bun's recursion in `hoist_dependency` (one call per ancestor folder) is a loop up the parents here,
and its breadth-first queue a list read by index; Starlark has neither recursion nor `while`.
"""

load(":bun_catalog_map.bzl", "catalogs_resolve_range")
load(
    ":bun_install_types.bzl",
    "RESOLUTION_TAG",
    "VERSION_TAG",
    "behavior_is_bundled",
    "behavior_is_optional",
    "behavior_is_optional_peer",
    "behavior_is_peer",
    "behavior_is_placed",
    "behavior_is_workspace",
    "dependency_features",
    "dependency_sort_key",
    "is_safe_install_folder_name",
    "libc_for_dependency",
    "meta_is_disabled",
    "resolution_satisfies_dependency_version",
)
load(
    ":bun_lockfile.bzl",
    "INVALID",
    "dependency_ids",
    "is_overridden_dependency",
    "is_valid",
    "resolve_peer_dep_version_based",
)
load(":bun_semver.bzl", "query_satisfies")

# `tree::ROOT_DEP_ID` and `tree::INVALID_ID` (TREE L68-L69).
ROOT_DEP_ID = -2
INVALID_ID = -1

_LIMIT = 1 << 30

# `MAX_PATH_BYTES` of the platforms the oracle runs on, as `name_is_single_path_entry` reads it.
_MAX_PATH_BYTES = 4096

# `HoistDependencyResult` (TREE L148-L171); `Contested` exists for `Filter` only.
_LOOP = "dependency_loop"
_HOISTED = "hoisted"
_RESOLVE = "resolve"
_RESOLVE_REPLACE = "resolve_replace"
_RESOLVE_LATER = "resolve_later"
_REBIND = "rebind"
_SERVED = "served"
_PLACEMENT = "placement"

def _result(kind, value = None, id = None, bundled = False):
    """`HoistDependencyResult`.

    Bun: src/install/lockfile/Tree.rs L148–L171 @ bun-v1.4.4
    """
    return struct(kind = kind, value = value, id = id, bundled = bundled)

def _in_slice(slice, dep_id):
    """`DependencySlice::contains`.

    Bun: src/install_types/resolver_hooks.rs L105–L108 @ bun-v1.4.4
    """
    return dep_id >= slice.off and dep_id < slice.off + slice.len

def _name_is_single_path_entry(name):
    """`name_is_single_path_entry`.

    Bun: src/install/PackageInstaller.rs L564–L574 @ bun-v1.4.4
    """
    if len(name) >= _MAX_PATH_BYTES or not is_safe_install_folder_name(name):
        return False
    slashes = name.count("/")
    return slashes == 0 or (slashes == 1 and name[0] == "@")

def _alias_is_safe_install_target(alias):
    """`alias_is_safe_install_target`: an alias that can be a folder under `node_modules`.

    Bun: src/install/PackageInstaller.rs L576–L589 @ bun-v1.4.4
    Bun: src/install/lockfile/Tree.rs L1727–L1745 @ bun-v1.4.4
    """
    if not _name_is_single_path_entry(alias):
        return False
    slash = alias.find("/")
    if slash != -1:
        if slash <= 1:
            return False
        name = alias[slash + 1:]
    elif alias[0] != "@":
        name = alias
    else:
        return False
    return not name.startswith(".") and name.lower() != "node_modules"

def is_unlinked_member(lockfile, tree):
    """`Tree::is_unlinked_member`: a workspace that has no symlink in the root `node_modules`.

    Bun: src/install/lockfile/Tree.rs L95–L112 @ bun-v1.4.4

    Args:
        lockfile: A hoisted lockfile.
        tree: One of its trees.

    Returns:
        Whether the tree belongs to a workspace whose name a root dependency took.
    """
    if tree.parent == INVALID_ID or tree.dependency_id < 0 or tree.dependency_id >= len(lockfile.dependencies):
        return False
    dep = lockfile.dependencies[tree.dependency_id]
    if not behavior_is_workspace(dep.behavior) or dep.version.tag != VERSION_TAG.WORKSPACE:
        return False
    parent = lockfile.trees[tree.parent]
    rows = lockfile.hoisted_dependencies[parent.dependencies.off:parent.dependencies.off + parent.dependencies.len]
    return tree.dependency_id not in rows

def bind_served_peers(served, rows, dependencies, resolutions):
    """`bind_served_peers`: each served peer gets its recorded package unless it is itself a row.

    Bun: src/install/lockfile/Tree.rs L814–L834 @ bun-v1.4.4

    Args:
        served: `(dependency ID, package ID)` pairs; emptied.
        rows: Each tree's rows (dependency IDs).
        dependencies: The lockfile's dependencies.
        resolutions: The lockfile's resolutions; changed in place.
    """
    if not served:
        return
    placed = {}
    for tree_rows in rows:
        for row in tree_rows:
            if behavior_is_peer(dependencies[row].behavior):
                placed[row] = True
    for dep_id, pkg_id in served:
        if dep_id not in placed:
            resolutions[dep_id] = pkg_id
    served.clear()

def _builder(lockfile):
    """`tree::Builder` for `BuilderMethod::Resolvable`.

    Bun: src/install/lockfile/Tree.rs L501–L565 @ bun-v1.4.4
    Bun: src/install/lockfile.rs L1657–L1699 @ bun-v1.4.4
    """
    return struct(
        lockfile = lockfile,
        packages = lockfile.packages,
        deps = lockfile.dependencies,
        resolutions = lockfile.resolutions,
        tree_parent = [],
        tree_dep_id = [],
        tree_rows = [],
        queue = [],
        pending_peers = {},
        state = {"late_bound_peer": False, "bundle_placed": False, "replaced_row": False, "error": None},
        walked = {},
        served = [],
        probes = [],
        cache = {},
        placed = {},
    )

def _with_peers(b):
    """The packages that have a peer dependency on an npm range (`PeerProbes`'s first cache).

    Bun: src/install/lockfile/Tree.rs L606–L618 @ bun-v1.4.4
    """
    with_peers = b.cache.get("with_peers")
    if with_peers == None:
        with_peers = {}
        for pkg_id in range(len(b.packages)):
            for dep_id in dependency_ids(b.lockfile, pkg_id):
                peer = b.deps[dep_id]
                if behavior_is_peer(peer.behavior) and peer.version.tag == VERSION_TAG.NPM:
                    with_peers[pkg_id] = True
                    break
        b.cache["with_peers"] = with_peers
    return with_peers

def _regular_targets(b):
    """`regular_targets`: the packages a dependency other than a peer resolves to (cached once).

    Bun: src/install/lockfile/Tree.rs L745–L758 @ bun-v1.4.4
    """
    targets = b.cache.get("regular_targets")
    if targets == None:
        targets = {}
        for dep_id in range(len(b.deps)):
            if not behavior_is_peer(b.deps[dep_id].behavior) and is_valid(b.resolutions[dep_id]):
                targets[b.resolutions[dep_id]] = True
        b.cache["regular_targets"] = targets
    return targets

def _probes_begin(b, owner_deps, package_id, is_for_peer):
    """`PeerProbes::begin`: the peers of the package about to be hoisted out of its owner.

    Bun: src/install/lockfile/Tree.rs L590–L683 @ bun-v1.4.4
    """
    b.probes.clear()
    if not is_valid(package_id) or package_id not in _with_peers(b):
        return
    if b.packages[package_id].resolution.tag in [RESOLUTION_TAG.WORKSPACE, RESOLUTION_TAG.SYMLINK]:
        return
    own = dependency_ids(b.lockfile, package_id)
    owner = range(owner_deps.off, owner_deps.off + owner_deps.len)
    for peer_dep_id in own:
        peer = b.deps[peer_dep_id]
        if not behavior_is_peer(peer.behavior) or peer.version.tag != VERSION_TAG.NPM:
            continue

        # A regular dependency on the same name is what gets installed next to the package.
        if any([b.deps[d].name == peer.name and not behavior_is_peer(b.deps[d].behavior) for d in own]):
            continue

        # The owner's own copy of the peer, if any, is the one the package finds from here.
        owner_copy = None
        for d in owner:
            dep = b.deps[d]
            if dep.name == peer.name and not behavior_is_peer(dep.behavior) and is_valid(b.resolutions[d]):
                owner_copy = b.resolutions[d]
                break
        if owner_copy != None:
            is_listed = resolution_satisfies_dependency_version(b.packages[owner_copy].resolution, peer.version)
        else:
            is_listed = not behavior_is_optional_peer(peer.behavior)
        if not is_listed:
            continue
        if is_for_peer:
            used_by_owner = None
        elif owner_copy != None:
            used_by_owner = ("package", owner_copy)
        elif any([b.deps[d].name == peer.name and not behavior_is_optional_peer(b.deps[d].behavior) for d in owner]):
            used_by_owner = ("first_above", None)
        else:
            used_by_owner = None
        b.probes.append([peer_dep_id, owner_copy != None, used_by_owner])

def _is_hidden_by(b, tree_id):
    """`PeerProbes::is_hidden_by`: hoisting into the tree would change a peer's copy.

    Bun: src/install/lockfile/Tree.rs L685–L742 @ bun-v1.4.4
    """
    i = 0
    for _ in range(len(b.probes) + 1):
        if i >= len(b.probes):
            break
        peer_dep_id, provided, owner_copy = b.probes[i]
        peer = b.deps[peer_dep_id]
        row = b.placed.get((tree_id, peer.name))
        held = b.resolutions[row] if row != None else INVALID
        if not is_valid(held):
            i += 1
            continue
        is_optional = behavior_is_optional_peer(peer.behavior)
        if resolution_satisfies_dependency_version(b.packages[held].resolution, peer.version):
            if owner_copy != None and owner_copy[0] == "package" and owner_copy[1] != held:
                if held not in _regular_targets(b):
                    return True
                b.probes[i][2] = None
            elif owner_copy != None and owner_copy[0] == "first_above":
                b.probes[i][2] = ("package", held)
            b.probes[i][1] = provided or not is_optional
            i += 1
        elif provided and not is_optional:
            return True
        else:
            # Out of range wherever the package ends up (`swap_remove`).
            last = b.probes.pop()
            if i < len(b.probes):
                b.probes[i] = last
    return False

def _repeating_period(b, parent, dependency_id):
    """`repeating_period`: two identical rounds of trees ending at `parent` nest forever.

    Bun: src/install/lockfile/Tree.rs L777–L812 @ bun-v1.4.4
    """
    period = 1
    round_start = parent
    for _ in range(len(b.tree_parent) + 1):
        if round_start == INVALID_ID:
            break
        above = b.tree_parent[round_start]
        if b.tree_dep_id[round_start] == dependency_id:
            lower, upper = parent, above
            same = 0
            for _ in range(period):
                if upper == INVALID_ID or b.tree_dep_id[lower] != b.tree_dep_id[upper]:
                    break
                upper_rows, lower_rows = b.tree_rows[upper], b.tree_rows[lower]
                if upper_rows[:len(lower_rows)] != lower_rows:
                    break
                lower, upper = b.tree_parent[lower], b.tree_parent[upper]
                same += 1
            if same == period:
                return period
        round_start = above
        period += 1
    return None

def _peer_by_version(b, dep_id):
    """`Builder::peer_by_version`.

    Bun: src/install/lockfile/Tree.rs L855–L869 @ bun-v1.4.4
    """
    return resolve_peer_dep_version_based(b.lockfile, b.deps[dep_id])

def _bind_peer(b, dep_id):
    """`Builder::bind_peer`: a peer starts every pass from its version-based package.

    Bun: src/install/lockfile/Tree.rs L871–L883 @ bun-v1.4.4
    """
    if not behavior_is_peer(b.deps[dep_id].behavior):
        return False
    bound = _peer_by_version(b, dep_id)
    if bound != None:
        b.resolutions[dep_id] = bound
    return bound != None

def _bind_pending_peers(b, name, pkg_id):
    """`Builder::bind_pending_peers`.

    Bun: src/install/lockfile/Tree.rs L843–L849 @ bun-v1.4.4
    """
    pending = b.pending_peers.pop(name, None)
    if pending != None:
        for dep_id in pending:
            b.resolutions[dep_id] = pkg_id

def _hoist_root_resolves_elsewhere(b, hoist_root, package_id, name):
    """`Tree::hoist_root_resolves_elsewhere`.

    Bun: src/install/lockfile/Tree.rs L2053–L2143 @ bun-v1.4.4
    """
    if not is_valid(package_id) or b.tree_parent[hoist_root] == INVALID_ID:
        return False

    def resolves_elsewhere(pkg_id):
        """Whether a dependency of `pkg_id` named `name` resolves to another package than `package_id`.

        Bun: src/install/lockfile/Tree.rs L2077–L2088 @ bun-v1.4.4
        """
        for dep_id in dependency_ids(b.lockfile, pkg_id):
            dep = b.deps[dep_id]
            if dep.name == name and not behavior_is_bundled(dep.behavior):
                by_version = _peer_by_version(b, dep_id)
                if (by_version if by_version != None else b.resolutions[dep_id]) != package_id:
                    return True
        return False

    def nested_in(tree_id, tree_owner):
        """The packages of `tree_owner`'s regular dependencies placed in its own tree `tree_id`.

        Bun: src/install/lockfile/Tree.rs L2090–L2103 @ bun-v1.4.4
        """
        own = b.packages[tree_owner].dependencies
        found = []
        for dep_id in b.tree_rows[tree_id]:
            if _in_slice(own, dep_id) and not behavior_is_bundled(b.deps[dep_id].behavior) and is_valid(b.resolutions[dep_id]):
                found.append(b.resolutions[dep_id])
        return found

    owner = b.resolutions[b.tree_dep_id[hoist_root]]
    if resolves_elsewhere(owner):
        return True
    nested = nested_in(hoist_root, owner)
    for pkg_id in nested:
        if resolves_elsewhere(pkg_id):
            return True
    if not nested:
        return False

    # The nested packages' own trees contain more of them; a tree always comes after its parent.
    scope = [(hoist_root, owner)]
    for tree_id in range(hoist_root + 1, len(b.tree_parent)):
        parent_owner = None
        for scope_id, scope_owner in scope:
            if scope_id == b.tree_parent[tree_id]:
                parent_owner = scope_owner
                break
        if parent_owner == None:
            continue
        tree_dep = b.tree_dep_id[tree_id]
        if not _in_slice(b.packages[parent_owner].dependencies, tree_dep) or behavior_is_bundled(b.deps[tree_dep].behavior):
            continue
        tree_owner = b.resolutions[tree_dep]
        if any([resolves_elsewhere(pkg_id) for pkg_id in nested_in(tree_id, tree_owner)]):
            return True
        scope.append((tree_id, tree_owner))
    return False

def _hoist_level(b, this_id, as_defined, hoist_root_id, package_id, input_dep_id, input_dep_range):
    """One folder of `Tree::hoist_dependency`: a result, or `parent` to try the folder above.

    Bun: src/install/lockfile/Tree.rs L1782–L2016 @ bun-v1.4.4
    """
    deps = b.deps
    dependency = deps[input_dep_id]
    if not as_defined and b.probes and _is_hidden_by(b, this_id):
        return _result(_LOOP)
    placed_dep = b.placed.get((this_id, dependency.name))
    if placed_dep != None:
        dep = deps[placed_dep]
        res_id = b.resolutions[placed_dep]

        # The copy that a tarball ships stays in this folder, whether or not it's resolved.
        if not is_valid(res_id) and behavior_is_bundled(dep.behavior):
            return _result(_LOOP)
        if not is_valid(res_id) and not is_valid(package_id):
            # both peers will need to be resolved if they can resolve later
            return _result(_RESOLVE_LATER)
        if not is_valid(res_id):
            return _result(_RESOLVE_REPLACE, id = this_id, value = placed_dep)
        if not is_valid(package_id):
            return _result(_RESOLVE, value = res_id)
        if res_id == package_id:
            return _result(_HOISTED)

        def is_in_peer_range():
            """Whether the dependency's npm range holds the npm version of the placed package `res_id`.

            Bun: src/install/lockfile/Tree.rs L1870–L1881 @ bun-v1.4.4
            """
            version = catalogs_resolve_range(b.lockfile, dependency)
            resolution = b.packages[res_id].resolution
            return version.tag == VERSION_TAG.NPM and resolution.tag == RESOLUTION_TAG.NPM and query_satisfies(version.npm.version, resolution.value)

        def is_always_linked(row):
            """Whether every platform installs the dependency `row`: it is neither optional nor bundled.

            Bun: src/install/lockfile/Tree.rs L1882–L1884 @ bun-v1.4.4
            """
            return not behavior_is_optional(row.behavior) and not behavior_is_bundled(row.behavior)

        if _in_slice(input_dep_range, placed_dep):
            # A root dependency named like a workspace package takes `node_modules/<name>` from it,
            # unless an earlier dependency group resolves to the workspace package.
            if behavior_is_workspace(dep.behavior):
                earlier_resolves = False
                for earlier in range(input_dep_range.off, input_dep_id):
                    row = deps[earlier]
                    if (row.name == dependency.name and not behavior_is_workspace(row.behavior) and
                        not behavior_is_peer(row.behavior) and b.resolutions[earlier] == res_id):
                        earlier_resolves = True
                        break
                if not earlier_resolves:
                    return _result(_RESOLVE_REPLACE, id = this_id, value = placed_dep)

            # The package's own dependency of this name is always installed, so the peer
            # resolves to it.
            if (behavior_is_peer(dependency.behavior) and not behavior_is_optional_peer(dependency.behavior) and
                is_always_linked(dep) and is_in_peer_range()):
                return _result(_SERVED, value = res_id)
            return _result(_HOISTED)

        # now we either keep the dependency at this place in the tree, or hoist if peer version
        # allows it
        if behavior_is_peer(dependency.behavior):
            # An override chose this peer's package, so an alias of a different package can't
            # stand in for it.
            if (b.packages[res_id].name != b.packages[package_id].name and
                is_overridden_dependency(b.lockfile, input_dep_id)):
                return _result(_LOOP)

            # An optional peer's binding follows the dedupe, but only in the tree being saved.
            dedupe = _result(_REBIND, value = res_id) if behavior_is_optional_peer(dependency.behavior) else _result(_HOISTED)
            is_root_dependency = _in_slice(b.packages[0].dependencies, placed_dep)
            if is_in_peer_range():
                own_dependency_shares_it = False
                if not behavior_is_optional_peer(dependency.behavior):
                    for own in range(input_dep_range.off, input_dep_range.off + input_dep_range.len):
                        row = deps[own]
                        if (row.name == dependency.name and not behavior_is_peer(row.behavior) and
                            is_always_linked(row) and b.resolutions[own] == res_id):
                            own_dependency_shares_it = True
                            break
                if not behavior_is_optional_peer(dependency.behavior) and ((is_root_dependency and is_always_linked(dep)) or own_dependency_shares_it):
                    return _result(_SERVED, value = res_id)
                return dedupe

            # Root dependencies are manually chosen by the user. Allow them to hoist other peers
            # even if they don't satisfy the version
            if is_root_dependency:
                return dedupe
        return _result(_LOOP)

    # this dependency was not found in this tree, try hoisting or placing in the next parent
    if b.tree_parent[this_id] != INVALID_ID and this_id != hoist_root_id:
        return _result("parent")
    return _hoist_bottom(b, this_id, as_defined, hoist_root_id, package_id, dependency.name)

def _hoist_bottom(b, this_id, as_defined, hoist_root_id, package_id, name):
    """The end of `Tree::hoist_dependency`: the hoist root's checks, then a placement here.

    Bun: src/install/lockfile/Tree.rs L2018–L2050 @ bun-v1.4.4
    """
    if this_id == hoist_root_id:
        # A bundle's dependency stops here, but it must not shadow a package that other
        # dependencies resolve through this folder.
        if not as_defined and _hoist_root_resolves_elsewhere(b, this_id, package_id, name):
            return _result(_LOOP)

        # Copying the bundling package into its own bundle would recurse forever.
        owner_dep = b.tree_dep_id[this_id]
        if owner_dep >= 0 and owner_dep < len(b.deps) and b.resolutions[owner_dep] == package_id and b.deps[owner_dep].name == name:
            return _result(_HOISTED)
    return _result(_PLACEMENT, id = this_id, bundled = False)

def _hoist_dependency(b, self_id, hoist_root_id, package_id, input_dep_id, input_dep_range):
    """`Tree::hoist_dependency`: deduplicate, move up, or leave the package here.

    Bun: src/install/lockfile/Tree.rs L1778–L2051 @ bun-v1.4.4

    Bun calls itself for the parent folder (`AS_DEFINED = false`); this walks the parents.
    """
    first = _hoist_level(b, self_id, True, hoist_root_id, package_id, input_dep_id, input_dep_range)
    if first.kind != "parent":
        return first
    _probes_begin(b, input_dep_range, package_id, behavior_is_peer(b.deps[input_dep_id].behavior))
    level = b.tree_parent[self_id]
    result = None
    for _ in range(len(b.tree_parent) + 1):
        result = _hoist_level(b, level, False, hoist_root_id, package_id, input_dep_id, input_dep_range)
        if result.kind != "parent":
            break
        level = b.tree_parent[level]
    if result.kind != _LOOP:
        return result
    return _hoist_bottom(b, self_id, True, hoist_root_id, package_id, b.deps[input_dep_id].name)

def _process_subtree(b, self_id, dependency_id, hoist_root_id):
    """`Tree::process_subtree`: place a package's dependencies, hoisting each as high as it goes.

    Bun: src/install/lockfile/Tree.rs L1411–L1776 @ bun-v1.4.4
    """
    deps = b.deps
    packages = b.packages
    parent_pkg_id = 0 if dependency_id == ROOT_DEP_ID else b.resolutions[dependency_id]
    resolution_list = packages[parent_pkg_id].dependencies
    if resolution_list.len == 0:
        return None

    # This dependency links back to a workspace package from inside that package's own tree.
    if (dependency_id != ROOT_DEP_ID and not behavior_is_workspace(deps[dependency_id].behavior) and
        packages[parent_pkg_id].resolution.tag == RESOLUTION_TAG.WORKSPACE):
        tree_id = self_id
        for _ in range(len(b.tree_parent) + 1):
            if tree_id == INVALID_ID:
                break
            tree_dep = b.tree_dep_id[tree_id]
            if tree_dep >= 0 and tree_dep < len(b.resolutions) and b.resolutions[tree_dep] == parent_pkg_id:
                return None
            tree_id = b.tree_parent[tree_id]

    period = _repeating_period(b, self_id, dependency_id)
    if period != None:
        return "{}: cannot install dependency cycle into node_modules (a package needs a nested copy of the next, forever); pin one to a single version with \"overrides\" in package.json".format(b.lockfile.file)

    next_id = len(b.tree_parent)
    b.tree_parent.append(self_id)
    b.tree_dep_id.append(dependency_id)
    b.tree_rows.append([])
    first_walk = parent_pkg_id not in b.walked
    b.walked[parent_pkg_id] = True
    sort_buf = sorted(range(resolution_list.off, resolution_list.off + resolution_list.len), key = lambda d: dependency_sort_key(deps[d]))

    def hoist_dep(root_id, pkg_id, dep_id):
        """Hoists the dependency `dep_id`, resolved to `pkg_id`, from the hoist root `root_id`.

        Bun: src/install/lockfile/Tree.rs L1526–L1535 @ bun-v1.4.4
        """
        return _hoist_dependency(b, next_id, root_id, pkg_id, dep_id, resolution_list)

    def stays_on(res_id, dep_id):
        """Whether resolving `dep_id` to `res_id` needs no other pass of the walk.

        Bun: src/install/lockfile/Tree.rs L1536–L1553 @ bun-v1.4.4
        """

        # Nothing reads a resolution before the first walk of the package that lists it.
        return first_walk and not b.state["bundle_placed"] and hoist_dep(hoist_root_id, res_id, dep_id).kind == _HOISTED

    for dep_id in sort_buf:
        bound_by_version = _bind_peer(b, dep_id)
        pkg_id = b.resolutions[dep_id]
        dependency = deps[dep_id]
        hoisted = None
        if behavior_is_bundled(dependency.behavior):
            # don't hoist a bundled dependency
            b.state["bundle_placed"] = True
            hoisted = _result(_PLACEMENT, id = next_id, bundled = True)
        elif not is_valid(pkg_id):
            # skip unresolvable dependencies. An unbound peer binds to the nearest copy.
            if not behavior_is_peer(dependency.behavior):
                continue
            hoisted = hoist_dep(hoist_root_id, pkg_id, dep_id)
        elif packages[pkg_id].resolution.tag == RESOLUTION_TAG.FOLDER:
            # A peer an ancestor edge already provides dedupes instead of nesting a second copy.
            if behavior_is_peer(dependency.behavior):
                provided = hoist_dep(hoist_root_id, pkg_id, dep_id)
                if provided.kind in [_HOISTED, _SERVED]:
                    hoisted = provided
            if hoisted == None:
                # Folder packages never hoist, so a cycle between them would nest forever.
                cycle = False
                tree_id = next_id
                for _ in range(len(b.tree_parent) + 1):
                    if tree_id == INVALID_ID:
                        break
                    ancestor = b.tree_dep_id[tree_id]
                    if ancestor >= 0 and ancestor < len(deps) and b.resolutions[ancestor] == pkg_id and deps[ancestor].name == dependency.name:
                        cycle = True
                        break
                    tree_id = b.tree_parent[tree_id]
                if cycle:
                    continue

                # It's its own hoist root, so it stays in this tree and only dedupes against a
                # sibling with the same name.
                hoisted = hoist_dep(next_id, pkg_id, dep_id)
        else:
            hoisted = hoist_dep(hoist_root_id, pkg_id, dep_id)

        kind = hoisted.kind
        if kind in [_LOOP, _HOISTED]:
            continue
        elif kind == _SERVED:
            # A dependency has one resolution, however many times its package is placed.
            if first_walk and bound_by_version:
                b.served.append((dep_id, hoisted.value))
        elif kind == _RESOLVE:
            if first_walk or not behavior_is_optional_peer(dependency.behavior):
                b.resolutions[dep_id] = hoisted.value
                if not stays_on(hoisted.value, dep_id):
                    b.state["late_bound_peer"] = True
        elif kind == _RESOLVE_REPLACE:
            tree_id, replaced = hoisted.id, hoisted.value
            b.state["replaced_row"] = True

            # A replaced workspace package keeps its resolution and only loses its symlink.
            if not behavior_is_workspace(deps[replaced].behavior):
                b.state["late_bound_peer"] = True
                b.resolutions[replaced] = pkg_id
                _bind_pending_peers(b, dependency.name, pkg_id)
            rows = b.tree_rows[tree_id]
            for i in range(len(rows)):
                if rows[i] == replaced:
                    rows[i] = dep_id
            if b.placed.get((tree_id, dependency.name)) == replaced:
                b.placed[(tree_id, dependency.name)] = dep_id
            if packages[pkg_id].dependencies.len > 0:
                b.queue.append((tree_id, dep_id, hoist_root_id))
        elif kind == _REBIND:
            # The first placement decides an optional peer's resolution, the same in every pass.
            if first_walk:
                b.resolutions[dep_id] = hoisted.value
                if not stays_on(hoisted.value, dep_id):
                    b.state["late_bound_peer"] = True
        elif kind == _RESOLVE_LATER:
            # an unresolved peer that deduplicated with another one
            b.pending_peers.setdefault(dependency.name, {})[dep_id] = True
        elif kind == _PLACEMENT:
            tree_id, bundled = hoisted.id, hoisted.bundled

            # The package also lists this name as a regular dependency, and loads that copy
            # wherever it was placed. A copy for the peer would shadow it.
            if behavior_is_peer(dependency.behavior) and not bundled:
                own = None
                for candidate in range(resolution_list.off, resolution_list.off + resolution_list.len):
                    row = deps[candidate]
                    if row.name == dependency.name and not behavior_is_peer(row.behavior) and is_valid(b.resolutions[candidate]):
                        own = candidate
                        break
                if own != None:
                    own_pkg_id = b.resolutions[own]
                    own_behavior = deps[own].behavior
                    if (first_walk and bound_by_version and not behavior_is_optional(own_behavior) and
                        not behavior_is_bundled(own_behavior) and
                        resolution_satisfies_dependency_version(packages[own_pkg_id].resolution, catalogs_resolve_range(b.lockfile, dependency))):
                        b.served.append((dep_id, own_pkg_id))
                    continue

            # Only a placed row becomes a folder name.
            if is_valid(pkg_id) and dependency.name and not _alias_is_safe_install_target(dependency.name):
                b.state["error"] = "{}: invalid dependency name \"{}\" (Bun refuses to install it)".format(b.lockfile.file, dependency.name)
                continue
            b.tree_rows[tree_id].append(dep_id)
            b.placed.setdefault((tree_id, dependency.name), dep_id)
            if is_valid(pkg_id) and packages[pkg_id].dependencies.len > 0:
                # if it's bundled, start a new hoist root
                b.queue.append((tree_id, dep_id, tree_id if bundled else hoist_root_id))

    if not b.tree_rows[next_id]:
        b.tree_parent.pop()
        b.tree_dep_id.pop()
        b.tree_rows.pop()
    return None

def hoist(lockfile):
    """`Lockfile::hoist::<Resolvable>`: the trees `bun.lock` prints, and late-bound peers.

    Bun: src/install/lockfile.rs L1645–L1725 @ bun-v1.4.4
    Bun: src/install/lockfile/Tree.rs L1250–L1303 @ bun-v1.4.4

    Args:
        lockfile: A loaded lockfile; its resolutions, trees and hoisted dependencies change.

    Returns:
        `struct(late_bound_peer, error)`.
    """
    b = _builder(lockfile)
    error = _process_subtree(b, INVALID_ID, ROOT_DEP_ID, INVALID_ID)
    if error:
        return struct(late_bound_peer = False, error = error)

    # This goes breadth-first
    for i in range(_LIMIT):
        if i >= len(b.queue):
            break
        tree_id, dep_id, hoist_root_id = b.queue[i]
        error = _process_subtree(b, tree_id, dep_id, hoist_root_id)
        if error:
            return struct(late_bound_peer = False, error = error)
    if b.state["error"]:
        return struct(late_bound_peer = False, error = b.state["error"])

    bind_served_peers(b.served, b.tree_rows, b.deps, b.resolutions)

    # `Builder::clean`: the rows of every tree in one list; peers that never resolved are dropped.
    trees = []
    hoisted = []
    for tree_id in range(len(b.tree_parent)):
        off = len(hoisted)
        for dep_id in b.tree_rows[tree_id]:
            if is_valid(b.resolutions[dep_id]):
                hoisted.append(dep_id)
        trees.append(struct(id = tree_id, dependency_id = b.tree_dep_id[tree_id], parent = b.tree_parent[tree_id], dependencies = struct(off = off, len = len(hoisted) - off)))
    lockfile.trees.clear()
    lockfile.trees.extend(trees)
    lockfile.hoisted_dependencies.clear()
    lockfile.hoisted_dependencies.extend(hoisted)
    return struct(late_bound_peer = b.state["late_bound_peer"], error = None)

def is_filtered_dependency_or_workspace(lockfile, dep_id, parent_pkg_id, platform):
    """`is_filtered_dependency_or_workspace` of a default `bun install` (S7).

    Bun: src/install/lockfile/Tree.rs L1313–L1405 @ bun-v1.4.4

    With every dev and optional dependency enabled, no `--filter` and no pruned workspace (a frozen
    install keeps every workspace, PRUNED L11-L16), the optional-peer omission, the pruned-workspace
    link and the workspace filter never skip a dependency (research Part 2, "Not carried over").

    Args:
        lockfile: A resolved lockfile.
        dep_id: A dependency ID.
        parent_pkg_id: The package that declares it.
        platform: `struct(cpu, os, libc)` bit sets of the target.

    Returns:
        Whether the dependency is not linked.
    """
    pkg_id = lockfile.resolutions[dep_id]
    dep = lockfile.dependencies[dep_id]
    if not is_valid(pkg_id):
        return not behavior_is_optional_peer(dep.behavior)
    packages = lockfile.packages
    if meta_is_disabled(packages[pkg_id].meta, platform.cpu, platform.os, libc_for_dependency(platform.libc, dep.behavior)):
        return True
    if not behavior_is_placed(dep.behavior, dependency_features(packages[parent_pkg_id].resolution.tag)):
        return True
    return False
