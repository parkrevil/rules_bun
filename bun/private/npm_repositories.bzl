"""Repository rules of the `npm` extension (research R3, R4, R7).

A package repository holds one `name@version`: the extracted archive under `package/` and the
instance-tree target `:tree`. The hub repository holds one instance target per package instance and
`defs.bzl`, whose `npm_link_all_packages()` creates the `:node_modules/<package>` targets of the
workspace package it is called in.
"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "use_netrc")

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

    A file named `BUILD` or `BUILD.bazel` would make its directory a subpackage, and a name with a
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
            renamed = (not entry.is_dir and name in ("BUILD", "BUILD.bazel")) or not _addressable(name)
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
    build = """\
load("{bzl}", "npm_package_tree")

npm_package_tree(
    name = "tree",
    srcs = glob(["package/**"], exclude = {exclude}, allow_empty = True),
    check = {check},
    replace_prefixes = {replace_prefixes},
    visibility = ["//visibility:public"],
)
""".format(
        bzl = _NPM_PACKAGE_BZL,
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
        "integrity": attr.string(doc = "The Subresource Integrity the lockfile records.", mandatory = True),
        "package": attr.string(doc = "The package name.", mandatory = True),
        "version": attr.string(doc = "The package version.", mandatory = True),
        "exclude": attr.string_list(doc = "`glob` exclude patterns relative to the package root."),
        "replacement": attr.label(doc = "A package archive extracted instead of the download.", allow_single_file = True),
        "replacement_label": attr.string(doc = "The replacement's label as its tag writes it, for errors."),
    },
)

# npm `os` and `cpu` values -> `@platforms` constraint names (research R8; @platforms 1.1.0
# `os/BUILD` and `cpu/BUILD`). A value not listed, such as `sunos`, matches no Bazel platform.
_OS = {
    "aix": "aix",
    "android": "android",
    "darwin": "macos",
    "freebsd": "freebsd",
    "linux": "linux",
    "netbsd": "netbsd",
    "openbsd": "openbsd",
    "win32": "windows",
}
_CPU = {
    "arm": "arm",
    "arm64": "aarch64",
    "ia32": "x86_32",
    "riscv64": "riscv64",
    "s390x": "s390x",
    "x64": "x86_64",
}

def _matches(values, actual):
    """npm's `os`/`cpu` rule: a listed value must match, a `!` value must not; `actual` may be `None`."""
    if not values:
        return True
    if actual != None and "!" + actual in values:
        return False
    positives = [v for v in values if not v.startswith("!")]
    return actual in positives if positives else True

# npm `libc` values -> constraint values of //bun/platforms/libc (feature 004 research R11).
_LIBC = {
    "glibc": str(Label("//bun/platforms/libc:glibc")),
    "musl": str(Label("//bun/platforms/libc:musl")),
}

def libc_matches(values, os, libc):
    """npm's `libc` rule (npm-install-checks `checkPlatform`) for a target's npm `os` and `libc`.

    npm defines libc only on Linux, so a package with `libc` matches no other OS. A Linux platform
    without the libc constraint (`libc` is `None`) does not say which libc it has, so it matches,
    and every libc variant is carried there.

    Args:
        values: The entry's `libc` list.
        os: The target's npm `os`, or `None` for an OS without a mapping.
        libc: The target's npm `libc`, or `None` when the platform does not set it.

    Returns:
        Whether the entry may be carried on that target.
    """
    if not values:
        return True
    if os != "linux":
        return False
    if libc == None or values == ["any"]:
        return True
    return _matches(values, libc)

def _holds(conditions, os, cpu, libc):
    """Whether one of `conditions` (each a list of `[os, cpu, libc]` requirements) holds for npm values."""
    for condition in conditions:
        if all([_matches(r[0], os) and _matches(r[1], cpu) and libc_matches(r[2], os, libc) for r in condition]):
            return True
    return False

def _settings():
    """Config setting name -> (npm os, npm cpu, npm libc, constraint labels).

    One per OS and per OS and CPU, and for Linux also each of those with a libc.
    """
    settings = {}
    for os, os_constraint in _OS.items():
        os_label = "@platforms//os:" + os_constraint
        libcs = [(None, None)] + (sorted(_LIBC.items()) if os == "linux" else [])
        for libc, libc_label in libcs:
            libc_suffix = "__libc_" + libc if libc else ""
            libc_labels = [libc_label] if libc else []
            settings["_os_" + os_constraint + libc_suffix] = (os, None, libc, [os_label] + libc_labels)
            for cpu, cpu_constraint in _CPU.items():
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
        selections[name] = sorted([i for i, conditions in optional.items() if _holds(conditions, os, cpu, libc)])
    selections["//conditions:default"] = sorted([i for i, conditions in optional.items() if _holds(conditions, None, None, None)])
    return selections

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
        build.append("""
npm_instance(
    name = {name},
    check = {check},
    dependency_keys = {dependency_keys},
    edges = {edges},
    package = {package},
    peers = {peers},
    store_name = {store_name},
    tree = {tree},
    visibility = ["//visibility:public"],
)
""".format(
            name = repr(instance_id),
            check = repr("@{}//check".format(instance["repo"])) if instance["replaced"] else None,
            dependency_keys = repr(instance["dependency_keys"]),
            edges = repr(instance["edges"]),
            package = repr(instance["package"]),
            peers = repr(instance["peers"]),
            store_name = repr(instance["store_name"]),
            tree = repr("@{}//:tree".format(instance["repo"])),
        ))
    links = json.decode(repository_ctx.attr.links)
    if [link for aliases in links.values() for link in aliases.values() if link.get("optional")]:
        for name, (_, _, _, constraints) in sorted(_settings().items()):
            build.append("""
config_setting(
    name = {name},
    constraint_values = {constraints},
    visibility = ["//visibility:public"],
)
""".format(name = repr(name), constraints = repr(constraints)))
    for aliases in links.values():
        for link in aliases.values():
            if "workspace" not in link:
                link["select"] = _selections(link.pop("optional")) if link["optional"] else None
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

def _compatible(link):
    \"\"\"`target_compatible_with` of the bins of a link: where the platform select carries its root.

    A declared optional package with `os`, `cpu` or `libc` is absent elsewhere (research R8;
    feature 004 research R11), and so are its bins (FR-016).
    \"\"\"
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
            root = link["root"],
            instances = [Label("//:" + i) for i in link["closure"]] + _select(link["select"]),
            tags = ["manual"] if unsupported else [],
            visibility = ["//visibility:public"],
        )
        for bin, (path, runnable, entry) in link["bins"].items():
            # A bin file Bun does not run gives a target whose analysis fails (research R10).
            npm_bin(
                name = "{{}}/bin/{{}}".format(name, bin),
                package = ":" + name,
                bin = bin,
                entry = entry,
                path = path,
                tags = [] if runnable and not unsupported else ["manual"],
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
