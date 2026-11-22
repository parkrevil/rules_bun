"""Unit tests for `//bun/private:bun_isolated_store.bzl` (research Part 2 S8).

The store is built the way the isolated linker builds it after loading and cleaning `bun.lock`; the
expectations are the pinned Bun's own store entries (research E2, T017's conformance rows).
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("@npm_fixture_results//:results.bzl", "RESULTS")
load("//bun/private:bun_install_types.bzl", "platform_value")
load("//bun/private:bun_isolated_store.bzl", "build_store", "store_inputs")
load("//bun/private:bun_lockfile.bzl", "load_lockfile", "lockfile_clean", "lockfile_resolve")
load("//bun/private:bun_tree.bzl", "hoist")
load("//bun/private:lockfile.bzl", "read_lockfile")
load("//bun/private:platforms.bzl", "platform_bits", "platform_classes")

_LINUX = struct(cpu = platform_value("cpu", "x64"), os = platform_value("os", "linux"), libc = platform_value("libc", "glibc"))

def _store(env, project):
    file = "bun/tests/npm/fixtures/{}/bun.lock".format(project)
    read = read_lockfile(RESULTS[project]["text"], file)
    loaded = load_lockfile(read.value, file)
    asserts.equals(env, None, loaded.error)
    asserts.equals(env, None, lockfile_resolve(loaded.value, hoist))
    cleaned = lockfile_clean(loaded.value, hoist)
    asserts.equals(env, None, cleaned.error)
    store = build_store(cleaned.value, _LINUX)
    asserts.equals(env, None, store.error)
    return cleaned.value, store.value

def _label(lockfile, store, entry_id):
    package = lockfile.packages[store.entries[entry_id].pkg_id]
    if package.resolution.tag == 2:
        v = package.resolution.value
        return "{}@{}.{}.{}".format(package.name, v.major, v.minor, v.patch)
    return package.name

def _entries_of(lockfile, store, name):
    """`[{dependency name: target label}]` of the entries of a package name."""
    found = []
    for entry_id in range(len(store.entries)):
        if lockfile.packages[store.entries[entry_id].pkg_id].name == name and entry_id != 0:
            found.append({dep: _label(lockfile, store, target[0]) for dep, target in store.entries[entry_id].dependencies.items()})
    return found

def _peer_contexts_test_impl(ctx):
    env = unittest.begin(ctx)

    # One entry per package and peer set (ISO L1276-L1351): `p` is reached under the root's
    # `q@1.0.0` and under `q2-user`'s `q@2.0.0`, so it is two entries.
    lockfile, store = _store(env, "conformance_peer_contexts")
    p = _entries_of(lockfile, store, "p")
    asserts.equals(env, 2, len(p))
    asserts.equals(env, ["q@1.0.0", "q@2.0.0"], sorted([links["q"] for links in p]))

    # BC-9 (T017): the entry with `q@1.0.0` links its optional peer `r` to `r@1.0.0`.
    asserts.equals(env, ["r@1.0.0"], [links.get("r") for links in p if links["q"] == "q@1.0.0"])

    # `leaking_peers` (ISO L573-L672): `p` leaks both its peers; `q2-user` provides `q` itself.
    names = lambda pkg_name: sorted(store.leaking_peers[[i for i in range(len(lockfile.packages)) if lockfile.packages[i].name == pkg_name][0]])
    asserts.equals(env, ["q", "r"], names("p"))
    asserts.equals(env, ["r"], names("q2-user"))
    return unittest.end(env)

def _unprovided_peer_test_impl(ctx):
    env = unittest.begin(ctx)

    # A peer nothing provides and the lockfile does not resolve is not linked (ISO L1183-L1186,
    # BC-5), and the package is one entry however many dependents reach it (T017).
    lockfile, store = _store(env, "conformance_unprovided_peer")
    entries = _entries_of(lockfile, store, "peer-unprovided")
    asserts.equals(env, 1, len(entries))
    asserts.equals(env, None, entries[0].get("state"))
    return unittest.end(env)

def _row_evidence_test_impl(ctx):
    env = unittest.begin(ctx)

    # Research E2: one store entry `x@1.0.0`, linking `b` to `b@1.0.0`.
    lockfile, store = _store(env, "dependency_conflict")
    x = _entries_of(lockfile, store, "x")
    asserts.equals(env, 2, len(x), "x@1.0.0 and x@2.0.0, one entry each")
    asserts.equals(env, [{"b": "b@1.0.0"}], [links for links in x if links])
    root = {dep: _label(lockfile, store, target[0]) for dep, target in store.entries[0].dependencies.items()}
    asserts.equals(env, {"a": "a@1.0.0", "b": "b@1.0.0", "x": "x@2.0.0", "y": "y@1.0.0", "z": "z@1.0.0"}, root)
    return unittest.end(env)

def _cycle_test_impl(ctx):
    env = unittest.begin(ctx)

    # A cycle reuses the ancestor's node (ISO L730-L776): `cyc-a` and `cyc-b` link each other.
    lockfile, store = _store(env, "basic")
    asserts.equals(env, [{"cyc-b": "cyc-b@1.0.0"}], _entries_of(lockfile, store, "cyc-a"))
    asserts.equals(env, [{"cyc-a": "cyc-a@1.0.0"}], _entries_of(lockfile, store, "cyc-b"))
    return unittest.end(env)

def _shared_inputs_test_impl(ctx):
    env = unittest.begin(ctx)

    # `store_inputs` computes once, for every platform class, what each class's `build_store`
    # would compute again (research R13, T183): with the inputs of all the classes, each class's
    # store is the one it builds from its own platform alone. Every fixture lockfile that loads
    # (62 of `bun/tests/npm/fixtures/`, 12 of them with more than one class).
    projects = 0
    platform_projects = 0
    for project in sorted(RESULTS.keys()):
        file = "bun/tests/npm/fixtures/{}/bun.lock".format(project)
        read = read_lockfile(RESULTS[project]["text"], file)
        if read.error:
            continue
        loaded = load_lockfile(read.value, file)
        if loaded.error or lockfile_resolve(loaded.value, hoist):
            continue
        cleaned = lockfile_clean(loaded.value, hoist)
        if cleaned.error:
            continue
        lockfile = cleaned.value
        targets = [platform_bits(platforms[0]) for platforms in platform_classes(lockfile)]
        inputs = store_inputs(lockfile, targets)
        for target in targets:
            asserts.equals(env, build_store(lockfile, target), build_store(lockfile, target, inputs), "{} on {}".format(project, target))
        projects += 1
        if len(targets) > 1:
            platform_projects += 1
    asserts.true(env, projects >= 60 and platform_projects >= 10, "compared {} projects, {} with more than one platform class".format(projects, platform_projects))
    return unittest.end(env)

peer_contexts_test = unittest.make(_peer_contexts_test_impl)
unprovided_peer_test = unittest.make(_unprovided_peer_test_impl)
row_evidence_test = unittest.make(_row_evidence_test_impl)
cycle_test = unittest.make(_cycle_test_impl)
shared_inputs_test = unittest.make(_shared_inputs_test_impl)

def bun_isolated_store_test_suite(name):
    unittest.suite(
        name,
        peer_contexts_test,
        unprovided_peer_test,
        row_evidence_test,
        cycle_test,
        shared_inputs_test,
    )
