"""Implementation of the `bun_library` rule."""

load(":providers.bzl", "BunDeclaredTargetsInfo", "BunLibraryInfo")

SOURCE_EXTENSIONS = [".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs"]

def check_no_directory(label, files):
    """Fails naming `data` and the directory when one of `files` is a directory.

    Args:
        label: The label of the target, for the message.
        files: List of `File`s.
    """
    for f in files:
        if f.is_directory:
            fail("{}: data holds the directory {}; directories in data are not supported".format(label, f.short_path))

def packages_of(info):
    """The `packages` of a `BunLibraryInfo`; a provider created without the field holds none."""
    return getattr(info, "packages", None) or depset()

def library_info(srcs, data, deps):
    """Returns the `BunLibraryInfo` of a target.

    Args:
        srcs: List of the target's own source `File`s.
        data: List of the target's `data` targets.
        deps: List of the target's `deps` targets, each providing `BunLibraryInfo`.

    Returns:
        `BunLibraryInfo` with the transitive sources, data files and package link records.
    """
    return BunLibraryInfo(
        srcs = depset(srcs, transitive = [d[BunLibraryInfo].srcs for d in deps]),
        data = depset(
            transitive = [t[DefaultInfo].files for t in data] + [d[BunLibraryInfo].data for d in deps],
        ),
        packages = depset(transitive = [packages_of(d[BunLibraryInfo]) for d in deps]),
    )

def _declared_targets_aspect_impl(target, ctx):
    transitive = []
    for name in dir(ctx.rule.attr):
        value = getattr(ctx.rule.attr, name, None)
        if type(value) == "dict":
            value = list(value.keys()) + list(value.values())
        elif type(value) != "list":
            value = [value]
        for dep in value:
            if type(dep) == "Target" and BunDeclaredTargetsInfo in dep:
                transitive.append(dep[BunDeclaredTargetsInfo].targets)
    direct = []
    if BunLibraryInfo in target:
        info = target[BunLibraryInfo]
        direct.append(struct(label = target.label, srcs = info.srcs, data = info.data))
    return [BunDeclaredTargetsInfo(targets = depset(direct, transitive = transitive))]

declared_targets_aspect = aspect(
    implementation = _declared_targets_aspect_impl,
    # Every attribute: a consumer's rule may build a member, or pass one on, under any name.
    attr_aspects = ["*"],
    doc = """Collects the targets providing `BunLibraryInfo` among a target and its transitive
dependencies, whatever rule builds them and through whatever attribute, each with the sources and
data files its `BunLibraryInfo` holds. Whether a workspace member counts as declared is decided from
these files, not from the attributes walked: `bun_binary` and `bun_test` accept a member only where
every one of them is in the copy tree they build (feature 006 BC-4; T124, T140).""",
)

def library_runfiles(ctx, files, data, deps):
    """Returns runfiles holding `files`, the files of `data` and the runfiles of `data` and `deps`.

    Args:
        ctx: The rule context.
        files: List of `File`s to add.
        data: List of the target's `data` targets.
        deps: List of the target's `deps` targets.

    Returns:
        A `runfiles` object.
    """
    runfiles = ctx.runfiles(
        files = files,
        transitive_files = depset(transitive = [t[DefaultInfo].files for t in data]),
    )
    return runfiles.merge_all([t[DefaultInfo].default_runfiles for t in data + deps])

def _bun_library_impl(ctx):
    check_no_directory(ctx.label, ctx.files.data)
    return [
        library_info(ctx.files.srcs, ctx.attr.data, ctx.attr.deps),
        DefaultInfo(
            files = depset(ctx.files.srcs),
            runfiles = library_runfiles(ctx, ctx.files.srcs, ctx.attr.data, ctx.attr.deps),
        ),
        coverage_common.instrumented_files_info(
            ctx,
            source_attributes = ["srcs"],
            dependency_attributes = ["deps", "data"],
        ),
    ]

bun_library = rule(
    implementation = _bun_library_impl,
    doc = """TypeScript or JavaScript sources and their data files, used by other Bun targets through `deps`.

A `bun_binary` or `bun_test` that depends on it copies these sources and data files into its own
copy tree and runs them there. A directory in `data` fails analysis.""",
    attrs = {
        "srcs": attr.label_list(
            doc = "Source files (`.ts .tsx .mts .cts .js .jsx .mjs .cjs`).",
            allow_files = SOURCE_EXTENSIONS,
        ),
        "data": attr.label_list(
            doc = "Files needed at run time; read relative to `import.meta.dir` of the file that reads them.",
            allow_files = True,
        ),
        "deps": attr.label_list(
            doc = "Other `bun_library` targets and npm package targets (`:node_modules/<package>`), whose packages it passes on.",
            providers = [BunLibraryInfo],
        ),
    },
)
