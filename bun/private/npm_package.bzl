"""Build rules of npm packages: instance trees, instances and links (research R4, R7)."""

load("@bazel_lib//lib:copy_to_directory.bzl", "copy_to_directory_bin_action")
load(":library.bzl", "packages_of")
load(":providers.bzl", "BunLibraryInfo", "NpmInstanceInfo", "NpmLinkInfo", "NpmPackageTreeInfo")

_COPY_TO_DIRECTORY_TOOLCHAIN = "@bazel_lib//lib:copy_to_directory_toolchain_type"

_EXECUTION_TYPE = Label("//bun/toolchain:execution_type")

COPY_TO_DIRECTORY_TOOLCHAINS = [_COPY_TO_DIRECTORY_TOOLCHAIN]

def _npm_package_tree_impl(ctx):
    tree = ctx.actions.declare_directory(ctx.label.name)
    copy_to_directory_bin_action(
        ctx,
        name = ctx.label.name,
        dst = tree,
        copy_to_directory_bin = ctx.toolchains[_COPY_TO_DIRECTORY_TOOLCHAIN].copy_to_directory_info.bin,
        # The replacement stamp is an input, so the tree exists only after the check passed
        # (FR-026); it lives in the package `check`, which the copy leaves out.
        files = ctx.files.srcs + ctx.files.check,
        root_paths = ["package"],
        exclude_srcs_packages = ["check"],
        replace_prefixes = ctx.attr.replace_prefixes,
        hardlink = "auto",
    )
    return [DefaultInfo(files = depset([tree])), NpmPackageTreeInfo(bins = dict(ctx.attr.bins))]

npm_package_tree = rule(
    implementation = _npm_package_tree_impl,
    doc = "Private: copies the extracted files of a package repository into one tree artifact.",
    attrs = {
        "bins": attr.string_dict(doc = "Each `bin` path of the package -> `\"\"` when it is a JavaScript program for Node or Bun, else the reason it is not."),
        "check": attr.label(doc = "The replacement check of a replaced package, in the package `check`.", allow_single_file = True),
        "replace_prefixes": attr.string_dict(doc = "The safe path of each renamed entry -> its path in the archive."),
        "srcs": attr.label_list(doc = "The files under `package/`.", allow_files = True),
    },
    toolchains = COPY_TO_DIRECTORY_TOOLCHAINS,
)

def _npm_replacement_check_impl(ctx):
    buninfo = ctx.toolchains[_EXECUTION_TYPE].buninfo
    stamp = ctx.actions.declare_file(ctx.label.name + ".ok")
    args = ctx.actions.args()
    args.add("--config=" + ctx.file._bunfig.path)
    args.add("--no-env-file")
    args.add(ctx.file._script)
    args.add(ctx.file.archive)
    args.add(ctx.attr.integrity)
    args.add(ctx.attr.package)
    args.add(ctx.attr.label)
    args.add(stamp)
    ctx.actions.run(
        executable = buninfo.bun,
        arguments = [args],
        inputs = [ctx.file.archive, ctx.file._script, ctx.file._bunfig],
        tools = buninfo.tool_files,
        outputs = [stamp],
        env = {"BUN_RUNTIME_TRANSPILER_CACHE_PATH": "0"},
        mnemonic = "NpmReplacementCheck",
        progress_message = "Checking the replacement archive of %s against bun.lock" % ctx.attr.package,
        toolchain = _EXECUTION_TYPE,
    )
    return [DefaultInfo(files = depset([stamp]))]

npm_replacement_check = rule(
    implementation = _npm_replacement_check_impl,
    doc = "Private: checks an `npm.replace_package` archive against the lockfile's integrity (FR-026).",
    attrs = {
        "archive": attr.label(doc = "The replacement archive.", allow_single_file = True, mandatory = True),
        "integrity": attr.string(doc = "The integrity the lockfile records.", mandatory = True),
        "label": attr.string(doc = "The archive's label as the tag names it, for the error.", mandatory = True),
        "package": attr.string(doc = "`name@version`, for the error.", mandatory = True),
        "_bunfig": attr.label(default = Label("//bun/private:isolated_bunfig.toml"), allow_single_file = True),
        "_script": attr.label(default = Label("//bun/private:check_integrity.js"), allow_single_file = True),
    },
    toolchains = [_EXECUTION_TYPE],
)

def _npm_instance_impl(ctx):
    trees = ctx.files.tree
    if len(trees) != 1 or not trees[0].is_directory:
        fail("{}: tree must provide exactly one tree artifact".format(ctx.label))
    return [NpmInstanceInfo(
        id = ctx.label.name,
        label = ctx.label,
        package = ctx.attr.package,
        store_name = ctx.attr.store_name,
        tree = trees[0],
        edges = dict(ctx.attr.edges),
        dependency_keys = dict(ctx.attr.dependency_keys),
        peers = list(ctx.attr.peers),
        check = ctx.file.check,
        integrity = ctx.attr.integrity,
        source = ctx.attr.source,
        exclude = list(ctx.attr.exclude),
        hub = ctx.attr.hub,
        lockfile = ctx.attr.lockfile,
        bins = dict(ctx.attr.tree[NpmPackageTreeInfo].bins) if NpmPackageTreeInfo in ctx.attr.tree else {},
    )]

npm_instance = rule(
    implementation = _npm_instance_impl,
    doc = "Private: one package instance of a hub: its tree and the instances its dependencies resolve to.",
    attrs = {
        "check": attr.label(doc = "The replacement check of a replaced package.", allow_single_file = True),
        "dependency_keys": attr.string_dict(doc = "Ordinary dependency alias -> the `bun.lock` key it resolves to."),
        "edges": attr.string_dict(doc = "Dependency alias -> instance ID."),
        "exclude": attr.string_list(doc = "The sorted exclusion patterns of the package (content identity)."),
        "hub": attr.string(doc = "The hub's name, for errors."),
        "integrity": attr.string(doc = "The padded integrity the package is verified against (content identity)."),
        "lockfile": attr.string(doc = "The hub's `bun.lock` label, for errors."),
        "package": attr.string(doc = "The package name.", mandatory = True),
        "peers": attr.string_list(doc = "The aliases of `edges` that are peers."),
        "source": attr.string(doc = "The download URL or the replacement's label text (content identity)."),
        "store_name": attr.string(doc = "`name@version` with `/` written `+`.", mandatory = True),
        "tree": attr.label(doc = "The package's instance-tree target.", mandatory = True),
    },
    provides = [NpmInstanceInfo],
)

def _npm_unsupported_impl(ctx):
    fail("rules_bun: {}: the npm package {} cannot be used: {}".format(ctx.label, ctx.attr.package, ctx.attr.reason))

npm_unsupported = rule(
    implementation = _npm_unsupported_impl,
    doc = "Private: an instance rules_bun does not fetch; its analysis fails naming the package and the reason (FR-010).",
    attrs = {
        "package": attr.string(doc = "`name@<resolution>` as the lockfile writes it.", mandatory = True),
        "reason": attr.string(doc = "Why the package cannot be used.", mandatory = True),
    },
    provides = [NpmInstanceInfo],
)

def _link_dir(label):
    repo = label.repo_name or "_main"
    return "/".join([p for p in [repo, label.package] if p])

def _npm_member_link(ctx):
    """The link of a `workspace:` dependency: the member target's files and packages (R5, R7)."""
    member = ctx.attr.workspace_target
    info = member[BunLibraryInfo]
    record = NpmLinkInfo(
        link_dir = _link_dir(ctx.label),
        alias = ctx.attr.alias,
        root = None,
        instances = depset(),
        workspace_target = _link_dir(member.label),
    )
    return [
        BunLibraryInfo(
            srcs = info.srcs,
            data = info.data,
            packages = depset([record], transitive = [packages_of(info)]),
        ),
        DefaultInfo(files = member[DefaultInfo].files, runfiles = member[DefaultInfo].default_runfiles),
    ]

def _npm_link_impl(ctx):
    if ctx.attr.workspace_target:
        return _npm_member_link(ctx)
    record = NpmLinkInfo(
        link_dir = _link_dir(ctx.label),
        alias = ctx.attr.alias,
        root = ctx.attr.root,
        instances = depset([t[NpmInstanceInfo] for t in ctx.attr.instances]),
        workspace_target = None,
    )
    instances = record.instances.to_list()
    files = [i.tree for i in instances] + [i.check for i in instances if i.check]
    return [
        BunLibraryInfo(srcs = depset(), data = depset(), packages = depset([record])),
        # Building the link builds its packages and checks their replacement archives.
        DefaultInfo(files = depset(files)),
    ]

npm_link = rule(
    implementation = _npm_link_impl,
    doc = "Private: a `:node_modules/<package>` target; carries the link record of one package or workspace member.",
    attrs = {
        "alias": attr.string(doc = "The name the package is linked under.", mandatory = True),
        "instances": attr.label_list(doc = "The instances reachable from `root`.", providers = [NpmInstanceInfo]),
        "root": attr.string(doc = "The ID of the instance the link points to."),
        "workspace_target": attr.label(doc = "For a `workspace:` dependency, the member's target.", providers = [BunLibraryInfo]),
    },
    provides = [BunLibraryInfo],
)
