"""Providers for rules_bun."""

BunInfo = provider(
    doc = "Information about a Bun executable provided by a toolchain.",
    fields = {
        "bun": "The Bun executable `File`.",
        "version": "Bun version string, such as `1.4.2`.",
        "tool_files": "List of files needed to run the executable.",
    },
)

BunLibraryInfo = provider(
    doc = "Sources and data files of a `bun_library`, `bun_binary` or `bun_test` and of its `deps`.",
    fields = {
        "srcs": "`depset` of `File`: transitive TypeScript/JavaScript sources.",
        "data": "`depset` of `File`: transitive files of `data` targets (their `DefaultInfo.files`).",
    },
)
