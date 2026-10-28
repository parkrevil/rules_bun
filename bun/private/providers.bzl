"""Providers for rules_bun."""

BunInfo = provider(
    doc = "Information about a Bun executable provided by a toolchain.",
    fields = {
        "bun": "The Bun executable `File`.",
        "version": "Bun version string, such as `1.4.4`.",
        "tool_files": "List of files needed to run the executable.",
    },
)

BunLibraryInfo = provider(
    doc = "Sources and data files of a `bun_library`, `bun_binary` or `bun_test` and of its `deps`.",
    fields = {
        "srcs": "`depset` of `File`: transitive TypeScript/JavaScript sources.",
        "data": "`depset` of `File`: transitive files of `data` targets (their `DefaultInfo.files`).",
        "packages": """`depset` of npm package link records: the `:node_modules/<package>` targets
among the transitive `deps`, which `bun_binary` and `bun_test` lay out in their copy tree. A
provider created without this field is read as holding none.""",
    },
)

NpmInstanceInfo = provider(
    doc = "Private: one package instance of a `bun.lock` hub (research R2, R7).",
    fields = {
        "id": "The instance ID, `name@version__<h>`.",
        "label": "The label of the instance's target. `id` and the IDs in `edges` are target names in its package; IDs of different hubs (several lockfiles) may be equal, the labels are not.",
        "package": "The package name, with its scope if any.",
        "store_name": "`name@version` with `/` written `+`: the instance's store directory.",
        "tree": "The tree artifact holding the package's files.",
        "edges": "Dict from dependency alias to the instance ID it resolves to.",
        "dependency_keys": "Dict from ordinary dependency alias to the `bun.lock` key it resolves to.",
        "peers": "The aliases of `edges` that are peers.",
        "check": "The stamp `File` of the replacement integrity check, or `None`.",
        "integrity": "Content identity (feature 005 research R1): the padded integrity the package's download or replacement is verified against.",
        "source": "Content identity: the download URL, or the `npm.replace_package` archive's label text.",
        "exclude": "Content identity: the sorted, de-duplicated `exclude_package_contents` patterns of the package.",
        "hub": "The hub's name, as its `npm.translate_lock` tag gives it, for errors.",
        "lockfile": "The hub's `bun.lock` label text, for errors.",
        "bins": "Dict from each `bin` path of the package to `\"\"` when it is a JavaScript program for Node or Bun, else the reason it is not (`NpmPackageTreeInfo`).",
    },
)

NpmPackageTreeInfo = provider(
    doc = "Private: what a package repository decided from the package's files (feature 005 research R4).",
    fields = {
        "bins": "Dict from each `bin` path of the package to `\"\"` when it is a JavaScript program for Node or Bun, else the reason it is not.",
    },
)

NpmLinkInfo = provider(
    doc = "Private: the record of one `:node_modules/<package>` link target (research R7).",
    fields = {
        "link_dir": "Runfiles path of the workspace package whose `node_modules` holds the link.",
        "alias": "The name the package is linked under.",
        "root": "The ID of the instance the link points to; `None` for a workspace member link.",
        "instances": "`depset` of `NpmInstanceInfo`: every instance reachable from `root`.",
        "workspace_target": "For a workspace member link, the runfiles path of the member's package, where its target's files are copied; otherwise `None`.",
    },
)
