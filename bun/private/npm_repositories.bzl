"""Repository rules of the `npm` extension (research R3, R4, R7).

A package repository holds one `name@version`: the extracted archive under `package/` and the
instance-tree target `:tree`. The hub repository holds one instance target per package instance and
`defs.bzl`, whose `npm_link_all_packages()` creates the `:node_modules/<package>` targets of the
workspace package it is called in.
"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "use_netrc")
load(":library.bzl", "SOURCE_EXTENSIONS")
load(":platforms.bzl", "NPM_CPU", "NPM_LIBC", "NPM_OS")

_NPM_PACKAGE_BZL = str(Label("//bun/private:npm_package.bzl"))

_RUN_BZL = str(Label("//bun/private:run.bzl"))

# Bazel's target-name characters (concepts/labels, 9.2.0), without `/`, which separates path
# segments.
_NAME_CHARACTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!%-@^_\"#$&'()*+,;<=>?[]{|}~."

# Bounds the directory walk; Starlark has no unbounded loop.
_MAX_DIRECTORIES = 1000000

def _addressable(name):
    for c in name.elems():
        if c not in _NAME_CHARACTERS:
            return False
    return True

def _glob_escape(path):
    """Escapes the glob characters of `replace_prefixes` keys (bmatcuk/doublestar)."""
    return "".join(["\\" + c if c in "*?[]{}" else c for c in path.elems()])

def _segment_matches(pattern, name):
    """Whether one path segment matches one segment of a `glob` pattern, which may hold `*`.

    As `glob` documents, `*` matches any substring of the segment, and a name starting with `.`
    is matched only by `*` alone or by a pattern starting with `.`.
    """
    if name.startswith(".") and pattern != "*" and not pattern.startswith("."):
        return False

    # matched[j]: the pattern so far matches the first j characters of `name`.
    matched = [True] + [False] * len(name)
    for c in pattern.elems():
        if c == "*":
            for j in range(1, len(name) + 1):
                matched[j] = matched[j] or matched[j - 1]
        else:
            matched = [False] + [matched[j] and name[j] == c for j in range(len(name))]
    return matched[len(name)]

def glob_matches(pattern, path):
    """Whether a path matches a `glob` pattern, with `*` and `**` as `glob` documents them.

    Args:
        pattern: The pattern; `**` stands alone as a segment and matches zero or more segments.
        path: A `/`-separated relative path.

    Returns:
        Whether `pattern` matches `path`.
    """
    names = path.split("/")

    # matched[j]: the pattern segments so far match the first j segments of `path`.
    matched = [True] + [False] * len(names)
    for segment in pattern.split("/"):
        if segment == "**":
            for j in range(1, len(names) + 1):
                matched[j] = matched[j] or matched[j - 1]
        else:
            matched = [False] + [matched[j] and _segment_matches(segment, names[j]) for j in range(len(names))]
    return matched[len(names)]

def _make_addressable(repository_ctx, package, exclude):
    """Renames the entries of `package/` that a `glob` would lose (research R4, FR-035).

    A file named `BUILD` or `BUILD.bazel`, in any case, would make its directory a subpackage (on a
    case-insensitive file system `build` is `BUILD`), and a name with a
    character outside Bazel's target-name set is no valid label; each gets the safe name
    `_rules_bun_<n>_`. A file whose path changes is deleted instead when its archive path matches
    an `exclude` pattern, since the `glob` exclude only sees the safe names (FR-033).

    Args:
        repository_ctx: The repository context.
        package: `name@version`, for errors.
        exclude: The `glob` exclude patterns, relative to the package root.

    Returns:
        Safe path -> original path, both relative to `package/`.
    """
    renames = {}
    count = 0
    stack = [(repository_ctx.path("package"), "", "")]
    for _ in range(_MAX_DIRECTORIES):
        if not stack:
            break
        directory, safe_dir, original_dir = stack.pop()
        for entry in sorted(directory.readdir(), key = lambda e: e.basename):
            name = entry.basename
            safe = name

            # Any case: on a case-insensitive file system `build` is a `BUILD` file (research R7).
            renamed = (not entry.is_dir and name.lower() in ("build", "build.bazel")) or not _addressable(name)
            if not entry.is_dir and (renamed or safe_dir != original_dir) and [p for p in exclude if glob_matches(p, original_dir + name)]:
                repository_ctx.delete(entry)
                continue
            if renamed:
                count += 1
                safe = "_rules_bun_{}_".format(count)
                destination = directory.get_child(safe)
                if destination.exists:
                    fail("rules_bun: cannot rename {} in the package {} to {}: the archive already holds {}".format(
                        original_dir + name,
                        package,
                        safe_dir + safe,
                        safe_dir + safe,
                    ))
                repository_ctx.rename(entry, destination)
                renames[safe_dir + safe] = original_dir + name
                entry = destination
            if entry.is_dir:
                stack.append((entry, safe_dir + safe + "/", original_dir + name + "/"))
    if stack:
        fail("rules_bun: the package {} has more than {} directories".format(package, _MAX_DIRECTORIES))
    return renames

# The commands a `#!` line may name for a bin rules_bun runs with Bun (research R4): npm's bin
# convention is `#!/usr/bin/env node` (docs.npmjs.com, package.json `bin`).
_BIN_COMMANDS = ["node", "bun"]

_NO_PROGRAM = "it has none of the extensions {} and its first line is no #! line naming node or bun".format(", ".join(SOURCE_EXTENSIONS))

def _names_node_or_bun(text):
    """Whether the first line of `text` is a `#!` line whose command is `node` or `bun`.

    The command is the basename of the first word, or for `env` the first following word that
    neither starts with `-` nor holds `=` (`#!/usr/bin/env -S node --flag`).
    """
    line = text.partition("\n")[0].rstrip("\r")
    if not line.startswith("#!"):
        return False
    words = [w for w in line[2:].replace("\t", " ").split(" ") if w]
    command = words[0].rpartition("/")[2] if words else None
    if command == "env":
        command = None
        for word in words[1:]:
            if not word.startswith("-") and "=" not in word:
                command = word.rpartition("/")[2]
                break
    return command in _BIN_COMMANDS

def _bin_reasons(repository_ctx, bins, renames, exclude):
    """Decides from the files whether each bin is a JavaScript program for Node or Bun (FR-012).

    Only a bin without a source extension is read, through its safe name when it was renamed.

    Args:
        repository_ctx: The repository context, after extraction and `_make_addressable`.
        bins: The entry's `bin` paths.
        renames: Safe path -> original path, as `_make_addressable` returns it.
        exclude: The `glob` exclude patterns, relative to the package root.

    Returns:
        Bin path -> `""` when runnable, else the reason it is not.
    """
    safe_names = {original: safe for safe, original in renames.items()}
    reasons = {}
    for path in bins:
        original = "/".join([p for p in path.split("/") if p not in ("", ".")])
        safe = ""
        prefix = ""
        for segment in original.split("/"):
            prefix = prefix + "/" + segment if prefix else segment
            safe = safe_names.get(prefix, safe + "/" + segment if safe else segment)
        file = repository_ctx.path("package/" + safe)
        if not original or not file.exists or [p for p in exclude if glob_matches(p, original)]:
            reasons[path] = "the package holds no such file"
        elif file.is_dir:
            reasons[path] = "it is a directory"
        elif [e for e in SOURCE_EXTENSIONS if original.endswith(e)]:
            reasons[path] = ""
        else:
            reasons[path] = "" if _names_node_or_bun(repository_ctx.read(file)) else _NO_PROGRAM
    return reasons

def _npm_package_repository_impl(repository_ctx):
    attr = repository_ctx.attr
    if attr.replacement:
        repository_ctx.extract(attr.replacement, output = "package", type = "tgz", strip_components = 1)
    else:
        # Credentials come from the user's .netrc (research R3), computed at fetch time and kept
        # nowhere; `--credential_helper` needs nothing from the rule.
        repository_ctx.download_and_extract(
            attr.url,
            output = "package",
            integrity = attr.integrity,
            canonical_id = attr.url,
            auth = use_netrc(read_user_netrc(repository_ctx), [attr.url], {}),
            type = "tgz",
            strip_components = 1,
        )
    package = "{}@{}".format(attr.package, attr.version)
    renames = _make_addressable(repository_ctx, package, attr.exclude)
    bins = _bin_reasons(repository_ctx, attr.bins, renames, attr.exclude)
    build = """\
load("{bzl}", "npm_package_tree")

npm_package_tree(
    name = "tree",
    srcs = glob(["package/**"], exclude = {exclude}, allow_empty = True),
    bins = {bins},
    check = {check},
    replace_prefixes = {replace_prefixes},
    visibility = ["//visibility:public"],
)
""".format(
        bzl = _NPM_PACKAGE_BZL,
        bins = repr(bins),
        check = repr("//check") if attr.replacement else None,
        exclude = repr(["package/" + p for p in attr.exclude]),
        replace_prefixes = repr({_glob_escape(k): v for k, v in renames.items()}),
    )
    if attr.replacement:
        repository_ctx.file("check/BUILD.bazel", """\
load("{bzl}", "npm_replacement_check")

npm_replacement_check(
    name = "check",
    archive = {archive},
    integrity = {integrity},
    label = {label},
    package = {package},
    visibility = ["//visibility:public"],
)
""".format(
            bzl = _NPM_PACKAGE_BZL,
            archive = repr(str(attr.replacement)),
            integrity = repr(attr.integrity),
            label = repr(attr.replacement_label),
            package = repr(package),
        ))
    repository_ctx.file("BUILD.bazel", build)

npm_package_repository = repository_rule(
    implementation = _npm_package_repository_impl,
    doc = "One npm package version: its archive, extracted, and the instance-tree target `:tree`.",
    attrs = {
        "url": attr.string(doc = "The tarball URL.", mandatory = True),
        "bins": attr.string_list(doc = "The `bin` paths of the package's entry, as `npm_bin.path` names them."),
        "integrity": attr.string(doc = "The Subresource Integrity the lockfile records.", mandatory = True),
        "package": attr.string(doc = "The package name.", mandatory = True),
        "version": attr.string(doc = "The package version.", mandatory = True),
        "exclude": attr.string_list(doc = "`glob` exclude patterns relative to the package root."),
        "replacement": attr.label(doc = "A package archive extracted instead of the download.", allow_single_file = True),
        "replacement_label": attr.string(doc = "The replacement's label as its tag writes it, for errors."),
    },
)

def conditions_hold(conditions, os, cpu, libc):
    """Whether a target's npm values are one of the platform tuples an instance is reached on.

    The resolver computes Bun's store for each class of the platforms the hub's `select()` tells
    apart (`platforms.bzl` `platform_tuples`, feature 006 research R3), so a condition is one such
    tuple, matched exactly.

    Args:
        conditions: List of `[os, cpu, libc]` platform tuples (`None` for a value the platform
            does not set).
        os: The target's npm `os`, or `None`.
        cpu: The target's npm `cpu`, or `None`.
        libc: The target's npm `libc`, or `None`.

    Returns:
        Whether the target is one of them.
    """
    return [os, cpu, libc] in conditions

def _settings():
    """Config setting name -> (npm os, npm cpu, npm libc, constraint labels).

    One per OS and per OS and CPU, and for Linux also each of those with a libc.
    """
    settings = {}
    for os, os_constraint in NPM_OS.items():
        os_label = "@platforms//os:" + os_constraint
        libcs = [(None, None)] + (sorted(NPM_LIBC.items()) if os == "linux" else [])
        for libc, libc_label in libcs:
            libc_suffix = "__libc_" + libc if libc else ""
            libc_labels = [libc_label] if libc else []
            settings["_os_" + os_constraint + libc_suffix] = (os, None, libc, [os_label] + libc_labels)
            for cpu, cpu_constraint in NPM_CPU.items():
                settings["_os_{}__cpu_{}{}".format(os_constraint, cpu_constraint, libc_suffix)] = (
                    os,
                    cpu,
                    libc,
                    [os_label, "@platforms//cpu:" + cpu_constraint] + libc_labels,
                )
    return settings

def _selections(optional):
    """Setting name (or `//conditions:default`) -> the optional instance IDs carried there."""
    selections = {}
    for name, (os, cpu, libc, _) in _settings().items():
        selections[name] = sorted([i for i, conditions in optional.items() if conditions_hold(conditions, os, cpu, libc)])
    selections["//conditions:default"] = sorted([i for i, conditions in optional.items() if conditions_hold(conditions, None, None, None)])
    return selections

def _root_selections(roots):
    """Setting name (or `//conditions:default`) -> the root instance ID there, or `""` for none.

    A link whose root the store binds to different entries on different platform classes
    (feature 006 BC-12) gets the root whose platform tuples hold.
    """
    selections = {}
    tuples = [(name, os, cpu, libc) for name, (os, cpu, libc, _) in _settings().items()]
    for name, os, cpu, libc in tuples + [("//conditions:default", None, None, None)]:
        ids = [i for i, conditions in sorted(roots.items()) if conditions_hold(conditions, os, cpu, libc)]
        selections[name] = ids[0] if ids else ""
    return selections

def _edge_fields(instance):
    """An instance's `edges`, `dependency_keys` and `peers` as `BUILD` text, by platform if needed.

    An edge the store has on some of the instance's platform classes only (`edge_conditions`,
    feature 006 T101), and each entry the store binds a dependency to on some classes
    (`edge_targets`, BC-16), is in the `select()` branches whose platform tuple it holds on, as the
    optional instances of a link are.
    """
    edges = instance["edges"]
    dependency_keys = instance["dependency_keys"]
    peers = instance["peers"]
    conditions = instance.get("edge_conditions", {})
    targets = instance.get("edge_targets", {})
    if not conditions and not targets:
        return repr(edges), repr(dependency_keys), repr(peers)
    branches = {}
    tuples = [(name, os, cpu, libc) for name, (os, cpu, libc, _) in sorted(_settings().items())]
    for name, os, cpu, libc in tuples + [("//conditions:default", None, None, None)]:
        selected = {a: t for a, t in edges.items() if a not in conditions or conditions_hold(conditions[a], os, cpu, libc)}
        for alias, by_target in targets.items():
            for target, target_conditions in by_target.items():
                if conditions_hold(target_conditions, os, cpu, libc):
                    selected[alias] = target
        branches[name if name.startswith("//conditions:") else ":" + name] = selected

    def field(value):
        if value == None:
            selected = {k: dict(chosen) for k, chosen in branches.items()}
        elif type(value) == "list":
            selected = {k: [a for a in value if a in chosen] for k, chosen in branches.items()}
        else:
            selected = {k: {a: v for a, v in value.items() if a in chosen} for k, chosen in branches.items()}
        if len({repr(v): True for v in selected.values()}) == 1:
            return repr(selected.values()[0])
        return "select({})".format(repr(selected))

    return field(None), field(dependency_keys), field(peers)

def _linked_members(link, instances):
    """The workspace members the instances of a package link reach link by path, on any platform."""
    reached = link["closure"] + list((link["optional"] or {}).keys())
    return [m for i in reached for m in instances[i].get("members", {}).values()]

def _member_edges(links, instances):
    """Workspace package -> the members its package links link by path, and the packages they reach.

    Args:
        links: Bazel package -> alias -> link, of every workspace package of the lockfile.
        instances: Instance ID -> instance, as the hub's `instances` attribute holds them.

    Returns:
        Bazel package -> `(members, packages)`: the canonical labels of the members the package's
        links reach by path, and the Bazel packages of those members and of its `workspace:` links.
    """
    edges = {}
    for package, aliases in links.items():
        members = {}
        packages = {}
        for link in aliases.values():
            if "workspace" in link:
                packages[Label(link["workspace"]).package] = True
                continue
            for member in _linked_members(link, instances):
                members[member] = True
                packages[Label(member).package] = True
        edges[package] = (members, packages)
    return edges

def _bin_members(link, edges, instances):
    """The workspace member targets a bin of `link` needs (feature 006 BC-4, T123).

    The members the link's instances link by path, and, to a fixed point, those that the package
    links of these members' own workspace packages (and of the members those reach through
    `workspace:` links) link by path: a member's target carries the packages of its `deps`, whose
    member links the bin must declare too, and the hub knows them only from `package.json`.

    Args:
        link: The package link, as `links` holds it.
        edges: `_member_edges` of the lockfile's links.
        instances: Instance ID -> instance, as the hub's `instances` attribute holds them.

    Returns:
        The sorted canonical labels of the member targets.
    """
    members = {m: True for m in _linked_members(link, instances)}
    visited = {}
    frontier = [Label(m).package for m in members]

    # Each round visits at least one workspace package not visited before, or ends the walk.
    for _ in range(len(edges) + 1):
        following = []
        for package in frontier:
            if package in visited:
                continue
            visited[package] = True
            reached, packages = edges.get(package, ({}, {}))
            members.update(reached)
            following.extend(packages.keys())
        frontier = following
    return sorted(members.keys())

def _npm_hub_repository_impl(repository_ctx):
    instances = json.decode(repository_ctx.attr.instances)
    build = ['load("{}", "npm_instance", "npm_unsupported")\n'.format(_NPM_PACKAGE_BZL)]
    for instance_id in sorted(instances.keys()):
        instance = instances[instance_id]
        if instance["status"] != "ok":
            build.append("""
npm_unsupported(
    name = {name},
    package = {package},
    reason = {reason},
    visibility = ["//visibility:public"],
)
""".format(name = repr(instance_id), package = repr(instance["package"]), reason = repr(instance["status"])))
            continue
        edges, dependency_keys, peers = _edge_fields(instance)
        build.append("""
npm_instance(
    name = {name},
    check = {check},
    dependency_keys = {dependency_keys},
    edges = {edges},
    exclude = {exclude},
    hub = {hub},
    integrity = {integrity},
    lockfile = {lockfile},
    members = {members},
    package = {package},
    peer_hash = {peer_hash},
    peers = {peers},
    source = {source},
    store_name = {store_name},
    tree = {tree},
    visibility = ["//visibility:public"],
)
""".format(
            name = repr(instance_id),
            check = repr("@{}//check".format(instance["repo"])) if instance["replaced"] else None,
            dependency_keys = dependency_keys,
            edges = edges,
            exclude = repr(instance["exclude"]),
            hub = repr(repository_ctx.original_name),
            integrity = repr(instance["integrity"]),
            lockfile = repr(repository_ctx.attr.lockfile),
            members = repr(instance.get("members", {})),
            package = repr(instance["package"]),
            peer_hash = repr(instance["peer_hash"]),
            peers = peers,
            source = repr(instance["source"]),
            store_name = repr(instance["store_name"]),
            tree = repr("@{}//:tree".format(instance["repo"])),
        ))
    links = json.decode(repository_ctx.attr.links)
    restricted = [link for aliases in links.values() for link in aliases.values() if link.get("optional") or link.get("roots")]
    if restricted or [i for i in instances.values() if i.get("edge_conditions") or i.get("edge_targets")]:
        for name, (_, _, _, constraints) in sorted(_settings().items()):
            build.append("""
config_setting(
    name = {name},
    constraint_values = {constraints},
    visibility = ["//visibility:public"],
)
""".format(name = repr(name), constraints = repr(constraints)))
    edges = _member_edges(links, instances)
    for aliases in links.values():
        for link in aliases.values():
            if "workspace" not in link:
                # A bin target has no deps to declare the workspace members its packages link by
                # path in (BC-4), so the hub declares them for it.
                link["members"] = _bin_members(link, edges, instances)
    for aliases in links.values():
        for link in aliases.values():
            if "workspace" not in link:
                link["select"] = _selections(link.pop("optional")) if link["optional"] else None
                roots = link.pop("roots")
                link["root_select"] = _root_selections(roots) if roots else None
    repository_ctx.file("BUILD.bazel", "".join(build))
    repository_ctx.file("defs.bzl", """\
\"\"\"Generated by the rules_bun `npm` extension.\"\"\"

load("{bzl}", "npm_link")
load("{run_bzl}", "npm_bin")

_LINKS = {links}

_LOCKFILE = {lockfile}

# Instances rules_bun does not fetch; a link reaching one fails analysis naming the package and
# the reason, and is `manual`, so `bazel build //...` does not build it (FR-010).
_UNSUPPORTED = {unsupported}

def _select(selections):
    \"\"\"The platform-restricted optional instances of a link, by target platform (research R8).\"\"\"
    if selections == None:
        return []
    return select({{
        (k if k.startswith("//conditions:") else Label("//:" + k)): [Label("//:" + i) for i in ids]
        for k, ids in selections.items()
    }})

def _root(link):
    \"\"\"The root instance of a link, by target platform where the store binds it differently there.

    The store binds a link's alias to a different entry on a platform where a package providing
    a peer is disabled (feature 006 BC-12); the root is selected by the platform tuples the
    resolver computed it for, as the optional instances are.
    \"\"\"
    if link["root_select"] == None:
        return link["root"]
    return select({{
        (k if k.startswith("//conditions:") else Label("//:" + k)): root
        for k, root in link["root_select"].items()
    }})

def _compatible(link):
    \"\"\"`target_compatible_with` of the bins of a link: where the platform select carries its root.

    A declared package with `os` or `cpu`, optional or not, and a declared optional package with
    `libc` are absent elsewhere (feature 006 BC-7; research R8; feature 004 research R11), and so
    are their bins (FR-016); a link the store makes on no platform has no root, and its bins are
    compatible with none (feature 006 T111).
    \"\"\"
    if link["root"] == None and link["root_select"] == None:
        return [Label("@platforms//:incompatible")]
    if link["root_select"] != None:
        return select({{
            (k if k.startswith("//conditions:") else Label("//:" + k)): [] if root else [Label("@platforms//:incompatible")]
            for k, root in link["root_select"].items()
        }})
    if link["select"] == None or link["root"] in link["closure"]:
        return []
    return select({{
        (k if k.startswith("//conditions:") else Label("//:" + k)): [] if link["root"] in ids else [Label("@platforms//:incompatible")]
        for k, ids in link["select"].items()
    }})

def npm_link_all_packages():
    \"\"\"Creates `:node_modules/<package>` for each package this workspace package declares.

    A workspace member it depends on (`workspace:`) links to that member's target. Each `bin` entry
    of a declared package becomes `:node_modules/<package>/bin/<bin>`.
    \"\"\"
    links = _LINKS.get(native.package_name())
    if links == None:
        fail("rules_bun: npm_link_all_packages() is called in //{{}}, which is no workspace package of {{}}; call it in one of: {{}}".format(
            native.package_name(),
            _LOCKFILE,
            ", ".join(["//" + p for p in sorted(_LINKS.keys())]),
        ))
    for alias, link in links.items():
        name = "node_modules/" + link["target"]
        if "workspace" in link:
            # A workspace member: the label is resolved in the calling repository.
            npm_link(
                name = name,
                alias = alias,
                workspace_target = link["workspace"],
                visibility = ["//visibility:public"],
            )
            continue
        reached = link["closure"] + [i for ids in (link["select"] or {{}}).values() for i in ids]
        unsupported = [i for i in reached if i in _UNSUPPORTED]
        npm_link(
            name = name,
            alias = alias,
            root = _root(link),
            instances = [Label("//:" + i) for i in link["closure"]] + _select(link["select"]),
            tags = ["manual"] if unsupported else [],
            visibility = ["//visibility:public"],
        )
        for bin, (path, entry) in link["bins"].items():
            # The package repository decides whether the file is a JavaScript program for Node or
            # Bun; this macro cannot, so every bin is `manual` and `bazel build //...` builds none
            # (feature 005 research R4, D1). A bin that is not fails its analysis naming why.
            npm_bin(
                name = "{{}}/bin/{{}}".format(name, bin),
                package = ":" + name,
                members = [Label(m) for m in link["members"]],
                bin = bin,
                entry = entry,
                path = path,
                tags = ["manual"],
                target_compatible_with = _compatible(link),
                visibility = ["//visibility:public"],
            )
""".format(
        bzl = _NPM_PACKAGE_BZL,
        run_bzl = _RUN_BZL,
        links = repr(links),
        lockfile = repr(repository_ctx.attr.lockfile),
        unsupported = repr(sorted([i for i, instance in instances.items() if instance["status"] != "ok"])),
    ))

npm_hub_repository = repository_rule(
    implementation = _npm_hub_repository_impl,
    doc = "The hub of one `bun.lock`: instance targets and `defs.bzl` with `npm_link_all_packages`.",
    attrs = {
        "instances": attr.string(doc = "JSON: instance ID -> edges, package repository, store name.", mandatory = True),
        "links": attr.string(doc = "JSON: Bazel package -> alias -> root instance ID and closure, or the member target of a `workspace:` dependency.", mandatory = True),
        "lockfile": attr.string(doc = "The `bun.lock` label, for errors.", mandatory = True),
    },
)
