"""The ruleset side of the conformance graph (contracts/conformance-graph.md, "Ruleset side").

It reads only `resolve.bzl`'s output, `struct(instances, links, members)`, so it serves any resolver
that produces it. For each platform tuple (research R3) the graph holds what the hub links there:
a link's root (or, for a link whose root differs by platform, the root whose conditions hold) and
its closure on every platform, an optional instance where its conditions hold, as
`npm_repositories.bzl` selects them, and an instance's edge where its target is carried in a link
that carries the instance, as `run.bzl` links them; and an instance's `status` when it is not
`ok`, since the hub fails analysis of that instance, marked `unfetched` when that is because
rules_bun does not fetch it (ID-4); and, per holder, each store directory its links reach as
several instances, since one target cannot hold them (`conflicts`).
"""

load("//bun/private:npm_repositories.bzl", "conditions_hold")
load("//bun/private:platforms.bzl", "NPM_CPU", "NPM_OS")

def platform_tuples():
    """The platform tuples of research R3: `(os, cpu, libc)` in npm values.

    Every `NPM_OS` x `NPM_CPU`; on Linux each libc and `unconstrained` (a platform without the libc
    constraint), elsewhere `libc` `None`; and `(None, None, None)` for a platform that maps to no
    npm value.

    Returns:
        List of tuples.
    """
    tuples = []
    for os in sorted(NPM_OS.keys()):
        for cpu in sorted(NPM_CPU.keys()):
            for libc in (["glibc", "musl", "unconstrained"] if os == "linux" else [None]):
                tuples.append((os, cpu, libc))
    tuples.append((None, None, None))
    return tuples

def _available(link, os, cpu, libc):
    """The instance IDs a link carries on a platform."""
    carried = {i: True for i in link.closure}
    for i, conditions in link.optional.items():
        if conditions_hold(conditions, os, cpu, libc):
            carried[i] = True
    return carried

def _store_path(instance):
    """An instance's store directory, as `run.bzl` names it: `<name>@<version>[+<peer hash>]`."""
    peer_hash = getattr(instance, "peer_hash", "")
    return "{}@{}".format(instance.name, instance.version) + ("+" + peer_hash if peer_hash else "")

def _root(link, os, cpu, libc):
    """The instance a link's alias links on a platform: its root, or the per-platform root (BC-12)."""
    roots = getattr(link, "roots", {})
    if not roots:
        return link.root
    for instance_id, conditions in roots.items():
        if conditions_hold(conditions, os, cpu, libc):
            return instance_id
    return None

def _graph(value, os, cpu, libc):
    instances = value.instances
    npm_libc = None if libc == "unconstrained" else libc
    holders = {}
    carried_sets = []
    for path in sorted(value.links.keys()):
        holder = {}
        for alias, link in sorted(value.links[path].items()):
            carried = _available(link, os, cpu, npm_libc)
            root = _root(link, os, cpu, npm_libc)
            if root not in carried:
                continue
            holder[alias] = root
            carried_sets.append(carried)
        for alias, member in sorted(getattr(value, "members", {}).get(path, {}).items()):
            holder[alias] = "w:" + member
        holders[path] = holder
    reached = sorted({i: True for carried in carried_sets for i in carried}.keys())

    # One target holds one instance of each store directory (run.bzl `_check_unique`): a holder
    # whose links reach several instances with one directory cannot be used by one target.
    conflicts = {}
    for path in sorted(value.links.keys()):
        by_directory = {}
        for alias, link in value.links[path].items():
            carried = _available(link, os, cpu, npm_libc)
            if _root(link, os, cpu, npm_libc) not in carried:
                continue
            for i in carried:
                by_directory.setdefault(_store_path(instances[i]), {})[i] = True
        found = {d: len(ids) for d, ids in sorted(by_directory.items()) if len(ids) > 1}
        if found:
            conflicts[path] = found
    index = {instance_id: n for n, instance_id in enumerate(reached)}

    def target(instance_id):
        return instance_id if instance_id.startswith("w:") else "e:{}".format(index[instance_id])

    entries = []
    for instance_id in reached:
        instance = instances[instance_id]
        links = {}
        for alias, edge in sorted(instance.edges.items()):
            if alias == instance.name:
                continue
            if any([instance_id in carried and edge in carried for carried in carried_sets]):
                links[alias] = target(edge)
        for alias, member in sorted(getattr(instance, "members", {}).items()):
            links[alias] = "w:" + member
        entry = {"name": instance.name, "version": instance.version, "links": links}
        if instance.status != "ok":
            # The hub fails analysis of this instance, so the consumer's build cannot use it.
            entry["status"] = instance.status
            if getattr(instance, "unfetched", False):
                # Because rules_bun does not fetch it: the status ID-4 excludes.
                entry["unfetched"] = True
        entries.append(entry)
    graph = {
        "holders": {path: {alias: target(t) for alias, t in holder.items()} for path, holder in holders.items()},
        "entries": entries,
    }
    if conflicts:
        graph["conflicts"] = conflicts
    return graph

def conformance_graphs(resolution, tuples):
    """The ruleset's linked graph per platform class.

    Args:
        resolution: `resolve.bzl`'s result, `struct(value, error)`.
        tuples: The platform tuples `(os, cpu, libc)` to resolve for (`platform_tuples()`).

    Returns:
        `{"error": <message>}` when resolution failed; otherwise a list of `{"platforms": [[os,
        cpu, libc], ...], "graph": <Graph JSON>}`, the tuples with equal graphs in one class.
    """
    if resolution.error != None:
        return {"error": resolution.error}
    if not any([link.optional or getattr(link, "roots", {}) for links in resolution.value.links.values() for link in links.values()]):
        # Nothing is platform-restricted: one class, computed once.
        return [{"platforms": [list(t) for t in tuples], "graph": _graph(resolution.value, None, None, None)}]
    classes = {}
    order = []
    for os, cpu, libc in tuples:
        graph = _graph(resolution.value, os, cpu, libc)
        encoded = json.encode(graph)
        if encoded not in classes:
            classes[encoded] = {"platforms": [], "graph": graph}
            order.append(encoded)
        classes[encoded]["platforms"].append([os, cpu, libc])
    return [classes[encoded] for encoded in order]
