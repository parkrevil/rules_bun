"""Rules a consumer could write with the public `BunLibraryInfo` (feature 006 T094).

They return only `BunLibraryInfo` and `DefaultInfo`, as a rule outside rules_bun can.
"""

load("//bun:defs.bzl", "BunLibraryInfo")

def _consumer_library_impl(ctx):
    return [
        BunLibraryInfo(srcs = depset(ctx.files.srcs), data = depset(ctx.files.data), packages = depset()),
        DefaultInfo(files = depset(ctx.files.srcs)),
    ]

# A library built by a consumer's own rule.
consumer_library = rule(
    implementation = _consumer_library_impl,
    attrs = {
        "data": attr.label_list(allow_files = True),
        "srcs": attr.label_list(allow_files = True),
    },
)

def _consumer_wrapper_impl(ctx):
    infos = [lib[BunLibraryInfo] for lib in ctx.attr.libraries]
    return [
        BunLibraryInfo(
            srcs = depset(transitive = [i.srcs for i in infos]),
            data = depset(transitive = [i.data for i in infos]),
            packages = depset(transitive = [getattr(i, "packages", None) or depset() for i in infos]),
        ),
        DefaultInfo(files = depset(transitive = [i.srcs for i in infos])),
    ]

# A consumer's rule between a program and the libraries it passes on, through an attribute not
# named `deps`.
consumer_wrapper = rule(
    implementation = _consumer_wrapper_impl,
    attrs = {"libraries": attr.label_list(providers = [BunLibraryInfo])},
)
