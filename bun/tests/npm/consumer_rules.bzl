"""Rules a consumer could write with the public `BunLibraryInfo` (feature 006 T094).

They return only `BunLibraryInfo` and `DefaultInfo`, as a rule outside rules_bun can.
"""

load("//bun:defs.bzl", "BunLibraryInfo")

def _consumer_library_impl(ctx):
    return [
        BunLibraryInfo(srcs = depset(ctx.files.srcs), data = depset(ctx.files.data), packages = depset()),
        DefaultInfo(files = depset(ctx.files.srcs)),
    ]

# A library built by a consumer's own rule. It passes nothing of `extras` on (T124).
consumer_library = rule(
    implementation = _consumer_library_impl,
    attrs = {
        "data": attr.label_list(allow_files = True),
        "extras": attr.label_list(),
        "srcs": attr.label_list(allow_files = True),
    },
)

def _consumer_carrier_impl(ctx):
    return [DefaultInfo(files = depset(transitive = [t[DefaultInfo].files for t in ctx.attr.targets]))]

# A consumer's rule that provides no `BunLibraryInfo`, so it carries none of its targets' (T124).
consumer_carrier = rule(
    implementation = _consumer_carrier_impl,
    attrs = {"targets": attr.label_list()},
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
