"""Test-only rule: the workspace members the matcher computes for each glob case (research R9)."""

load("//bun/private:workspaces.bzl", "match_members", "workspace_patterns")
load(":glob_cases.bzl", "GLOB_CASES", "MANIFESTS", "TREE")

def _glob_members_impl(ctx):
    children = {}
    for path in TREE:
        parent, _, name = path.rpartition("/")
        children.setdefault(parent, []).append(name)
    results = {}
    for case, workspaces in GLOB_CASES.items():
        result = match_members(
            workspace_patterns({"workspaces": workspaces}),
            lambda path: sorted(children.get(path, [])),
            lambda path: path in MANIFESTS,
            "package.json",
        )
        results[case] = result.value if result.error == None else {"error": result.error}
    out = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(out, json.encode({"cases": GLOB_CASES, "manifests": MANIFESTS, "members": results, "tree": TREE}))
    return [DefaultInfo(files = depset([out]))]

glob_members = rule(
    implementation = _glob_members_impl,
    doc = "Writes `<name>.json`: the tree, the cases and the member set the matcher computes for each.",
)
