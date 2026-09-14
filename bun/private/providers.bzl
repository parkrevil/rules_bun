"""Providers for rules_bun."""

BunInfo = provider(
    doc = "Information about a Bun executable provided by a toolchain.",
    fields = {
        "bun": "The Bun executable `File`.",
        "version": "Bun version string, such as `1.4.2`.",
        "tool_files": "List of files needed to run the executable.",
    },
)
