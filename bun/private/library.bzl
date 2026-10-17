"""Implementation of the `bun_library` rule."""

load(":providers.bzl", "BunLibraryInfo")

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

def library_info(srcs, data, deps):
    """Returns the `BunLibraryInfo` of a target.

    Args:
        srcs: List of the target's own source `File`s.
        data: List of the target's `data` targets.
        deps: List of the target's `deps` targets, each providing `BunLibraryInfo`.

    Returns:
        `BunLibraryInfo` with the transitive sources and data files.
    """
    return BunLibraryInfo(
        srcs = depset(srcs, transitive = [d[BunLibraryInfo].srcs for d in deps]),
        data = depset(
            transitive = [t[DefaultInfo].files for t in data] + [d[BunLibraryInfo].data for d in deps],
        ),
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
            doc = "Other `bun_library` targets.",
            providers = [BunLibraryInfo],
        ),
    },
)
